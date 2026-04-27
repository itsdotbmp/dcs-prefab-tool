# dcs-sms Framework — `sms.events` v1

**Date:** 2026-04-26 (amended 2026-04-27)
**Status:** Approved (brainstorm phase)
**Scope:** Sixth framework module. Second behavioral primitive (after `sms.timer`). A pub/sub signal bus where DCS world events are pre-registered emitters and users can also emit custom signals. Adds entity-scoped subscription sugar to existing `sms.unit` and `sms.group` modules. Extends `sms.unit.destroy()` with an opt-in event-emission mode.

## Amendments (post-implementation, 2026-04-27)

After hands-on testing, two refinements landed before merge — the original v1 was kept in its branch but never tagged. The amendments are:

1. **`evt.initiator_group_name` added to the normalized payload.** Captured from the raw DCS object at event time (not via `sms.unit:get_group()` which refuses dead units). Enables `g:connect` filters to work for dead initiators without log spam.
2. **`g:connect(DEAD, fn)` semantic changed from per-unit to "group fully dead."** Fires once when the last unit in the group dies, deferred one sim frame so DCS state has settled. All other entity-scoped events on `g:connect` keep per-unit semantics. Per-unit-death is still available via `sms.events.connect(DEAD, fn)` with manual filtering.
3. **`sms.unit.destroy(u, opts)` opt-in event mode.** Pass `{emit_event = true}` to synthesize a DEAD event onto the bus after the unit is removed. Default is silent (matching DCS native behavior).

## Goal

Build a small pub/sub bus that:

- Wraps DCS's single-handler `world.addEventHandler` API so multiple subscribers can listen to specific event types independently.
- Translates raw DCS event IDs to friendly string names (`world.event.S_EVENT_DEAD` → `"dead"`) exposed as `ALL_CAPS` constants on `sms.events`.
- Wraps raw DCS unit references in the event payload as `sms.unit` handles so user callbacks stay in the framework's idiom.
- Lets user mission code emit its own custom signals through the same bus (`sms.events.emit("convoy_arrived", convoy)`), enabling Godot-style decoupling between event producers and consumers.
- Adds `:connect(name, fn)` sugar to `sms.unit` and `sms.group` handles that pre-filters events to ones initiated by the entity itself.

This is the "reactive missions" foundation. With `sms.spawn` (just landed) the user can put things in the world; with `sms.events` they can react to what those things do.

## User value

After this iteration the user can write:

```lua
-- Subscribe to a DCS-emitted event globally
local conn = sms.events.connect(sms.events.DEAD, function(evt)
  sms.log.info(evt.initiator:get_name() .. " was killed at " .. evt.time)
end)

-- Disconnect when done
conn:disconnect()

-- Entity-scoped sugar — fires only when this group's units die
local convoy = sms.group.create({...})
convoy:connect(sms.events.DEAD, function(evt)
  sms.log.info("convoy lost: " .. evt.initiator:get_name())
end)

-- Custom signal bus — anyone can emit, anyone can subscribe
sms.events.connect("convoy_arrived", function(convoy, status)
  discord:send(convoy:get_name() .. " arrived: " .. status)
end)
sms.events.emit("convoy_arrived", convoy, "intact")
```

…with no inheritance, no SPAWN-style classes, no MOOSE EVENTHANDLER scaffolding. The DCS event payload is normalized into a single ergonomic table; user-emitted signals pass through verbatim.

## Scope

### In scope (v1)

**One new module file `framework/events.lua`** — single file, ~200 lines. Loaded last in the framework load order (after `spawn.lua`).

**One small change to `framework/sms.lua`** — add a shared `sms._make_handle(module, name)` helper for unverified handle construction. Used by the events normalizer to wrap units that may already be dead. Also collapses a line of duplication out of `sms._make_callable_handle`.

**Public API on `sms.events`:**

