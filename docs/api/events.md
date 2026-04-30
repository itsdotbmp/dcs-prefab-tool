# `sms.events` — DCS world-event bus and pub/sub signals

`sms.events` is a pub/sub bus that wraps DCS's single-handler `world.addEventHandler` so multiple subscribers can listen to the same event independently. Every `world.event.S_EVENT_FOO` is mirrored as a lowercase string constant (`sms.events.FOO = "foo"`); user code can also `emit` arbitrary custom signals on the same bus. Subscribers always receive a normalized event payload — `initiator` and `target` are wrapped `sms.unit` handles, even when the underlying unit is already dead.

This page is the canonical reference for `sms.events`. Failure semantics for every function on this page follow the [framework failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw): bad input is logged and `nil` (or `false`) is returned — nothing throws.

## Loading

`framework/events.lua` requires `sms.unit` to be loaded first (the normalizer wraps `initiator` / `target` as `sms.unit` handles). The standard `load_all.lua` chain handles this. Loading `sms.weapon` before `sms.events` is optional — when present, `evt.weapon` is upgraded to an [`sms.weapon`](weapon.md) handle on `SHOT` / `HIT`; otherwise that field stays nil and `evt.weapon_type` (string) is the only weapon-side data.

## Event-name constants

For every `world.event.S_EVENT_FOO` that DCS exposes, the framework defines `sms.events.FOO = "foo"`. The mirroring is automatic — new events added by future DCS patches show up without a framework change (they default to non-entity-scoped, which the entity sugar safely rejects). The constants every mission-script writer touches:

| Constant | String | Notes |
|---|---|---|
| `sms.events.SHOT` | `"shot"` | Weapon released. `evt.weapon_type` set; `evt.weapon` set if `sms.weapon` is loaded. |
| `sms.events.HIT` | `"hit"` | Weapon impacted a unit. `evt.target` is the unit that was hit. |
| `sms.events.KILL` | `"kill"` | Initiator scored a kill on `evt.target`. |
| `sms.events.DEAD` | `"dead"` | Unit died. `evt.initiator` is the dead unit. |
| `sms.events.BIRTH` | `"birth"` | Unit spawned / appeared. |
| `sms.events.TAKEOFF` | `"takeoff"` | `evt.place_name` is the airbase / FARP. |
| `sms.events.LAND` | `"land"` | `evt.place_name` is the airbase / FARP. |
| `sms.events.CRASH` | `"crash"` | Aircraft crash (distinct from DEAD). |
| `sms.events.EJECTION` | `"ejection"` | Pilot ejected; `evt.initiator` is the ejection seat / pilot. |
| `sms.events.PILOT_DEAD` | `"pilot_dead"` | Pilot killed (aircraft may still be flying). |
| `sms.events.ENGINE_STARTUP` | `"engine_startup"` | |
| `sms.events.ENGINE_SHUTDOWN` | `"engine_shutdown"` | |
| `sms.events.REFUELING` | `"refueling"` | A/A refuel boom contact. |
| `sms.events.REFUELING_STOP` | `"refueling_stop"` | A/A refuel boom disconnect. |
| `sms.events.PLAYER_ENTER_UNIT` | `"player_enter_unit"` | Player slotted into `evt.initiator`. |
| `sms.events.PLAYER_LEAVE_UNIT` | `"player_leave_unit"` | |
| `sms.events.MISSION_START` | `"mission_start"` | No `initiator`. Not entity-scopable. |
| `sms.events.MISSION_END` | `"mission_end"` | No `initiator`. Not entity-scopable. |

The full set is whatever DCS exposes — iterate `world.event` to confirm. Anything matching `S_EVENT_*` becomes a constant on `sms.events`.

### Fabricated constant

| Constant | String | Notes |
|---|---|---|
| `sms.events.WEAPON_IMPACT` | `"weapon_impact"` | **Not** a DCS event. Fired by the [`sms.weapon`](weapon.md) tracker when a tracked weapon impacts. Payload: `{weapon, impact_position, time}` (verbatim, not the normalized payload below). See [`weapon.md`](weapon.md). |

## Functions

### `sms.events.connect(name, fn) → Connection | nil`

**Synopsis** — subscribe `fn` to events named `name`. The world handler is installed lazily on the first connect.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | Event name. Use a constant (`sms.events.SHOT`) for DCS events, or any string for custom signals. |
| `fn` | `function` | Receives the normalized payload for DCS events, or whatever was passed to `emit(...)` for custom signals. Errors raised by `fn` are caught — they log under `[sms.events]` but do not abort dispatch to other subscribers. |

**Returns** — a `Connection` handle (see below). On bad input: nil + log.

**Example**

```lua
-- Log every shot fired by a red coalition unit, but only if we know what
-- they fired. evt.weapon_type is the string DCS type; evt.weapon (if
-- sms.weapon is loaded) is a wrapped handle.
sms.events.connect(sms.events.SHOT, function(evt)
  if not evt.initiator then return end
  if evt.initiator:get_coalition() ~= "red" then return end
  sms.log.info(string.format(
    "%s fired %s at t=%.1f",
    evt.initiator:get_name(),
    evt.weapon_type or "<unknown>",
    evt.time
  ))
end)
```

