-- dcs-sms framework: events module (sms.events).
--
-- Pub/sub bus where DCS world events are pre-registered emitters and user
-- mission code can also emit custom signals. Wraps DCS's single-handler
-- world.addEventHandler API so multiple subscribers can listen to specific
-- event types independently.
--
-- API:
--   sms.events.<NAME>                          -> string constant for every world.event.S_EVENT_<NAME>
--   sms.events.connect(name, fn)               -> Connection handle | nil + log
--   sms.events.emit(name, ...)                 -> nil (verbatim args to subscribers)
--   sms.events.disconnect(conn)                -> bool (idempotent)
--   sms.events.is_active(conn)                 -> bool (silent probe)
--
-- Entity sugar on existing modules:
--   u:connect(name, fn)                        -> Connection | nil + log
--   g:connect(name, fn)                        -> Connection | nil + log
--
-- DCS event payload is normalized into {name, id, time, initiator,
-- initiator_group_name, target, weapon_type, place_name}. initiator/target
-- are sms.unit handles (returned even for dead units; :is_alive() returns
-- false). initiator_group_name is captured from the raw DCS object at event
-- time so g:connect filters work even when the initiator is already dead
-- (sms.unit.get_group refuses dead units). User-emitted signals pass args
-- verbatim.
--
-- g:connect semantic: for DEAD specifically, fires once when the group is
-- fully dead (last unit just died). For all other entity-scoped events,
-- fires per-unit (a "group hit" or "group takeoff" has no sensible
-- aggregate meaning).
--
-- Subscriptions are independent. Calling connect (or g:connect / u:connect)
-- twice on the same channel produces two independent Connection handles that
-- each fire once per emit. This applies to all paths including g:connect(DEAD)
-- — its fully-dead-once latch is per-connection, not per-group. Caller is
-- responsible for not double-subscribing if double-firing is unwanted;
-- conn:disconnect() is the escape hatch.
--
-- Loading order: framework/sms.lua -> log.lua -> utils.lua -> group.lua ->
-- unit.lua -> area.lua -> timer.lua -> spawn.lua -> events.lua. Entity
-- sugar requires sms.unit and sms.group to exist; the g:connect(DEAD)
-- deferred check requires sms.timer.
--
-- See docs/superpowers/specs/2026-04-26-framework-events-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.unit) == "table", "framework/unit.lua must be loaded first")
assert(type(sms.group) == "table", "framework/group.lua must be loaded first")
assert(type(sms.timer) == "table", "framework/timer.lua must be loaded first")
local log = sms.log.module("sms.events")
sms.events = sms.events or {}

-- Module-level state (file-local).
local _subscribers = {}                 -- _subscribers[name] = { conn, conn, ... }
local _world_handler_installed = false  -- one-shot guard
local _id_to_name = {}                  -- numeric DCS id -> friendly string

-- Build constants from world.event. For each S_EVENT_FOO with value N,
-- defines sms.events.FOO = "foo" and _id_to_name[N] = "foo". Auto-derives
-- new events when DCS patches add them (they default to non-entity-scoped,
-- which the entity sugar in this module rejects safely).
for k, v in pairs(world.event) do
  if type(k) == "string" and k:match("^S_EVENT_") then
    local short = k:gsub("^S_EVENT_", "")
    local lname = short:lower()
    sms.events[short] = lname
    _id_to_name[v] = lname
  end
end

-- Connection handle metatable. __index points at sms.events so
-- conn:disconnect() dispatches to sms.events.disconnect(conn). Identity-
-- checked in disconnect/is_active so callers can't slip arbitrary tables in.
local _conn_mt = {__index = sms.events}

local function _is_connection(c)
  return type(c) == "table" and getmetatable(c) == _conn_mt
end

-- Build the user-facing evt payload from a raw DCS world event. Every
-- DCS-side method call is pcall-wrapped because half-deconstructed
-- unit/weapon/place objects are a real failure mode in DCS during
-- destruction events. A field that fails to extract just stays nil; the
-- rest of the event still dispatches.
local function _normalize_event(raw)
  local evt = {
    id   = raw.id,
    name = _id_to_name[raw.id] or ("unknown_" .. tostring(raw.id)),
    time = raw.time,
  }
  if raw.initiator then
    local ok, n = pcall(raw.initiator.getName, raw.initiator)
    if ok and n then
      evt.initiator = sms._make_handle(sms.unit, n)
      -- Capture the group name while raw.initiator is still responsive.
      -- For death-shaped events the unit is already gone from is_alive's
      -- perspective, so sms.unit.get_group on the wrapped handle would
      -- log + return nil. The raw DCS object usually still works for one
      -- frame after death, which is enough to extract the group name.
      local ok2, g = pcall(raw.initiator.getGroup, raw.initiator)
      if ok2 and g then
        local ok3, gn = pcall(g.getName, g)
        if ok3 and gn then evt.initiator_group_name = gn end
      end
    end
  end
  if raw.target then
    local ok, n = pcall(raw.target.getName, raw.target)
    if ok and n then evt.target = sms._make_handle(sms.unit, n) end
  end
  if raw.weapon then
    local ok, t = pcall(raw.weapon.getTypeName, raw.weapon)
    if ok and t then evt.weapon_type = t end
    -- Lazy upgrade: if sms.weapon is loaded, also expose the wrapped
    -- handle as evt.weapon. If sms.weapon isn't loaded, evt.weapon stays
    -- nil (current behavior). Closes #10.
    if sms.weapon and sms.weapon.wrap then
      local w = sms.weapon.wrap(raw.weapon)
      if w then evt.weapon = w end
    end
  end
  if raw.place then
    local ok, p = pcall(raw.place.getName, raw.place)
    if ok and p then evt.place_name = p end
  end
  return evt
