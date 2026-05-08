-- dcs-sms hook
-- Lives in: Saved Games/DCS*/Scripts/Hooks/dcs-sms-hook.lua
-- Runs in: DCS GUI/hook environment (no sandbox; lfs and net.* are available)
-- Protocol: see docs/superpowers/specs/2026-04-25-execution-bridge-design.md

local DCS_SMS = {
  version = "0.2.0",
  heartbeat_every_frames = 30,
  cleanup_max_age_seconds = 60,
}

DCS_SMS.root   = lfs.writedir() .. "dcs-sms\\"
DCS_SMS.inbox  = DCS_SMS.root .. "inbox\\"
DCS_SMS.outbox = DCS_SMS.root .. "outbox\\"
DCS_SMS.state  = DCS_SMS.root .. "state\\"
DCS_SMS.logdir = DCS_SMS.root .. "log\\"

DCS_SMS.tick                  = 0
DCS_SMS.last_heartbeat_tick   = -1e9  -- force first heartbeat immediately
DCS_SMS.mission_loaded        = false
DCS_SMS.mission_name          = ""
-- The Hooks/ env has no per-frame tick outside a running mission. UpdateManager
-- exists as a require()-able module here, but `Gui.AddUpdateCallback(UpdateManager.update)`
-- is wired up in UserHooks.lua's GUI env / MissionEditor.lua's ME env, NOT this
-- hook env — so add()-ing here does nothing. The hook only ticks during sim,
-- via onSimulationFrame. Outside-of-sim work (target=gui) lives in the ME-mod's
-- bridge.lua, which runs in the ME env where UpdateManager is actually wired.
DCS_SMS.state_label           = ""               -- ME-mod's heartbeat is the source of truth for state
DCS_SMS.tick_source           = "simulation_frame_only"
DCS_SMS.gui_bridge_enabled    = false            -- hook can't see the ME-env flag; ME-mod's heartbeat is authoritative

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
  -- Pure-Lua JSON for the heartbeat. Keep last_frame / last_frame_at populated
  -- as aliases of last_tick / last_tick_at for one release so older CLIs that
  -- don't know about the new field names still work.
  local payload = string.format(
    '{"hook_version":"%s","state":"%s","mission_loaded":%s,"mission_name":"%s",' ..
    '"gui_bridge_enabled":%s,"tick_source":"%s",' ..
    '"last_tick":%d,"last_tick_at":"%s",' ..
    '"last_frame":%d,"last_frame_at":"%s"}',
    DCS_SMS.version,
    DCS_SMS.state_label,
    tostring(DCS_SMS.mission_loaded),
    escape_json_string(DCS_SMS.mission_name),
    tostring(DCS_SMS.gui_bridge_enabled == true),
    DCS_SMS.tick_source,
    DCS_SMS.tick, iso_now(),
    DCS_SMS.tick, iso_now()
  )
  write_atomic(DCS_SMS.state .. "hook.json", payload)
  DCS_SMS.last_heartbeat_tick = DCS_SMS.tick
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