- Constants: `sms.events.<NAME>` for every `world.event.S_EVENT_<NAME>`. Auto-derived at module load. Examples: `sms.events.BIRTH = "birth"`, `sms.events.DEAD = "dead"`, `sms.events.PILOT_DEAD = "pilot_dead"`, `sms.events.MISSION_START = "mission_start"`. The string values are exactly the constant name lowercased (with `S_EVENT_` stripped).
- `sms.events.connect(name, fn) -> Connection handle | nil + log` — subscribe to a signal.
- `sms.events.emit(name, ...) -> nil` — emit a custom signal. Args passed verbatim to subscribers.
- `sms.events.disconnect(conn) -> bool` — cancel a subscription. Idempotent (true once, false thereafter).
- `sms.events.is_active(conn) -> bool` — silent probe.

**Connection handle methods (via metatable `__index = sms.events`):**

- `conn:disconnect()` — same as `sms.events.disconnect(conn)`.
- `conn:is_active()` — same as `sms.events.is_active(conn)`.

**Entity sugar added to existing modules:**

- `sms.unit.connect(self, name, fn) -> Connection | nil + log` — fires only when `evt.initiator.name == self.name`.
- `sms.group.connect(self, name, fn) -> Connection | nil + log` — fires only when `evt.initiator:get_group()` matches this group. Per-unit dispatch (a 4-vehicle group losing all 4 fires the callback 4 times).
- Both reject (log + return nil) at connect time if the requested event has no entity scope (e.g., `MISSION_START`).

**Normalized DCS event payload** — single `evt` table arg to subscribers:

| Field | Type | When present |
|---|---|---|
| `evt.name` | string | always (the friendly name, e.g., `"dead"`) |
| `evt.id` | number | always (raw DCS `S_EVENT_*` id, escape hatch) |
| `evt.time` | number | always (sim time) |
| `evt.initiator` | `sms.unit` handle | when raw event has `.initiator` (most events) |
| `evt.target` | `sms.unit` handle | on `hit`, `kill` |
| `evt.weapon_type` | string | on `shot`, `hit` (from `weapon:getTypeName()`) |
| `evt.place_name` | string | on `takeoff`, `land` (from `place:getName()`) |

`evt.initiator` and `evt.target` are returned as `sms.unit` handles even when the underlying unit is already destroyed (`evt.initiator:is_alive()` returns `false`, but `:get_name()` still works from cached state).

**Custom signal payload** — verbatim:

```lua
sms.events.emit("foo", a, b, c)
sms.events.connect("foo", function(a, b, c) ... end)  -- receives exactly those args
```

**One smoke test `framework/test/smoke_events.sh`** — bash, drives the bridge. Hybrid: synthetic `emit()`-based assertions for bus mechanics (fast, exhaustive), plus one live-DCS section that spawns + destroys a unit to verify the world-handler wiring round-trip.

### Out of scope (v1)

- **Pause/resume on Connection.** Adds state machine; same call as `sms.timer` made.
- **Bulk `disconnect_all(name)` / `disconnect_all()`.** Trivial to add later.
- **Filter predicates baked into `connect`** (`connect(DEAD, fn, predicate)`). User can `if ... then` inside the callback. Entity sugar already covers the 90% case.
- **Wildcard subscriptions** (`connect("*", fn)`). Niche; easy add later.
- **~~Synthetic "group fully dead" event.~~** *(landed in 2026-04-27 amendment — `g:connect(DEAD, fn)` now has this semantic.)*
- **`return false` from a callback to self-cancel.** Magical; user should call `conn:disconnect()` explicitly from inside the callback (closure is in scope).
- **`sms.events.once(name, fn)` helper.** Three lines for the user to roll themselves; not worth the API surface.
- **Cross-mission persistence.** Framework re-loads fresh per mission.
- **Uninstall world handler** (teardown of the entire events subsystem).
- **Per-event throttling/debouncing.** Compose with `sms.timer`.
- **`sms.weapon` / `sms.airbase` handles in the payload.** Tracked as issue #10 — when those modules ship, `evt.weapon` and `evt.place` will be added alongside the existing `evt.weapon_type` / `evt.place_name` strings (purely additive).