end

-- Lazy world-handler install. Called from connect(). One install for the
-- lifetime of the mission load; no teardown API.
local function _ensure_world_handler()
  if _world_handler_installed then return end
  _world_handler_installed = true
  world.addEventHandler({
    onEvent = function(self, raw)
      local evt = _normalize_event(raw)
      local subs = _subscribers[evt.name]
      if not subs then return end
      -- Same snapshot semantics as sms.events.emit: snapshot only currently-
      -- active subscribers; mid-dispatch disconnects of subs already in the
      -- snapshot will still fire this iteration (Godot semantics).
      local snapshot = {}
      for _, c in ipairs(subs) do
        if c.active then snapshot[#snapshot + 1] = c end
      end
      for _, conn in ipairs(snapshot) do
        local ok, err = pcall(conn.fn, evt)
        if not ok then
          log.error("dispatch '" .. evt.name .. "': " .. tostring(err))
        end
      end
    end,
  })
end

sms.events.connect = function(name, fn)
  if type(name) ~= "string" then
    log.error("connect: name must be a string, got " .. type(name))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("connect: fn must be a function, got " .. type(fn))
    return nil
  end
  _ensure_world_handler()
  local conn = setmetatable({name = name, fn = fn, active = true}, _conn_mt)
  _subscribers[name] = _subscribers[name] or {}
  table.insert(_subscribers[name], conn)
  return conn
end

sms.events.emit = function(name, ...)
  if type(name) ~= "string" then
    log.error("emit: name must be a string, got " .. type(name))
    return
  end
  local subs = _subscribers[name]
  if not subs then return end
  -- Snapshot only currently-active subscribers. Any connection that was
  -- already inactive before emit() is called is excluded here and will
  -- not fire this iteration. Connections that are disconnected DURING
  -- dispatch were active at snapshot time, are included in the snapshot,
  -- and will still fire for the in-flight emit (Godot semantics).
  -- Subscribers added during dispatch are NOT in the snapshot and take
  -- effect on the next emit.
  local snapshot = {}
  for _, c in ipairs(subs) do
    if c.active then snapshot[#snapshot + 1] = c end
  end
  for _, conn in ipairs(snapshot) do
    local ok, err = pcall(conn.fn, ...)
    if not ok then
      log.error("subscriber for '" .. name .. "' raised: " .. tostring(err))
    end
  end
end

sms.events.disconnect = function(conn)
  if not _is_connection(conn) then
    log.error("disconnect: argument must be a Connection handle")
    return false
  end
  if not conn.active then return false end
  conn.active = false
  local subs = _subscribers[conn.name]
  if subs then
    for i, c in ipairs(subs) do
      if c == conn then
        table.remove(subs, i)
        break
      end
    end
  end
  return true
end

sms.events.is_active = function(conn)
  if not _is_connection(conn) then return false end
  return conn.active == true
end

-- Whitelist of event names with a meaningful .initiator field. Entity
-- sugar (u:connect / g:connect) rejects everything else at connect time
-- so users get a clear error instead of silent never-fires. Hand-
-- maintained — new DCS events default to non-entity-scoped (safe).
local _entity_scoped = {
  birth              = true,
  dead               = true,
  hit                = true,
  kill               = true,
  takeoff            = true,
  land               = true,
  crash              = true,
  ejection           = true,
  pilot_dead         = true,
  shot               = true,
  engine_startup     = true,
  engine_shutdown    = true,
  refueling          = true,
  refueling_stop     = true,
  player_enter_unit  = true,
  player_leave_unit  = true,
  human_failure      = true,
  unit_lost          = true,
  shooting_start     = true,
  shooting_end       = true,
  landing_quality_mark = true,
  landing_after_ejection = true,
  emergency_landing  = true,
}

-- u:connect(name, fn) — fires only when evt.initiator.name == self.name.
-- Returns the wrapped Connection (so :disconnect() works as expected).
sms.unit.connect = function(self, name, fn)
  if not sms._is_handle_of(self, sms.unit) then
    log.error("unit:connect: self must be an sms.unit handle")
    return nil
  end
  if type(name) ~= "string" then
    log.error("unit:connect: event name must be a string, got " .. type(name))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("unit:connect: fn must be a function, got " .. type(fn))
    return nil
  end
  if not _entity_scoped[name] then
    log.error("unit:connect: event '" .. name .. "' has no entity scope")
    return nil
  end
  -- Capture name into a local so the closure doesn't keep a reference to
  -- the caller's self table (defensive; lets the caller drop the handle).
  local target_name = self.name
  return sms.events.connect(name, function(evt)
    if evt.initiator and evt.initiator.name == target_name then
      fn(evt)
    end
  end)
end

-- g:connect(name, fn). Filter uses evt.initiator_group_name (captured at
-- event time from the raw DCS object) so dead initiators still resolve to
-- a group. For DEAD specifically, fires once when the group is fully dead
-- (last unit just died). For all other entity-scoped events, fires per-unit
-- — a "group hit" or "group takeoff" has no sensible aggregate meaning.
sms.group.connect = function(self, name, fn)
  if not sms._is_handle_of(self, sms.group) then
    log.error("group:connect: self must be an sms.group handle")
    return nil
  end
  if type(name) ~= "string" then
    log.error("group:connect: event name must be a string, got " .. type(name))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("group:connect: fn must be a function, got " .. type(fn))
    return nil
  end
  if not _entity_scoped[name] then
    log.error("group:connect: event '" .. name .. "' has no entity scope")
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
