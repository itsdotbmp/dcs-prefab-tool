-- dcs-sms hook
-- Lives in: Saved Games/DCS*/Scripts/Hooks/dcs-sms-hook.lua
-- Runs in: DCS GUI/hook environment (no sandbox; lfs and net.* are available)
-- Protocol: see docs/superpowers/specs/2026-04-25-execution-bridge-design.md

local DCS_SMS = {
  version = "0.1.0",
  heartbeat_every_frames = 30,
  cleanup_max_age_seconds = 60,
}

DCS_SMS.root   = lfs.writedir() .. "dcs-sms\\"
DCS_SMS.inbox  = DCS_SMS.root .. "inbox\\"
DCS_SMS.outbox = DCS_SMS.root .. "outbox\\"
DCS_SMS.state  = DCS_SMS.root .. "state\\"
DCS_SMS.logdir = DCS_SMS.root .. "log\\"

DCS_SMS.frame                 = 0
DCS_SMS.last_heartbeat_frame  = -1e9  -- force first heartbeat immediately
DCS_SMS.mission_loaded        = false
DCS_SMS.mission_name          = ""

-- ----------------------------------------------------------------------------
-- helpers

local function ensure_dirs()
  for _, d in ipairs({DCS_SMS.root, DCS_SMS.inbox, DCS_SMS.outbox,
                      DCS_SMS.state, DCS_SMS.logdir}) do
    lfs.mkdir(d)
  end
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function write_atomic(path, data)
  local tmp = path .. ".tmp"
  local f, err = io.open(tmp, "wb")
  if not f then
    log.write("dcs-sms", log.ERROR, "open tmp " .. tmp .. ": " .. tostring(err))
    return false
  end
  f:write(data)
  f:close()
  -- os.rename overwrites the target on Windows when source and target are
  -- on the same volume (which they are here).
  local ok, err2 = os.rename(tmp, path)
  if not ok then
    log.write("dcs-sms", log.ERROR, "rename " .. tmp .. " -> " .. path .. ": " .. tostring(err2))
    -- Try delete + rename as fallback for older Windows behavior.
    os.remove(path)
    os.rename(tmp, path)
  end
  return true
end

local function iso_now()
  -- DCS Lua's os.date with !%Y-%m-%dT%H:%M:%S gives UTC seconds; we append
  -- a Z suffix. No millisecond precision, which is fine for our purposes.
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function escape_json_string(s)
  -- Cover the common cases. The hook only emits a handful of fields by
  -- this path (mission_name, version), so we don't need a full JSON
  -- encoder here.
  s = s:gsub("\\", "\\\\")
  s = s:gsub('"', '\\"')
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  return s
end

local function write_heartbeat()
  local payload = string.format(
    '{"hook_version":"%s","mission_loaded":%s,"mission_name":"%s","last_frame":%d,"last_frame_at":"%s"}',
    DCS_SMS.version,
    tostring(DCS_SMS.mission_loaded),
    escape_json_string(DCS_SMS.mission_name),
    DCS_SMS.frame,
    iso_now()
  )
  write_atomic(DCS_SMS.state .. "hook.json", payload)
  DCS_SMS.last_heartbeat_frame = DCS_SMS.frame
end

