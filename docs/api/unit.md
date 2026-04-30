# `sms.unit` — unit entity wrapper

`sms.unit` is the per-unit entity handle. It mirrors [`sms.group`](group.md) but operates on a single DCS unit: position, heading, pitch, altitude (ASL or AGL), parent group lookup, programmatic destroy, and event sugar.

A handle is a small `{name = "..."}` table that re-resolves through `Unit.getByName` on every method call, so it stays correct after the underlying unit dies. Method-style (`u:get_position()`), module-style (`sms.unit.get_position(u)`), and bare-name (`sms.unit.get_position("Bandit-1")`) calls all work — see [§5 entity handles](../../AGENTS.md#5-entity-handles--the-universal-pattern) for the universal pattern.

All methods follow the framework's [failure model: log + nil, never throw](../../AGENTS.md#3-failure-model-log--nil-never-throw). "Returns X" implicitly means "returns X | nil + log on bad input or dead unit".

**Units (public API):** headings in **degrees** (0=north, 90=east, clockwise, 0–360); pitch in **degrees** (positive = nose up); altitudes in **meters**; coalitions as lowercase strings (`"red"` / `"blue"` / `"neutral"`).

## Loading

Requires `sms.lua`, `log.lua`, `utils.lua`, `group.lua`, `unit.lua`. `:connect` additionally requires `sms.events`. The simplest path is `framework/load_all.lua` — see the [API index](README.md).

## `sms.unit(name)` — constructor

Look up an existing DCS unit by name.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | DCS unit name (the name shown on the F10 map / set in the ME). |

**Returns** — handle on success, `nil` + log otherwise (unit not found, wrong type, etc.).

**Example**

```lua
local bandit = sms.unit("Bandit-1")
if bandit then
  sms.log.info(bandit:get_name() .. " at " .. bandit:get_altitude() .. "m ASL")
end
```

## Methods

### `u:is_alive() → bool`

**Synopsis** — silent presence check. True iff `Unit.getByName(name)` resolves and `:isExist()` returns true.

**Returns** — `bool`. Silent on failure (returns `false` for nil / garbage / dead / unknown names — does not log).

**Example**

```lua
local bandit = sms.unit("Bandit-1")
if not bandit:is_alive() then
  sms.log.info("Bandit-1 is gone")
end
```

### `u:get_name() → string`

**Synopsis** — returns the handle's stored name. No DCS lookup; works even after the unit dies.

**Returns** — `string` (or `nil` if the handle was constructed from garbage).

**Example**

```lua
local bandit = sms.unit("Bandit-1")
sms.log.info("tracking " .. bandit:get_name())
```

### `u:get_coalition() → "red" | "blue" | "neutral"`

**Synopsis** — coalition as a lowercase string.

**Returns** — `"red"`, `"blue"`, or `"neutral"`. Logs and returns `nil` if the unit is dead, or logs as `error` on the (very unlikely) case DCS returns an unknown coalition int.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
if bandit:get_coalition() == "red" then
  sms.log.info("hostile inbound")
end
```

### `u:get_position() → vec3`

**Synopsis** — current world position.

**Returns** — `{x = north, y = altitude, z = east}` (DCS-native vec3, in meters). Logs + nil on dead unit.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
local pos = bandit:get_position()
if pos then
  sms.log.info(string.format("pos: x=%.0f y=%.0f z=%.0f", pos.x, pos.y, pos.z))
end
```

### `u:get_type() → string`

**Synopsis** — DCS type name (the airframe / vehicle type).

**Returns** — `string`, e.g. `"M-2000C"`, `"FA-18C_hornet"`, `"T-72B"`, `"Soldier M4"`. Logs + nil on dead unit.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
if bandit:get_type() == "FA-18C_hornet" then
  sms.log.info("it's a hornet")
end
```

### `u:get_group() → sms.group handle`

**Synopsis** — parent group of this unit, as an [`sms.group`](group.md) handle.

**Returns** — `sms.group` handle. Logs + nil on dead unit.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
local parent_group = bandit:get_group()
if parent_group then
  sms.log.info("part of group " .. parent_group:get_name())
end
```

### `u:get_heading() → number`

**Synopsis** — true heading in **degrees**, normalized to `[0, 360)`. 0 = north, 90 = east, clockwise. Computed from the forward axis of the unit's pose, projected to the horizontal plane.

**Returns** — `number` (degrees). Logs + nil on dead unit.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
local heading = bandit:get_heading()
if heading then
  sms.log.info(string.format("heading %03d", math.floor(heading + 0.5)))
end
```

### `u:get_pitch() → number`

**Synopsis** — pitch angle in **degrees**, positive = nose up. Computed from the y-component of the forward axis (`asin(forward.y)`).

**Returns** — `number` (degrees). Logs + nil on dead unit.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
local pitch = bandit:get_pitch()
if pitch and pitch > 30 then
  sms.log.info("nose-high — climbing or merging")
end
```

### `u:get_altitude(agl?) → number`

**Synopsis** — altitude in **meters**. ASL (above sea level) by default; pass `true` for AGL (terrain height subtracted at the unit's horizontal position via `land.getHeight`).

**Arguments**

| Name | Type | Default | Description |
|---|---|---|---|
| `agl` | `boolean` | `false` | When `true`, returns AGL (ASL minus terrain height at the unit's xz position). |

**Returns** — `number` (meters). Logs + nil on dead unit.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
local asl = bandit:get_altitude()
local agl = bandit:get_altitude(true)
if asl and agl then
  sms.log.info(string.format("alt: %.0fm ASL / %.0fm AGL", asl, agl))
end
```

For pilot-facing feet, convert with [`sms.utils.meters_to_feet`](utils.md).

### `u:destroy(opts?) → true`

**Synopsis** — silently removes the unit from the mission. By default DCS fires **no** event for this — it's a removal, not a death. Pass `{emit_event = true}` to additionally synthesize a `sms.events.DEAD` event onto the bus so reactive code (subscribers, `:connect(DEAD)` listeners on the parent group, etc.) treats the programmatic destroy the same as a combat death.

**Arguments**

| Key | Type | Default | Description |
|---|---|---|---|
| `emit_event` | `boolean` | `false` | When `true`, emits a normalized DEAD event on `sms.events` after the unit is gone. The event payload's `initiator` is a wrapped (dead) `sms.unit` handle and `initiator_group_name` is captured before destroy so listeners that filter by group still match. |

**Returns** — `true` on success. Logs + nil on dead unit (nothing to destroy). When `emit_event = true` is requested but `sms.events` isn't loaded, the destroy still succeeds — the missing emit is logged.

**Example — silent removal (no DEAD event):**

```lua
-- Ferry the wreckage offstage at end-of-mission. No reactive code fires.
sms.unit("Bandit-1"):destroy()
```

**Example — synthesized DEAD event:**

```lua
-- Trigger end-of-mission scoring as if the unit had died in combat.
local cas = sms.group("red-cas-1")
cas:connect(sms.events.DEAD, function(evt)
  sms.log.info("red CAS down at " .. evt.time)
end)

-- Later, force the kill — the connect handler above fires.
sms.unit("Bandit-1"):destroy({emit_event = true})
```

**Notes** — `emit_event` is the right choice when scripted scenarios (cutscenes, scripted attrition, mission-end cleanup) should be observable by the same listeners that handle real combat deaths. Use the default (no event) when you're cleaning up fixtures and explicitly do **not** want subscribers to react.

### `u:connect(event_name, fn) → Connection`

**Synopsis** — entity-scoped event subscription. Wraps [`sms.events.connect`](events.md) and only invokes `fn` when the event's `initiator` is this unit (filtered by `evt.initiator.name == self.name`).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `event_name` | `string` | One of the entity-scopable `sms.events.*` constants (e.g. `sms.events.HIT`, `sms.events.SHOT`, `sms.events.DEAD`, `sms.events.TAKEOFF`, `sms.events.LAND`, `sms.events.PILOT_DEAD`, `sms.events.EJECTION`, `sms.events.ENGINE_STARTUP`, `sms.events.ENGINE_SHUTDOWN`). |
| `fn` | `function(evt)` | Callback. Receives the normalized event payload — see [`events.md`](events.md) for the full payload shape and the complete event list. |

**Returns** — a `Connection` handle (call `:disconnect()` to cancel). Logs + nil if `self` isn't an `sms.unit` handle, if `event_name` isn't a string or isn't in the entity-scope whitelist, or if `fn` isn't a function.

**Example — react when this unit gets hit:**

```lua
local bandit = sms.unit("Bandit-1")
bandit:connect(sms.events.HIT, function(evt)
  sms.log.info(bandit:get_name() .. " hit by " .. (evt.weapon_type or "?"))
end)
```

**Example — log every shot the player takes:**

```lua
local player = sms.unit("Player-1")
local conn = player:connect(sms.events.SHOT, function(evt)
  sms.log.info("player fired " .. (evt.weapon_type or "?"))
end)

-- Later, stop listening:
sms.events.disconnect(conn)
```

**See also** — [`events.md`](events.md) for the bus, the full event-name list, payload structure, and the `_entity_scoped` whitelist; [`sms.group:connect`](group.md) for group-scoped listening (with last-unit-latch semantics for DEAD).
