-- dcs-sms framework: group module (sms.group).
--
-- sms.group("name") returns a lightweight handle, or nil + log if the
-- group doesn't exist in DCS. Handles are {name=name} tables with
-- __index = sms.group, so handle:method() dispatches to sms.group.method(handle).
--
-- All methods accept either a handle or a raw name string, normalized at
-- entry. Methods that touch DCS state internally check is_alive first;
-- if the group is not alive, they log and return nil — they never throw.
-- _name_of also accepts garbage input (nil, numbers, ...) and returns nil,
-- which then makes is_alive return false and the standard log+nil path
-- triggers. This protects the framework-wide "never throw" promise even
-- when callers pass bad values.
--
-- get_units() returns sms.unit handles, so sms.unit must be loaded by
-- the time get_units is *called* (not at load time). Loading order:
-- framework/sms.lua -> log.lua -> group.lua -> unit.lua.
--
-- See docs/superpowers/specs/2026-04-25-framework-group-design.md.
-- See docs/superpowers/specs/2026-04-26-framework-unit-design.md (get_units).

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.group")
sms.group = sms.group or {}

-- DCS coalition int -> normalized lowercase string. Lookup now lives in
-- sms.utils.coalition_str_from_int (issue #14).

-- Accept either a handle ({name=...}) or a raw name string; return the name.
-- Returns nil for any other input (nil, number, boolean, table-without-name).
-- Callers handle nil names as "not alive" rather than throwing.
local function _name_of(g)
  if type(g) == "string" then return g end
  if type(g) == "table" and type(g.name) == "string" then return g.name end
  return nil
end

sms.group.is_alive = function(g)
  local name = _name_of(g)
  if not name then return false end
  local obj = Group.getByName(name)
  return obj ~= nil and obj:isExist()
end

sms.group.get_name = function(g)
  return _name_of(g)
end

sms.group.get_coalition = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local c = Group.getByName(name):getCoalition()
  local s = sms.utils.coalition_str_from_int(c)
  if not s then
    log.error("get_coalition: '" .. tostring(name) .. "' returned unknown coalition " .. tostring(c))
    return nil
  end
  return s
end

sms.group.get_position = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_position: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local units = Group.getByName(name):getUnits()
  if not units or #units == 0 then
    log.error("get_position: '" .. tostring(name) .. "' has no units")
    return nil
  end
  local p = units[1]:getPoint()
  -- DCS world coords: x = east, y = altitude, z = north.
  return {x = p.x, y = p.y, z = p.z}
end

sms.group.destroy = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  Group.getByName(name):destroy()
  return true
end

sms.group.get_units = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_units: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local raw = Group.getByName(name):getUnits()
  local handles = {}
  for i, u in ipairs(raw or {}) do
    handles[i] = sms.unit(u:getName())
  end
  return handles
end

-- Sugar constructor: sms.group("name") -> handle | nil + log.
-- The factory lives in sms.lua; this call wires it up using Group.getByName
-- as the existence check.
sms._make_callable_handle(sms.group, Group.getByName, log)
