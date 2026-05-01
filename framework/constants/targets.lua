-- dcs-sms framework: targets module (sms.constants.targets / sms.K.targets).
--
-- Named constants for DCS target attribute strings used by enroute
-- engagement tasks (sms.task.engage_en_route_*, sms.task.escort, etc.).
-- Constants resolve to plain strings; builders accept either the
-- constants (recommended) or raw strings (forward-compat for new DCS
-- attributes the framework hasn't catalogued yet).
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/targets.lua.

assert(type(sms) == "table",          "framework/sms.lua must be loaded first")
assert(type(sms.constants) == "table","framework/constants.lua must be loaded first")

---@class sms.constants.targets
---@field AIR             "Air"
---@field PLANES          "Planes"
---@field HELICOPTERS     "Helicopters"
---@field GROUND_UNITS    "Ground Units"
---@field GROUND_VEHICLES "Ground vehicles"
---@field SHIPS           "Ships"
---@field AIR_DEFENCE     "Air Defence"
---@field SAM             "SAM"
---@field AAA             "AAA"
---@field STATICS         "Static"
---@field BUILDINGS       "Buildings"
---@field ALL             "All"
sms.constants.targets = sms.constants.targets or {}

sms.constants.targets.AIR             = "Air"
sms.constants.targets.PLANES          = "Planes"
sms.constants.targets.HELICOPTERS     = "Helicopters"
sms.constants.targets.GROUND_UNITS    = "Ground Units"
sms.constants.targets.GROUND_VEHICLES = "Ground vehicles"
sms.constants.targets.SHIPS           = "Ships"
sms.constants.targets.AIR_DEFENCE     = "Air Defence"
sms.constants.targets.SAM             = "SAM"
sms.constants.targets.AAA             = "AAA"
sms.constants.targets.STATICS         = "Static"
sms.constants.targets.BUILDINGS       = "Buildings"
sms.constants.targets.ALL             = "All"
