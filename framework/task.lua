-- dcs-sms framework: task module (sms.task).
--
-- Ergonomic builders for DCS task tables, plus runtime apply methods
-- (group:set_task, group:push_task) installed on sms.group's metatable.
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
--                unit.lua -> area.lua -> timer.lua -> spawn.lua ->
--                static.lua -> events.lua -> weapon.lua -> task.lua.
--
-- See docs/superpowers/specs/2026-04-27-framework-task-design.md.

assert(type(sms) == "table",        "framework/sms.lua must be loaded first")
assert(type(sms.unit) == "table",   "framework/unit.lua must be loaded first")
assert(type(sms.group) == "table",  "framework/group.lua must be loaded first")
assert(type(sms.static) == "table", "framework/static.lua must be loaded first")
assert(type(sms.area) == "table",   "framework/area.lua must be loaded first")
assert(type(sms.utils) == "table",  "framework/utils.lua must be loaded first")
assert(type(sms.timer) == "table",  "framework/timer.lua must be loaded first")
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
    log.error(verb .. ": unknown weapon_type '" .. v .. "', falling back to Auto")
    return _weapon_type_str.Auto
  end
  log.error(verb .. ": weapon_type must be a number or string, got " .. type(v))
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
  log.error(verb .. ": target must be a vec3 or an sms.unit/group/static/area handle")
  return nil
end

