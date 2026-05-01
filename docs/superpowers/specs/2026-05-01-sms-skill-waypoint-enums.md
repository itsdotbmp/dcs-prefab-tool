# `sms.skill`, `sms.alt_type`, `sms.waypoint` enums — design spec

**Status:** approved (auto-approved via `/write-it`, 2026-05-01)
**Branch:** `feat/sms-skill-waypoint`
**Worktree:** `.worktrees/sms-skill-waypoint`

## Goal

Add three more enum modules to dcs-sms covering the magic-string fields users hit when writing spawn configs and routes:

- `sms.skill` (flat, 7 entries) — unit AI skill levels.
- `sms.alt_type` (flat, 2 entries) — waypoint altitude reference.
- `sms.waypoint.TYPE` (7 entries) and `sms.waypoint.ACTION` (11 entries) under one `sms.waypoint` module.

This is the second batch of enum work, following the `sms.countries` module that landed at `b3d7b02`. Same pattern, same shape: hand-listed table, `<KEY> = "<DCS string>"`, LuaCATS class + alias for autocomplete on both `sms.X.KEY` access and raw-string literals.

## User value

Today, mission code writes magic strings everywhere:

```lua
sms.group.create({
  name = "convoy", country = "USA", category = "ground",
  units = { {type = "M-1 Abrams", heading = 0, skill = "Average"} },  -- ← magic string
})
```

Typos in any of these strings (`"Avarage"`, `"BARO_"`, `"TurningPoint"`) silently fall through DCS — sometimes accepted as the default, sometimes rejected at runtime, never typo-checked at edit time. The four enums in this spec close those gaps:

- `sms.skill.AVERAGE` resolves to `"Average"`. Autocomplete lists every skill level. `sms.skill|string` LuaCATS alias on the `skill` field of unit specs catches typos in raw strings too.
- `sms.alt_type.BARO` / `RADIO`. Two values; trivial. The LuaCATS alias makes `alt_type = "BARO"` typo-checkable.
- `sms.waypoint.TYPE.TURNING_POINT` resolves to `"Turning Point"` — the multi-word form DCS expects, which is the most common typo source. Same for the 6 takeoff/land variants.
- `sms.waypoint.ACTION.OFF_ROAD` / `ON_ROAD` / `FROM_PARKING_AREA` / etc. The 11 DCS waypoint-action strings, several of which contain spaces and case-sensitive substrings.

After this work, the `sms.group.create` config surface and any hand-built route table is fully autocomplete-friendly: `country`, `type`, `skill`, `alt_type`, plus waypoint `type` and `action` all have first-class enum support.

## Scope

### In scope

1. New module `framework/skill.lua` exposing `sms.skill.<KEY> = "<DCS string>"` for 7 skill levels (`AVERAGE`, `GOOD`, `HIGH`, `EXCELLENT`, `RANDOM`, `PLAYER`, `CLIENT`).
2. New module `framework/alt_type.lua` exposing `sms.alt_type.BARO = "BARO"` and `sms.alt_type.RADIO = "RADIO"`.
3. New module `framework/waypoint.lua` exposing:
   - `sms.waypoint.TYPE.<KEY>` for 7 waypoint type strings.
   - `sms.waypoint.ACTION.<KEY>` for 11 waypoint action strings.
4. LuaCATS for each: `---@class` field block driving `sms.X.KEY` autocomplete, plus `---@alias sms.Skill` / `sms.AltType` / `sms.WaypointType` / `sms.WaypointAction` literal-union aliases driving raw-string autocomplete.
5. Update `framework/load_all.lua` to load the three new files (after `countries.lua`, before `units.lua` — see Decision D5 for ordering).
6. Update `framework/group_spawn.lua` so the existing LuaCATS `---@field skill? string` and `---@field alt_type? string` annotations on `sms.group.unit_spec` reference `sms.Skill|string` and `sms.AltType|string`. Comment text updated to mention the new enum modules.
7. New API doc pages: `docs/api/skill.md`, `docs/api/alt_type.md`, `docs/api/waypoint.md`.
8. Update `docs/api/README.md` module-index table to add three rows.
9. Update `AGENTS.md` §7 module-index table to add three rows.
10. Update `README.md` "Repo layout" framework module list.
11. Smoke-test additions in `framework/test/smoke.sh` covering: load + identity invariant (`sms.skill.AVERAGE == "Average"`, `sms.alt_type.BARO == "BARO"`, `sms.waypoint.TYPE.TURNING_POINT == "Turning Point"`, etc.) for a representative subset.

