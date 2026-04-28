-- dcs-sms framework: task module (sms.task).
--
-- Ergonomic builders for DCS task tables. The runtime apply methods
-- (sms.group.set_task, sms.group.push_task) live in framework/group.lua
-- — that is where they belong, since they extend sms.group's namespace.
-- This file is build-only.
--
-- The split between *build* and *apply* keeps tasks as first-class
-- values: a task can be stored, passed around, composed via combo,
-- or built once and applied to multiple groups.
--
-- Each builder returns a plain DCS task table with two private fields:
--   _sms_verb     -- string, used for log messages
--   _sms_air_only -- true for verbs DCS only honors on air groups
--
-- The fields are otherwise transparent to DCS. Manually-built task
-- tables (no _sms_* tags) skip the air-only check at apply time.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua ->
--                unit.lua -> area.lua -> timer.lua -> group_spawn.lua ->
--                static.lua -> events.lua -> weapon.lua -> task.lua.
--
-- See docs/superpowers/specs/2026-04-27-framework-task-design.md.

assert(type(sms) == "table",        "framework/sms.lua must be loaded first")
assert(type(sms.unit) == "table",   "framework/unit.lua must be loaded first")
assert(type(sms.group) == "table",  "framework/group.lua must be loaded first")
assert(type(sms.static) == "table", "framework/static.lua must be loaded first")
assert(type(sms.area) == "table",   "framework/area.lua must be loaded first")
assert(type(sms.utils) == "table",  "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.task")
sms.task = sms.task or {}

-- ============================================================
-- Internal helpers
-- ============================================================

-- DCS weaponType bitmask. "Auto" lets DCS pick from anything available.
-- These are the canonical aggregate values from the DCS task framework.
local _weapon_type_str = {
  Auto     = 4194304,
  Guns     = 805306368,
  Rockets  = 30720,
  Missiles = 4161536,
  Bombs    = 2032,
}

local function _resolve_weapon_type(v, verb)
  if v == nil then return _weapon_type_str.Auto end
  if type(v) == "number" then return v end
  if type(v) == "string" then
    local n = _weapon_type_str[v]
    if n then return n end
    log.warn(verb .. ": unknown weapon_type '" .. v .. "', falling back to Auto")
    return _weapon_type_str.Auto
  end
  log.warn(verb .. ": weapon_type must be a number or string, got " .. type(v))
  return _weapon_type_str.Auto
end

-- Resolve a target argument to a vec3 position. Accepts vec3, sms.unit,
-- sms.group, sms.static, sms.area handles. Returns nil + log on bad input.
local function _position_of(target, verb)
  if sms.utils.is_vec3(target) then
    return {x = target.x, y = target.y, z = target.z}
  end
  if sms._is_handle_of(target, sms.unit)   then return target:get_position() end
  if sms._is_handle_of(target, sms.group)  then return target:get_position() end
  if sms._is_handle_of(target, sms.static) then return target:get_position() end
  if sms._is_handle_of(target, sms.area)   then return target:get_position() end
  log.warn(verb .. ": target must be a vec3 or an sms.unit/group/static/area handle")
  return nil
end

-- Stamp the framework's private metadata on a task table. Returns t for
-- chaining.
local function _stamp(t, verb, air_only, ground_only)
  t._sms_verb = verb
  if air_only    then t._sms_air_only    = true end
  if ground_only then t._sms_ground_only = true end
  return t
end

