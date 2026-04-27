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
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.unit")
sms.unit = sms.unit or {}

-- DCS coalition int -> normalized lowercase string. Lookup now lives in
-- sms.utils.coalition_int_to_str (issue #14).

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
  local s = sms.utils.coalition_int_to_str(c)
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

-- destroy(u, opts) — silently removes the unit from the mission. By default
-- DCS fires NO event for this (it's not a "death", it's a removal). Pass
-- {emit_event = true} to also synthesize a DEAD event onto the sms.events
-- bus after the unit is gone. Useful when reactive code (g:connect(DEAD),
-- subscribers, etc.) should treat a programmatic destroy the same as a
-- combat death.
sms.unit.destroy = function(u, opts)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  -- If asked to emit a DEAD event, capture the group name BEFORE destroy.
  -- After Unit:destroy() the unit is gone and the raw DCS object can no
  -- longer answer :getGroup().
  local group_name = nil
  if opts and opts.emit_event then
    local raw = Unit.getByName(name)
    local ok, g = pcall(raw.getGroup, raw)
    if ok and g then
      local ok2, gn = pcall(g.getName, g)
      if ok2 then group_name = gn end
    end
  end
  Unit.getByName(name):destroy()
  if opts and opts.emit_event then
    -- emit_event requires both sms.events and sms.timer to be loaded.
    -- The framework load order guarantees this: events.lua loads after
    -- timer.lua, so if events is present, timer is too.
    if sms.events and sms.events.emit then
      sms.events.emit("dead", {
        id   = world.event.S_EVENT_DEAD,
        name = "dead",
        time = sms.timer.now(),
        initiator = sms._make_handle(sms.unit, name),
        initiator_group_name = group_name,
      })
    else
      log.error("destroy: emit_event=true requested but sms.events not loaded")
    end
  end
  return true
end

-- Heading in degrees (0 = north, 90 = east). Computed from the forward
-- axis of the unit's pose, projected to the horizontal plane and
-- converted from radians. Returns nil + log if the unit is not alive.
sms.unit.get_heading = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_heading: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local pos = Unit.getByName(name):getPosition()
  -- DCS world coords: x = east, y = altitude, z = north. Forward is pos.x.
  -- atan2(east, north) = heading from north, clockwise (DCS convention).
  local heading_rad = math.atan2(pos.x.x, pos.x.z)
  return sms.utils.normalize_heading(heading_rad * 180 / math.pi)
end

-- Pitch in degrees, positive = nose up. Computed from the y-component
-- (vertical) of the forward axis: asin(forward.y). Returns nil + log
-- if the unit is not alive.
sms.unit.get_pitch = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_pitch: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local pos = Unit.getByName(name):getPosition()
  local pitch_rad = math.asin(pos.x.y)
  return pitch_rad * 180 / math.pi
end

-- Altitude in meters. ASL (above sea level) by default; pass true for
-- AGL (above ground level). Returns nil + log if the unit is not alive.
sms.unit.get_altitude = function(u, agl)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_altitude: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local p = Unit.getByName(name):getPoint()
  -- DCS world coords: y = altitude.
  if not agl then
    return p.y
  end
  -- AGL: subtract terrain height at the unit's horizontal position.
  -- land.getHeight uses DCS-2D coords: input.y corresponds to vec3.z.
  local terrain = land.getHeight({x = p.x, y = p.z})
  return p.y - terrain
end

-- Sugar constructor: sms.unit("name") -> handle | nil + log.
-- The factory lives in sms.lua; this call wires it up using Unit.getByName
-- as the existence check.
sms._make_callable_handle(sms.unit, Unit.getByName, log)
