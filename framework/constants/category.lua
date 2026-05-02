-- dcs-sms framework: category constants (sms.constants.category / sms.K.category).
--
-- DCS group categories on the wire are the lowercase strings "airplane",
-- "helicopter", "ground", "ship", "train". The framework uses these
-- strings for category dispatch (set_option ROE, _sms_air_only, etc.).
-- Mission code uses sms.K.category.AIRPLANE etc. instead of magic strings.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/category.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.category
---@field AIRPLANE   "airplane"
---@field HELICOPTER "helicopter"
---@field GROUND     "ground"
---@field SHIP       "ship"
---@field TRAIN      "train"
sms.constants.category = sms.constants.category or {}

---@alias sms.Category
---| "airplane"
---| "helicopter"
---| "ground"
---| "ship"
---| "train"

sms.constants.category.AIRPLANE   = "airplane"
sms.constants.category.HELICOPTER = "helicopter"
sms.constants.category.GROUND     = "ground"
sms.constants.category.SHIP       = "ship"
sms.constants.category.TRAIN      = "train"
