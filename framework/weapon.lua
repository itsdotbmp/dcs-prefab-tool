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

-- DCS coalition int -> normalized lowercase string.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}

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
  if ok_coa and coa then handle.coalition = _coalition_str[coa] end

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