-- Stamp the framework's private metadata on a task table. Returns t for
-- chaining.
local function _stamp(t, verb, air_only)
  t._sms_verb = verb
  if air_only then t._sms_air_only = true end
  return t
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
    log.error("move_to: opts must be a table or nil, got " .. type(opts))
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
      log.error("move_to: opts.speed must be a number, got " .. type(opts.speed))
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
    log.error("follow: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local offset = opts.offset or {x = -50, y = 0, z = -50}
  if not sms.utils.is_vec3(offset) then
    log.error("follow: opts.offset must be a vec3, got " .. type(offset))
    return nil
  end

  local group_id
  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.error("follow: group '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    group_id = raw:getID()
  elseif sms._is_handle_of(target, sms.unit) then
    local raw = Unit.getByName(target.name)
    if not raw then
      log.error("follow: unit '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    local g = raw:getGroup()
    if not g then
      log.error("follow: unit '" .. tostring(target.name) .. "' has no group")
      return nil
    end
    group_id = g:getID()
  else
    log.error("follow: target must be sms.unit or sms.group handle")
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

-- Orbit a point. Pattern is "Circle" (default) or "RaceTrack". Air only.
sms.task.orbit = function(pos, opts)
  if not sms.utils.is_vec3(pos) then
    log.error("orbit: pos must be a vec3, got " .. type(pos))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("orbit: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local altitude = opts.altitude or 5000
  local speed    = opts.speed    or 200
  local pattern  = opts.pattern  or "Circle"
  if pattern ~= "Circle" and pattern ~= "RaceTrack" then
    log.error("orbit: pattern must be 'Circle' or 'RaceTrack', got '" .. tostring(pattern) .. "'")
    return nil
  end
  if type(altitude) ~= "number" then
    log.error("orbit: opts.altitude must be a number, got " .. type(altitude))
    return nil
  end
  if type(speed) ~= "number" then
    log.error("orbit: opts.speed must be a number, got " .. type(speed))
    return nil
  end

  return _stamp({
    id = "Orbit",
    params = {
      pattern  = pattern,
      point    = {x = pos.x, y = pos.z},  -- DCS 2D
      altitude = altitude,
      speed    = speed,
    },
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
    log.error("attack: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack")
  local expend      = opts.expend or "Auto"

  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.error("attack: group '" .. tostring(target.name) .. "' not in mission")
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
      log.error("attack: unit '" .. tostring(target.name) .. "' not in mission")
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
      log.error("attack: static '" .. tostring(target.name) .. "' not in mission")
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

  log.error("attack: target must be sms.group, sms.unit, or sms.static handle")
  return nil
end

-- Engage anything in a circular sms.area. Air only in v1; polygon areas
-- rejected with log + nil.
sms.task.attack_in_area = function(area, opts)
  if not sms._is_handle_of(area, sms.area) then
    log.error("attack_in_area: area must be an sms.area handle")
    return nil
  end
  if area:get_kind() ~= "circle" then
    log.error("attack_in_area: area '" .. tostring(area.name) .. "' is " .. tostring(area:get_kind()) .. "; only circular areas supported in v1")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("attack_in_area: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local center = area:get_position()
  local radius = area:get_radius()
  if not center or not radius then
    log.error("attack_in_area: failed to read center/radius from area '" .. tostring(area.name) .. "'")
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack_in_area")

  local params = {
    point       = {x = center.x, y = center.z},
    zoneRadius  = radius,
    targetTypes = {"All"},
    weaponType  = weapon_type,
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
    log.error("bomb: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "bomb")
  local altitude    = opts.altitude or 6000
  if type(altitude) ~= "number" then
    log.error("bomb: opts.altitude must be a number, got " .. type(altitude))
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
    log.error("land: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local duration = opts.duration or 300
  if type(duration) ~= "number" then
    log.error("land: opts.duration must be a number, got " .. type(duration))
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
    log.error("combo: tasks must be an array of task tables, got " .. type(tasks))
    return nil
  end
  if #tasks == 0 then
    log.error("combo: tasks list is empty")
    return nil
  end
  local any_air_only = false
  for i, t in ipairs(tasks) do
    if type(t) ~= "table" then
      log.error("combo: tasks[" .. i .. "] must be a task table, got " .. type(t))
      return nil
    end
    if t._sms_air_only then any_air_only = true end
  end
  return _stamp({
    id     = "ComboTask",
    params = { tasks = tasks },
  }, "combo", any_air_only)
end

-- ============================================================
-- Apply API (installed on sms.group metatable)
-- ============================================================

-- Validate task table shape: must be a table with id and params fields.
-- Manually-built tables (no _sms_* tags) are accepted; only the basic DCS
-- shape is required.
local function _is_task_table(t)
  return type(t) == "table" and type(t.id) == "string" and type(t.params) == "table"
end

-- Categories DCS will honor an air-only task on.
local _air_categories = { airplane = true, helicopter = true }

-- Shared validation for set_task and push_task. Returns the live DCS group
-- object on success, or nil after logging.
local function _validate_apply(method, group_handle, task)
  if not sms._is_handle_of(group_handle, sms.group) then
    log.error(method .. ": first argument must be an sms.group handle")
    return nil
  end
  if not group_handle:is_alive() then
    log.error(method .. ": group '" .. tostring(group_handle.name) .. "' is not alive")
    return nil
  end
  if not _is_task_table(task) then
    log.error(method .. ": task must be a table with 'id' (string) and 'params' (table) fields")
    return nil
  end
  if task._sms_air_only then
    local cat = group_handle:get_category()
    if not _air_categories[cat] then
      local verb = task._sms_verb or "task"
      log.error(method .. ": '" .. verb .. "' is air-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  local raw = Group.getByName(group_handle.name)
  if not raw then
    log.error(method .. ": group '" .. tostring(group_handle.name) .. "' disappeared between is_alive and apply")
    return nil
  end
  return raw
end

-- Rewrite move_to waypoint fields and route metadata to match the
-- destination group. DCS Mission tasks need three category-dependent
-- shape changes the build-time builder can't know about:
--   * waypoint action: "Turning Point" for aircraft (with alt_type
--     "BARO"); "Off Road" for ground/ship/train.
--   * params.airborne = true for air groups (without it DCS treats
--     the route as a ground route and the AI ignores it).
--   * a starting waypoint at the group's current position prepended
--     to the route — DCS's AI needs a "from" waypoint to compute the
--     route. MOOSE's RouteAirTo / RouteGroundTo do this unconditionally;
--     we mirror the pattern. The destination point is marked with
--     _sms_start_prepended so re-applies don't double-prepend.
-- Recurses into combo so a move_to nested inside a combo is fixed up
-- the same way. Mutates in place; idempotent across re-applies.
local function _adapt_task_for_category(task, category, g)
  if type(task) ~= "table" then return end
  if task._sms_verb == "combo" then
    local subtasks = task.params and task.params.tasks
    if type(subtasks) == "table" then
      for _, sub in ipairs(subtasks) do _adapt_task_for_category(sub, category, g) end
    end
    return
  end
  if task._sms_verb ~= "move_to" then return end
  local route = task.params and task.params.route
  local pt = route and route.points and route.points[1]
  if not pt then return end

  local is_air = (category == "airplane" or category == "helicopter")
  if is_air then
    pt.action            = "Turning Point"
    pt.alt_type          = pt.alt_type or "BARO"
    task.params.airborne = true
  else
    pt.action = "Off Road"
  end

  if g and not pt._sms_start_prepended and #route.points == 1 then
    local cur = g:get_position()
    if cur then
      local start = {
        x      = cur.x,
        y      = cur.z,
        alt    = cur.y,
        type   = "Turning Point",
        action = pt.action,
        task   = { id = "ComboTask", params = { tasks = {} } },
      }
      if is_air then start.alt_type = "BARO" end
      if pt.speed then
        start.speed        = pt.speed
        start.speed_locked = pt.speed_locked
      end
      table.insert(route.points, 1, start)
      pt._sms_start_prepended = true
    end
  end
end

-- DCS controllers reject task assignment in the same frame as spawn
-- (the controller isn't fully wired up yet — observed as silent despawn
-- for aircraft, no-op for ground). MOOSE works around this by scheduling
-- task assignment in the future. We defer all set/push by ~one frame via
-- sms.timer.after. The call returns true after validation; the actual
-- DCS dispatch happens on the next sim tick (errors are logged then).
local _DEFER_SECONDS = 0.01

-- Replace the group's current task. Wraps Controller:setTask via a
-- one-frame deferred dispatch.
sms.group.set_task = function(g, task)
  local raw = _validate_apply("set_task", g, task)
  if not raw then return false end
  local category = g:get_category()
  _adapt_task_for_category(task, category, g)
  local name = g.name
  sms.timer.after(_DEFER_SECONDS, function()
    local raw_now = Group.getByName(name)
    if not raw_now then
      log.error("set_task: group '" .. tostring(name) .. "' gone before deferred dispatch")
      return
    end
    local ctrl_now = raw_now:getController()
    if not ctrl_now then
      log.error("set_task: group '" .. tostring(name) .. "' has no controller at deferred dispatch")
      return
    end
    local ok, err = pcall(ctrl_now.setTask, ctrl_now, task)
    if not ok then
      log.error("set_task: DCS rejected task for '" .. tostring(name) .. "' (deferred): " .. tostring(err))
    end
  end)
  return true
end

-- Push a task onto the group's task stack. Wraps Controller:pushTask
-- via a one-frame deferred dispatch (same race-avoidance reason as
-- set_task). DCS pushTask is LIFO: the new task interrupts the current
-- one and runs to completion, then the previous task resumes.
sms.group.push_task = function(g, task)
  local raw = _validate_apply("push_task", g, task)
  if not raw then return false end
  local category = g:get_category()
  _adapt_task_for_category(task, category, g)
  local name = g.name
  sms.timer.after(_DEFER_SECONDS, function()
    local raw_now = Group.getByName(name)
    if not raw_now then
      log.error("push_task: group '" .. tostring(name) .. "' gone before deferred dispatch")
      return
    end
    local ctrl_now = raw_now:getController()
    if not ctrl_now then
      log.error("push_task: group '" .. tostring(name) .. "' has no controller at deferred dispatch")
      return
    end
    local ok, err = pcall(ctrl_now.pushTask, ctrl_now, task)
    if not ok then
      log.error("push_task: DCS rejected task for '" .. tostring(name) .. "' (deferred): " .. tostring(err))
    end
  end)
  return true
end
