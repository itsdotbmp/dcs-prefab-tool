-- dcs-sms framework: unit module (sms.unit).
--
-- Second entity wrapper in the framework. Cargo-culted from group.lua.
--
-- sms.unit("name") returns a lightweight handle, or nil + log if the
-- unit doesn't exist in DCS. Handles are {name=name} tables with
-- __index = sms.unit, so handle:method() dispatches to sms.unit.method(handle).
--
-- All methods accept either a handle or a raw name string, normalized at
-- entry. Methods that touch DCS state internally check is_alive first;
-- if the unit is not alive, they log and return nil — they never throw.
-- _name_of also accepts garbage input (nil, numbers, ...) and returns nil,
-- which then makes is_alive return false and the standard log+nil path
-- triggers.
--
-- Loading order: framework/sms.lua -> log.lua -> group.lua -> unit.lua.
-- get_group() returns an sms.group handle, so sms.group must already be
-- loaded by the time get_group is called.
--
-- See docs/superpowers/specs/2026-04-26-framework-unit-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
local log = sms.log.module("sms.unit")
sms.unit = sms.unit or {}

-- DCS coalition int -> normalized lowercase string.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}

-- Accept either a handle ({name=...}) or a raw name string; return the name.
-- Returns nil for any other input (nil, number, boolean, table-without-name).
-- Callers handle nil names as "not alive" rather than throwing.
local function _name_of(u)
  if type(u) == "string" then return u end
  if type(u) == "table" and type(u.name) == "string" then return u.name end
  return nil
end

sms.unit.is_alive = function(u)
  local name = _name_of(u)
  if not name then return false end
  local obj = Unit.getByName(name)
  return obj ~= nil and obj:isExist()
end

sms.unit.get_name = function(u)
  return _name_of(u)
end

sms.unit.get_coalition = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local c = Unit.getByName(name):getCoalition()
  local s = _coalition_str[c]
  if not s then
    log.error("get_coalition: '" .. tostring(name) .. "' returned unknown coalition " .. tostring(c))
    return nil
  end
  return s
end

sms.unit.get_position = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_position: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local p = Unit.getByName(name):getPoint()
  -- DCS world coords: x = east, y = altitude, z = north.
  return {x = p.x, y = p.y, z = p.z}
end

sms.unit.get_type = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_type: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  return Unit.getByName(name):getTypeName()
end

sms.unit.get_group = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_group: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local group_name = Unit.getByName(name):getGroup():getName()
  return sms.group(group_name)
end

sms.unit.destroy = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  Unit.getByName(name):destroy()
  return true
end

-- Sugar constructor: sms.unit("name") -> handle | nil + log.
-- The factory lives in sms.lua; this call wires it up using Unit.getByName
-- as the existence check.
sms._make_callable_handle(sms.unit, Unit.getByName, log)