### Out of scope

- Sweep of `framework/group.lua` / `framework/task.lua` / `framework/group_spawn.lua` to replace internal literal emissions (`type = "Turning Point"`, `action = "Off Road"`, `alt_type = "BARO"`) with the new enum references. The literals are framework internals, not user-facing API; replacing them is mechanical busywork without user-visible value. **Decision D7** documents the call.
- Sweep of `docs/api/examples.md` — verify but expect no changes; current examples don't hand-build routes or set skills, so there should be nothing to sweep. If the sweep finds anything, add it; otherwise no commit.
- A `sms.waypoint.create(opts) → wp_table` builder. That's a real follow-up project (a route DSL), not part of this enum-only batch.
- A `sms.formation` enum for ground-unit formation strings (`"Rank"`, `"Cone"`, `"Vee"`, `"Diamond"`, `"EchelonL"`, `"EchelonR"`). MOOSE has these; dcs-sms doesn't currently emit any of them. Defer until a use case appears.
- Numeric Group.Category integers (`Group.Category.AIRPLANE` etc.) on a hypothetical `sms.category` enum. The `category` spawn-config field currently accepts lowercase strings (`"airplane"`); MOOSE's parallel enum is integers, but framework users don't hit those directly. Defer.
- Reverse lookup helpers (`sms.skill.from_dcs(...)`). YAGNI.

## Constraints

- **Lua 5.1.** All three modules run inside the DCS mission environment.
- **Idempotent load.** Each `sms.<module> = sms.<module> or {}` to survive reload.
- **No throws.** No public functions on these modules — just tables and LuaCATS — so the failure model is trivially satisfied. There's no DCS global to introspect for these enums (unlike `country.id`), so no runtime drift check this round; if DCS adds new skill levels or waypoint actions, mission authors pass raw strings (the `|string` half of the alias keeps that legal) and the static list is updated by hand.
- **Drop-in.** Existing call sites with raw strings continue to work. The new enums are pure additions — no behavior changes in `group_spawn.lua`'s spawn path.
- **Match existing precedent.** Follow the shape of `framework/skills.lua`-equivalents in the codebase: `framework/targets.lua`, `framework/designations.lua`, `framework/countries.lua`. Header comment, `assert(...)` prerequisites, `local log = sms.log.module(...)`, idempotent `or {}`, `---@class` + `---@alias` double form, explicit assignments.

## Decisions

### D1 — Three separate files, not one

Each module is its own file: `framework/skill.lua`, `framework/alt_type.lua`, `framework/waypoint.lua`. Reasoning: matches the established precedent of one-module-per-file (`targets.lua`, `designations.lua`, `countries.lua` all do this even when small). A combined `framework/enums.lua` would be tidier in the loader but harder to navigate when looking up "where do I add a new skill level?".

### D2 — `sms.skill` and `sms.alt_type` flat; `sms.waypoint` nested

