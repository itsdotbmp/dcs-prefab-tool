-- dcs-sms utils module. Cross-cutting helpers used by every entity-wrapper
-- module in the framework. Pure-functional where possible; failure mode is
-- the framework standard (log via [sms.utils] tag and return nil — never
-- throw).
--
-- Scope is deliberately narrow:
--   - unit conversions (deg/rad, ft/m)
--   - vec3 maths (length, distance)
--   - shared validation/lookup helpers lifted here once 2+ modules needed
--     them (is_vec3, resolve_country, deep_copy, coalition_int_to_str)
--
-- New helpers should land here only when (a) there are real in-tree callers
-- and (b) they are DCS-shaped enough to be worth a public name. We do not
-- aim to be a generic "stdlib" — that bloat is what we are explicitly
-- avoiding. See AGENTS.md for the curation philosophy.

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

-- ============================================================
-- Unit conversions
-- ============================================================

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

-- ============================================================
-- vec3 validation and maths
-- ============================================================

-- Cheap structural check used by every cfg-validation path that takes a
-- vec3 (spawn.create position/offset, static.create position, area
-- is_vec3_in target, etc.). Returns bool — does not log, since callers
-- do their own contextual error message.
sms.utils.is_vec3 = function(v)
  return type(v) == "table"
     and type(v.x) == "number"
     and type(v.y) == "number"
     and type(v.z) == "number"
end

-- Euclidean length of a DCS vec3 (x = north, y = altitude, z = east).
-- Uses 3D length, not horizontal-plane length — vec3 is a full 3D vector
-- and pilots care about vertical speed components too.
sms.utils.vec3_length = function(v)
  if not sms.utils.is_vec3(v) then
    log.error("vec3_length: argument must be a vec3 with x/y/z numbers")
    return nil
  end
  return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Euclidean distance between two DCS vec3s. Pure maths — does not
-- duck-type position-handle arguments. If a caller has a positionable
-- handle, they call :get_position() themselves.
sms.utils.vec3_distance = function(a, b)
  if not sms.utils.is_vec3(a) then
    log.error("vec3_distance: first argument must be a vec3 with x/y/z numbers")
    return nil
  end
  if not sms.utils.is_vec3(b) then
    log.error("vec3_distance: second argument must be a vec3 with x/y/z numbers")
    return nil
  end
  local dx = a.x - b.x
  local dy = a.y - b.y
  local dz = a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ============================================================
-- Heading helpers
-- ============================================================

-- Wrap a heading in degrees to the canonical [0, 360) range. Lua 5.1's
-- modulo is mathematical (not C-style remainder), so a single `% 360`
-- handles negative inputs correctly: -90 % 360 == 270.
sms.utils.normalize_heading = function(deg)
  if type(deg) ~= "number" then
    log.error("normalize_heading: argument must be a number, got " .. type(deg))
    return nil
  end
  return deg % 360
end

-- Compass bearing from one vec3 to another, in degrees, 0 = north,
-- 90 = east (clockwise — DCS convention). Computed on the horizontal
-- plane (xz), ignoring altitude. atan2(east, north) gives heading
-- measured clockwise from north; we then convert and normalize.
sms.utils.bearing_to = function(from, to)
  if not sms.utils.is_vec3(from) then
    log.error("bearing_to: 'from' must be a vec3 with x/y/z numbers")
    return nil
  end
  if not sms.utils.is_vec3(to) then
    log.error("bearing_to: 'to' must be a vec3 with x/y/z numbers")
    return nil
  end
  local dx = to.x - from.x  -- east component
  local dz = to.z - from.z  -- north component
  local heading_rad = math.atan2(dx, dz)
  return sms.utils.normalize_heading(heading_rad * 180 / math.pi)
end

-- ============================================================
-- DCS country / coalition lookup helpers
-- ============================================================

-- Public country string -> DCS country.id integer. Lifted from
-- spawn.lua / static.lua where both modules previously had byte-identical
-- private copies. Case-insensitive; spaces become underscores so users
-- can pass "United Kingdom" and have it resolve to country.id.UNITED_KINGDOM.
-- Returns nil silently on bad input or unknown country — callers craft
-- their own contextual error message ("create: unknown country '...'").
sms.utils.resolve_country = function(s)
  if type(s) ~= "string" then return nil end
  local key = s:upper():gsub(" ", "_")
  return country.id[key]
end

-- DCS coalition int -> normalized lowercase string ("red"|"blue"|"neutral").
-- Lifted from unit/group/static/weapon, all of which kept the same
-- {[0]="neutral", [1]="red", [2]="blue"} table privately. Returns nil
-- silently on unknown int — callers do their own log message with context.
-- Naming follows the X_to_Y convention used by deg_to_rad / feet_to_meters.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}
sms.utils.coalition_int_to_str = function(c)
  return _coalition_str[c]
end

-- ============================================================
-- Table helpers
-- ============================================================

-- Recursive deep copy of a table. Non-table values pass through. Lifted
-- from spawn.lua / static.lua where both kept byte-identical private
-- copies for clone()-style mission-descriptor cloning. Does not preserve
-- metatables (callers building cfg tables don't use them) and does not
-- handle cycles (mission descriptors are trees).
sms.utils.deep_copy = function(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = sms.utils.deep_copy(v)
  end
  return copy
end