### `sms.events.emit(name, ...) → nil`

**Synopsis** — dispatch to every active subscriber of `name`. Args pass verbatim; the framework does **not** normalize user-emitted payloads.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | Channel name. Free-form for custom signals. |
| `...` | any | Forwarded verbatim to each subscriber. For DCS event names, the framework still skips normalization — only the world handler builds normalized payloads. |

**Returns** — nil. On bad input: log + early return.

### `sms.events.disconnect(conn) → bool`

**Synopsis** — drop a subscription. Idempotent — calling it twice on the same handle returns `false` the second time.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `conn` | `Connection` | Handle returned by `connect`. Identity-checked; arbitrary tables are rejected. |

**Returns** — `true` on first successful disconnect, `false` on subsequent calls or if `conn` is not a Connection handle (logs a warning in the latter case).

### `sms.events.is_active(conn) → bool`

**Synopsis** — silent probe. Returns `true` if `conn` is a live Connection, `false` otherwise (including for non-Connection inputs — no log).

## The `Connection` handle

`connect` returns a small handle with a private metatable. It is not a plain table — the bus identity-checks it before accepting it in `disconnect` / `is_active`. The metatable's `__index` points at `sms.events`, so the method-style forms work:

```lua
local conn = sms.events.connect("phase_two_start", on_phase_two)

conn:is_active()   -- true
conn:disconnect()  -- true (drops the subscription)
conn:disconnect()  -- false (idempotent)
conn:is_active()   -- false
```

Calling `connect` twice on the same channel produces two independent handles that each fire once per `emit`. Disconnect is per-handle.

## Normalized event payload

Every subscriber attached to a DCS event receives a single table argument:

```lua
{
  id                   = <int>,        -- DCS S_EVENT_* numeric id
  name                 = "<string>",   -- "shot", "hit", "dead", ...
  time                 = <number>,     -- sim seconds
  initiator            = <sms.unit | nil>,
  initiator_group_name = <string | nil>,
  target               = <sms.unit | nil>,
  weapon_type          = <string | nil>,
  weapon               = <sms.weapon | nil>,
  place_name           = <string | nil>,
}
```

| Field | Type | When nil |
|---|---|---|
| `id` | `number` | Never nil for DCS events. |
| `name` | `string` | Never nil. Falls back to `"unknown_<id>"` if DCS adds an event the framework hasn't seen. |
| `time` | `number` | Never nil for DCS events (sim seconds). |
| `initiator` | [`sms.unit`](unit.md) handle | Nil for events without an initiator (e.g. `MISSION_START`), or if the raw DCS object refused to yield a name during normalization. |
| `initiator_group_name` | `string` | Captured eagerly from the raw DCS object at event time, so it survives death-shaped events even after the wrapped handle's `:get_group()` would log + nil. Nil if the initiator had no group, or if the lookup failed. |
| `target` | [`sms.unit`](unit.md) handle | Nil for events with no target, or if `getName` failed during normalization. |
| `weapon_type` | `string` | Nil unless `raw.weapon` is present (`SHOT` / `HIT`). |
| `weapon` | [`sms.weapon`](weapon.md) handle | Nil unless `raw.weapon` is present **and** `sms.weapon` is loaded. Lazy upgrade — older code that only used `weapon_type` is unaffected. |
| `place_name` | `string` | Nil unless the raw event has a `place` (typical for `TAKEOFF` / `LAND`). |

`initiator` and `target` are always wrapped `sms.unit` handles when present, **even if the underlying unit is already dead**. `:is_alive()` returns false on those, but `:get_name()`, `:get_coalition()` etc. still work because they don't require a live DCS object.

User-emitted signals (`sms.events.emit(name, ...)`) bypass the normalizer entirely — whatever you pass is what the subscriber sees.

## Snapshot semantics

When an event fires, the bus snapshots the currently-active subscriber list **before** invoking any of them. The consequences:

- **Disconnects during dispatch** — a subscriber that disconnects another subscriber mid-dispatch does not stop the just-disconnected one from firing this iteration if it was already in the snapshot. It will of course not fire on the next emit.
- **Disconnects of self** — a subscriber that disconnects itself still completes its current call; it just won't fire again.
- **Subscriptions during dispatch** — `connect()` calls made from inside a subscriber take effect on the **next** emit, not the current one.
- **Errors in a subscriber** — caught and logged under `[sms.events]`. Other subscribers in the same snapshot still run.

## Entity-scoped sugar

[`sms.unit`](unit.md) and [`sms.group`](group.md) handles each have a `:connect(event_name, fn)` method that wraps `sms.events.connect` with an initiator filter. They live in `unit.lua` / `group.lua`, but both gate on the whitelist `sms.events._entity_scoped` — events without a meaningful `initiator` field cannot be entity-scoped and are rejected with a log.

