-- dcs-sms framework: skill module (sms.constants.skill / sms.K.skill).
--
-- Hand-maintained enum of DCS unit-skill strings. Mission code uses
-- sms.K.skill.<KEY> instead of magic strings:
--
--     sms.group.create({
--       units = { {type = sms.units.planes.F_16C_50, skill = sms.K.skill.AVERAGE} },
--       ...
--     })
--
-- Values are the verbatim DCS strings ("Average", "Good", "High",
-- "Excellent", "Random"). PLAYER and CLIENT are special placeholder
-- skills DCS recognizes for unit slots that mark a unit as
-- human-controllable (player aircraft / multiplayer clients).
--
-- The sms.Skill alias enables LuaCATS autocomplete on raw-string
-- usage (skill = "Average"). The skill field on sms.group.unit_spec
-- is annotated sms.Skill|string so both forms are typo-checkable.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/skill.lua. No runtime drift check (no DCS-global to introspect).
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",          "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",      "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table","framework/constants.lua must be loaded first")

local log = sms.log.module("sms.constants.skill")

---@class sms.constants.skill
---@field AVERAGE   "Average"
---@field GOOD      "Good"
---@field HIGH      "High"
---@field EXCELLENT "Excellent"
---@field RANDOM    "Random"
---@field PLAYER    "Player"
---@field CLIENT    "Client"
sms.constants.skill = sms.constants.skill or {}

---@alias sms.Skill
---| "Average"
---| "Good"
---| "High"
---| "Excellent"
---| "Random"
---| "Player"
---| "Client"

sms.constants.skill.AVERAGE   = "Average"
sms.constants.skill.GOOD      = "Good"
sms.constants.skill.HIGH      = "High"
sms.constants.skill.EXCELLENT = "Excellent"
sms.constants.skill.RANDOM    = "Random"
sms.constants.skill.PLAYER    = "Player"
sms.constants.skill.CLIENT    = "Client"