-- build_wrapper takes the user's Lua snippet and produces a chunk that runs
-- in the mission env. The wrapper:
--   * captures print() output
--   * runs the snippet under xpcall to get a traceback on error
--   * encodes the result as JSON in pure Lua (no net.lua2json dependency,
--     because that function isn't reliably present in the mission env)
--   * writes the response file directly to the outbox via io.open + rename
--     (relies on the user having un-sanitized io/os in MissionScripting.lua)
--
-- This avoids the previous architecture of stashing the JSON in a global
-- and fetching it via a second net.dostring_in call — `dostring_in` doesn't
-- reliably pass non-trivial values across the env boundary.
-- build_wrapper produces the Lua chunk we send via net.dostring_in('mission').
-- Architecture:
--
--   net.dostring_in('mission', code)
--     ↓
--   Server-side scripting state  ← env/trigger/io NOT here
--     ↓ a_do_script(inner)
--   Real mission scripting env   ← env/trigger/io ARE here
--
-- net.dostring_in lands in DCS's server-side scripting state, which doesn't
-- have access to the mission scripting environment. To reach the mission
-- scripting env (where env, trigger, io, etc. are visible), the code must
-- call a_do_script(...) which forwards a string to be executed there. This
-- is the same indirection dcs_code_injector uses.
local function build_wrapper(req_id, frame, user_code, outbox_path)
  -- The inner chunk runs in the real mission scripting env. It captures
  -- print, runs the user's snippet under xpcall, encodes the response as
  -- JSON in pure Lua (no net.lua2json dependency), and writes the response
  -- file directly via io.open + os.rename.
  local inner = string.format([[
do
  local __id     = %q
  local __frame  = %d
  local __outbox = %q
  local __start  = os.clock()
  local __out    = {}

  local __orig_print = print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    __out[#__out+1] = table.concat(parts, '\t')
  end

  local __ok, __ret = xpcall(function()
%s
  end, debug.traceback)

  print = __orig_print
  local __dur = (os.clock() - __start) * 1000

  -- Pure-Lua JSON encoder for our response shape. Handles nil, booleans,
  -- numbers, strings, arrays, and string-keyed tables.
  local function __jstr(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    s = s:gsub("[%%z\1-\31]", function(c) return string.format("\\u%%04x", string.byte(c)) end)
    return '"' .. s .. '"'
  end
  local function __jval(v)
    if v == nil then return "null" end
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then return "null" end
      if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%%d", v)
      end
      return string.format("%%.6g", v)
    end
    if t == "string" then return __jstr(v) end
    if t == "table" then
      local n = 0
      local is_array = true
      for k in pairs(v) do
        n = n + 1
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then is_array = false end
      end
      if is_array and n == #v then
        local parts = {}
        for i = 1, n do parts[i] = __jval(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
      end
      local parts = {}
      for k, val in pairs(v) do
        parts[#parts+1] = __jstr(k) .. ":" .. __jval(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
  end

  -- Preserve Lua false in the response. The naive `(__ok and __ret) or nil`
  -- short-circuits Lua false to nil before JSON encoding, making `return false`
  -- and `return nil` indistinguishable to callers. Use a plain conditional so
  -- false is forwarded to the JSON encoder (which serializes it as `false`).
  local __return_value = nil
  if __ok then __return_value = __ret end

  local __resp = {
    id             = __id,
    ok             = __ok,
    output         = table.concat(__out, '\n'),
    return_value   = __return_value,
    error          = (not __ok) and { message = tostring(__ret), traceback = "" } or nil,
    frame_executed = __frame,
    duration_ms    = __dur,
  }

  local __json_ok, __json_or_err = pcall(__jval, __resp)
  if not __json_ok then
    if env and env.error then env.error("dcs-sms: json encode failed: " .. tostring(__json_or_err)) end
    return
  end
  local __json = __json_or_err

  -- Atomic write: tmp + rename. Mission env has io because the user has
  -- commented out the sanitizeModule lines in MissionScripting.lua.
  if not io or not io.open then
    if env and env.error then env.error("dcs-sms: io is not available — check MissionScripting.lua") end
    return
  end
  local __tmp = __outbox .. ".tmp"
  local __f, __ferr = io.open(__tmp, "wb")
  if not __f then
    if env and env.error then env.error("dcs-sms: io.open failed: " .. tostring(__ferr)) end
    return
  end
  __f:write(__json)
  __f:close()
  local __rok = os.rename(__tmp, __outbox)
  if not __rok then
    -- Fallback: delete target then retry (older Windows behavior).
    os.remove(__outbox)
    os.rename(__tmp, __outbox)
  end
end
]], req_id, frame, outbox_path, user_code)
  -- Wrap inner in a_do_script(...) so it lands in the real mission env.
  -- Long-bracket level 4 ([====[ ]====]) avoids collisions with any [===[
  -- that might appear inside inner or user code.
  return "a_do_script([====[\n" .. inner .. "\n]====])\n"
end

local function parse_request_id_from_filename(name)
  -- "abc-123.req.json" -> "abc-123"
  return name:match("^(.+)%.req%.json$")
end

-- write_response_file writes <id>.res.json atomically. Used by the gui-target
-- path which builds the response in Lua-land directly (the mission-target
-- path's wrapper writes its own response from inside the mission env).
local function write_response_file(req_id, ok, return_value, output, error_table, duration_ms)
  -- Pure-Lua JSON encoder shared with the mission-env wrapper. Keep in sync
  -- with build_wrapper's __jstr / __jval.
  local function jstr(s)
    s = tostring(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    s = s:gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", string.byte(c)) end)
    return '"' .. s .. '"'
  end
  local function jval(v)
    if v == nil then return "null" end
    local t = type(v)
    if t == "boolean" then return tostring(v) end
    if t == "number" then
      if v ~= v or v == math.huge or v == -math.huge then return "null" end
      if v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format("%d", v)
      end
      return string.format("%.6g", v)
    end
    if t == "string" then return jstr(v) end
    if t == "table" then
      local n, is_array = 0, true
      for k in pairs(v) do
        n = n + 1
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then is_array = false end
      end
      if is_array and n == #v then
        local parts = {}
        for i = 1, n do parts[i] = jval(v[i]) end
        return "[" .. table.concat(parts, ",") .. "]"
      end
      local parts = {}
      for k, val in pairs(v) do
        parts[#parts+1] = jstr(k) .. ":" .. jval(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
  end

  local resp = {
    id             = req_id,
    ok             = ok,
    output         = output or "",
    return_value   = return_value,
    error          = error_table,
    frame_executed = DCS_SMS.tick,
    duration_ms    = duration_ms or 0,
  }
  local outbox_path = DCS_SMS.outbox .. req_id .. ".res.json"
  local ok_enc, json_or_err = pcall(jval, resp)
  if not ok_enc then
    log.write("dcs-sms", log.ERROR, "json encode failed for " .. tostring(req_id) .. ": " .. tostring(json_or_err))
    return
  end
  local tmp = outbox_path .. ".tmp"
  local f, ferr = io.open(tmp, "wb")
  if not f then
    log.write("dcs-sms", log.ERROR, "open " .. tmp .. ": " .. tostring(ferr))
    return
  end
  f:write(json_or_err)
  f:close()
  local ok_rn = os.rename(tmp, outbox_path)
  if not ok_rn then
    os.remove(outbox_path)
    os.rename(tmp, outbox_path)
  end
end

-- execute_mission runs the user's snippet in the sandboxed mission scripting
-- env via net.dostring_in('mission', wrapper) + a_do_script(...). This is the
-- original 0.1.0 path. Now also writes an error response if the mission isn't
-- running, so callers don't time out waiting for a response that never comes.
local function execute_mission(req_id, code)
  if not DCS_SMS.mission_loaded then
    write_response_file(req_id, false, nil, "", {
      message   = "target=mission requested but no mission is running — load a mission or use --target gui",
      traceback = "",
    }, 0)
    return
  end
  local outbox_path = DCS_SMS.outbox .. req_id .. ".res.json"
  local wrapper = build_wrapper(req_id, DCS_SMS.tick, code, outbox_path)
  local ok_out, err_out = pcall(net.dostring_in, 'mission', wrapper)
  if not ok_out then
    log.write("dcs-sms", log.ERROR, "wrapper exec failed for " .. req_id .. ": " .. tostring(err_out))
    write_response_file(req_id, false, nil, "", {
      message   = "wrapper exec failed: " .. tostring(err_out),
      traceback = "",
    }, 0)
  end
end

local function execute_request(filename)
  local req_path = DCS_SMS.inbox .. filename
  local raw = read_file(req_path)
  if not raw then return end

  local req_id = parse_request_id_from_filename(filename)
  local ok, parsed = pcall(net.json2lua, raw)
  if not ok or type(parsed) ~= "table" or type(parsed.code) ~= "string" or not req_id then
    log.write("dcs-sms", log.ERROR, "could not parse request " .. filename
      .. " (" .. tostring(parsed) .. ")")
    os.remove(req_path)
    return
  end
  if type(parsed.id) == "string" and parsed.id ~= "" then
    req_id = parsed.id
  end
  local code = parsed.code
  local target = parsed.target
  if type(target) ~= "string" or target == "" then
    target = "mission"  -- back-compat: legacy requests have no target field
  end

  if target == "mission" then
    execute_mission(req_id, code)
    os.remove(req_path)
  elseif target == "gui" then
    -- The Hooks/ env can't tick outside a sim and can't reach the editable
    -- mission table. The ME-mod's bridge.lua handles target=gui from the ME
    -- env. Leave the request file in the inbox so bridge.lua can pick it up.
    -- (sweep_stale removes orphans if no ME-mod is running.)
    return
  else
    write_response_file(req_id, false, nil, "", {
      message   = "unknown target: " .. tostring(target),
      traceback = "",
    }, 0)
    os.remove(req_path)
  end
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
  DCS_SMS.state_label = "in_mission"
  DCS_SMS.mission_name = (DCS and DCS.getMissionName and DCS.getMissionName()) or ""
  pcall(sweep_stale, DCS_SMS.inbox, ".req.json")
  pcall(sweep_stale, DCS_SMS.outbox, ".res.json")
  write_heartbeat()
  log.write("dcs-sms", log.INFO, "mission loaded: " .. DCS_SMS.mission_name)
end

function handler.onSimulationFrame()
  DCS_SMS.tick = DCS_SMS.tick + 1
  if DCS_SMS.mission_loaded then
    pcall(process_inbox)
  end
  if DCS_SMS.tick - DCS_SMS.last_heartbeat_tick >= DCS_SMS.heartbeat_every_frames then
    pcall(write_heartbeat)
  end
end

function handler.onSimulationStop()
  DCS_SMS.mission_loaded = false
  DCS_SMS.state_label = ""
  pcall(write_heartbeat)
  log.write("dcs-sms", log.INFO, "simulation stopped")
end

local function init()
  ensure_dirs()
  write_heartbeat()
  DCS.setUserCallbacks(handler)
  log.write("dcs-sms", log.INFO, "hook loaded v" .. DCS_SMS.version
    .. " (tick_source=simulation_frame_only — ME-side bridge handles target=gui)")
end

local ok, err = pcall(init)
if not ok then
  log.write("dcs-sms", log.ERROR, "init failed: " .. tostring(err))
end