-- Generic priority validator + extractor for enroute role tasks.
local function _validate_priority(verb, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn(verb .. ": opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn(verb .. ": opts.priority must be a number, got " .. type(priority))
    return nil
  end
  return priority
end

-- ============================================================
-- Builders
-- ============================================================

-- Mission task with one waypoint at the target's snapshotted position.
-- Works for all categories: DCS interprets "Off Road" + "Turning Point"
-- per group category. Snapshot is at build time — if target moves, the
-- task still drives to the original spot. Use sms.task.follow for live
-- tracking.
--
-- opts: { speed = number? }  (m/s; locked when given)
-- When opts.speed is omitted, the speed field is not set on the waypoint
-- and DCS uses the group's default cruise speed — the closest thing DCS
-- offers to "keep what you were doing." Pass opts.speed explicitly when
-- you need a specific transit speed.
sms.task.move_to = function(target, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("move_to: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local pos = _position_of(target, "move_to")
  if not pos then return nil end

  local point = {
    x      = pos.x,
    y      = pos.z,  -- DCS 2D y maps to vec3 z
    alt    = pos.y,
    type   = "Turning Point",
    action = "Off Road",
    task   = { id = "ComboTask", params = { tasks = {} } },
  }
  if opts.speed ~= nil then
    if type(opts.speed) ~= "number" then
      log.warn("move_to: opts.speed must be a number, got " .. type(opts.speed))
      return nil
    end
    point.speed        = opts.speed
    point.speed_locked = true
  end

  return _stamp({
    id = "Mission",
    params = {
      route = {
        points = { point },
      },
    },
  }, "move_to", false)
end

-- Stop and hold position. Air group loiters; ground group stops.
-- DCS interprets "Nothing" appropriately per category.
sms.task.hold = function()
  return _stamp({ id = "Nothing", params = {} }, "hold", false)
end

-- Continuously follow a unit or group at a fixed offset.
-- Accepts sms.unit (resolves to its parent group) or sms.group.
-- Air-only in v1 — DCS Follow task is for aircraft formations.
sms.task.follow = function(target, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("follow: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local offset = opts.offset or {x = -50, y = 0, z = -50}
  if not sms.utils.is_vec3(offset) then
    log.warn("follow: opts.offset must be a vec3, got " .. type(offset))
    return nil
  end

  local group_id
  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.warn("follow: group '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    group_id = raw:getID()
  elseif sms._is_handle_of(target, sms.unit) then
    local raw = Unit.getByName(target.name)
    if not raw then
      log.warn("follow: unit '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    local g = raw:getGroup()
    if not g then
      log.error("follow: unit '" .. tostring(target.name) .. "' has no group")
      return nil
    end
    group_id = g:getID()
  else
    log.warn("follow: target must be sms.unit or sms.group handle")
    return nil
  end

  return _stamp({
    id = "Follow",
    params = {
      groupId          = group_id,
      pos              = {x = offset.x, y = offset.y, z = offset.z},
      lastWptIndexFlag = false,
    },
  }, "follow", true)
end

-- Orbit a point. Pattern is "Circle" (default) or "Anchored" (DCS renamed
-- this from "RaceTrack" in a recent update). Air only.
--
-- opts:
--   altitude          number?    meters,   default 5000
--   speed             number?    m/s,      default 200
--   pattern           string?    "Circle" | "Anchored", default "Circle"
--
-- Anchored-only opts (ignored on Circle):
--   hot_leg_bearing   number?    degrees, 0=north clockwise, default 0
--   leg_length        number?    meters,                     default 30000 (~16 nm)
--   width             number?    meters,                     default 10000 (~5 nm)
--   clockwise         boolean?                               default false
sms.task.orbit = function(pos, opts)
  if not sms.utils.is_vec3(pos) then
    log.warn("orbit: pos must be a vec3, got " .. type(pos))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("orbit: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local altitude = opts.altitude or 5000
  local speed    = opts.speed    or 200
  local pattern  = opts.pattern  or "Circle"
  if pattern ~= "Circle" and pattern ~= "Anchored" then
    log.warn("orbit: pattern must be 'Circle' or 'Anchored', got '" .. tostring(pattern) .. "'")
    return nil
  end
  if type(altitude) ~= "number" then
    log.warn("orbit: opts.altitude must be a number, got " .. type(altitude))
    return nil
  end
  if type(speed) ~= "number" then
    log.warn("orbit: opts.speed must be a number, got " .. type(speed))
    return nil
  end

  local params = {
    pattern  = pattern,
    point    = {x = pos.x, y = pos.z},  -- DCS 2D
    altitude = altitude,
    speed    = speed,
  }

  if pattern == "Anchored" then
    local hot_leg_bearing = opts.hot_leg_bearing or 0
    local leg_length      = opts.leg_length      or 30000
    local width           = opts.width           or 10000
    if type(hot_leg_bearing) ~= "number" then
      log.warn("orbit: opts.hot_leg_bearing must be a number (degrees), got " .. type(hot_leg_bearing))
      return nil
    end
    if type(leg_length) ~= "number" then
      log.warn("orbit: opts.leg_length must be a number (meters), got " .. type(leg_length))
      return nil
    end
    if type(width) ~= "number" then
      log.warn("orbit: opts.width must be a number (meters), got " .. type(width))
      return nil
    end
    if opts.clockwise ~= nil and type(opts.clockwise) ~= "boolean" then
      log.warn("orbit: opts.clockwise must be a boolean, got " .. type(opts.clockwise))
      return nil
    end
    params.hotLegDir = sms.utils.deg_to_rad(hot_leg_bearing) or 0
    params.legLength = leg_length
    params.width     = width
    params.clockWise = opts.clockwise == true
  end

  return _stamp({
    id = "Orbit",
    params = params,
  }, "orbit", true)
end

-- Attack a unit, group, or static. Air only in v1. Statics route through
-- AttackUnit using the static object's ID — DCS shares the unit/static
-- ID space for targeting purposes. If a static target turns out to be a
-- poor fit for the AI's weapon profile, fall back to sms.task.bomb on
-- the static's position.
sms.task.attack = function(target, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("attack: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack")
  local expend      = opts.expend or "Auto"

  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.warn("attack: group '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    return _stamp({
      id = "AttackGroup",
      params = {
        groupId        = raw:getID(),
        weaponType     = weapon_type,
        expend         = expend,
        attackQty      = opts.attack_qty,
        attackQtyLimit = opts.attack_qty ~= nil,
      },
    }, "attack", true)
  end

  if sms._is_handle_of(target, sms.unit) then
    local raw = Unit.getByName(target.name)
    if not raw then
      log.warn("attack: unit '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    return _stamp({
      id = "AttackUnit",
      params = {
        unitId         = raw:getID(),
        weaponType     = weapon_type,
        expend         = expend,
        attackQty      = opts.attack_qty,
        attackQtyLimit = opts.attack_qty ~= nil,
      },
    }, "attack", true)
  end

  if sms._is_handle_of(target, sms.static) then
    local raw = StaticObject.getByName(target.name)
    if not raw then
      log.warn("attack: static '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    return _stamp({
      id = "AttackUnit",
      params = {
        unitId         = raw:getID(),
        weaponType     = weapon_type,
        expend         = expend,
        attackQty      = opts.attack_qty,
        attackQtyLimit = opts.attack_qty ~= nil,
      },
    }, "attack", true)
  end

  log.warn("attack: target must be sms.group, sms.unit, or sms.static handle")
  return nil
end

-- Engage anything in a circular sms.area. Air only in v1; polygon areas
-- rejected with log + nil.
sms.task.attack_in_area = function(area, opts)
  if not sms._is_handle_of(area, sms.area) then
    log.warn("attack_in_area: area must be an sms.area handle")
    return nil
  end
  if area:get_kind() ~= "circle" then
    log.warn("attack_in_area: area '" .. tostring(area.name) .. "' is " .. tostring(area:get_kind()) .. "; only circular areas supported in v1")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("attack_in_area: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local center = area:get_position()
  local radius = area:get_radius()
  if not center or not radius then
    log.error("attack_in_area: failed to read center/radius from area '" .. tostring(area.name) .. "'")
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack_in_area")

  local priority = _validate_priority("attack_in_area", opts)
  if priority == nil then return nil end

  local params = {
    point       = {x = center.x, y = center.z},
    zoneRadius  = radius,
    targetTypes = {"All"},
    weaponType  = weapon_type,
    priority    = priority,
  }
  if opts.altitude_min then params.minAlt = opts.altitude_min end
  if opts.altitude_max then params.maxAlt = opts.altitude_max end

  return _stamp({
    id     = "EngageTargetsInZone",
    params = params,
  }, "attack_in_area", true)
end

-- Bomb a position. Target may be a vec3 or a handle (snapshotted to vec3).
-- Air only.
sms.task.bomb = function(target, opts)
  local pos = _position_of(target, "bomb")
  if not pos then return nil end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("bomb: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "bomb")
  local altitude    = opts.altitude or 6000
  if type(altitude) ~= "number" then
    log.warn("bomb: opts.altitude must be a number, got " .. type(altitude))
    return nil
  end

  return _stamp({
    id = "Bombing",
    params = {
      point             = {x = pos.x, y = pos.z},
      altitude          = altitude,
      altitudeEnabled   = true,
      expend            = opts.expend or "Auto",
      weaponType        = weapon_type,
      direction         = opts.direction,
      directionEnabled  = opts.direction ~= nil,
      groupAttack       = opts.group_attack and true or false,
    },
  }, "bomb", true)
end

-- Land at a position or a handle's position. duration in seconds (default 300).
-- Air only (helicopters mostly).
sms.task.land = function(target, opts)
  local pos = _position_of(target, "land")
  if not pos then return nil end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("land: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local duration = opts.duration or 300
  if type(duration) ~= "number" then
    log.warn("land: opts.duration must be a number, got " .. type(duration))
    return nil
  end

  return _stamp({
    id = "Land",
    params = {
      point         = {x = pos.x, y = pos.z},
      durationFlag  = true,
      duration      = duration,
    },
  }, "land", true)
end

-- Run all listed tasks in parallel via DCS ComboTask. Propagates
-- _sms_air_only if any constituent has it. Rejects with log + nil if any
-- constituent is nil (caught a builder error upstream) or non-table.
sms.task.combo = function(tasks)
  if type(tasks) ~= "table" then
    log.warn("combo: tasks must be an array of task tables, got " .. type(tasks))
    return nil
  end
  if #tasks == 0 then
    log.warn("combo: tasks list is empty")
    return nil
  end
  local any_air_only    = false
  local any_ground_only = false
  for i, t in ipairs(tasks) do
    if type(t) ~= "table" then
      log.warn("combo: tasks[" .. i .. "] must be a task table, got " .. type(t))
      return nil
    end
    if t._sms_air_only    then any_air_only    = true end
    if t._sms_ground_only then any_ground_only = true end
  end
  return _stamp({
    id     = "ComboTask",
    params = { tasks = tasks },
  }, "combo", any_air_only, any_ground_only)
end

-- ============================================================
-- Role-type / no-target builders (Task v1.1 additions)
-- ============================================================

-- Empty noop. Air only per DCS FAQ. Useful for clearing the active
-- task without resetting the controller (resetTask clears the queue
-- entirely; setTask(no_task) just stops the current activity).
sms.task.no_task = function()
  return _stamp({id = "NoTask", params = {}}, "no_task", true)
end

-- Refuel from nearest tanker. Air only.
sms.task.refuel = function()
  return _stamp({id = "Refueling", params = {}}, "refuel", true)
end

-- Act as AWACS for friendly units. Enroute, air only.
sms.task.awacs = function(opts)
  local priority = _validate_priority("awacs", opts)
  if priority == nil then return nil end
  return _stamp({
    id     = "AWACS",
    params = {priority = priority},
  }, "awacs", true)
end

-- Act as tanker for friendly units. Enroute, air only.
sms.task.tanker = function(opts)
  local priority = _validate_priority("tanker", opts)
  if priority == nil then return nil end
  return _stamp({
    id     = "Tanker",
    params = {priority = priority},
  }, "tanker", true)
end

-- Act as EW radar for friendly units. Enroute, ground only.
sms.task.ewr = function(opts)
  local priority = _validate_priority("ewr", opts)
  if priority == nil then return nil end
  return _stamp({
    id     = "EWR",
    params = {priority = priority},
  }, "ewr", false, true)
end

-- ============================================================
-- Point/runway-target builders (Task v1.1 additions)
-- ============================================================

-- Fire at a point on the ground. Optional radius spreads fire over a
-- circle; without radius DCS targets the exact point. Ground only.
sms.task.fire_at_point = function(point, opts)
  if not sms.utils.is_vec3(point) then
    log.warn("fire_at_point: point must be a vec3, got " .. type(point))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fire_at_point: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.radius ~= nil and type(opts.radius) ~= "number" then
    log.warn("fire_at_point: opts.radius must be a number, got " .. type(opts.radius))
    return nil
  end
  return _stamp({
    id = "FireAtPoint",
    params = {
      point  = {x = point.x, y = point.z},  -- DCS 2D
      radius = opts.radius,
    },
  }, "fire_at_point", false, true)
end

-- Attack a map object (building / structure / etc.) at the given vec3.
-- DCS doesn't take a map-object id from scripts; the point must be
-- within ~2km of the structure for the AI to find it. Air only.
sms.task.attack_map_object = function(point, opts)
  if not sms.utils.is_vec3(point) then
    log.warn("attack_map_object: point must be a vec3, got " .. type(point))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("attack_map_object: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.attack_qty ~= nil and type(opts.attack_qty) ~= "number" then
    log.warn("attack_map_object: opts.attack_qty must be a number, got " .. type(opts.attack_qty))
    return nil
  end
  if opts.direction ~= nil and type(opts.direction) ~= "number" then
    log.warn("attack_map_object: opts.direction must be a number (degrees), got " .. type(opts.direction))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack_map_object")
  return _stamp({
    id = "AttackMapObject",
    params = {
      point       = {x = point.x, y = point.z},
      weaponType  = weapon_type,
      expend      = opts.expend or "Auto",
      attackQty   = opts.attack_qty,
      direction   = opts.direction and sms.utils.deg_to_rad(opts.direction) or nil,
      groupAttack = opts.group_attack and true or false,
    },
  }, "attack_map_object", true)
end

-- Bomb a runway by integer DCS airdrome ID. See issue #23 for the
-- planned sms.airdrome handle integration. Air only.
sms.task.bomb_runway = function(airdrome_id, opts)
  if type(airdrome_id) ~= "number" then
    log.warn("bomb_runway: airdrome_id must be a number (DCS airdrome ID), got " .. type(airdrome_id))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("bomb_runway: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.attack_qty ~= nil and type(opts.attack_qty) ~= "number" then
    log.warn("bomb_runway: opts.attack_qty must be a number, got " .. type(opts.attack_qty))
    return nil
  end
  if opts.direction ~= nil and type(opts.direction) ~= "number" then
    log.warn("bomb_runway: opts.direction must be a number (degrees), got " .. type(opts.direction))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "bomb_runway")
  return _stamp({
    id = "BombingRunway",
    params = {
      runwayId    = airdrome_id,
      weaponType  = weapon_type,
      expend      = opts.expend or "Auto",
      attackQty   = opts.attack_qty,
      direction   = opts.direction and sms.utils.deg_to_rad(opts.direction) or nil,
      groupAttack = opts.group_attack and true or false,
    },
  }, "bomb_runway", true)
end

-- ============================================================
-- Coordination builders (Task v1.1 additions)
-- ============================================================

-- Escort another airborne group: follow at offset, engage threats
-- matching opts.target_types. Air only. Mirrors sms.task.follow's
-- target/offset shape.
--
-- opts:
--   offset                 vec3?    relative to target leader, default {-50, 0, -50}
--   engagement_dist_max    number?  meters, default 5000
--   target_types           table?   array of attribute strings (sms.targets.* recommended)
--   last_waypoint_index    number?  detach when target reaches this waypoint
sms.task.escort = function(target, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("escort: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local offset = opts.offset or {x = -50, y = 0, z = -50}
  if not sms.utils.is_vec3(offset) then
    log.warn("escort: opts.offset must be a vec3, got " .. type(offset))
    return nil
  end

  local group_id
  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.warn("escort: group '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    group_id = raw:getID()
  elseif sms._is_handle_of(target, sms.unit) then
    local raw = Unit.getByName(target.name)
    if not raw then
      log.warn("escort: unit '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    local g = raw:getGroup()
    if not g then
      log.error("escort: unit '" .. tostring(target.name) .. "' has no group")
      return nil
    end
    group_id = g:getID()
  else
    log.warn("escort: target must be sms.unit or sms.group handle")
    return nil
  end

  local engagement_dist_max = opts.engagement_dist_max or 5000
  if type(engagement_dist_max) ~= "number" then
    log.warn("escort: opts.engagement_dist_max must be a number, got " .. type(engagement_dist_max))
    return nil
  end
  if opts.target_types ~= nil and type(opts.target_types) ~= "table" then
    log.warn("escort: opts.target_types must be a table, got " .. type(opts.target_types))
    return nil
  end
  if opts.last_waypoint_index ~= nil and type(opts.last_waypoint_index) ~= "number" then
    log.warn("escort: opts.last_waypoint_index must be a number, got " .. type(opts.last_waypoint_index))
    return nil
  end

  return _stamp({
    id = "Escort",
    params = {
      groupId           = group_id,
      pos               = {x = offset.x, y = offset.y, z = offset.z},
      lastWptIndexFlag  = opts.last_waypoint_index ~= nil,
      lastWptIndex      = opts.last_waypoint_index,
      engagementDistMax = engagement_dist_max,
      targetTypes       = opts.target_types,
    },
  }, "escort", true)
end

-- ============================================================
-- FAC builders (Task v1.1 additions)
-- ============================================================

-- Validate a designation string. Accepts sms.designations.* values or
-- the raw string equivalents. Returns the resolved string or nil + warn.
local function _validate_designation(verb, raw)
  if raw == nil then return "Auto" end
  if type(raw) ~= "string" then
    log.warn(verb .. ": opts.designation must be a string, got " .. type(raw))
    return nil
  end
  return raw  -- pass-through; DCS validates
end

-- FAC for a specific target group (immediate). Air or ground.
sms.task.fac_attack_group = function(target, opts)
  if not sms._is_handle_of(target, sms.group) then
    log.warn("fac_attack_group: target must be an sms.group handle")
    return nil
  end
  local raw = Group.getByName(target.name)
  if not raw then
    log.warn("fac_attack_group: group '" .. tostring(target.name) .. "' not in mission")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fac_attack_group: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local designation = _validate_designation("fac_attack_group", opts.designation)
  if designation == nil then return nil end
  if opts.datalink ~= nil and type(opts.datalink) ~= "boolean" then
    log.warn("fac_attack_group: opts.datalink must be a boolean, got " .. type(opts.datalink))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "fac_attack_group")
  return _stamp({
    id = "FAC_AttackGroup",
    params = {
      groupId     = raw:getID(),
      weaponType  = weapon_type,
      designation = designation,
      datalink    = opts.datalink ~= false,  -- default true
    },
  }, "fac_attack_group", false, false)  -- air or ground
end

-- Area FAC (enroute). Air or ground.
sms.task.fac = function(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fac: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if type(opts.radius) ~= "number" then
    log.warn("fac: opts.radius is required (number, meters)")
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("fac: opts.priority must be a number, got " .. type(priority))
    return nil
  end
  return _stamp({
    id = "FAC",
    params = {
      radius   = opts.radius,
      priority = priority,
    },
  }, "fac", false, false)
end

-- Enroute FAC for a specific target group. Air or ground.
sms.task.fac_engage_group = function(target, opts)
  if not sms._is_handle_of(target, sms.group) then
    log.warn("fac_engage_group: target must be an sms.group handle")
    return nil
  end
  local raw = Group.getByName(target.name)
  if not raw then
    log.warn("fac_engage_group: group '" .. tostring(target.name) .. "' not in mission")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fac_engage_group: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local designation = _validate_designation("fac_engage_group", opts.designation)
  if designation == nil then return nil end
  if opts.datalink ~= nil and type(opts.datalink) ~= "boolean" then
    log.warn("fac_engage_group: opts.datalink must be a boolean, got " .. type(opts.datalink))
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("fac_engage_group: opts.priority must be a number, got " .. type(priority))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "fac_engage_group")
  return _stamp({
    id = "FAC_EngageGroup",
    params = {
      groupId     = raw:getID(),
      weaponType  = weapon_type,
      designation = designation,
      datalink    = opts.datalink ~= false,
      priority    = priority,
    },
  }, "fac_engage_group", false, false)
end
