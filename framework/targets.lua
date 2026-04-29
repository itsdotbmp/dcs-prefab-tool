-- dcs-sms framework: targets module (sms.targets).
--
-- Named constants for DCS target attribute strings used by enroute
-- engagement tasks (sms.task.engage_en_route_*, sms.task.escort, etc.).
-- Constants resolve to plain strings; builders accept either the
-- constants (recommended) or raw strings (forward-compat for new DCS
-- attributes the framework hasn't catalogued yet).
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> targets.lua.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")

---@class sms.targets
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
sms.targets = sms.targets or {}

sms.targets.AIR             = "Air"
sms.targets.PLANES          = "Planes"
sms.targets.HELICOPTERS     = "Helicopters"
sms.targets.GROUND_UNITS    = "Ground Units"
sms.targets.GROUND_VEHICLES = "Ground vehicles"
sms.targets.SHIPS           = "Ships"
sms.targets.AIR_DEFENCE     = "Air Defence"
sms.targets.SAM             = "SAM"
sms.targets.AAA             = "AAA"
sms.targets.STATICS         = "Static"
sms.targets.BUILDINGS       = "Buildings"
sms.targets.ALL             = "All"
