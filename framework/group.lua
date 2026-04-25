-- dcs-sms framework: group module (sms.group).
--
-- sms.group("name") returns a lightweight handle, or nil + log if the
-- group doesn't exist in DCS. Handles are {name=name} tables with
-- __index = sms.group, so handle:method() dispatches to sms.group.method(handle).
--
-- All methods accept either a handle or a raw name string, normalized at
-- entry. Methods other than is_alive internally check is_alive first; if
-- the group is not alive, they log and return nil — they never throw.
--
-- See docs/superpowers/specs/2026-04-25-framework-group-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
local log = sms.log.module("sms.group")
sms.group = sms.group or {}

-- DCS coalition int -> normalized lowercase string.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}

-- Accept either a handle ({name=...}) or a raw name string; return the name.
local function _name_of(g)
  return type(g) == "string" and g or g.name
end

sms.group.is_alive = function(g)
  local name = _name_of(g)
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
  return _coalition_str[c]
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

-- Sugar constructor: sms.group("name") -> handle | nil + log.
setmetatable(sms.group, {
  __call = function(_, name)
    if not Group.getByName(name) then
      log.error("couldn't find group '" .. tostring(name) .. "'")
      return nil
    end
    return setmetatable({name = name}, {__index = sms.group})
  end,
})
