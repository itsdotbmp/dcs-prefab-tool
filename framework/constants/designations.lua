-- dcs-sms framework: designations module (sms.constants.designations / sms.K.designations).
--
-- Named constants for DCS FAC designation enum strings used by FAC
-- task builders (sms.task.fac_attack_group, sms.task.fac_engage_group).
-- Constants resolve to plain strings; builders accept either the
-- constants (recommended) or raw strings.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/designations.lua.

assert(type(sms) == "table",          "framework/sms.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.designations
---@field NO         string  # "No"          — no designation
---@field AUTO       string  # "Auto"        — auto-select designation
---@field WP         string  # "WP"          — white phosphorus marker
---@field IR_POINTER string  # "IR-Pointer"  — IR pointer designation
---@field LASER      string  # "Laser"       — laser designation
sms.constants.designations = sms.constants.designations or {}

sms.constants.designations.NO         = "No"
sms.constants.designations.AUTO       = "Auto"
sms.constants.designations.WP         = "WP"          -- white phosphorus marker
sms.constants.designations.IR_POINTER = "IR-Pointer"
sms.constants.designations.LASER      = "Laser"
