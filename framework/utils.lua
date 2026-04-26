-- dcs-sms utils module. Real module that doubles as the smoke-test
-- exerciser for cross-module logging in v1.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
-- Explicit tag because in v1 the framework is bridge-loaded
-- (net.dostring_in), and `debug.getinfo(2, "S").source` for those chunks
-- is the wrapper source, not "@.../utils.lua". When mechanism C/A lands
-- and modules are loaded via dofile, the no-arg form will auto-derive.
-- The auto-derived tag will also be "sms.utils" (basename + "sms." prefix),
-- so the migration is a one-line swap with no log-output change.
local log = sms.log.module("sms.utils")
sms.utils = sms.utils or {}

sms.utils.add_numbers = function(a, b)
  log.info("add_numbers(" .. tostring(a) .. ", " .. tostring(b) .. ")")
  return a + b
end

-- Heading conversion: framework public input is degrees, DCS API is radians.
sms.utils.deg_to_rad = function(deg)
  if type(deg) ~= "number" then
    log.error("deg_to_rad: argument must be a number, got " .. type(deg))
    return nil
  end
  return deg * math.pi / 180
end

sms.utils.rad_to_deg = function(rad)
  if type(rad) ~= "number" then
    log.error("rad_to_deg: argument must be a number, got " .. type(rad))
    return nil
  end
  return rad * 180 / math.pi
end

-- Altitude conversion: framework I/O is meters (DCS-native), but pilots
-- think in feet — these helpers are for user code, not internal.
sms.utils.feet_to_meters = function(ft)
  if type(ft) ~= "number" then
    log.error("feet_to_meters: argument must be a number, got " .. type(ft))
    return nil
  end
  return ft * 0.3048
end

sms.utils.meters_to_feet = function(m)
  if type(m) ~= "number" then
    log.error("meters_to_feet: argument must be a number, got " .. type(m))
    return nil
  end
  return m / 0.3048
end