## Constraints

- Lua 5.1 (DCS mission environment). No `goto`, no `//`, no Lua 5.2+ idioms.
- DCS exposes a single-handler API (`world.addEventHandler`). The framework installs ONE handler for the lifetime of the mission load and dispatches to all subscribers internally. Lazy install on first `connect()`.
- Failure model: log + return nil/false, never throw. User callback errors are caught via `pcall`, logged, and dispatch continues to remaining subscribers.
- No DCS objects (raw units, weapons, airbases) leak into user callbacks — the "stay in `sms.*` land" promise. Fields we can't wrap as `sms.*` handles yet (weapon, place) are stringified.
- The module name `sms.events` does not collide with any DCS global.

## Architecture

`framework/events.lua` — single file, ~200 lines. Three layers:

```lua
-- 1. Module-level state (file-local)
local _subscribers              -- _subscribers[name] = { conn, conn, ... }
local _world_handler_installed  -- one-shot guard
local _id_to_name               -- numeric DCS id -> friendly string
local _entity_scoped            -- whitelist of event names with .initiator

-- 2. Constants (sms.events.BIRTH = "birth", ...) auto-derived from world.event

-- 3. Connection handle metatable: {__index = sms.events}
--    so conn:disconnect() dispatches via sms.events.disconnect(conn)

-- 4. Module functions: connect, emit, disconnect, is_active
-- 5. Entity sugar: sms.unit.connect, sms.group.connect
```

### Load order

```
sms.lua → log.lua → utils.lua → group.lua → unit.lua → area.lua → timer.lua → spawn.lua → events.lua
```

Entity sugar requires `sms.unit` and `sms.group` modules to exist before `events.lua` runs.

### Constants auto-derivation

At module load time, walk `world.event`:

```lua
for k, v in pairs(world.event) do
  if type(k) == "string" and k:match("^S_EVENT_") then
    local short = k:gsub("^S_EVENT_", "")
    local lname = short:lower()
    sms.events[short] = lname           -- e.g. sms.events.BIRTH = "birth"
    _id_to_name[v]    = lname           -- 15 -> "birth"
  end
end
```

This automatically picks up new events when DCS patches add them. New events default to NOT entity-scoped (safe — entity sugar will reject them) until added to the `_entity_scoped` whitelist.

### `_entity_scoped` whitelist

Hand-maintained list of event names that have a meaningful `initiator` field. Includes (at minimum): `birth`, `dead`, `hit`, `kill`, `takeoff`, `land`, `crash`, `ejection`, `pilot_dead`, `shot`, `engine_startup`, `engine_shutdown`, `refueling`, `refueling_stop`, `player_enter_unit`, `player_leave_unit`, `human_failure`, `unit_lost`, `shooting_start`, `shooting_end`. Excludes: `mission_start`, `mission_end`, `base_captured`, `mark_added`, `mark_change`, `mark_removed`, `daynight`, `score`, `simulation_start`. Final list to be settled in implementation.

### Dispatch flow

**DCS event arrives:**
```
world handler onEvent(self, raw)
  evt = _normalize_event(raw)
  subs = _subscribers[evt.name]      -- nil if nobody subscribed: no-op
  snapshot = shallow_copy(subs)      -- so mid-dispatch disconnects don't mutate iteration
  for each conn in snapshot:
    if conn.active: pcall(conn.fn, evt); log on error and continue
```

**User emit:**
```
sms.events.emit(name, ...)
  subs = _subscribers[name]
  snapshot = shallow_copy(subs)
  for each conn in snapshot:
    if conn.active: pcall(conn.fn, ...); log on error and continue
```

Same dispatch core. Only difference: DCS path normalizes the raw event into a single `evt` arg first; user path passes args verbatim.

### Entity sugar implementation (illustrative — `sms.unit.connect`)

