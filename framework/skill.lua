-- dcs-sms framework: skill module (sms.skill).
--
-- Hand-maintained enum of DCS unit-skill strings. Mission code uses
-- sms.skill.<KEY> instead of magic strings:
--
--     sms.group.create({
--       units = { {type = sms.units.planes.F_16C_50, skill = sms.skill.AVERAGE} },
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
-- Loading order: sms.lua -> log.lua -> utils.lua -> countries.lua ->
-- skill.lua. No runtime drift check (no DCS-global to introspect).
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

local log = sms.log.module("sms.skill")

---@class sms.skill
---@field AVERAGE   "Average"
---@field GOOD      "Good"
---@field HIGH      "High"
---@field EXCELLENT "Excellent"
---@field RANDOM    "Random"
---@field PLAYER    "Player"
---@field CLIENT    "Client"
sms.skill = sms.skill or {}

---@alias sms.Skill
---| "Average"
---| "Good"
---| "High"
---| "Excellent"
---| "Random"
---| "Player"
---| "Client"

sms.skill.AVERAGE   = "Average"
sms.skill.GOOD      = "Good"
sms.skill.HIGH      = "High"
sms.skill.EXCELLENT = "Excellent"
sms.skill.RANDOM    = "Random"
sms.skill.PLAYER    = "Player"
sms.skill.CLIENT    = "Client"
