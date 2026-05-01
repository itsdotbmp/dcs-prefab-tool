-- dcs-sms framework: constants module (sms.constants, alias sms.K).
--
-- Single namespace for every enum-shaped public table in the framework:
-- countries, skill, alt_type, waypoint type / action, targets, designations,
-- ROE, alarm-state, formation, reaction-on-threat, radar-using, flare-using,
-- coalition, category, plus the auto-generated unit and static catalogs.
--
-- Each topic lives in framework/constants/<topic>.lua. This entry point
-- dofiles every topic file and finally aliases sms.K = sms.constants so
-- mission code can write sms.K.units.armor.apc.AAV7 instead of the long
-- form sms.constants.units.armor.apc.AAV7.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua.
-- Topic files load inside this file in alphabetical order; cross-topic
-- dependencies do not exist (each topic is a self-contained table).
--
-- See docs/api/constants.md for the per-topic reference.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

---@class sms.constants
sms.constants = sms.constants or {}

local CONSTANTS_DIR_FALLBACK = "D:/git/dcs-sms/framework/constants/"

local CONSTANTS_DIR = (function()
  local src = (debug.getinfo(1, "S") or {}).source or ""
  local dir = src:match("^@(.*[/\\])constants%.lua$")
  return dir and (dir .. "constants/") or CONSTANTS_DIR_FALLBACK
end)()

-- Topic files are added by subsequent tasks. List is alphabetical so a
-- diff between commits shows exactly which topic was added without
-- reordering noise. No file means no dofile — Task 1 has none yet.
local topics = {
  "alt_type.lua",
  "countries.lua",
  "designations.lua",
  "skill.lua",
  "targets.lua",
  "waypoint.lua",
}

for _, name in ipairs(topics) do
  dofile(CONSTANTS_DIR .. name)
end

-- Short alias: sms.K is the documented shorthand. Both names point at the
-- same table; mission code uses sms.K, framework internals use sms.K too.
sms.K = sms.constants