Per the user's explicit direction. Reasoning is per-enum:
- `sms.skill` — "skill" doesn't have sibling subdivisions. A flat namespace is honest about that and matches `sms.targets` / `sms.designations` / `sms.countries`.
- `sms.alt_type` — Two entries; flat is overwhelmingly the right shape. Could be folded under `sms.waypoint.ALT_TYPE` since the field only appears on waypoints, but the user wants flat for ergonomic reasons (it's used in unit specs too, e.g. air units have `alt_type` on the unit table independent of route).
- `sms.waypoint` — Two related sub-namespaces (`TYPE` and `ACTION`) with overlapping vocabulary (`Turning Point` appears in both, as different identifiers). Nesting under `sms.waypoint` keeps the relationship visible. Matches `sms.options.ROE` / `sms.commands.MODULATION` precedent.

### D3 — Skill includes `PLAYER` and `CLIENT`

DCS uses these as special placeholder skill values for unit slots that mark a unit as human-controllable (player aircraft slots / multiplayer client slots). They're not skill levels per se but they live in the same `skill` field, and MOOSE's Unit.lua explicitly checks for them. Including them in the enum reflects what the field actually accepts.

### D4 — Waypoint `TakeOff` alias dropped

MOOSE's `Point.lua` declares `TakeOff = "TakeOffParkingHot"` as an alias. We expose the canonical `TAKEOFF_PARKING_HOT` only. Reasoning: aliases inflate autocomplete with two identifiers for the same DCS value, which is more confusing than helpful in editor suggestions. Users who want a "default takeoff" shorthand can `local Takeoff = sms.waypoint.TYPE.TAKEOFF_PARKING_HOT` in their own code.

### D5 — Loader order: after `countries.lua`, before `units.lua`

Insert the three new files immediately after `countries.lua` in `framework/load_all.lua`'s `modules` array, in the order `skill.lua`, `alt_type.lua`, `waypoint.lua`. Reasoning: these are pure-data modules with no inter-dependencies, and grouping them with `countries.lua` clusters all the "small enum" modules together in the loader. Loading before `units.lua` doesn't matter functionally (no cross-references) but keeps the cluster together.

### D6 — `OFF_ROAD` and `ON_ROAD` included in `sms.waypoint.ACTION`

These appear in `framework/group.lua` and `framework/task.lua` as the action emitted for ground / ship / train waypoints (`action = "Off Road"`). They aren't in MOOSE's `COORDINATE.WaypointAction` table because MOOSE separates ground-unit actions, but they're real DCS values that the framework already produces. Including them keeps the enum honest: every waypoint action string the framework or its users ever pass is in the enum.

### D7 — Internal framework emissions NOT swept

`framework/group.lua` and `framework/task.lua` currently emit literals like `type = "Turning Point"`, `action = "Off Road"`, `alt_type = "BARO"`. We are NOT replacing these with `sms.waypoint.TYPE.TURNING_POINT` etc.

Reasoning:
- These are framework internals, not user-facing.
- The literal values are tightly bound to the function that emits them — replacing them with enum references adds an indirection (`sms.waypoint.TYPE.TURNING_POINT` resolves to `"Turning Point"` at module load) without making the code any less correct.
- A future regression where the literal accidentally becomes `"TurningPoint"` is no more or less likely than a regression where the enum value is mis-spelled — both fail the same way.
- Doing the sweep would inflate the diff with mechanical changes, making it harder to review the actual new-enum-shape.

If a future maintainer wants to do this sweep as a separate refactor, that's fine — it's a self-contained mechanical change. We just don't do it here.

### D8 — Comment-text update on `group_spawn.lua` annotations

The existing `---@field skill?` annotation on `sms.group.unit_spec` reads:

```lua
---@field skill? string  # "Average" | "Good" | "High" | "Excellent" | "Random" (default "Average")
```

Update to:

```lua
---@field skill? sms.Skill|string  # AI skill level; pass sms.skill.<KEY> for autocomplete (default "Average")
```

Same shape for `alt_type?` annotation. The `|string` half keeps raw-string usage legal; the alias drives autocomplete. Inline value enumeration ("Average | Good | ...") drops out of the comment because the alias supplies that information richer.

### D9 — No drift check this round

Unlike `sms.countries`, which has DCS's `country.id` as a runtime ground truth and warns when keys diverge, none of these four enums have a corresponding DCS-global table. The values are documented in DCS scripting docs and MOOSE source but not introspectable at runtime. If DCS adds a new skill level or waypoint action in a future patch, mission authors pass the raw string (the `|string` half of the alias allows it) and we update the static list by hand when someone notices.

### D10 — Smoke-test scope

Add a small `sms.skill / sms.alt_type / sms.waypoint enums` block to `framework/test/smoke.sh` (after the existing `sms.countries` block) covering one representative entry from each enum: `sms.skill.AVERAGE == "Average"`, `sms.alt_type.BARO == "BARO"`, `sms.waypoint.TYPE.TURNING_POINT == "Turning Point"`, `sms.waypoint.ACTION.OFF_ROAD == "Off Road"`. Plus a presence check on `sms.skill.PLAYER` (the less obvious "skill is also a player marker" case). Five assertions total.

## Open questions

(none)

## Appendix — Canonical value lists

### `sms.skill` (7 entries)

| Identifier | DCS string | Source |
|---|---|---|
| `AVERAGE` | `"Average"` | MOOSE `Spawn.lua` |
| `GOOD` | `"Good"` | MOOSE `Spawn.lua` |
| `HIGH` | `"High"` | MOOSE `Spawn.lua` |
| `EXCELLENT` | `"Excellent"` | MOOSE `Spawn.lua` |
| `RANDOM` | `"Random"` | MOOSE `Spawn.lua` |
| `PLAYER` | `"Player"` | MOOSE `Unit.lua` (player-slot marker) |
| `CLIENT` | `"Client"` | MOOSE `Unit.lua` (multiplayer-client-slot marker) |

### `sms.alt_type` (2 entries)

| Identifier | DCS string | Source |
|---|---|---|
| `BARO` | `"BARO"` | MOOSE `Point.lua`, dcs-sms emissions |
| `RADIO` | `"RADIO"` | MOOSE `Point.lua` |

### `sms.waypoint.TYPE` (7 entries)

| Identifier | DCS string | Source |
|---|---|---|
| `TAKEOFF_PARKING` | `"TakeOffParking"` | MOOSE `Point.lua` |
| `TAKEOFF_PARKING_HOT` | `"TakeOffParkingHot"` | MOOSE `Point.lua` |
| `TAKEOFF_GROUND` | `"TakeOffGround"` | MOOSE `Point.lua` |
| `TAKEOFF_GROUND_HOT` | `"TakeOffGroundHot"` | MOOSE `Point.lua` |
| `TURNING_POINT` | `"Turning Point"` | MOOSE `Point.lua`, dcs-sms emissions |
| `LAND` | `"Land"` | MOOSE `Point.lua` |
| `LANDING_REFUEL_REARM` | `"LandingReFuAr"` | MOOSE `Point.lua` |

### `sms.waypoint.ACTION` (11 entries)

| Identifier | DCS string | Source |
|---|---|---|
| `TURNING_POINT` | `"Turning Point"` | MOOSE `Point.lua`, dcs-sms emissions |
| `FLYOVER_POINT` | `"Fly Over Point"` | MOOSE `Point.lua` |
| `FROM_PARKING_AREA` | `"From Parking Area"` | MOOSE `Point.lua` |
| `FROM_PARKING_AREA_HOT` | `"From Parking Area Hot"` | MOOSE `Point.lua` |
| `FROM_GROUND_AREA` | `"From Ground Area"` | MOOSE `Point.lua` |
| `FROM_GROUND_AREA_HOT` | `"From Ground Area Hot"` | MOOSE `Point.lua` |
| `FROM_RUNWAY` | `"From Runway"` | MOOSE `Point.lua` |
| `LANDING` | `"Landing"` | MOOSE `Point.lua` |
| `LANDING_REFUEL_REARM` | `"LandingReFuAr"` | MOOSE `Point.lua` |
| `OFF_ROAD` | `"Off Road"` | dcs-sms emissions (`group.lua`, `task.lua`) |
| `ON_ROAD` | `"On Road"` | DCS scripting docs |
