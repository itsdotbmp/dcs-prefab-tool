-- dcs-sms framework: coalition constants (sms.constants.coalition / sms.K.coalition).
--
-- DCS coalitions on the wire are the lowercase strings "red", "blue",
-- and "neutral". sms.utils.coalition_int_to_str returns one of these.
-- Mission code uses sms.K.coalition.RED etc. instead of magic strings.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/coalition.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.coalition
---@field RED     "red"
---@field BLUE    "blue"
---@field NEUTRAL "neutral"
sms.constants.coalition = sms.constants.coalition or {}

---@alias sms.Coalition
---| "red"
---| "blue"
---| "neutral"

sms.constants.coalition.RED     = "red"
sms.constants.coalition.BLUE    = "blue"
sms.constants.coalition.NEUTRAL = "neutral"
