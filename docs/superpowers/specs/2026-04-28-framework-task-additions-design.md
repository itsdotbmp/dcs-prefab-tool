# Framework task v1.1 additions — design

> Supplements [`2026-04-27-framework-task-design.md`](2026-04-27-framework-task-design.md). The v1 spec defines the build/apply split, `_sms_air_only` enforcement, `_sms_verb` tagging, and the existing builders (`move_to`, `hold`, `follow`, `orbit`, `attack`, `attack_in_area`, `bomb`, `land`, `combo`). This spec adds builders, namespaces, and one validation-flag extension.

## Goal

Bring `sms.task` to feature parity with the DCS scripting "Tasks" and "Enroute Tasks" sections of [FAQ #1267](https://www.digitalcombatsimulator.com/en/support/faq/1267/), excluding `Mission`, `ControlledTask`, and `WrappedAction` (those are deferred). Adds 14 new builders, updates 1 existing, introduces two constants namespaces, and extends category enforcement to ground-only tasks.

## Scope (in)

### 14 new task builders

**Air-only, immediate:**

| Builder | DCS task id | Notes |
|---|---|---|
| `sms.task.no_task()` | `NoTask` | Empty noop. No params. Useful for clearing the active task without resetting the controller. |
| `sms.task.attack_map_object(point, opts?)` | `AttackMapObject` | Attack a building/structure. `point` is a vec3 within 2 km of the structure (DCS doesn't expose map-object IDs to scripts, so coordinate proximity is the lookup). |
| `sms.task.bomb_runway(airdrome_id, opts?)` | `BombingRunway` | `airdrome_id` is an integer DCS airdrome ID. (See [#23](https://github.com/nielsvaes/dcs-sms/issues/23) — accepting `sms.airdrome` handles is deferred.) |
| `sms.task.refuel()` | `Refueling` | Head to nearest tanker. No params. |
| `sms.task.escort(target, opts?)` | `Escort` | Follow `target` (sms.unit or sms.group) and protect it from threats matching `opts.target_types`. |

**Ground-only, immediate:**

| Builder | DCS task id | Notes |
|---|---|---|
| `sms.task.fire_at_point(point, opts?)` | `FireAtPoint` | Shoot at point until ammo gone. `opts.radius` (optional) — if set, fires at random places within the radius. |

**Air-or-ground, immediate:**

| Builder | DCS task id | Notes |
|---|---|---|
| `sms.task.fac_attack_group(target, opts?)` | `FAC_AttackGroup` | Become FAC for `target` (sms.group). Target killed by player CAS aircraft. |

**Air-only, en route (all take `opts.priority`, default 1):**

| Builder | DCS task id | Notes |
|---|---|---|
| `sms.task.engage_en_route_targets(opts?)` | `EngageTargets` | Engage anything matching `opts.target_types`. `opts.max_dist` (optional) limits target distance from route leg. |
| `sms.task.engage_en_route_group(target, opts?)` | `EngageGroup` | Permission to engage this group (not an immediate-attack imperative — distinct from `sms.task.attack`). |
| `sms.task.engage_en_route_unit(target, opts?)` | `EngageUnit` | Permission to engage this unit. |
| `sms.task.awacs(opts?)` | `AWACS` | Act as AWACS. No params other than `priority`. |
| `sms.task.tanker(opts?)` | `Tanker` | Act as tanker. No params other than `priority`. |

**Ground-only, en route:**

| Builder | DCS task id | Notes |
|---|---|---|
| `sms.task.ewr(opts?)` | `EWR` | EW radar role. No params other than `priority`. |

**Air-or-ground, en route:**

| Builder | DCS task id | Notes |
|---|---|---|
| `sms.task.fac(opts?)` | `FAC` | Area FAC. `opts.radius` required, `priority` defaults to 1. |
| `sms.task.fac_engage_group(target, opts?)` | `FAC_EngageGroup` | En-route FAC for `target` group. |

### 1 existing builder update

`sms.task.attack_in_area` (DCS task `EngageTargetsInZone`) is documented by DCS as an enroute task, so it gets `opts.priority` (default 1).

### 2 constants namespaces

**`sms.targets.*`** — DCS target attribute strings, named for ergonomics:

```lua
sms.targets.AIR             = "Air"
sms.targets.PLANES          = "Planes"
sms.targets.HELICOPTERS     = "Helicopters"
sms.targets.GROUND_UNITS    = "Ground Units"
sms.targets.GROUND_VEHICLES = "Ground vehicles"
sms.targets.SHIPS           = "Ships"
sms.targets.AIR_DEFENCE     = "Air Defence"
sms.targets.SAM             = "SAM"
sms.targets.AAA             = "AAA"
sms.targets.STATICS         = "Static"
sms.targets.BUILDINGS       = "Buildings"
sms.targets.ALL             = "All"
```

**`sms.designations.*`** — FAC designation enum strings:

```lua
sms.designations.NO         = "No"
sms.designations.AUTO       = "Auto"
sms.designations.WP         = "WP"          -- white phosphorus marker
sms.designations.IR_POINTER = "IR-Pointer"
sms.designations.LASER      = "Laser"
```

Both namespaces hold plain strings under the hood. Builders accept the constants but also accept raw strings (forward-compat: if DCS adds a new attribute or designation, users can pass the string before the framework gets a constant for it).

### Category enforcement extension

The framework already has `_sms_air_only = true` on builder output for tasks DCS only honors on `airplane`/`helicopter` groups. We add a parallel `_sms_ground_only = true` flag for `fire_at_point` and `ewr`.

`_validate_apply` (in `framework/group.lua`) checks both: an `_sms_air_only` task on a ground group is rejected with a logged warn; an `_sms_ground_only` task on an air group is rejected the same way. `combo` propagates: if any sub-task has either flag, the combo inherits it. A combo containing **both** an air-only and a ground-only sub-task is built without warning (DCS-side will reject when applied — same failure-model boundary as today; the framework doesn't pre-validate combo internal contradictions).

## Out of scope

- **`Mission` task wrapper.** Already deferred; we already wrap routes inside `move_to` / `hold` for ground.
- **`ControlledTask` (stop conditions on tasks).** Useful but its own design conversation (StopCondition shape, user flag plumbing).
- **`WrappedAction` (commands inside ComboTask).** Requires a Commands surface we don't have yet.
- **Aerobatic tasks.** MOOSE has a suite of these; not a v1 priority.
- **Cargo tasks** (`Embarking`, `EmbarkToTransport`, `Disembarking`). Separate concern.
- **`AI.Task.WeaponExpend` constants.** Stays a raw string/integer pass-through (matches existing `weapon_type` pattern in `attack`/`bomb`).
- **`sms.airdrome` wrapper.** Tracked at [#23](https://github.com/nielsvaes/dcs-sms/issues/23). `bomb_runway` accepts integer airdrome ID for v1.1.
- **EngageTargets / EngageGroup / EngageUnit alternative param shapes.** MOOSE defines several — the FAQ documents one shape per task; we ship that.

## Builder details

### Param shapes

For each builder, the framework validates types up front (`log.warn` + nil on bad input, per failure model), then emits the DCS task table. Snake_case opts are translated to DCS's camelCase fields at build time.

`opts.target_types` is always an array of strings (constants from `sms.targets.*` recommended). `opts.weapon_type` is a string from the existing weapon-type-string table (`"Auto"`, `"Guns"`, `"Rockets"`, `"Missiles"`, `"Bombs"`) or a raw integer bitmask.

| Builder | Required args | Optional opts (with defaults) |
|---|---|---|
| `no_task()` | — | — |
| `attack_map_object(point, opts?)` | `point` (vec3) | `weapon_type="Auto"`, `expend="Auto"`, `attack_qty?`, `direction?` (degrees), `group_attack=false` |
| `bomb_runway(airdrome_id, opts?)` | `airdrome_id` (integer) | same opts as `attack_map_object` |
| `refuel()` | — | — |
| `escort(target, opts?)` | `target` (sms.unit | sms.group) | `offset={x=-50,y=0,z=-50}`, `engagement_dist_max=5000`, `target_types?`, `last_waypoint_index?` |
| `fire_at_point(point, opts?)` | `point` (vec3) | `radius?` |
| `fac_attack_group(target, opts?)` | `target` (sms.group) | `weapon_type="Auto"`, `designation="Auto"`, `datalink=true` |
| `engage_en_route_targets(opts?)` | — | `target_types` (required), `max_dist?`, `priority=1` |
| `engage_en_route_group(target, opts?)` | `target` (sms.group) | `weapon_type="Auto"`, `expend="Auto"`, `attack_qty?`, `direction?`, `priority=1` |
| `engage_en_route_unit(target, opts?)` | `target` (sms.unit) | `weapon_type="Auto"`, `expend="Auto"`, `attack_qty?`, `direction?`, `group_attack=false`, `priority=1` |
| `awacs(opts?)` | — | `priority=1` |
| `tanker(opts?)` | — | `priority=1` |
| `ewr(opts?)` | — | `priority=1` |
| `fac(opts?)` | — | `radius` (required), `priority=1` |
| `fac_engage_group(target, opts?)` | `target` (sms.group) | same as `fac_attack_group` plus `priority=1` |

### Coordinate translation

DCS task params use Vec2 (`{x, y}` where `y = vec3.z`) for ground-targeted tasks. Builders take vec3 and translate at build time (same as existing `bomb`/`attack_in_area`).

## Smoke test plan

Extend `framework/test/smoke_task.sh`:

- **Build coverage** for each new builder: returns the right `id`, has `_sms_verb` set, has `_sms_air_only` / `_sms_ground_only` correctly set, validates required args (each negative path → nil + warn).
- **Constants coverage** for `sms.targets` and `sms.designations`: assert each constant is a non-empty string (sentinel test against typos).
- **Apply coverage** — a `set_task` test for one of each category bucket, verifying the deferred dispatch returns the expected `true`/`false` and (for live cases) DCS doesn't reject.
- **Ground-only enforcement** — `set_task(fire_at_point)` on an air group → false + warn line `[sms.group] set_task: 'fire_at_point' is ground-only`.
- **Combo propagation** — `combo({move_to(X), fire_at_point(Y)})._sms_air_only == nil` (move_to isn't air-only); `combo({orbit(X), fire_at_point(Y)})._sms_air_only == true and _sms_ground_only == true` (mixed; will fail at apply).

Live smokes use the existing `_smoke_task_*` fixture pattern. Air enroute roles (AWACS, Tanker) probably can't be meaningfully verified without specific aircraft types — coverage is build-only for those.

## Decisions

Recorded autonomously, traceable to brainstorming questions in chat:

- **Q1 = A** — `engage_en_route_*` is its own verb family separate from `attack`. Two distinct DCS task ids (immediate `AttackGroup` vs enroute permission `EngageGroup`); collapsing them obscures runtime semantics.
- **Q2 = C** — enroute `priority` defaults to **1** (matches ME-generated tasks).
- **Q3 = B** — `sms.targets.*` namespace as named constants; raw strings still accepted by the builder for forward-compat.
- **Q4 = B** — new spec dated 2026-04-28 supplementing the v1 task spec.
- **Q5 = A** — `sms.designations.*` mirrors `sms.targets.*`.
- **Q6 = A** — `bomb_runway` takes an integer DCS airdrome ID for v1.1; `sms.airdrome` integration tracked in [#23](https://github.com/nielsvaes/dcs-sms/issues/23).
- **Naming** — `engage_en_route_*` (snake_case with the underscore) matches the explicit user request; chosen over `enroute_*` for clarity that "en route" is two words in DCS docs.

## Related issues

- [#23](https://github.com/nielsvaes/dcs-sms/issues/23) — `sms.airdrome` wrapper + handle/name acceptance in `bomb_runway`.

## AGENTS.md updates required

- §7 Module reference (`sms.task`) — add 14 builder rows, note `priority` on `attack_in_area`.
- §7 Module reference — add new entries for `sms.targets` and `sms.designations`.
- §8 (or wherever air-only is documented) — add ground-only enforcement note.
