-- dcs-sms framework: weapon module (sms.weapon).
--
-- Wraps DCS weapon objects from SHOT events with snapshotted release-time
-- state and an opt-in polling-based tracker. Unlike unit/group/static,
-- weapons are NOT name-addressable in DCS — Weapon.getByName does not
-- exist. The only public constructor is sms.weapon.wrap(raw_dcs_weapon),
-- which is what sms.events uses internally to populate evt.weapon on
-- SHOT/HIT events.
--
-- Tracking uses sms.timer.every to poll weapon:getPosition at a configurable
-- rate (default 60 Hz). When the DCS object stops existing, the handle
-- transitions to "impacted" and the impact position is computed via
-- land.getIP extrapolation from the last known position+forward axis,
-- falling back to the last known position when no terrain intersection
-- is found. Per-handle callbacks (on_impact, on_tick) are the primary API;
-- a fabricated WEAPON_IMPACT signal is also emitted on the sms.events bus
-- for cross-cutting subscribers.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua -> unit.lua
--                -> area.lua -> timer.lua -> spawn.lua -> static.lua
--                -> events.lua -> weapon.lua.
--
-- See docs/superpowers/specs/2026-04-27-framework-weapon-design.md.

assert(type(sms) == "table",         "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table",   "framework/utils.lua must be loaded first")
assert(type(sms.unit) == "table",    "framework/unit.lua must be loaded first")
assert(type(sms.timer) == "table",   "framework/timer.lua must be loaded first")
assert(type(sms.events) == "table",  "framework/events.lua must be loaded first")
local log = sms.log.module("sms.weapon")
sms.weapon = sms.weapon or {}

-- Fabricated bus event constant. Auto-derivation only handles
-- world.event.S_EVENT_*; weapon impact is fabricated by this module's
-- polling loop, so the constant is added explicitly at load time.
sms.events.WEAPON_IMPACT = "weapon_impact"

-- Handle metatable. Identity-checked in module functions so callers
-- can't slip arbitrary tables in.
local _handle_mt = {__index = sms.weapon}

local function _is_handle(h)
  return type(h) == "table" and getmetatable(h) == _handle_mt
end

-- DCS Weapon.Category int -> normalized lowercase string.
local _category_str = {
  [0] = "shell",
  [1] = "missile",
  [2] = "rocket",
  [3] = "bomb",
  [4] = "torpedo",
}

