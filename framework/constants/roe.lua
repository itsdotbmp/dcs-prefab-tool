-- dcs-sms framework: ROE constants (sms.constants.roe / sms.K.roe).
--
-- ROE strings consumed by the sms.options.roe(value) builder. The builder
-- is responsible for category-specific validation (some values are
-- air-only) -- this table just lists every value the framework recognises.
--
-- Example:
--   cap:set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/roe.lua.
--
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",       "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.roe
---@field WEAPON_FREE           "weapon_free"
---@field OPEN_FIRE_WEAPON_FREE "open_fire_weapon_free"
---@field OPEN_FIRE             "open_fire"
---@field RETURN_FIRE           "return_fire"
---@field WEAPON_HOLD           "weapon_hold"
sms.constants.roe = sms.constants.roe or {}

sms.constants.roe.WEAPON_FREE           = "weapon_free"
sms.constants.roe.OPEN_FIRE_WEAPON_FREE = "open_fire_weapon_free"
sms.constants.roe.OPEN_FIRE             = "open_fire"
sms.constants.roe.RETURN_FIRE           = "return_fire"
sms.constants.roe.WEAPON_HOLD           = "weapon_hold"