```lua
sms.unit.connect = function(self, name, fn)
  if not _entity_scoped[name] then
    log.error("connect: event '" .. tostring(name) .. "' has no entity scope")
    return nil
  end
  local target_name = self.name
  return sms.events.connect(name, function(evt)
    if evt.initiator and evt.initiator.name == target_name then
      fn(evt)
    end
  end)
end
```

`sms.group.connect` is the same shape; the filter is:
```lua
if evt.initiator then
  local g = evt.initiator:get_group()
  if g and g.name == self.name then fn(evt) end
end
```
`get_group()` may return nil (group GC'd or unit was solo) — treat as "no match," not an error.

The closure inside the entity-sugar `connect` doesn't need its own `pcall`: the outer dispatcher already wraps each subscriber call in `pcall`.

### `_normalize_event(raw)` — full spec

Internal. Builds the `evt` payload:

```lua
local function _normalize_event(raw)
  local evt = {
    id   = raw.id,
    name = _id_to_name[raw.id] or ("unknown_" .. tostring(raw.id)),
    time = raw.time,
  }
  if raw.initiator then
    local ok, n = pcall(raw.initiator.getName, raw.initiator)
    if ok and n then evt.initiator = sms._make_handle(sms.unit, n) end
  end
  if raw.target then
    local ok, n = pcall(raw.target.getName, raw.target)
    if ok and n then evt.target = sms._make_handle(sms.unit, n) end
  end
  if raw.weapon then
    local ok, t = pcall(raw.weapon.getTypeName, raw.weapon)
    if ok and t then evt.weapon_type = t end
  end
  if raw.place then
    local ok, p = pcall(raw.place.getName, raw.place)
    if ok and p then evt.place_name = p end
  end
  return evt
end
```

Every DCS-side method call is `pcall`-wrapped. Half-deconstructed unit/weapon/place objects are a real failure mode in DCS during destruction events — a field that fails to extract just stays nil; the rest of the event still dispatches.

### World-handler lifecycle

```lua
local function _ensure_world_handler()
  if _world_handler_installed then return end
  _world_handler_installed = true
  world.addEventHandler({
    onEvent = function(self, raw)
      local evt = _normalize_event(raw)
      local subs = _subscribers[evt.name]
      if not subs then return end
      local snapshot = {}
      for i, c in ipairs(subs) do snapshot[i] = c end
      for _, conn in ipairs(snapshot) do
        if conn.active then
          local ok, err = pcall(conn.fn, evt)
          if not ok then log.error("dispatch '" .. evt.name .. "': " .. tostring(err)) end
        end
      end
    end,
  })
end
```

Called at the top of `sms.events.connect` (only). One install for the lifetime of the mission load. No teardown API — there is no realistic use case for tearing down the entire events subsystem mid-mission.

### Connection handle state

```
{ name = string, fn = function, active = bool }
```

Identity-checked via `getmetatable(conn) == _conn_mt` in `disconnect` and `is_active` so callers can't slip arbitrary tables in.

## Decisions (made autonomously, recorded for revisit)

- **Verb pair `connect`/`disconnect`** instead of `on`/`off` or `subscribe`/`unsubscribe`. User explicitly chose this — Godot signal-bus mental model. Different verbs from `sms.timer.after()` / `:stop()` is intentional: timers create things, signals connect to things — different concepts.
- **All ~30+ DCS events get friendly names up front, auto-derived from `world.event`.** No tight-core / common-set tier system. One-time setup, done.
- **`ALL_CAPS` constants** (`sms.events.BIRTH = "birth"`) recommended; raw strings (`"birth"`) also work. Constants give typo safety and discoverability.
- **Wrapped `sms.unit` handles in payload, not raw DCS objects.** "Stay in sms.* land" promise. Dead units come back as handles with `is_alive() == false`.
- **Stringify `weapon` and `place`** as `evt.weapon_type` / `evt.place_name` since `sms.weapon` and `sms.airbase` modules don't exist yet. Tracked as issue #10 for additive upgrade later.
- **No `return false` self-cancel.** User explicitly rejected this as too magical. Caller closes the closure over `conn` and calls `conn:disconnect()` explicitly.
- **No `sms.events.once(name, fn)` helper.** User explicitly rejected. Three lines to roll your own.
- **No filter predicates on `connect`.** Entity sugar covers the common case; everything else fits inside the callback.
- **Entity sugar `g:connect(DEAD, fn)` fires once when the group is fully dead** (amendment 2026-04-27). All other entity-scoped events on `g:connect` (HIT, KILL, TAKEOFF, LAND, etc.) still fire per-unit — those have no sensible aggregate meaning. The DEAD case uses an internal `fired_once` latch and a one-frame deferred `Group:getSize()` check to handle DCS's stale-state-after-Unit:destroy() behavior. Per-unit-death is still available via `sms.events.connect(DEAD, fn)` with manual filtering on `evt.initiator_group_name`.
- **`sms.unit.destroy(u, opts)` opt-in event emission** (amendment 2026-04-27). `opts.emit_event = true` synthesizes a DEAD event onto the bus after Unit:destroy() returns. Captures the unit's group name BEFORE destroy (raw DCS object can no longer answer `:getGroup()` afterward). Default is silent — matches DCS's native behavior for programmatic destroys.
- **`evt.initiator_group_name` in the normalized payload** (amendment 2026-04-27). Captured from `raw.initiator:getGroup():getName()` while the raw DCS object is still responsive (one frame after death is usually enough). Replaces the broken v1 approach of calling `sms.unit:get_group()` on a dead handle (logs error + returns nil).
- **Entity sugar rejects non-entity events** at connect time with log + nil. (`g:connect(MISSION_START, fn)` is invalid.)
- **Lazy install of the world handler** on first `connect()` call. No upfront cost if the user never subscribes.
- **Verbatim multi-arg dispatch for user emits.** `emit("foo", a, b)` → `fn(a, b)`. DCS events stay single-arg-`evt` because the DCS handler only ever produces one normalized table.
- **Snapshot subscriber list before dispatching.** A subscriber that disconnects mid-dispatch (or itself) won't mutate the iteration.
- **`_entity_scoped` is a hand-maintained whitelist.** Alternative is runtime introspection; whitelist is simpler and faster. New DCS events default to non-entity-scoped (safe).
- **Connection identity check via `getmetatable(conn) == _conn_mt`.** Same protection that `sms.timer` uses.
- **Add `sms._make_handle(module, name)` to `sms.lua`** as a shared unverified-construction helper. Used by the normalizer; also collapses one line of duplication in `_make_callable_handle`.

## Smoke test outline

`framework/test/smoke_events.sh` — host-side bash that drives the bridge.

Hybrid approach: most assertions are synthetic via `sms.events.emit()` (fast, no DCS sleeps required), with one live-DCS section that spawns + destroys a unit to verify the world-handler round-trip.

1. `dcs-sms.exe status` — `mission loaded: true, fresh: true` or bail.
2. Load `sms.lua`, `log.lua`, `utils.lua`, `group.lua`, `unit.lua`, `area.lua`, `timer.lua`, `spawn.lua`, `events.lua`. Each `ok: true`.
3. **Constants exist:**
   - Verify `sms.events.DEAD == "dead"`, `sms.events.MISSION_START == "mission_start"`, `sms.events.PILOT_DEAD == "pilot_dead"`, `sms.events.BIRTH == "birth"`. Spot-check.
4. **Bad-arg validation:**
   - `sms.events.connect(nil, function() end)` → nil; verify log line.
   - `sms.events.connect("foo", "not a function")` → nil; verify log.
   - `sms.events.disconnect("not a conn")` → false; verify log.
   - `sms.events.is_active("garbage")` → false (silent — no log).
5. **Synthetic emit + connect — basic dispatch:**
   - `_G._smoke = {fired=0, last=nil}`.
   - `local conn = sms.events.connect("test_signal", function(x) _G._smoke.fired = _G._smoke.fired + 1; _G._smoke.last = x end)`.
   - `sms.events.emit("test_signal", "hello")`.
   - Verify `_G._smoke.fired == 1`, `_G._smoke.last == "hello"`.
   - Verify `conn:is_active() == true`.
6. **Multiple subscribers, dispatch order:**
   - Connect three subs to `"order_test"`; each appends its index to a list.
   - Emit. Verify list is `{1, 2, 3}`.
7. **Disconnect mid-dispatch is safe:**
   - Two subs on `"x"`; first disconnects the second.
   - Emit. Verify first fired (1 call), second did not, neither raised.
8. **Disconnect idempotent:**
   - `conn:disconnect()` → true. `conn:disconnect()` → false. `conn:is_active()` → false.
9. **Subscriber error doesn't break dispatch:**
   - Two subs: first does `error("boom")`, second increments a counter.
   - Emit. Verify counter == 1; verify `dcs.log` contains a `[sms.events]` error line.
10. **Verbatim multi-arg pass-through:**
    - `connect("multi", function(a, b, c) _G._smoke.args = {a=a, b=b, c=c} end)`.
    - `emit("multi", 1, "two", true)`.
    - Verify `_G._smoke.args.a == 1`, `_G._smoke.args.b == "two"`, `_G._smoke.args.c == true`.
11. **Entity sugar — non-entity event rejected:**
    - Spawn a single-unit ground group via `sms.group.create({...})`.
    - `g:connect(sms.events.MISSION_START, function() end)` → nil; verify log line about no entity scope.
12. **Entity sugar — initiator filter (synthetic):**
    - Spawn two single-unit groups `evt_a` and `evt_b`.
    - `g_a:connect(sms.events.DEAD, fn)` (fires only when `evt_a` is initiator).
    - `sms.events.emit("dead", {initiator=g_a:get_units()[1], name="dead"})` — should fire.
    - `sms.events.emit("dead", {initiator=g_b:get_units()[1], name="dead"})` — should NOT fire.
    - Verify counter == 1.
13. **Live DCS round-trip — DEAD event:**
    - Spawn a single-unit ground group `smoke_evt_target` at a known position via `sms.group.create({...})`.
    - `_G._smoke.dead_evt = nil; sms.events.connect(sms.events.DEAD, function(evt) _G._smoke.dead_evt = evt end)`.
    - Destroy the unit: `Unit.getByName("smoke_evt_target"):destroy()`.
    - Sleep host-side ~1.5s.
    - Verify `_G._smoke.dead_evt ~= nil`, `.name == "dead"`, `.initiator.name == "smoke_evt_target"`, `.initiator:is_alive() == false`, `.time > 0`.
14. **Cleanup** — remove any spawned groups, log `smoke ok`, exit 0.

Total runtime: ~3-4s. Lighter than `smoke_timer.sh`. Step 13 needs DCS unpaused for the sleep window; a `status` re-check before that step bails clearly if not.

## Out-of-band fallbacks

- **DCS half-deconstructed objects on death events:** every `:getName()` etc. in the normalizer is `pcall`-wrapped. Failed extraction just leaves the field nil; rest of the event still dispatches.
- **Subscriber that itself emits an event:** allowed. The new emit is processed within the same call stack (re-entrant). Bounded recursion is the user's responsibility — same constraint as DCS itself.
- **DCS adds new event types in a future patch:** auto-derivation picks them up as constants; they default to non-entity-scoped (entity sugar safely rejects). Friendly name in `evt.name` will be present; `_id_to_name` covers it.

## Related issues

- **#3** — bridge auto-return-prepend ergonomics. Independent of this work.
- **#10** — replace stringified `weapon_type` / `place_name` with `sms.weapon` / `sms.airbase` handles when those modules exist (additive, not a breaking change).

## Open questions

None. All decisions recorded above.
