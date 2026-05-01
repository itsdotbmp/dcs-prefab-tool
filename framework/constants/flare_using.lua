-- dcs-sms framework: flare_using constants (sms.constants.flare_using /
-- sms.K.flare_using). Consumed by sms.options.flare_using(value).
-- Air-only -- see the builder for category enforcement.
--
-- Example:
--   cap:set_option(sms.options.flare_using(sms.K.flare_using.AGAINST_FIRED_MISSILE))
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/flare_using.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.flare_using
---@field NEVER                    "never"
---@field AGAINST_FIRED_MISSILE    "against_fired_missile"
---@field WHEN_FLYING_IN_SAM_WEZ   "when_flying_in_sam_wez"
---@field WHEN_FLYING_NEAR_ENEMIES "when_flying_near_enemies"
sms.constants.flare_using = sms.constants.flare_using or {}

sms.constants.flare_using.NEVER                    = "never"
sms.constants.flare_using.AGAINST_FIRED_MISSILE    = "against_fired_missile"
sms.constants.flare_using.WHEN_FLYING_IN_SAM_WEZ   = "when_flying_in_sam_wez"
sms.constants.flare_using.WHEN_FLYING_NEAR_ENEMIES = "when_flying_near_enemies"
