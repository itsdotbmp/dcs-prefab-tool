-- dcs-sms framework: designations module (sms.designations).
--
-- Named constants for DCS FAC designation enum strings used by FAC
-- task builders (sms.task.fac_attack_group, sms.task.fac_engage_group).
-- Constants resolve to plain strings; builders accept either the
-- constants (recommended) or raw strings.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> designations.lua.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
sms.designations = sms.designations or {}

sms.designations.NO         = "No"
sms.designations.AUTO       = "Auto"
sms.designations.WP         = "WP"          -- white phosphorus marker
sms.designations.IR_POINTER = "IR-Pointer"
sms.designations.LASER      = "Laser"
