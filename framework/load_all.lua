-- dcs-sms framework: one-shot loader for every module, in dependency order.
-- Run this once to bring up the whole framework, or re-run it to reload
-- every module after edits.
--
-- Two ways to invoke:
--   1. From a mission script:
--        dofile("<path-to-dcs-sms>/framework/load_all.lua")
--   2. Via the bridge:
--        dcs-sms exec --file framework/load_all.lua
--
-- The directory is auto-derived when this file is loaded via dofile (the
-- chunkname is "@.../framework/load_all.lua"). When loaded via the bridge
-- (`dcs-sms exec --file framework/load_all.lua`), net.dostring_in does not
-- set a chunkname, so derive_dir() returns nil and we fall back to either:
--   1. _SMS_FRAMEWORK_DIR (a global the caller may set), or
--   2. FALLBACK_DIR (edit below to point at your local framework checkout).
-- If neither is set, the loader errors with a clear message rather than
-- silently using a wrong path.

local FALLBACK_DIR = nil  -- e.g. "D:/path/to/dcs-sms/framework/"

local function derive_dir()
  local src = (debug.getinfo(1, "S") or {}).source or ""
  local dir = src:match("^@(.*[/\\])load_all%.lua$")
  return dir
end

local FRAMEWORK_DIR = derive_dir() or _SMS_FRAMEWORK_DIR or FALLBACK_DIR
if not FRAMEWORK_DIR then
  error("sms framework loader: could not auto-derive framework directory.\n" ..
        "  This usually means you loaded via `dcs-sms exec --file` or net.dostring_in,\n" ..
        "  neither of which sets a Lua chunkname. To fix:\n" ..
        "    a) load via dofile() with the full path:\n" ..
        "       dofile('<path-to-dcs-sms>/framework/load_all.lua')\n" ..
        "    b) set _SMS_FRAMEWORK_DIR before loading:\n" ..
        "       _SMS_FRAMEWORK_DIR = '<path-to-dcs-sms>/framework/'\n" ..
        "    c) edit FALLBACK_DIR at the top of load_all.lua")
end

local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "constants.lua",
  "group.lua",
  "unit.lua",
  "area.lua",
  "timer.lua",
  "rule.lua",
  "group_spawn.lua",
  "static.lua",
  "events.lua",
  "weapon.lua",
  "task.lua",
  "commands.lua",
  "options.lua",
  "utils_serialize.lua",
  "prefab_distill.lua",
  "prefab.lua",
}

for _, name in ipairs(modules) do
  dofile(FRAMEWORK_DIR .. name)
end

env.info("[sms] framework loaded ("
  .. #modules .. " modules, version " .. tostring(sms and sms.version) .. ")")
