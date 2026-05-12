# `sms.weapon` — weapon-from-event wrapper with tracking and impact extrapolation

Wraps DCS weapon objects produced by SHOT / HIT events. Unlike units, groups,
and statics, **weapons are not name-addressable in DCS** — `Weapon.getByName`
does not exist. The only way to get an `sms.weapon` handle is from an event
payload (`evt.weapon` on [`sms.events`](events.md) SHOT / HIT events). The
constructor `sms.weapon.wrap` is wired into the events module and is normally
not called by user code.

A handle snapshots release-time state (name, type, category, coalition,
country, launcher, release position / heading / pitch / altitude) at
construction time. Those getters keep working forever — even after the DCS
weapon object is destroyed and the handle has transitioned to `"impacted"` or
`"destroyed"`.

For live in-flight state and a one-shot impact callback, opt in with
`:start_tracking(...)`. Tracking polls `weapon:getPosition` via
[`sms.timer.every`](timer.md) at a configurable rate. When the DCS object
stops existing, the handle transitions to `"impacted"`, the impact position is
extrapolated via `land.getIP` along the last-known forward axis (with
last-known position as fallback), the per-handle `on_impact` callback fires,
and a `sms.events.WEAPON_IMPACT` signal is emitted on the bus.

This page is the canonical reference for `sms.weapon`. For the cross-cutting rules every method follows, see [AGENTS.md §3 failure model](../../framework/AGENTS.md#3-failure-model-log--nil-never-throw), [§4 conventions](../../framework/AGENTS.md#4-conventions-and-units), and [§5 entity handles](../../framework/AGENTS.md#5-entity-handles--the-universal-pattern).
All public calls follow the [framework failure model](../../framework/AGENTS.md#3-failure-model-log--nil-never-throw)
— bad input or wrong-state calls log via `[sms.weapon]` and return `nil` /
`false` rather than throwing. Silent-nil paths (calls that legitimately return
`nil` without logging) are called out per function below.

## State machine

```
                       :destroy()
            ┌────────────────────────────┐
            │                            ▼
   wrap → created ──:start_tracking()──► tracking ──(DCS object gone)──► impacted
            │                            │
            │                            └──:destroy()──► destroyed
            │
            └──:destroy()──► destroyed
```

Forward-only. `:stop_tracking()` returns from `tracking` to `created` (no
impact event fired). `:destroy()` is a silent abort and never fires
`on_impact`. Only natural impact (DCS object disappearing while tracking)
fires the per-handle `on_impact` callback and the `WEAPON_IMPACT` bus event.

## Loading

`sms.weapon` requires `sms.utils`, `sms.unit`, `sms.timer`, and `sms.events`
to be loaded first (in that order). Use [`framework/load_all.lua`](../../framework/load_all.lua)
to load the whole framework in the correct order.

## Constructor

### `sms.weapon.wrap(raw_dcs_weapon) → handle | nil`

**Synopsis** — wrap a raw DCS weapon userdata into an `sms.weapon` handle,
snapshotting all release-time state.

This is normally invoked automatically by [`sms.events`](events.md) to
populate `evt.weapon` on SHOT and HIT events. User code rarely calls it
directly. There is no name-based lookup: `sms.weapon("name")` is **not** a
valid form because DCS does not expose `Weapon.getByName`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `raw_dcs_weapon` | `userdata` / `table` | A live DCS `Weapon` object as delivered by the SHOT / HIT event. |

**Returns** — handle (a table with the `sms.weapon` metatable), or `nil` +
log on failure (bad type, or the weapon's name cannot be read because the
object was already half-deconstructed).

**Example**

```lua
sms.events.connect(sms.events.SHOT, function(evt)
  -- evt.weapon was populated by sms.weapon.wrap() inside the events module.
  -- User code just consumes the handle.
  if evt.weapon then
    sms.log.info("shot fired: " .. evt.weapon:get_type())
  end
end)
```

## Always-available getters

These read snapshotted fields and work in any state — `created`, `tracking`,
`impacted`, or `destroyed`. They reject non-handles with a `[sms.weapon]`
warn and `nil`. Where the snapshot itself failed at wrap time (e.g. no
launcher, so no release_*), the getter returns `nil` without logging.

### `:get_name() → string`

DCS-assigned weapon name, usually a numeric string. Snapshotted at wrap.

### `:get_type() → string`

DCS type name (e.g. `"weapons.shells.M114_HE"`, `"weapons.missiles.AIM_120C"`).

### `:get_category() → "bomb" | "missile" | "rocket" | "shell" | "torpedo"`

Lowercase normalized category. `nil` if DCS returned an unknown category int
at wrap time (logged as error).

### `:get_coalition() → "red" | "blue" | "neutral"`

Lowercase coalition string.

### `:get_country() → string`

Lowercase country name (e.g. `"usa"`, `"russia"`, `"united_kingdom"`).

### `:get_launcher() → sms.unit handle | nil`

The unit that fired the weapon, as an [`sms.unit`](unit.md) handle. `nil`
without logging when the weapon has no launcher (triggered explosions,
some scripted spawns).

### `:get_state() → "created" | "tracking" | "impacted" | "destroyed"`

Current state in the lifecycle.

### `:get_release_position() → vec3 | nil`

Launcher position at the moment of release. `nil` if the launcher was absent
at wrap time.

### `:get_release_heading() → number | nil`

Launcher heading in **degrees** (0 = north, 90 = east, clockwise) at release.

### `:get_release_pitch() → number | nil`

Launcher pitch in **degrees**, positive = nose up, at release.

### `:get_release_altitude_asl() → number | nil`

Launcher altitude in **meters ASL** at release.

### `:get_release_altitude_agl() → number | nil`

Launcher altitude in **meters AGL** at release (terrain-subtracted).

### `:is_bomb() / :is_missile() / :is_rocket() / :is_shell() / :is_torpedo() → bool`

Category sugar. Silent — return `false` on bad input rather than logging,
because they're commonly used as filter predicates in event handlers.

**Example — release-time getters**

```lua
sms.events.connect(sms.events.SHOT, function(evt)
  local weapon = evt.weapon
  if not weapon or not weapon:is_bomb() then return end
  sms.log.info(string.format(
    "%s dropped a %s from %dm AGL at heading %d deg",
    weapon:get_launcher():get_name(),
    weapon:get_type(),
    weapon:get_release_altitude_agl() or -1,
    weapon:get_release_heading()       or -1
  ))
end)
```

## Tracking lifecycle

Tracking is opt-in, per-handle, and uses [`sms.timer.every`](timer.md) under
the hood. Each handle owns one timer and at most one `on_tick` and one
`on_impact` callback. Callbacks are single-slot: assigning a second
function to either replaces the first (last-write-wins).

### `:start_tracking(opts?) → bool`

**Synopsis** — begin polling the weapon's live position. Transitions state
from `created` to `tracking`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `opts` | `table` | (optional) Tracking configuration. |

**`opts` table — fully documented:**

| Key | Type | Default | Description |
|---|---|---|---|
| `rate` | `number` (Hz) | `60` | Poll rate in hertz. The timer fires every `1/rate` seconds. Must be positive. |
| `ip_distance` | `number` (m) | `50` | Max distance (meters) used by `land.getIP` when extrapolating impact along the last-known forward axis. Larger values catch shallower impact angles; values too large can intersect terrain past the actual impact point. Must be non-negative. |

**Returns** — `true` on successful start; `false` + log if the handle is
the wrong type, the weapon is not in `created` state (already tracking,
already impacted, or destroyed), `rate` / `ip_distance` are invalid, or
the underlying `sms.timer.every` failed to schedule.

**Example**

```lua
sms.events.connect(sms.events.SHOT, function(evt)
  local weapon = evt.weapon
  if not weapon or not weapon:is_missile() then return end
  weapon:start_tracking({ rate = 30, ip_distance = 100 })
end)
```

### `:stop_tracking() → bool`

**Synopsis** — stop polling and return to the `created` state. **Does NOT
fire `on_impact`** and does **not** emit `WEAPON_IMPACT` on the bus —
this is an explicit abort, semantically distinct from a real impact.

**Returns** — `true` on success; `false` + log if the handle is the wrong
type or the weapon is not currently in `tracking` state.

### `:is_tracking() → bool`

Silent boolean probe. Returns `false` on non-handles, on weapons that
haven't been started, and on impacted / destroyed weapons.

### `:on_tick(fn)`

**Synopsis** — set the per-tick callback. `fn(weapon)` is invoked once per
poll while tracking. `fn` is `pcall`-wrapped — exceptions are logged via
`[sms.weapon] error: on_tick: user fn raised: ...` and do not break tracking.

Single-slot. Calling `on_tick` again replaces the previous function.
There is no return value.

| Name | Type | Description |
|---|---|---|
| `fn` | `function(weapon)` | Receives the `sms.weapon` handle each tick. |

### `:on_impact(fn)`

**Synopsis** — set the natural-impact callback. Fires exactly once when
the DCS weapon object stops existing while in `tracking` state. Does **not**
fire on `:stop_tracking()` or `:destroy()`. `fn` is `pcall`-wrapped.

Single-slot, last-write-wins. No return value.

| Name | Type | Description |
|---|---|---|
| `fn` | `function(weapon)` | Receives the `sms.weapon` handle, now in state `"impacted"`. Impact getters are valid inside this callback. |

**Example — track and react**

```lua
sms.events.connect(sms.events.SHOT, function(evt)
  local weapon = evt.weapon
  if not weapon or not weapon:is_bomb() then return end
  weapon:on_tick(function(weapon)
    -- Cheap per-tick logging — keep this light, it runs at the poll rate.
    local pos = weapon:get_position()
    if pos then
      sms.log.debug(string.format("bomb at %.0f, %.0f m AGL %.0f", pos.x, pos.z, pos.y))
    end
  end)
  weapon:on_impact(function(weapon)
    sms.log.info("bomb impact at " .. tostring(weapon:get_impact_position()))
  end)
  weapon:start_tracking({ rate = 30 })
end)
```

## Live getters

These require the handle to be in state `"tracking"`. Calling them in any
other state logs and returns `nil` — **except `:get_target()`, which is
silent-nil** in non-tracking states (mid-flight target loss is an expected,
non-erroneous outcome).

### `:is_alive() → bool`

Silent probe. Returns `true` only when in `tracking` state and the underlying
DCS object's `isExist()` returns true. Returns `false` on bad input, wrong
state, or after the DCS object has gone away.

### `:get_position() → vec3 | nil`

Last-polled position. May be up to `1/rate` seconds stale. `nil` + log
outside `tracking`. `nil` without logging if no poll has yet succeeded
(extremely brief window between `start_tracking` returning and the first
tick firing).

### `:get_velocity() → vec3 | nil`

Last-polled velocity vector (m/s components). Same staleness and silent-nil
caveats as `get_position`.

### `:get_speed() → number | nil`

Magnitude of the last-polled velocity vector, in m/s. `nil` if velocity is
unavailable.

### `:get_target() → sms.unit handle | sms.static handle | nil`

Re-resolves the weapon's current target each call by querying DCS, then
wrapping the result as an [`sms.unit`](unit.md) (preferred) or
[`sms.static`](static.md) handle. **Silent-nil** in every failure path —
non-handle input, wrong state, no target set, target disappeared, or DCS
returned a target name we couldn't re-resolve. Mid-flight target loss is
normal (e.g. the SAM the missile was chasing died while the missile was
still in the air); spamming logs there would be noise.

**Example — live getters**

```lua
sms.events.connect(sms.events.SHOT, function(evt)
  local weapon = evt.weapon
  if not weapon or not weapon:is_missile() then return end
  weapon:on_tick(function(weapon)
    local target = weapon:get_target()
    if not target then return end  -- silent-nil; not an error
    local speed  = weapon:get_speed() or 0
    sms.log.debug(string.format(
      "%s tracking %s at %.0f m/s",
      weapon:get_name(), target:get_name(), speed
    ))
  end)
  weapon:start_tracking()
end)
```

## Impact getters

These require the handle to be in state `"impacted"`. Calling them in any
other state logs and returns `nil`.

### `:get_impact_position() → vec3 | nil`

Extrapolated impact point. Computed via `land.getIP(last_pos, last_forward,
ip_distance)` from the last polled position and forward axis. Falls back to
the raw last-known position when no terrain intersection is found within
`ip_distance` (off-map weapons, mid-air detonation, or a weapon that simply
disappeared without a downward trajectory).

### `:get_last_known_position() → vec3 | nil`

The raw last-polled position, **without** the `land.getIP` extrapolation.
Useful when you want to inspect where tracking was last successful — for
instance, to debug whether an extrapolated impact looks plausible.

### `:get_impact_distance_from(target) → number | nil`

Euclidean 3D distance, in meters, from the impact position to a target.
The target argument is duck-typed:

| `target` shape | Meaning |
|---|---|
| `{x, y, z}` (a vec3) | Used directly. |
| handle with `:get_position()` | The handle's current position is queried. Works for any [`sms.unit`](unit.md), [`sms.static`](static.md), or [`sms.weapon`](weapon.md) handle, as well as any future positionable handle that follows the same convention. |

`nil` + log when the weapon has no impact yet, or when `target` is neither a
vec3 nor a handle exposing `:get_position()`.

**Example — impact getters**

```lua
sms.events.connect(sms.events.SHOT, function(evt)
  local weapon = evt.weapon
  if not weapon or not weapon:is_bomb() then return end
  local target = sms.unit("Bandit-1")
  weapon:on_impact(function(weapon)
    local distance = weapon:get_impact_distance_from(target)
    if distance then
      sms.log.info(string.format("CEP this drop: %.1f m", distance))
    end
  end)
  weapon:start_tracking()
end)
```

## Destroy

### `:destroy() → bool`

**Synopsis** — programmatically remove the weapon from the DCS world. Stops
tracking silently. **Does not fire `on_impact` and does not emit
`WEAPON_IMPACT`** — `destroy` and natural impact describe genuinely
different events; conflating them would lose information.

Valid only from `created` or `tracking`. Returns `false` (no log) from
`impacted` (a real impact already happened) or `destroyed` (already done).
Returns `false` + log on non-handle input.

If you need an impact-style event from a programmatic abort, capture
`:get_position()` and any other state you care about *before* calling
`:destroy()`.

**Example**

```lua
-- Abort an unwanted shot mid-flight.
sms.events.connect(sms.events.SHOT, function(evt)
  local weapon = evt.weapon
  if not weapon then return end
  if weapon:get_coalition() == sms.K.coalition.RED and friendly_zone:is_vec3_in(weapon:get_release_position()) then
    weapon:destroy()
  end
end)
```

## Bus integration: `sms.events.WEAPON_IMPACT`

Tracking emits a fabricated `sms.events.WEAPON_IMPACT = "weapon_impact"`
signal on the [`sms.events`](events.md) bus when a tracked weapon impacts
naturally. The per-handle `on_impact` callback fires first, then the bus
signal — both for the same impact, in that order.

**Payload:**

```lua
{
  weapon          = <sms.weapon handle, now in state "impacted">,
  impact_position = <vec3>,
  time            = <sim seconds at impact>,
}
```

Use `WEAPON_IMPACT` for cross-cutting subscribers (range scoring, kill
auditing, mission analytics) — anything where one logical impact may have
many independent listeners. Use `:on_impact` for the local subscriber that
set up tracking in the first place.

**Example**

```lua
sms.events.connect(sms.events.WEAPON_IMPACT, function(evt)
  sms.log.info(string.format(
    "[score] %s impact at t=%.1fs",
    evt.weapon:get_type(), evt.time
  ))
end)
```

## Full example — bombing-range scoring

Subscribes to SHOT, filters for bombs whose release happens inside a named
range zone, registers an `on_impact` callback, starts tracking, and logs the
distance from the bomb impact to a designated target unit.

```lua
local range  = sms.area("Bombing-Range-Alpha")
local target = sms.unit("Range-Target-1")

sms.events.connect(sms.events.SHOT, function(evt)
  local weapon = evt.weapon
  if not weapon or not weapon:is_bomb() then return end

  -- Only score drops released inside the range area.
  local release_pos = weapon:get_release_position()
  if not release_pos or not range:is_vec3_in(release_pos) then return end

  sms.log.info(string.format(
    "scoring drop: %s by %s, release alt %dm AGL",
    weapon:get_type(),
    weapon:get_launcher() and weapon:get_launcher():get_name() or "?",
    weapon:get_release_altitude_agl() or -1
  ))

  weapon:on_impact(function(weapon)
    local distance = weapon:get_impact_distance_from(target)
    if distance then
      sms.log.info(string.format(
        "[score] %s impact %.1f m from %s",
        weapon:get_type(), distance, target:get_name()
      ))
    else
      sms.log.warn("[score] impact distance unavailable")
    end
  end)

  weapon:start_tracking({ rate = 30, ip_distance = 100 })
end)
```

## See also

- [`sms.events`](events.md) — pub/sub bus, SHOT / HIT payloads, `WEAPON_IMPACT`.
- [`sms.unit`](unit.md) — launcher and target handles.
- [`sms.static`](static.md) — alternative target handle type.
- [`sms.timer`](timer.md) — the polling primitive `start_tracking` uses.
- [`sms.area`](area.md) — for filtering events by geographic region.