local function sweep_stale(dir, suffix)
  local now = os.time()
  for entry in lfs.dir(dir) do
    if entry ~= "." and entry ~= ".." then
      local full = dir .. entry
      local attrs = lfs.attributes(full)
      if attrs and attrs.mode == "file"
         and (entry:sub(-#suffix) == suffix or entry:match("%.tmp$"))
         and (now - (attrs.modification or now)) > DCS_SMS.cleanup_max_age_seconds then
        os.remove(full)
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- request execution

-- build_wrapper takes the user's Lua snippet and wraps it in code that:
--   * captures print() output
--   * runs the snippet under xpcall to get a traceback on error
--   * builds a JSON-serializable response with id/frame/duration metadata
--   * stashes the resulting JSON string in __DCS_SMS_RESPONSE_JSON
local function build_wrapper(req_id, frame, user_code)
  return string.format([[
do
  local __dcs_sms_id    = %q
  local __dcs_sms_frame = %d
  local __dcs_sms_start = os.clock()
  local __dcs_sms_out   = {}

  local __dcs_sms_orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    __dcs_sms_out[#__dcs_sms_out+1] = table.concat(parts, '\t')
  end

  local __dcs_sms_ok, __dcs_sms_ret = xpcall(function()
%s
  end, debug.traceback)

  print = __dcs_sms_orig_print

  local __dcs_sms_dur = (os.clock() - __dcs_sms_start) * 1000
  local __dcs_sms_resp = {
    id             = __dcs_sms_id,
    ok             = __dcs_sms_ok,
    output         = table.concat(__dcs_sms_out, '\n'),
    return_value   = (__dcs_sms_ok and __dcs_sms_ret) or nil,
    error          = (not __dcs_sms_ok) and { message = tostring(__dcs_sms_ret), traceback = "" } or nil,
    frame_executed = __dcs_sms_frame,
    duration_ms    = __dcs_sms_dur,
  }
  __DCS_SMS_RESPONSE_JSON = net.lua2json(__dcs_sms_resp)
end
]], req_id, frame, user_code)
end

local function parse_request_id_from_filename(name)
  -- "abc-123.req.json" -> "abc-123"
  return name:match("^(.+)%.req%.json$")
end

local function execute_request(filename)
  local req_path = DCS_SMS.inbox .. filename
  local raw = read_file(req_path)
  if not raw then return end

  -- DCS provides net.json2lua in the hook env (mirror of net.lua2json),
  -- so we parse the request properly instead of regex-matching it. Fall
  -- back to the request-id from the filename if the JSON is malformed.
  local req_id = parse_request_id_from_filename(filename)
  local ok, parsed = pcall(net.json2lua, raw)
  if not ok or type(parsed) ~= "table" or type(parsed.code) ~= "string" or not req_id then
    log.write("dcs-sms", log.ERROR, "could not parse request " .. filename
      .. " (" .. tostring(parsed) .. ")")
    os.remove(req_path)
    return
  end
  -- Prefer the request-id parsed from JSON when present; fall back to the
  -- filename-derived one (which we use anyway to delete the request file).
  if type(parsed.id) == "string" and parsed.id ~= "" then
    req_id = parsed.id
  end
  local code = parsed.code

  local wrapper = build_wrapper(req_id, DCS_SMS.frame, code)
  local ok_out, err_out = pcall(net.dostring_in, 'mission', wrapper)
  if not ok_out then
    log.write("dcs-sms", log.ERROR, "wrapper exec failed: " .. tostring(err_out))
    os.remove(req_path)
    return
  end
  local response_json = net.dostring_in('mission', "return __DCS_SMS_RESPONSE_JSON")
  if type(response_json) ~= "string" or response_json == "" then
    log.write("dcs-sms", log.ERROR, "no response JSON for " .. req_id)
    os.remove(req_path)
    return
  end

  write_atomic(DCS_SMS.outbox .. req_id .. ".res.json", response_json)
  os.remove(req_path)
end

local function process_inbox()
  for entry in lfs.dir(DCS_SMS.inbox) do
    if entry:sub(-9) == ".req.json" then
      local ok, err = pcall(execute_request, entry)
      if not ok then
        log.write("dcs-sms", log.ERROR, "execute_request crashed: " .. tostring(err))
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- userCallbacks

local handler = {}

function handler.onMissionLoadEnd()
  DCS_SMS.mission_loaded = true
  DCS_SMS.mission_name = (DCS and DCS.getMissionName and DCS.getMissionName()) or ""
  pcall(sweep_stale, DCS_SMS.inbox, ".req.json")
  pcall(sweep_stale, DCS_SMS.outbox, ".res.json")
  write_heartbeat()
  log.write("dcs-sms", log.INFO, "mission loaded: " .. DCS_SMS.mission_name)
end

function handler.onSimulationFrame()
  DCS_SMS.frame = DCS_SMS.frame + 1
  if DCS_SMS.mission_loaded then
    pcall(process_inbox)
  end
  if DCS_SMS.frame - DCS_SMS.last_heartbeat_frame >= DCS_SMS.heartbeat_every_frames then
    pcall(write_heartbeat)
  end
end

function handler.onSimulationStop()
  DCS_SMS.mission_loaded = false
  pcall(write_heartbeat)
  log.write("dcs-sms", log.INFO, "simulation stopped")
end

local function init()
  ensure_dirs()
  write_heartbeat()
  DCS.setUserCallbacks(handler)
  log.write("dcs-sms", log.INFO, "hook loaded v" .. DCS_SMS.version)
end

local ok, err = pcall(init)
if not ok then
  log.write("dcs-sms", log.ERROR, "init failed: " .. tostring(err))
end
