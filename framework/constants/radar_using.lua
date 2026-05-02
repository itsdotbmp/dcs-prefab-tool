-- dcs-sms framework: radar_using constants (sms.constants.radar_using /
-- sms.K.radar_using). Consumed by sms.options.radar_using(value).
-- Air-only -- see the builder for category enforcement.
--
-- Example:
--   cap:set_option(sms.options.radar_using(sms.K.radar_using.FOR_ATTACK_ONLY))
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/radar_using.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.radar_using
---@field NEVER                  "never"
---@field FOR_ATTACK_ONLY        "for_attack_only"
---@field FOR_SEARCH_IF_REQUIRED "for_search_if_required"
---@field FOR_CONTINUOUS_SEARCH  "for_continuous_search"
sms.constants.radar_using = sms.constants.radar_using or {}

sms.constants.radar_using.NEVER                  = "never"
sms.constants.radar_using.FOR_ATTACK_ONLY        = "for_attack_only"
sms.constants.radar_using.FOR_SEARCH_IF_REQUIRED = "for_search_if_required"
sms.constants.radar_using.FOR_CONTINUOUS_SEARCH  = "for_continuous_search"
