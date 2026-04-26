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
-- DCS event payload is normalized into {name, id, time, initiator, target,
-- weapon_type, place_name}. initiator/target are sms.unit handles (returned
-- even for dead units; :is_alive() returns false). User-emitted signals
-- pass args verbatim.
--
-- Loading order: framework/sms.lua -> log.lua -> utils.lua -> group.lua ->
-- unit.lua -> area.lua -> timer.lua -> spawn.lua -> events.lua. Entity
-- sugar requires sms.unit and sms.group to already exist.
--
-- See docs/superpowers/specs/2026-04-26-framework-events-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.unit) == "table", "framework/unit.lua must be loaded first")
assert(type(sms.group) == "table", "framework/group.lua must be loaded first")
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
