-- dcs-sms framework: formation constants (sms.constants.formation /
-- sms.K.formation). Consumed by sms.options.formation(value).
-- Air-only -- see the builder for category enforcement. The builder also
-- accepts a raw DCS packed integer as an escape hatch for unlisted presets.
--
-- Example:
--   cap:set_option(sms.options.formation(sms.K.formation.WEDGE))
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/formation.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.formation
---@field LINE_ABREAST  "line_abreast"
---@field TRAIL         "trail"
---@field WEDGE         "wedge"
---@field ECHELON_RIGHT "echelon_right"
---@field ECHELON_LEFT  "echelon_left"
---@field FINGER_FOUR   "finger_four"
---@field SPREAD        "spread"
sms.constants.formation = sms.constants.formation or {}

sms.constants.formation.LINE_ABREAST  = "line_abreast"
sms.constants.formation.TRAIL         = "trail"
sms.constants.formation.WEDGE         = "wedge"
sms.constants.formation.ECHELON_RIGHT = "echelon_right"
sms.constants.formation.ECHELON_LEFT  = "echelon_left"
sms.constants.formation.FINGER_FOUR   = "finger_four"
sms.constants.formation.SPREAD        = "spread"
