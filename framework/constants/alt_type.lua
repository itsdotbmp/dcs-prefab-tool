-- dcs-sms framework: alt_type module (sms.constants.alt_type / sms.K.alt_type).
--
-- Hand-maintained enum of DCS waypoint altitude-reference strings.
-- Mission code uses sms.K.alt_type.BARO / sms.K.alt_type.RADIO instead of
-- magic strings:
--
--     local wp = {x=1234, y=0, z=5678, alt=4500, alt_type=sms.K.alt_type.BARO, ...}
--
-- BARO is altitude above mean sea level (the most common altitude
-- reference for aircraft). RADIO is altitude above ground level (radar
-- altimeter), used for terrain-following or low-level routing.
--
-- The sms.AltType alias enables LuaCATS autocomplete on raw-string
-- usage (alt_type = "BARO"). The alt_type field on sms.group.unit_spec
-- is annotated sms.AltType|string so both forms are typo-checkable.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/alt_type.lua.
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",          "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",      "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table","framework/constants.lua must be loaded first")

local log = sms.log.module("sms.constants.alt_type")

---@class sms.constants.alt_type
---@field BARO  "BARO"
---@field RADIO "RADIO"
sms.constants.alt_type = sms.constants.alt_type or {}

---@alias sms.AltType
---| "BARO"
---| "RADIO"

sms.constants.alt_type.BARO  = "BARO"
sms.constants.alt_type.RADIO = "RADIO"
