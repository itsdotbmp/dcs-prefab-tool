-- dcs-sms framework: one-shot loader for every module, in dependency order.
-- Run this once to bring up the whole framework, or re-run it to reload
-- every module after edits.
--
-- Two ways to invoke:
--   1. From a mission script:
--        dofile("D:/git/dcs-sms/framework/load_all.lua")
--   2. Via the bridge:
--        dcs-sms exec --file framework/load_all.lua
--
-- The directory is auto-derived when this file is loaded via dofile (the
-- chunkname is "@.../framework/load_all.lua"). When loaded via the bridge,
-- net.dostring_in does not set a chunkname, so the FALLBACK_DIR below is
-- used instead. Edit FALLBACK_DIR if the repo lives somewhere else.

local FALLBACK_DIR = "D:/git/dcs-sms/framework/"

local function derive_dir()
  local src = (debug.getinfo(1, "S") or {}).source or ""
  local dir = src:match("^@(.*[/\\])load_all%.lua$")
  return dir
end

local FRAMEWORK_DIR = derive_dir() or FALLBACK_DIR

local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "group.lua",
  "unit.lua",
  "area.lua",
  "timer.lua",
  "group_spawn.lua",
  "static.lua",
  "events.lua",
  "weapon.lua",
  "task.lua",
}

for _, name in ipairs(modules) do
  dofile(FRAMEWORK_DIR .. name)
end

env.info("[sms] framework loaded ("
  .. #modules .. " modules, version " .. tostring(sms and sms.version) .. ")")
