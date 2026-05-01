-- dcs-sms framework: reaction_on_threat constants (sms.constants.reaction_on_threat /
-- sms.K.reaction_on_threat). Consumed by sms.options.reaction_on_threat(value).
-- Air-only -- see the builder for category enforcement.
--
-- Example:
--   cap:set_option(sms.options.reaction_on_threat(sms.K.reaction_on_threat.EVADE_FIRE))
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/reaction_on_threat.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.reaction_on_threat
---@field NO_REACTION         "no_reaction"
---@field PASSIVE_DEFENCE     "passive_defence"
---@field EVADE_FIRE          "evade_fire"
---@field BYPASS_AND_ESCAPE   "bypass_and_escape"
---@field ALLOW_ABORT_MISSION "allow_abort_mission"
sms.constants.reaction_on_threat = sms.constants.reaction_on_threat or {}

sms.constants.reaction_on_threat.NO_REACTION         = "no_reaction"
sms.constants.reaction_on_threat.PASSIVE_DEFENCE     = "passive_defence"
sms.constants.reaction_on_threat.EVADE_FIRE          = "evade_fire"
sms.constants.reaction_on_threat.BYPASS_AND_ESCAPE   = "bypass_and_escape"
sms.constants.reaction_on_threat.ALLOW_ABORT_MISSION = "allow_abort_mission"
