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
-- group:connect, group.set_task and group.push_task all reference
-- modules loaded later in the framework load order (sms.events,
-- sms.timer). The references are deferred to call time, so group.lua
-- itself loads early; users must finish loading the rest of the
-- framework before invoking those methods.
--
-- See docs/superpowers/specs/2026-04-25-framework-group-design.md.
-- See docs/superpowers/specs/2026-04-26-framework-unit-design.md (get_units).
-- See docs/superpowers/specs/2026-04-26-framework-events-design.md (g:connect).
-- See docs/superpowers/specs/2026-04-27-framework-task-design.md (set/push_task).

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.group")
sms.group = sms.group or {}

-- DCS coalition int -> normalized lowercase string. Lookup now lives in
-- sms.utils.coalition_int_to_str (issue #14).

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
    log.warn("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local c = Group.getByName(name):getCoalition()
  local s = sms.utils.coalition_int_to_str(c)
  if not s then
    log.error("get_coalition: '" .. tostring(name) .. "' returned unknown coalition " .. tostring(c))
    return nil
  end
  return s
end

-- DCS Group.Category int -> normalized lowercase string. Inline (not in
-- sms.utils) because no other module needs this mapping.
local _category_str = {
  [Group.Category.GROUND]     = "ground",
  [Group.Category.AIRPLANE]   = "airplane",
  [Group.Category.HELICOPTER] = "helicopter",
  [Group.Category.SHIP]       = "ship",
  [Group.Category.TRAIN]      = "train",
}

sms.group.get_category = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.warn("get_category: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local cat = Group.getByName(name):getCategory()
  local s = _category_str[cat]
  if not s then
    log.error("get_category: '" .. tostring(name) .. "' returned unknown category " .. tostring(cat))
    return nil
  end
  return s
end

sms.group.get_position = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.warn("get_position: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local units = Group.getByName(name):getUnits()
  if not units or #units == 0 then
    log.warn("get_position: '" .. tostring(name) .. "' has no units")
    return nil
  end
  local p = units[1]:getPoint()
  -- DCS world coords: x = north, y = altitude, z = east.
  return {x = p.x, y = p.y, z = p.z}
end

sms.group.destroy = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.warn("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  Group.getByName(name):destroy()
  return true
end

sms.group.get_units = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.warn("get_units: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local raw = Group.getByName(name):getUnits()
  local handles = {}
  for i, u in ipairs(raw or {}) do
    handles[i] = sms.unit(u:getName())
  end
  return handles
end

-- ============================================================
-- g:connect (event-bus sugar; reads sms.events._entity_scoped)
-- ============================================================

-- g:connect(name, fn). Filter uses evt.initiator_group_name (captured at
-- event time from the raw DCS object) so dead initiators still resolve to
-- a group. For DEAD specifically, fires once when the group is fully dead
-- (last unit just died). For all other entity-scoped events, fires per-unit
-- — a "group hit" or "group takeoff" has no sensible aggregate meaning.
sms.group.connect = function(self, name, fn)
  if not sms._is_handle_of(self, sms.group) then
    log.warn("group:connect: self must be an sms.group handle")
    return nil
  end
  if type(name) ~= "string" then
    log.warn("group:connect: event name must be a string, got " .. type(name))
    return nil
  end
  if type(fn) ~= "function" then
    log.warn("group:connect: fn must be a function, got " .. type(fn))
    return nil
  end
  if not (sms.events and sms.events._entity_scoped and sms.events._entity_scoped[name]) then
    log.warn("group:connect: event '" .. tostring(name) .. "' has no entity scope")
    return nil
  end
  -- Capture name into a local so the closure doesn't keep a reference to
  -- the caller's self table (defensive; lets the caller drop the handle).
  local target_name = self.name
  if name == sms.events.DEAD then
    -- DCS does NOT synchronously update Group:getSize() after Unit:destroy()
    -- — the field stays stale until the next frame. The fully-dead check is
    -- therefore deferred via sms.timer.after with a small positive delay.
    -- (sms.timer.after(0, ...) can fire same-frame in DCS's scheduler; the
    -- 0.01s offset guarantees next-frame.) The fired_once latch dedupes
    -- simultaneous deaths (e.g. one explosion that kills every unit in the
    -- group fires N DEAD events in the same frame and would otherwise
    -- schedule N timers that all see size==0).
    local fired_once = false
    return sms.events.connect(name, function(evt)
      if fired_once then return end
      if evt.initiator_group_name ~= target_name then return end
      sms.timer.after(0.01, function()
        if fired_once then return end
        local g = Group.getByName(target_name)
        if not g or g:getSize() == 0 then
          fired_once = true
          local ok, err = pcall(fn, evt)
          if not ok then
            log.error("group:connect dispatch '" .. target_name .. "': " .. tostring(err))
          end
        end
      end)
    end)
  end
  return sms.events.connect(name, function(evt)
    if evt.initiator_group_name == target_name then
      fn(evt)
    end
  end)
end

-- ============================================================
-- set_task / push_task (apply API for sms.task builders)
-- ============================================================

-- Validate task table shape: must be a table with id and params fields.
-- Manually-built tables (no _sms_* tags) are accepted; only the basic DCS
-- shape is required.
local function _is_task_table(t)
  return type(t) == "table" and type(t.id) == "string" and type(t.params) == "table"
end

-- Categories DCS will honor a flag-restricted command/option/task on.
local _air_categories    = { airplane = true, helicopter = true }
local _ground_categories = { ground = true }
local _naval_categories  = { ship = true }

-- Shared validation for set_task / push_task / set_command / set_option.
-- Returns the live DCS group object on success, or nil after logging.
local function _validate_apply(method, group_handle, payload)
  if not sms._is_handle_of(group_handle, sms.group) then
    log.warn(method .. ": first argument must be an sms.group handle")
    return nil
  end
  if not group_handle:is_alive() then
    log.warn(method .. ": group '" .. tostring(group_handle.name) .. "' is not alive")
    return nil
  end
  if type(payload) ~= "table" then
    log.warn(method .. ": payload must be a table")
    return nil
  end
  -- For tasks (set_task / push_task), require the DCS shape (id+params).
  -- For commands/options, the apply method has already done its own shape check.
  if (method == "set_task" or method == "push_task") and not _is_task_table(payload) then
    log.warn(method .. ": task must be a table with 'id' (string) and 'params' (table) fields")
    return nil
  end
  if payload._sms_air_only then
    local cat = group_handle:get_category()
    if not _air_categories[cat] then
      local verb = payload._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is air-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  if payload._sms_ground_only then
    local cat = group_handle:get_category()
    if not _ground_categories[cat] then
      local verb = payload._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is ground-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  if payload._sms_naval_only then
    local cat = group_handle:get_category()
    if not _naval_categories[cat] then
      local verb = payload._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is naval-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  -- ROE option carries _sms_roe instead of a fixed category flag.
  -- Defer to sms.options._validate_roe (loaded by options.lua) which knows
  -- the per-category value tables. Resolved at call time so group.lua does
  -- not need options.lua to be loaded first.
  if payload._sms_roe then
    if not (sms.options and type(sms.options._validate_roe) == "function") then
      log.error(method .. ": _sms_roe payload but sms.options._validate_roe not loaded")
      return nil
    end
    local cat = group_handle:get_category()
    local ok, msg = sms.options._validate_roe(payload.value, cat)
    if not ok then
      log.warn(method .. ": " .. (msg or "roe validation failed") .. "; group '" .. tostring(group_handle.name) .. "' — not applied")
      return nil
    end
  end
  local raw = Group.getByName(group_handle.name)
  if not raw then
    log.warn(method .. ": group '" .. tostring(group_handle.name) .. "' disappeared between is_alive and apply")
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
  -- hold(): "Nothing" works for air (DCS interprets as loiter) but DCS
  -- rejects it as a runtime task on ground. Replace with a Mission to
  -- the group's current position at speed 0 — that's how MOOSE / common
  -- mission scripts stop a ground unit.
  if task._sms_verb == "hold" then
    if category ~= "airplane" and category ~= "helicopter" and g then
      local cur = g:get_position()
      if cur then
        task.id = "Mission"
        task.params = {
          route = {
            points = {
              {
                x            = cur.x,
                y            = cur.z,
                alt          = cur.y,
                type         = "Turning Point",
                action       = "Off Road",
                speed        = 0,
                speed_locked = true,
                task         = { id = "ComboTask", params = { tasks = {} } },
              },
            },
          },
        }
      end
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

  -- Default waypoint speed for surface categories. DCS aircraft fall back
  -- to the group's cruise speed when speed is unset on a waypoint, but
  -- ground/ship/train units silently sit still without an explicit value.
  -- Picked per-category from common cruise speeds; users can override via
  -- opts.speed on the builder.
  if not is_air and not pt.speed then
    local default_speed = ({ground = 8.33, ship = 5, train = 13.89})[category] or 8.33
    pt.speed        = default_speed
    pt.speed_locked = true
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
      log.warn("set_task: group '" .. tostring(name) .. "' gone before deferred dispatch")
      return
    end
    local ctrl_now = raw_now:getController()
    if not ctrl_now then
      log.warn("set_task: group '" .. tostring(name) .. "' has no controller at deferred dispatch")
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
-- set_task).
--
-- DCS pushTask is *partially* LIFO. Empirically (verified with parallel
-- M-1 Abrams runs, see commit history around the move_to speed fix):
--
--   * Short-lived tasks (attack / bomb / land — claim from earlier
--     framework versions, not re-verified post-task-refactor) interrupt
--     the current task, run to completion, then the previous task
--     resumes. If you find this isn't actually true, file an issue.
--
--   * Mission tasks do NOT stack with each other under any wrapping.
--     We confirmed all three permutations behave identically — the
--     pushed Mission replaces the active one, AI does not return to
--     the original target:
--       - bare Mission   +  push bare Mission        -> replaces
--       - ComboTask{M}   +  push ComboTask{M}        -> replaces
--       - ComboTask{M}   +  push bare Mission        -> replaces
--     Wrapping in ComboTask is NOT a workaround. Don't reach for it.
--
-- For "via B then to A" semantics, use a multi-waypoint route (planned
-- for v1.1) or chain via timer/event callbacks.
sms.group.push_task = function(g, task)
  local raw = _validate_apply("push_task", g, task)
  if not raw then return false end
  local category = g:get_category()
  _adapt_task_for_category(task, category, g)
  local name = g.name
  sms.timer.after(_DEFER_SECONDS, function()
    local raw_now = Group.getByName(name)
    if not raw_now then
      log.warn("push_task: group '" .. tostring(name) .. "' gone before deferred dispatch")
      return
    end
    local ctrl_now = raw_now:getController()
    if not ctrl_now then
      log.warn("push_task: group '" .. tostring(name) .. "' has no controller at deferred dispatch")
      return
    end
    local ok, err = pcall(ctrl_now.pushTask, ctrl_now, task)
    if not ok then
      log.error("push_task: DCS rejected task for '" .. tostring(name) .. "' (deferred): " .. tostring(err))
    end
  end)
  return true
end

-- ============================================================
-- set_command (apply API for sms.commands builders)
-- ============================================================

-- Dispatch a command from sms.commands to the group's controller. Wraps
-- Group:getController():setCommand(cmd). Unlike set_task, no deferred
-- dispatch — commands have no observed same-frame race.
sms.group.set_command = function(g, cmd)
  if type(cmd) ~= "table" or type(cmd._sms_verb) ~= "string" then
    log.warn("set_command: command must be built via sms.commands.* (missing _sms_verb)")
    return false
  end
  local raw = _validate_apply("set_command", g, cmd)
  if not raw then return false end
  local ctrl = raw:getController()
  if not ctrl then
    log.warn("set_command: group '" .. tostring(g.name) .. "' has no controller")
    return false
  end
  local ok, err = pcall(ctrl.setCommand, ctrl, { id = cmd.id, params = cmd.params })
  if not ok then
    log.error("set_command: DCS rejected command for '" .. tostring(g.name) .. "': " .. tostring(err))
    return false
  end
  return true
end

-- Sugar constructor: sms.group("name") -> handle | nil + log.
-- The factory lives in sms.lua; this call wires it up using Group.getByName
-- as the existence check.
sms._make_callable_handle(sms.group, Group.getByName, log)
