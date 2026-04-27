# dcs-sms Framework — `sms.task` v1

**Date:** 2026-04-27
**Status:** Approved (brainstorm phase)
**Scope:** Tenth framework module. Adds ergonomic task construction (`sms.task.<verb>(...)`) and runtime task application (`group:set_task` / `group:push_task`) so mission scripts can issue commands like "go here", "attack this group", "engage anything in this area" without hand-rolling DCS task tables. Adds `sms.group:get_category()` as a small companion change. Closes issues that arise from the brainstorm; no existing issue back-references.

## Goal

DCS task tables are hostile to write by hand. The canonical example for telling an air group to bomb a position is roughly 30 lines of nested `id`/`params` that a mission scripter has no business memorising. Worse, the same intent maps to different DCS task IDs depending on attacker category and target type, so rolling your own is fragile.

This module wraps the most common verbs (movement, attack, orbit, land, hold, plus parallel composition) in functions that return ready-to-apply task tables, and adds two methods to `sms.group` to actually apply them. The split between *build* and *apply* keeps tasks as first-class values: a task can be stored, passed around, composed via `combo`, or built once and applied to multiple groups.

The shape borrows from MOOSE's task helpers but stays deliberately smaller — only verbs the user has identified as MVP, no per-waypoint mutation (the framework does not own group routes), no introspection of currently-running tasks (DCS doesn't expose this cleanly anyway).

## User value

After this iteration the user can write:

```lua
-- React to a SAM activation by tasking a CAP flight to engage anything in the area
sms.events.connect(sms.events.SHOT, function(evt)
  if not evt.weapon or not evt.weapon:is_missile() then return end

  local cap = sms.group("cap_flight_1")
  if not cap then return end

  cap:set_task(sms.task.attack_in_area(threat_zone, {
    altitude_min = 3000,
    altitude_max = 8000,
  }))
end)

-- Pre-script a chain at mission start using combo (parallel)
local strike = sms.group("strike_1")
strike:set_task(sms.task.combo({
  sms.task.move_to(ingress_point),
  sms.task.bomb(target_pos, {altitude = 6000}),
}))

-- Move a ground group somewhere
sms.group("convoy"):set_task(sms.task.move_to(rally_point))

-- Push an attack on top of an existing task; group resumes prior task when done
defenders:push_task(sms.task.attack(intruder_group))
```

## Module shape

New file `framework/task.lua`. Loading order extends the existing chain:

```
sms → log → utils → group → unit → area → timer → spawn → static → events → weapon → task
```

`task.lua` depends on `sms.unit`, `sms.group`, `sms.static`, `sms.area` (for target type-checking when verbs duck-type their argument). It also installs two methods on `sms.group`'s metatable: `:set_task(t)` and `:push_task(t)`. Those live in `task.lua`, not `group.lua` — the dependency stays one-way (task knows about group; group stays unaware of task).

Files in scope:

- **new** `framework/task.lua` — verbs + apply methods + air-only category check
- **new** `framework/test/smoke_task.sh` — synthetic + live-DCS smoke coverage with EXIT-trap cleanup matching the existing pattern
- **modify** `framework/group.lua` — add `:get_category()` getter
- **modify** `framework/sms.lua` — append `task.lua` to the module load list
- **modify** `AGENTS.md` — new `sms.task` section + `:get_category()` row in `sms.group` table
- **new spec** this file

## Verbs

Nine builders. Each returns a DCS task table with two private fields stamped on:

```lua
{ id = "<DCS task id>", params = {...}, _sms_verb = "<verb name>", _sms_air_only = true|nil }
```

The `_sms_*` fields are read by the apply layer for the air-only check and for log messages. They are otherwise transparent to DCS.

