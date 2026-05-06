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

-- CONSTANTS_DIR_FALLBACK is only consulted when this file is loaded
-- without a chunkname (the bridge / net.dostring_in path). Most callers
-- come through load_all.lua → dofile, where derive_dir succeeds. If you
-- hit the fallback, set _SMS_FRAMEWORK_DIR before loading or edit the
-- value below to your framework checkout (see load_all.lua header for
-- the full background).
local CONSTANTS_DIR_FALLBACK = nil  -- e.g. "D:/path/to/dcs-sms/framework/constants/"

local CONSTANTS_DIR = (function()
  local src = (debug.getinfo(1, "S") or {}).source or ""
  local dir = src:match("^@(.*[/\\])constants%.lua$")
  if dir then return dir .. "constants/" end
  if _SMS_FRAMEWORK_DIR then return _SMS_FRAMEWORK_DIR .. "constants/" end
  return CONSTANTS_DIR_FALLBACK
end)()
if not CONSTANTS_DIR then
  error("sms.constants: could not derive constants directory.\n" ..
        "  This usually means constants.lua was loaded without a chunkname.\n" ..
        "  Set _SMS_FRAMEWORK_DIR before loading, or edit CONSTANTS_DIR_FALLBACK\n" ..
        "  in framework/constants.lua. (See framework/load_all.lua for the full\n" ..
        "  background — same issue, same set of workarounds.)")
end

-- Topic files are listed alphabetically so a diff between commits shows
-- exactly which topic was added without reordering noise.
local topics = {
  "alarm_state.lua",
  "alt_type.lua",
  "category.lua",
  "coalition.lua",
  "countries.lua",
  "designations.lua",
  "flare_using.lua",
  "formation.lua",
  "radar_using.lua",
  "reaction_on_threat.lua",
  "roe.lua",
  "skill.lua",
  "statics.lua",
  "targets.lua",
  "units.lua",
  "waypoint.lua",
}

for _, name in ipairs(topics) do
  dofile(CONSTANTS_DIR .. name)
end

-- Short alias: sms.K is the documented shorthand. Both names point at the
-- same table; mission code uses sms.K, framework internals use sms.K too.
sms.K = sms.constants
