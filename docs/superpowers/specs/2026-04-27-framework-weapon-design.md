# dcs-sms Framework — `sms.weapon` v1

**Date:** 2026-04-27
**Status:** Approved (brainstorm phase)
**Scope:** Ninth framework module. Wraps DCS weapon objects from SHOT events with snapshotted release-time state and an opt-in polling-based tracker that detects impact and reports a best-estimate impact position. Closes issue #10 by promoting `evt.weapon_type` (string) to also expose `evt.weapon` (`sms.weapon` handle) on SHOT/HIT events.

## Goal

Build the wrapper-with-tracker the framework needs to answer "where did that bomb actually land?" — the canonical use case being a test range that watches SHOT events, filters to weapons released within its borders, and measures impact distance from a target. DCS doesn't expose any update/tick callback for in-flight weapons, so we fabricate one with `sms.timer.every` polling the DCS weapon object's position at high frequency. When the object stops existing (impacted or otherwise destroyed), the last-known position is captured and an extrapolation trick (`land.getIP` along last-known forward axis) gives a best-estimate ground intersection.

The shape is direct-ported from MOOSE's `WEAPON` class — proven prior art — with three deliberate departures:

1. **Lightweight handle, no inheritance.** No `BASE:Inherit(POSITIONABLE...)`, no FSM, no `self:T()` log scaffolding. Same shape as `sms.unit`, `sms.static`.
2. **No viz built-ins.** Tracker doesn't paint F10 markers or smoke. Whoever owns the impact position decides what to do with it. Keeps weapon.lua focused on "wrap + track + report."
3. **Hybrid callbacks.** Per-handle `on_impact`/`on_tick` are the primary API (locally scoped, dies with the handle). One fabricated bus event `sms.events.WEAPON_IMPACT` also fires for cross-cutting subscribers (e.g. mission-wide kill log). No `WEAPON_TICK` on the bus — that's needlessly noisy at 60 Hz × N weapons.

## User value

After this iteration the user can write:

```lua
local target_pos = {x = 1234, y = 0, z = 5678}

sms.events.connect(sms.events.SHOT, function(evt)
  local w = evt.weapon
  if not w then return end                            -- some shots have no weapon obj
  if not w:is_bomb() then return end                  -- only care about bombs
  if not range_zone:contains(w:get_release_position()) then return end

  w:on_impact(function(weapon)
    local d = weapon:get_impact_distance_from(target_pos)
    sms.log.info(string.format("impact %.1fm from target", d))
  end)

  w:start_tracking()                                  -- 60 Hz default
end)

-- Cross-cutting subscriber elsewhere in the mission (no extra wiring)
sms.events.connect(sms.events.WEAPON_IMPACT, function(evt)
  global_kill_log:append(evt)
end)
```

…and gets accurate impact positions without a manual update loop, weapon-manager singleton, or polling boilerplate.

## Scope

### In scope (v1)

**One new module file `framework/weapon.lua`** — loaded last in the framework load order (after `events.lua`). Single file. Module table `sms.weapon`. Lightweight handle pattern with metatable `__index = sms.weapon` so `w:method()` dispatches to `sms.weapon.method(w)`.

**Constructor:**

- `sms.weapon.wrap(raw_dcs_weapon) -> handle | nil + log` — only constructor. Snapshots release-time state immediately. No callable-by-name form because DCS weapons aren't name-addressable (verified empirically and explicitly stated in MOOSE's class doc).