| Verb | Targets | DCS task | Categories | Notes |
|---|---|---|---|---|
| `move_to(target, opts?)` | vec3 / sms.unit / sms.group / sms.static / sms.area (centroid); opts: `{speed = number}` (m/s; locked when given; otherwise DCS uses the group's default cruise) | `Mission` task, single-waypoint route at snapshot pos | all | snapshot once; for continuous tracking use `follow` |
| `follow(target, opts?)` | sms.unit / sms.group; opts: `{offset = {x,y,z}}` (default `{x=-50,y=0,z=-50}`) | `Follow` with `groupId` + `pos` offset | air (v1) | `_sms_air_only = true` |
| `orbit(pos, opts?)` | vec3; opts: `{altitude=5000, speed=200, pattern="Circle"\|"RaceTrack"}` | `Orbit` | air | `_sms_air_only = true` |
| `attack(target, opts?)` | sms.group / sms.unit / sms.static; opts: `{weapon_type="Auto", expend="Auto", attack_qty}` | `AttackGroup` (sms.group) / `AttackUnit` (sms.unit and sms.static — DCS shares unit/static ID space for targeting) | air (v1) | `_sms_air_only = true`; if a static is a poor fit for the AI's weapon profile, fall back to `bomb(static:get_position())` |
| `attack_in_area(area, opts?)` | sms.area (circular for v1); opts: `{altitude_min, altitude_max, weapon_type}` | `EngageTargetsInZone` from area center+radius | air (v1) | `_sms_air_only = true`; rejects non-circular areas with log + nil |
| `bomb(target, opts?)` | vec3 / sms.area (centroid) / sms.unit / sms.static; opts: `{altitude, weapon_type, expend, group_attack, direction}` | `Bombing` | air | `_sms_air_only = true` |
| `land(target, opts?)` | vec3 / sms.static / sms.unit / DCS `Airbase`; opts: `{duration=300}` | `Land` | air (incl. helo) | `_sms_air_only = true` |
| `hold()` | — | `"Nothing"` literal | all | DCS interprets per category (air loiters; ground stops) |
| `combo({t1, t2, ...})` | array of task tables | `ComboTask` (parallel) | inherits | `_sms_air_only` is `true` if **any** constituent has it |

**Snapshot vs follow.** `move_to(unit)` reads `unit:get_position()` once at build time; if the unit moves before the task ends, the task still drives to the original location. For continuous tracking, use `follow(unit)`, which emits a DCS `Follow` task referencing the target by ID.

**Air-skewed v1.** `follow`, `attack`, `attack_in_area`, `orbit`, `bomb`, `land` are functionally air-only in v1. DCS's ground-engage model is ROE-based rather than task-based, and wrapping it ergonomically is its own design problem deferred to v1.1+. Pushing one of these tasks to a ground group is rejected at apply time (see Apply API below) — the framework will not silently dispatch a task DCS can't honour.

**Polygon `attack_in_area`.** Scoped to circular areas in v1. A polygon `sms.area` would require either iterating per-vertex EngageTargetsInZone calls (loses semantics) or a manual sweep (different verb). Out of v1 scope.

## Apply API

Two methods on `sms.group` metatable, installed by `task.lua`:

```lua
group:set_task(task) → bool        -- replaces current; wraps Group:getController():setTask()
group:push_task(task) → bool       -- pushes onto stack; wraps Group:getController():pushTask()
```

**Returns `true`** on dispatch (DCS gives no completion feedback — completion handling stays event-driven via `sms.events`).

**Returns `false` + log on:**

- non-handle argument (`group` is not an `sms.group`)
- dead group (`is_alive()` returns false)
- non-table `task`, or table without both `id` and `params` fields
- `_sms_air_only` task being applied to a group whose category is not `"airplane"` or `"helicopter"`
- DCS-side pcall failure (rare; controller gone, malformed table reaches DCS)

**Air-only check log message:**

```
[sms.task] set_task: 'orbit' is air-only; group 'tank-1' is ground — not applied
```

The verb name comes from `task._sms_verb`. The group name and category come from the handle. Manually-built task tables (no `_sms_*` tags) skip the check — user's responsibility.

## Companion change: `sms.group:get_category()`

Returns the lowercase category string: `"ground" | "airplane" | "helicopter" | "ship" | "train"`. Read via `Group:getCategory()` from the live DCS object; `nil` + log on non-handle or dead group.

This pairs with `sms.group.create({category = ...})` symmetrically and is read internally by the air-only check. Mirrors the shape of `get_coalition` and `get_country` (already on the handle). Adds one row to the `sms.group` table in `AGENTS.md`.

## Failure model

| Layer | Bad input | Behavior |
|---|---|---|
| Builders | Wrong target type, nil target, malformed opts, polygon area for `attack_in_area` | `log.error` with builder name + reason; return `nil` |
| Apply | Non-handle, dead group, non-table task, missing `id`/`params`, air-only-on-ground | `log.error`; return `false` |
| DCS pcall failure | Rare — controller gone mid-call, DCS rejects malformed table | `log.error`; return `false` |

Invariant across the module: never throws. Builders return `nil` so `combo({maybe_nil_value, ...})` can detect any nil constituents and reject in turn (also returning `nil`). The apply methods always return a bool.

## Testing

New `framework/test/smoke_task.sh` with:

**Synthetic (no DCS dispatch)** — for each builder, verify:

- valid args → returns a table with the expected `id`, `_sms_verb`, and `_sms_air_only` flag
- bad args → returns `nil` (per-verb matrix: nil target, wrong type, malformed opts)
- `combo` propagates `_sms_air_only` correctly (true if any constituent; nil if none)
- `combo` with a nil constituent returns `nil`

**Live DCS (uses fixture cleanup via the EXIT-trap pattern)** — spawn small fixture groups and exercise dispatch:

- ground AAV-7: `set_task(move_to(pos))` → returns `true`; group remains alive
- air F-16: `set_task(orbit(pos))` → returns `true`
- air F-16: `set_task(attack(some_group))` → returns `true`
- ground AAV-7: `set_task(orbit(pos))` → returns `false`; log line contains `"orbit"` and `"air-only"`
- `push_task` round-trip on an air group
- `combo` of `move_to + attack_in_area` on an air group → returns `true`
- bad-arg matrix on apply: non-handle, dead group (destroy then apply), non-table task

`SMOKE_FIXTURES` lists every group name created by the smoke. EXIT trap matches the convention added in `test/smoke-cleanup-traps`.

## Out of scope (v1)

- **`sequence` verb.** Dropped from v1 — DCS lacks a clean native "do these in order" task primitive at the same level as ComboTask, and the available workarounds (ControlledTask + WrappedAction chains, or apply-time push-in-reverse-order) trade off composability for correctness. Use `push_task` LIFO ordering or event-driven retasking when sequencing is genuinely needed. Add as v1.1 if a real use case appears.
- **Ground-specific engage verbs.** No ground equivalent of `attack` / `attack_in_area` in v1. Ground engagement in DCS is ROE-driven, which is a different mental model and deserves its own design pass.
- **Polygon-area `attack_in_area`.** Circular areas only.
- **`pop_task`.** DCS has `popTask`; no clear v1 use case, so skipped (YAGNI).
- **`get_current_task` / completion introspection.** DCS doesn't expose this cleanly. Completion handling is event-driven via `sms.events` (e.g., subscribe to DEAD events and re-task on group death).
- **Per-waypoint task mutation.** Explicitly out of scope per brainstorm — the framework does not own group routes after spawn, and runtime route mutation interrupts current tasks anyway.

## Decisions / rationale

1. **Build vs apply as separate steps.** Tasks are values, not actions. A user can construct a task once and apply it to multiple groups, store it for later, or compose it into a `combo`. Methods like `group:move_to(pos)` (build + apply in one) were rejected because they double the apply-side surface (need set/push variants per verb) and lose composability.

2. **Raw DCS task tables, not opaque handles.** Builders return plain tables with `id`/`params` plus two private `_sms_*` tags. Transparent — easy to debug, easy to drop down to DCS for verbs the framework doesn't yet wrap. Tags are cheap and only consulted by the apply layer.

3. **Air-only check at apply time, not build time.** A user might construct `sms.task.orbit(...)` for several different groups and only some of them are ground. Failing at build time would prevent legitimate construction. Failing at apply time gives a precise log message and rejects only the wrong group.

4. **No `pop_task`, no `get_current_task`.** Both have weak use cases for v1. `pop_task` symmetry isn't needed when `set_task` replaces; `get_current_task` would lie because DCS doesn't actually expose it. Adding either pre-emptively violates the framework's lightweight philosophy.

5. **`hold()` emits `"Nothing"`.** DCS interprets `"Nothing"` per category (air loiters at current pos; ground stops). Cheaper than building a "true hold" branch per category and good enough for the canonical "stop doing what you're doing" intent.

6. **`get_category()` as part of this work.** Needed for the air-only check internally and useful as a public getter independently. Trivial addition, mirrors `get_coalition` / `get_country` shape.

7. **Spec mandates AGENTS.md update.** Per project rule: every spec adding public surface must explicitly include "Update AGENTS.md" in scope. New `sms.task` section + `:get_category()` row in `sms.group` table land in the same change-set as `task.lua`.