-- DCS coalition int -> normalized lowercase string. Lookup now lives in
-- sms.utils.coalition_int_to_str (issue #14).

-- int country id -> string country name. Built lazily.
local _country_reverse = nil
local function _build_country_reverse()
  if _country_reverse then return end
  _country_reverse = {}
  for k, v in pairs(country.id) do
    _country_reverse[v] = k:lower()
  end
end

-- ============================================================
-- Constructor
-- ============================================================

-- Snapshot all release-time state at construction. The handle stays
-- usable after the DCS weapon object is destroyed because nothing here
-- relies on the raw object after wrap returns.
sms.weapon.wrap = function(raw)
  if type(raw) ~= "userdata" and type(raw) ~= "table" then
    log.error("wrap: argument must be a DCS weapon object, got " .. type(raw))
    return nil
  end

  -- Snapshot fields. Each call is pcall-wrapped because half-deconstructed
  -- weapon objects can throw during late-frame access.
  local ok_name, name = pcall(raw.getName, raw)
  if not ok_name or not name then
    log.error("wrap: failed to read weapon name (object may be invalid)")
    return nil
  end

  local handle = setmetatable({
    name             = name,
    state            = "created",
    _raw             = raw,                 -- cleared on impacted / destroyed
  }, _handle_mt)

  local ok_type, t = pcall(raw.getTypeName, raw)
  if ok_type and t then handle.type = t end

  local ok_desc, desc = pcall(raw.getDesc, raw)
  if ok_desc and desc and type(desc.category) == "number" then
    handle.category = _category_str[desc.category]
    if not handle.category then
      log.error("wrap: '" .. name .. "' returned unknown category " .. tostring(desc.category))
    end
  end

  local ok_coa, coa = pcall(raw.getCoalition, raw)
  if ok_coa and coa then handle.coalition = sms.utils.coalition_int_to_str(coa) end

  local ok_country, country_int = pcall(raw.getCountry, raw)
  if ok_country and country_int then
    _build_country_reverse()
    handle.country = _country_reverse[country_int]
  end

  -- Launcher snapshot. Some weapons (triggered explosions, etc.) have no
  -- launcher; in that case launcher and all release_* fields stay nil.
  local ok_launcher, launcher_obj = pcall(raw.getLauncher, raw)
  if ok_launcher and launcher_obj then
    local ok_lname, lname = pcall(launcher_obj.getName, launcher_obj)
    if ok_lname and lname then
      handle.launcher = sms._make_handle(sms.unit, lname)
      -- Capture release-time state from the launcher. Use sms.unit
      -- getters so we stay inside the framework's idiom. If the launcher
      -- is somehow already gone (rare, racy), the getters will log + nil
      -- and the corresponding handle fields stay nil.
      handle.release_position     = sms.unit.get_position(handle.launcher)
      handle.release_heading      = sms.unit.get_heading(handle.launcher)
      handle.release_pitch        = sms.unit.get_pitch(handle.launcher)
      handle.release_altitude_asl = sms.unit.get_altitude(handle.launcher)
      handle.release_altitude_agl = sms.unit.get_altitude(handle.launcher, true)
    end
  end

  return handle
end

-- ============================================================
-- Always-available getters (snapshotted, work in any state)
-- ============================================================

sms.weapon.get_name = function(w)
  if not _is_handle(w) then
    log.error("get_name: argument must be an sms.weapon handle")
    return nil
  end
  return w.name
end

sms.weapon.get_type = function(w)
  if not _is_handle(w) then
    log.error("get_type: argument must be an sms.weapon handle")
    return nil
  end
  return w.type
end

sms.weapon.get_category = function(w)
  if not _is_handle(w) then
    log.error("get_category: argument must be an sms.weapon handle")
    return nil
  end
  return w.category
end

sms.weapon.get_coalition = function(w)
  if not _is_handle(w) then
    log.error("get_coalition: argument must be an sms.weapon handle")
    return nil
  end
  return w.coalition
end

sms.weapon.get_country = function(w)
  if not _is_handle(w) then
    log.error("get_country: argument must be an sms.weapon handle")
    return nil
  end
  return w.country
end

sms.weapon.get_launcher = function(w)
  if not _is_handle(w) then
    log.error("get_launcher: argument must be an sms.weapon handle")
    return nil
  end
  return w.launcher
end

sms.weapon.get_state = function(w)
  if not _is_handle(w) then
    log.error("get_state: argument must be an sms.weapon handle")
    return nil
  end
  return w.state
end

-- Release-time getters. Snapshotted at wrap; nil if launcher was absent.

sms.weapon.get_release_position = function(w)
  if not _is_handle(w) then
    log.error("get_release_position: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_position
end

sms.weapon.get_release_heading = function(w)
  if not _is_handle(w) then
    log.error("get_release_heading: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_heading
end

sms.weapon.get_release_pitch = function(w)
  if not _is_handle(w) then
    log.error("get_release_pitch: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_pitch
end

sms.weapon.get_release_altitude_asl = function(w)
  if not _is_handle(w) then
    log.error("get_release_altitude_asl: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_altitude_asl
end

sms.weapon.get_release_altitude_agl = function(w)
  if not _is_handle(w) then
    log.error("get_release_altitude_agl: argument must be an sms.weapon handle")
    return nil
  end
  return w.release_altitude_agl
end

-- Category sugar. False if category lookup failed at wrap time.

sms.weapon.is_bomb    = function(w) return _is_handle(w) and w.category == "bomb"    or false end
sms.weapon.is_missile = function(w) return _is_handle(w) and w.category == "missile" or false end
sms.weapon.is_rocket  = function(w) return _is_handle(w) and w.category == "rocket"  or false end
sms.weapon.is_shell   = function(w) return _is_handle(w) and w.category == "shell"   or false end
sms.weapon.is_torpedo = function(w) return _is_handle(w) and w.category == "torpedo" or false end

-- ============================================================
-- Tracking
-- ============================================================

-- Internal: handle a single poll. Stops the timer (returns false) when
-- the DCS weapon object is gone. Updates _last_pos3 and _last_velocity
-- otherwise. Triggers on_tick callback (pcall-wrapped) if set.
local function _tick(w)
  if w.state ~= "tracking" then
    return false  -- safety: timer somehow outlived the state machine
  end
  local raw = w._raw
  if not raw then
    -- Defensive: should not happen while tracking, but bail cleanly.
    return false
  end
  local ok_pos, pos3 = pcall(raw.getPosition, raw)
  local ok_exist, exists = pcall(raw.isExist, raw)
  if not ok_pos or not pos3 or not ok_exist or not exists then
    -- Weapon is gone: enter the impact path. (Task 5 fleshes this out;
    -- for now, just transition state and stop the timer cleanly.)
    sms.weapon._on_impact_detected(w)
    return false
  end
  w._last_pos3 = pos3
  local ok_vel, vel = pcall(raw.getVelocity, raw)
  if ok_vel and vel then w._last_velocity = vel end
  if w._on_tick_fn then
    local ok_cb, err = pcall(w._on_tick_fn, w)
    if not ok_cb then
      log.error("on_tick: user fn raised: " .. tostring(err))
    end
  end
  return nil  -- nil = continue at next interval (sms.timer contract)
end

-- Impact-detection hook. Called by the polling _tick when the DCS
-- weapon object stops existing. Transitions state, computes extrapolated
-- impact position (with last-known fallback), fires the on_impact
-- callback, and emits sms.events.WEAPON_IMPACT for cross-cutting subscribers.
sms.weapon._on_impact_detected = function(w)
  if w.state ~= "tracking" then return end  -- defensive
  -- Extrapolate impact via land.getIP. Falls back to last-known position
  -- if no terrain intersection within ip_distance (off-map, mid-air
  -- detonation, or weapon disappeared without a ground-bound trajectory).
  local impact = nil
  if w._last_pos3 and w._last_pos3.p and w._last_pos3.x then
    local ok_ip, ip = pcall(land.getIP, w._last_pos3.p, w._last_pos3.x, w._ip_distance or 50)
    if ok_ip and ip then impact = ip end
  end
  if not impact and w._last_pos3 and w._last_pos3.p then
    impact = {x = w._last_pos3.p.x, y = w._last_pos3.p.y, z = w._last_pos3.p.z}
  end
  w._impact_position = impact
  w._impact_time = sms.timer.now()
  w.state = "impacted"
  w._raw = nil
  if w._timer_handle then
    sms.timer.stop(w._timer_handle)
    w._timer_handle = nil
  end
  -- Per-handle callback first (locally scoped, expected to dominate use cases).
  if w._on_impact_fn then
    local ok_cb, err = pcall(w._on_impact_fn, w)
    if not ok_cb then
      log.error("on_impact: user fn raised: " .. tostring(err))
    end
  end
  -- Then bus emit for cross-cutting subscribers.
  sms.events.emit(sms.events.WEAPON_IMPACT, {
    weapon          = w,
    impact_position = impact,
    time            = w._impact_time,
  })
end

sms.weapon.is_tracking = function(w)
  if not _is_handle(w) then return false end
  return w.state == "tracking"
end

sms.weapon.start_tracking = function(w, opts)
  if not _is_handle(w) then
    log.error("start_tracking: argument must be an sms.weapon handle")
    return false
  end
  if w.state ~= "created" then
    log.error("start_tracking: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', cannot start")
    return false
  end
  opts = opts or {}
  local rate = opts.rate or 60
  if type(rate) ~= "number" or rate <= 0 then
    log.error("start_tracking: rate must be a positive number, got " .. tostring(rate))
    return false
  end
  local ip_distance = opts.ip_distance or 50
  if type(ip_distance) ~= "number" or ip_distance < 0 then
    log.error("start_tracking: ip_distance must be a non-negative number, got " .. tostring(ip_distance))
    return false
  end
  w._ip_distance = ip_distance
  w.state = "tracking"
  w._timer_handle = sms.timer.every(1 / rate, function() return _tick(w) end)
  if not w._timer_handle then
    -- sms.timer.every already logged; revert state.
    w.state = "created"
    return false
  end
  return true
end

sms.weapon.stop_tracking = function(w)
  if not _is_handle(w) then
    log.error("stop_tracking: argument must be an sms.weapon handle")
    return false
  end
  if w.state ~= "tracking" then
    return false
  end
  if w._timer_handle then
    sms.timer.stop(w._timer_handle)
    w._timer_handle = nil
  end
  w.state = "created"
  return true
end

-- ============================================================
-- Callback slots (single-slot, last-write-wins)
-- ============================================================

sms.weapon.on_tick = function(w, fn)
  if not _is_handle(w) then
    log.error("on_tick: argument must be an sms.weapon handle")
    return
  end
  if type(fn) ~= "function" then
    log.error("on_tick: fn must be a function, got " .. type(fn))
    return
  end
  w._on_tick_fn = fn
end

sms.weapon.on_impact = function(w, fn)
  if not _is_handle(w) then
    log.error("on_impact: argument must be an sms.weapon handle")
    return
  end
  if type(fn) ~= "function" then
    log.error("on_impact: fn must be a function, got " .. type(fn))
    return
  end
  w._on_impact_fn = fn
end

-- ============================================================
-- Live getters (require state == "tracking")
-- ============================================================

sms.weapon.is_alive = function(w)
  if not _is_handle(w) then return false end
  if w.state ~= "tracking" then return false end
  if not w._raw then return false end
  local ok, exists = pcall(w._raw.isExist, w._raw)
  return ok and exists == true
end

sms.weapon.get_position = function(w)
  if not _is_handle(w) then
    log.error("get_position: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "tracking" then
    log.error("get_position: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no live position")
    return nil
  end
  if not w._last_pos3 then return nil end
  local p = w._last_pos3.p
  return {x = p.x, y = p.y, z = p.z}
end

sms.weapon.get_velocity = function(w)
  if not _is_handle(w) then
    log.error("get_velocity: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "tracking" then
    log.error("get_velocity: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no live velocity")
    return nil
  end
  if not w._last_velocity then return nil end
  local v = w._last_velocity
  return {x = v.x, y = v.y, z = v.z}
end

sms.weapon.get_speed = function(w)
  local v = sms.weapon.get_velocity(w)
  if not v then return nil end
  return sms.utils.vec3_length(v)
end

sms.weapon.get_target = function(w)
  if not _is_handle(w) then
    log.error("get_target: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "tracking" or not w._raw then return nil end
  local ok_t, target_obj = pcall(w._raw.getTarget, w._raw)
  if not ok_t or not target_obj then return nil end
  local ok_n, target_name = pcall(target_obj.getName, target_obj)
  if not ok_n or not target_name then return nil end
  -- Try unit first; fall back to static.
  if Unit.getByName(target_name) then
    return sms.unit(target_name)
  end
  if StaticObject.getByName(target_name) then
    return sms.static and sms.static(target_name) or nil
  end
  return nil
end

-- ============================================================
-- Impact getters (require state == "impacted")
-- ============================================================

sms.weapon.get_impact_position = function(w)
  if not _is_handle(w) then
    log.error("get_impact_position: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "impacted" then
    log.error("get_impact_position: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no impact yet")
    return nil
  end
  if not w._impact_position then return nil end
  local p = w._impact_position
  return {x = p.x, y = p.y, z = p.z}
end

sms.weapon.get_last_known_position = function(w)
  if not _is_handle(w) then
    log.error("get_last_known_position: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "impacted" then
    log.error("get_last_known_position: weapon '" .. tostring(w.name) .. "' is in state '" .. tostring(w.state) .. "', no impact yet")
    return nil
  end
  if not w._last_pos3 or not w._last_pos3.p then return nil end
  local p = w._last_pos3.p
  return {x = p.x, y = p.y, z = p.z}
end

-- Distance from impact to a vec3 OR to any handle that exposes :get_position().
-- Duck-typed: works for sms.unit, sms.static, sms.weapon, or any future
-- positionable handle.
sms.weapon.get_impact_distance_from = function(w, target)
  if not _is_handle(w) then
    log.error("get_impact_distance_from: argument must be an sms.weapon handle")
    return nil
  end
  if w.state ~= "impacted" or not w._impact_position then
    log.error("get_impact_distance_from: weapon '" .. tostring(w.name) .. "' has no impact yet")
    return nil
  end
  local target_pos
  if type(target) == "table" and type(target.x) == "number"
     and type(target.y) == "number" and type(target.z) == "number" then
    target_pos = target
  elseif type(target) == "table" and type(target.get_position) == "function" then
    target_pos = target:get_position()
  end
  if not target_pos then
    log.error("get_impact_distance_from: target must be a vec3 or a handle with :get_position()")
    return nil
  end
  return sms.utils.vec3_distance(w._impact_position, target_pos)
end

-- ============================================================
-- destroy
-- ============================================================

-- Stops tracking (silently, no impact event), removes the weapon from
-- the DCS world, transitions state to "destroyed". Only valid from
-- "created" or "tracking" — returns false from "impacted" (natural
-- impact already happened — the two outcomes describe genuinely
-- different events and conflating them loses information) or
-- "destroyed" (already done). To get an impact-style event from a
-- programmatic abort, read get_position() before calling destroy().
sms.weapon.destroy = function(w)
  if not _is_handle(w) then
    log.error("destroy: argument must be an sms.weapon handle")
    return false
  end
  if w.state ~= "created" and w.state ~= "tracking" then return false end
  if w.state == "tracking" and w._timer_handle then
    sms.timer.stop(w._timer_handle)
    w._timer_handle = nil
  end
  if w._raw then
    pcall(w._raw.destroy, w._raw)
    w._raw = nil
  end
  w.state = "destroyed"
  return true
end