**Snapshot fields, captured at `wrap` time** (survive the weapon's eventual destruction):

| Field | Source |
|---|---|
| `name` | `raw:getName()` (DCS-assigned, usually a numeric string) |
| `type` | `raw:getTypeName()` |
| `category` | normalized from `raw:getDesc().category` to `"bomb" \| "missile" \| "rocket" \| "shell" \| "torpedo"` |
| `coalition` | normalized from `raw:getCoalition()` to `"red" \| "blue" \| "neutral"` |
| `country` | normalized from `raw:getCountry()` to lowercase string via reverse `country.id` table |
| `launcher` | `sms.unit` handle from `raw:getLauncher():getName()` if launcher exists |
| `release_position` | `launcher:get_position()` |
| `release_heading` | `launcher:get_heading()` (degrees) |
| `release_pitch` | `launcher:get_pitch()` (degrees) |
| `release_altitude_asl` | `launcher:get_altitude()` (meters above sea level) |
| `release_altitude_agl` | `launcher:get_altitude(true)` (meters above ground level) |

If the launcher is absent (rare — happens for some triggered weapons), all `release_*` and `launcher` fields are `nil`. The handle is still valid; the affected getters log + return nil.

**State machine** — single `state` field on the handle, transitions only forward:

```
"created" --start_tracking()--> "tracking" --DCS object gone--> "impacted"
                                          \--stop_tracking()--> "created"
"created" or "tracking" --destroy()--> "destroyed"
```

**Tracking lifecycle:**

- `w:start_tracking(opts?) -> bool` — opts: `{rate = 60, ip_distance = 50}`. Both numbers, both optional. Idempotent: second call on a tracking handle logs + returns `false`. Returns `true` on success.
- `w:stop_tracking() -> bool` — stops the timer, transitions to `"created"`, no impact event fired (this is an explicit abort). Idempotent: returns `true` once, `false` thereafter.
- `w:is_tracking() -> bool` — silent probe.
- `w:destroy() -> bool` — stops tracking if active, calls raw `weapon:destroy()`. Silent. No impact event. Transitions to `"destroyed"`. Idempotent: returns `true` once, `false` thereafter.

**Per-tick mechanics** (internal, runs under `sms.timer.every(1/rate, ...)`):

1. `pcall(raw.getPosition, raw)` to get DCS Position3 (`{p, x, y, z}` — origin + three orientation axes).
2. If pcall succeeds AND `raw:isExist()` returns true: update `_last_pos3` (full struct) and `_last_velocity` (from `raw:getVelocity()`); fire `on_tick` callback if set; return.
3. If pcall fails OR `isExist()` returns false: weapon has been destroyed.
   - Compute extrapolated impact: `land.getIP(last_pos3.p, last_pos3.x, ip_distance)`. Cast a ray from last-known origin along last-known forward axis (which equals velocity direction for in-flight weapons) up to `ip_distance` meters; returns the ground intersection vec3 or nil.
   - `_impact_position = extrapolated or last_pos3.p` — fall back to last-known position when no terrain intersection (off-map, mid-air detonation, etc.).
   - Transition to `"impacted"`.
   - Stop the timer (return `false` from the `every` callback, which self-cancels per `sms.timer` contract).
   - Fire `on_impact` callback if set.
   - Emit `sms.events.WEAPON_IMPACT` on the bus with payload `{weapon = handle, impact_position = vec3, time = <sim time>}`.

**Per-handle callbacks (single-slot, last-write-wins):**

- `w:on_tick(fn) -> nil` — `fn` receives `(weapon)`. Fires per poll while tracking. pcall-wrapped, errors logged.
- `w:on_impact(fn) -> nil` — `fn` receives `(weapon)`. Fires once on natural impact (not on `stop_tracking()` or `destroy()`). pcall-wrapped, errors logged.

**Live methods (state must be `"tracking"` and DCS object must exist; otherwise log + nil — except `w:get_target()`, which is silent-nil; see below):**

- `w:is_alive()` — silent: returns `true` only when state is `"tracking"` AND raw weapon `:isExist()` returns true. After impact this returns `false` (the weapon object is gone).
- `w:get_position()` — returns the `_last_pos3.p` snapshot updated by the most recent tick. Note: this is the *last polled* position; immediately after a tick fires this is fresh, between ticks it can be up to `1/rate` seconds stale. nil before tracking starts (no `_last_pos3` yet).
- `w:get_velocity()` — vec3 from last tick. nil if no tick has fired yet.
- `w:get_speed()` — `sms.utils.vec3_length(get_velocity())`. nil if no velocity.
- `w:get_target()` — re-resolves each call via `raw:getTarget()`. Returns `sms.unit` or `sms.static` handle, or **silently** nil. Unlike the other live getters this does *not* log on missing state or missing target: targets routinely change/disappear mid-flight (re-acquired, killed, lost lock, none ever acquired) and treating each as an API misuse would spam the log on a 60 Hz poll. Argument-validation failures (non-handle input) still log.

**Always-available methods (snapshotted, work in any state):**

- `w:get_name()`, `w:get_type()`, `w:get_category()` — returns one of `"bomb" | "missile" | "rocket" | "shell" | "torpedo"` or nil if category lookup failed.
- `w:get_coalition()`, `w:get_country()`
- `w:get_launcher()` — `sms.unit` handle or nil.
- `w:is_bomb()`, `w:is_missile()`, `w:is_rocket()`, `w:is_shell()`, `w:is_torpedo()` — sugar over `get_category()`. False if category lookup failed.
- `w:get_release_position()`, `w:get_release_heading()`, `w:get_release_pitch()`, `w:get_release_altitude_asl()`, `w:get_release_altitude_agl()` — return snapshot values. nil if launcher was absent at construction.
- `w:get_state()` — returns the state string (debugging aid).

**Impact methods (state must be `"impacted"`; log + nil before):**

- `w:get_impact_position()` — extrapolated where `land.getIP` returned a hit, last-known `pos3.p` otherwise.
- `w:get_last_known_position()` — pre-extrapolation, raw last-polled origin. For users who want the unmassaged value.
- `w:get_impact_distance_from(handle_or_vec3)` — Euclidean distance from impact to a vec3 OR to any handle that has `:get_position()` (sms.unit, sms.static, sms.weapon — duck-typed).

### Bus integration

**One fabricated event constant added by `weapon.lua` at load time:**

```lua
sms.events.WEAPON_IMPACT = "weapon_impact"
```

(Cannot be auto-derived because it's not a `world.event.S_EVENT_*`.)

**One targeted edit to `framework/events.lua`** — extend `_normalize_event` to populate `evt.weapon` when both (a) `raw.weapon` is present, and (b) `sms.weapon` module is loaded:

```lua
if raw.weapon then
  local ok, t = pcall(raw.weapon.getTypeName, raw.weapon)
  if ok and t then evt.weapon_type = t end
  if sms.weapon and sms.weapon.wrap then          -- NEW
    local w = sms.weapon.wrap(raw.weapon)         -- NEW
    if w then evt.weapon = w end                  -- NEW
  end
end
```

`evt.weapon_type` stays for back-compat. If `sms.weapon` isn't loaded, `evt.weapon` is nil (current behavior). Closes issue #10.

### Bundled additions to `sms.unit`

The release-time snapshot needs heading/pitch/altitude on the launcher unit. These belong on `sms.unit` regardless and are reused in `weapon.lua`'s snapshot path:

- `sms.unit.get_heading(u) -> number | nil + log` — degrees, 0–360, north=0, east=90. Computed from `Unit:getPosition().x` (the forward axis) projected to the horizontal plane via `atan2(z, x)`, then converted to degrees and normalized via `sms.utils` helpers if needed.
- `sms.unit.get_pitch(u) -> number | nil + log` — degrees, positive = nose up. Computed from forward axis y-component: `asin(forward.y)` converted to degrees.
- `sms.unit.get_altitude(u, agl?) -> number | nil + log` — meters. ASL by default; pass `true` for AGL (subtract `land.getHeight({x = pos.x, y = pos.z})`).

All three follow the existing `sms.unit` pattern: `is_alive` gate, log + nil on failure.

### Out of scope (v1, deferred)

- `mark_impact_on_f10()` / `smoke_impact()` — separation of concerns; tracker does whatever it wants with the impact position. Future viz module if needed.
- `is_fox_one`/`is_fox_two`/`is_fox_three`, `categoryMissile`, guidance descriptors — niche; ship when someone needs them.
- `destroy({emit_event = true})` opt-in — consistent with `sms.unit.destroy` would be nice eventually, but YAGNI for v1.
- `WEAPON_TICK` on the bus — too noisy. Per-tick reactions go through `w:on_tick` instead.
- Restart-after-stop semantics — calling `start_tracking` again after `stop_tracking` is technically allowed by the state machine but not specifically tested or supported in v1.
- Auto-extending `sms.events` entity-sugar (`u:on_shot_with_tracking(fn)`) — premature; the explicit two-step (subscribe, then wrap+track inside the handler) is fine.

## Constraints

- **Loading order:** `sms.lua → log.lua → utils.lua → group.lua → unit.lua → area.lua → timer.lua → spawn.lua → static.lua → events.lua → weapon.lua`. weapon.lua asserts the dependencies it actually uses (`sms.unit`, `sms.timer`, `sms.events`).
- **DCS quirk:** `Weapon.getByName` does NOT exist. Weapon objects are obtained ONLY from the SHOT event payload's `raw.weapon` (or held over from a prior call). The `wrap` constructor takes the raw object directly.
- **DCS quirk:** `weapon:getPosition()` and other getters can throw mid-frame as the engine deconstructs the object. All raw-DCS calls in weapon.lua's polling path are pcall-wrapped; failure transitions to "impacted" rather than logging an error.
- **DCS quirk:** `weapon:getDesc().category` returns an integer matching `Weapon.Category.{SHELL, MISSILE, ROCKET, BOMB, TORPEDO}` (numbered 0–4). Module-local reverse map normalizes to lowercase string; values outside the table → nil with log.
- **Sim time, pauses with DCS.** Polling runs through `sms.timer.every`, which is sim-time-based. If the mission is paused, polling pauses with it.
- **Polling rate budget:** Default 60 Hz × N tracked weapons. At 60 Hz one tick is ~17 ms of simulated time; one weapon's tick callback should comfortably run in tens of microseconds. Even 100 simultaneously tracked weapons (extreme) is ~6000 callbacks/sec, well within DCS scripting headroom. No internal rate-limiting in v1.
- **Memory:** Each handle holds a reference to the raw DCS weapon object until the natural impact path nils it; this prevents the GC from prematurely collecting a still-in-flight weapon's wrapper. After "impacted" or "destroyed" the raw reference is cleared.

## Decisions

Recorded here for reference — settled in conversation, not open for re-litigation:

1. **Polling rate default = 60 Hz (`1/60 ≈ 0.0167s` per tick).** Conservative vs MOOSE's 100 Hz; user-overridable. Justification: 60 Hz × Mach 1 weapon = ~6m gap between ticks, well within `ip_distance` extrapolation cap.
2. **`ip_distance` default = 50 m.** Direct from MOOSE; covers up to ~Mach 3 at 60 Hz with margin.
3. **Single-slot per-handle callbacks (`on_tick`, `on_impact`).** Last-write-wins. Multi-subscriber-per-weapon is solved via the bus + filter on `evt.weapon:get_name()`, keeping the handle simple.
4. **One fabricated bus event (`WEAPON_IMPACT`), not `WEAPON_TICK`.** Cross-cutting use cases for "any weapon impacted" are real (kill logs, range-wide stats); cross-cutting for "any weapon position update at 60 Hz" is not.
5. **`destroy()` is silent in v1.** Mirrors current `sms.unit.destroy()` default. The `{emit_event = true}` opt-in pattern can be added later when there's a clear need.
6. **`stop_tracking()` does NOT fire `on_impact`.** It's an explicit abort. Users who want "treat this as impacted right now" can read `get_position()` directly and stop.
7. **Constructor naming: `sms.weapon.wrap(raw)`** rather than callable shortcut. The DCS constraint that weapons aren't name-addressable makes the entity-callable pattern (`sms.unit("name")`) impossible; `wrap` is honest about what it does.
8. **`evt.weapon_type` (string) stays alongside the new `evt.weapon` (handle).** Back-compat; cheap to keep; explicit-but-derivable redundancy is fine.
9. **`get_target()` re-resolves each call** rather than caching. Targets change/disappear mid-flight; a cached value would lie.
10. **`get_position()` returns the last polled position, not a fresh DCS read.** Reading via `raw:getPoint()` mid-tick would either duplicate work (if the tick already ran this frame) or risk failure (if the weapon is mid-deconstruction). Polled value is "good enough" given the high rate.
11. **Bundle the `sms.unit` getters (heading/pitch/altitude) into this iteration.** They belong on `sms.unit` regardless and are needed for the launcher snapshot. Worth a small scope expansion.
12. **The state machine has only "created", "tracking", "impacted", "destroyed".** No "lost" — DCS only tells us "weapon object stopped existing"; we cannot reliably distinguish ground-impact from mid-air-detonation from off-map. MOOSE doesn't distinguish either.
13. **Smoke test approach:** spawn an aircraft via `sms.spawn` with a bombing task at known target coordinates, wire up SHOT → wrap → track → impact, assert `get_impact_position` is within ~`ip_distance` of expected ground point and `get_release_position` is within a small margin of the launcher's position at SHOT time. Test will need an unpaused mission for the round trip; documented as a constraint in the smoke test header.

## Open questions

None.
