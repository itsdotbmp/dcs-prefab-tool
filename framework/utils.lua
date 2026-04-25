-- dcs-sms utils module. Real module that doubles as the smoke-test
-- exerciser for cross-module logging in v1.

assert(sms, "framework/sms.lua must be loaded first")
local log = sms.log.module()       -- auto-tagged as "sms.utils"
sms.utils = sms.utils or {}

sms.utils.add_numbers = function(a, b)
  log.info("add_numbers(" .. tostring(a) .. ", " .. tostring(b) .. ")")
  return a + b
end
