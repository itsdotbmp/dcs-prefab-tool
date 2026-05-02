-- dcs-sms framework: alarm_state constants (sms.constants.alarm_state /
-- sms.K.alarm_state). Consumed by sms.options.alarm_state(value).
--
-- Example:
--   sa6:set_option(sms.options.alarm_state(sms.K.alarm_state.RED))
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/alarm_state.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.alarm_state
---@field AUTO  "auto"
---@field GREEN "green"
---@field RED   "red"
sms.constants.alarm_state = sms.constants.alarm_state or {}

sms.constants.alarm_state.AUTO  = "auto"
sms.constants.alarm_state.GREEN = "green"
sms.constants.alarm_state.RED   = "red"
