-- dcs-sms utils module. Real module that doubles as the smoke-test
-- exerciser for cross-module logging in v1.

assert(sms, "framework/sms.lua must be loaded first")
-- Explicit tag because in v1 the framework is bridge-loaded
-- (net.dostring_in), and `debug.getinfo(2, "S").source` for those chunks
-- is the wrapper source, not "@.../utils.lua". When mechanism C/A lands
-- and modules are loaded via dofile, the no-arg form will auto-derive.
local log = sms.log.module("sms.utils")
sms.utils = sms.utils or {}

sms.utils.add_numbers = function(a, b)
  log.info("add_numbers(" .. tostring(a) .. ", " .. tostring(b) .. ")")
  return a + b
end