```lua
-- Fires only when evt.initiator is exactly this unit.
unit_handle:connect(sms.events.HIT, fn)

-- For DEAD specifically, fires once when the *last* unit in the group dies
-- (the last-unit latch). Filter is on evt.initiator_group_name.
group_handle:connect(sms.events.DEAD, fn)

-- All other entity-scoped events fire per-unit-event for any unit in the
-- group. Filter is on evt.initiator_group_name.
group_handle:connect(sms.events.HIT, fn)
```

Both helpers return the underlying `Connection` handle so `:disconnect()` works as expected.

### Whitelist of entity-scopable events

Connecting any other event name on a unit or group handle returns nil + log.

```
birth, dead, hit, kill, takeoff, land, crash, ejection, pilot_dead, shot,
engine_startup, engine_shutdown, refueling, refueling_stop,
player_enter_unit, player_leave_unit, human_failure, unit_lost,
shooting_start, shooting_end, landing_quality_mark,
landing_after_ejection, emergency_landing
```

Non-listed events (e.g. `MISSION_START`, `MISSION_END`, `WEAPON_IMPACT`) must be subscribed via `sms.events.connect` directly.

## Worked examples

### Example 1 — bare `connect` with a SHOT filter

```lua
-- Print a one-line tag whenever a blue aircraft fires an AIM-120.
local shot_conn = sms.events.connect(sms.events.SHOT, function(evt)
  if not evt.initiator then return end
  if evt.initiator:get_coalition() ~= "blue" then return end
  if evt.weapon_type ~= "weapons.missiles.AIM_120C" then return end

  sms.log.info(string.format(
    "AMRAAM away from %s (group %s) at t=%.1f",
    evt.initiator:get_name(),
    evt.initiator_group_name or "<none>",
    evt.time
  ))
end)

-- Later, when the script wants to stop listening:
shot_conn:disconnect()
```

### Example 2 — `group:connect(DEAD, ...)` with last-unit latch

```lua
-- Spawn a 4-tank ground group. The DEAD callback should fire exactly once,
-- when the last of the four tanks dies — not four separate times.
local platoon = sms.group.create({
  name     = "red-armor-1",
  position = {x = -50000, y = 0, z = -50000},
  country  = "Russia",
  category = "ground",
  units    = {
    { type = "T-72B", offset = {x =  0, y = 0, z =  0} },
    { type = "T-72B", offset = {x = 20, y = 0, z =  0} },
    { type = "T-72B", offset = {x =  0, y = 0, z = 20} },
    { type = "T-72B", offset = {x = 20, y = 0, z = 20} },
  },
})

platoon:connect(sms.events.DEAD, function(evt)
  -- evt.initiator is the unit whose death tipped the group into "fully dead".
  -- :is_alive() returns false on it, but :get_name() still works.
  sms.log.info("Platoon wiped out — last loss was " .. evt.initiator:get_name())
  sms.events.emit("red_armor_destroyed", {group = "red-armor-1", time = evt.time})
end)
```

### Example 3 — custom `emit` / `connect` for cross-module signaling

```lua
-- Module A: when a strike package crosses the FEBA, fan out a custom signal
-- that any number of unrelated systems can subscribe to. The payload is
-- verbatim — emit does NOT normalize user signals.
local function on_feba_crossed(group_name, ingress_heading_deg)
  sms.events.emit("strike_package_crossed_feba", {
    group     = group_name,
    heading   = ingress_heading_deg,
    time      = sms.timer.now(),
  })
end

-- Module B: SAM site activation logic. Listens on the same channel.
sms.events.connect("strike_package_crossed_feba", function(payload)
  sms.log.info("SAMs going hot for " .. payload.group)
  -- ...flip ROE, retask CAP, etc.
end)

-- Module C: AWACS chatter. Multiple independent subscribers are fine —
-- each connect call produces its own Connection handle.
sms.events.connect("strike_package_crossed_feba", function(payload)
  trigger.action.outText(
    payload.group .. " feet dry, hdg " .. tostring(payload.heading),
    10
  )
end)
```

## Notes

- The world handler is installed on the first `connect` call and lives for the rest of the mission. There is no teardown API — disconnect individual subscriptions instead.
- Names are case-sensitive strings. The mirrored constants are `UPPER_CASE` keys whose **values** are `lower_case` strings. Use the constant (`sms.events.HIT`) rather than spelling the string yourself, so a typo is caught at load time.
- For SHOT / HIT, prefer `evt.weapon` over `evt.weapon_type` when [`sms.weapon`](weapon.md) is loaded — the wrapped handle exposes launcher, release position, tracking, and impact extrapolation.

## See also

- [`unit.md`](unit.md) — `unit_handle:connect`, programmatic destroy with `{emit_event = true}`.
- [`group.md`](group.md) — `group_handle:connect` and the DEAD last-unit latch.
- [`weapon.md`](weapon.md) — `WEAPON_IMPACT` payload and tracking lifecycle.
- [`timer.md`](timer.md) — `sms.timer.now()` is handy for stamping custom emit payloads.
