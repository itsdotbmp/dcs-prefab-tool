# dcs-sms Framework — `sms.group.create` + `sms.group.clone` v1

**Date:** 2026-04-26
**Status:** Approved (brainstorm phase)
**Scope:** First spawning capability in the framework. Adds two factory functions to `sms.group` (`create` for from-scratch, `clone` for ME-template-derived) plus four unit-conversion helpers in `sms.utils`. Stateless, plain-table-config API — explicitly NOT a SPAWN-class equivalent.

## Goal

Build a small, stateless spawning surface that:

- Replaces what would be a "SPAWN" class with **two plain factory functions** that take config tables and return `sms.group` handles.
- Hides DCS's most painful spawn footguns (2D-y-means-z, name uniqueness, units-stack-without-offsets, radians/degrees mismatch) behind ergonomic input.
- Establishes auto-suffix on name collision so `create({name = "tank"})` always succeeds (returning `tank`, `tank-1`, `tank-2`, ...) rather than ever failing on uniqueness.
- Supports both ground and air spawns with a complete-enough field set for v1 (universal + air-specific blessed fields, plus pass-through for unknowns).
- Adds the `sms.utils.deg_to_rad`/`rad_to_deg`/`feet_to_meters`/`meters_to_feet` helpers as a side-deliverable since the spawn API needs them internally.

## User value

After this iteration the user can write:

```lua
-- Spawn three AAV-7s in formation, anywhere on the map
local convoy = sms.group.create({
  name      = "convoy",
  position  = sms.area("BattleZone"):get_random_point(),
  country   = "USA",
  category  = "ground",
  units = {
    { type = "AAV7", offset = {x = 0, y = 0, z = 0},  heading = 0 },
    { type = "AAV7", offset = {x = 0, y = 0, z = 20}, heading = 0 },
    { type = "AAV7", offset = {x = 0, y = 0, z = 40}, heading = 0 },
  },
})

-- Clone an ME-defined complex package with full configuration fidelity
local strike1 = sms.group.clone("Red-Strike-Package", {
  name     = "strike-1",
  position = sms.area("StrikeArea"):get_random_point(),
})
local strike2 = sms.group.clone("Red-Strike-Package", {
  name     = "strike-1",  -- collision: returns "strike-1-1"
  position = sms.area("StrikeArea"):get_random_point(),
})
```

…with no SPAWN class, no method chains, no name-collision boilerplate, and the same handle returned by `sms.group("name")` for downstream operations.

## Scope

### In scope (v1)

**New conversion helpers in `framework/utils.lua`:**

- `sms.utils.deg_to_rad(deg) -> number`
- `sms.utils.rad_to_deg(rad) -> number`
- `sms.utils.feet_to_meters(ft) -> number`
- `sms.utils.meters_to_feet(m) -> number`

**New module file `framework/spawn.lua`** — implementation only; exposes `sms.group.create` and `sms.group.clone` on the existing `sms.group` module. Internal helpers private to the file. Loaded after `area.lua` in the framework load order.

**Public API:**

- `sms.group.create(config) -> sms.group handle | nil + log`
  - Takes a config table describing one group + its units.
  - Resolves a unique name via auto-suffix.
  - Builds a DCS `group_def`, calls `coalition.addGroup`, verifies via `Group.getByName`, returns an `sms.group` handle wrapping the resolved name.

- `sms.group.clone(template_name, overrides) -> sms.group handle | nil + log`
  - Walks `env.mission.coalition[*].country[*].<category>.group[]` for a group named `template_name`.
  - Deep-copies its def. Decomposes each unit's absolute position into an `offset` relative to the original anchor (leader unit). Re-anchors using `overrides.position`. Renames per `overrides.name` with auto-suffix.
  - Calls the same internal `_spawn` path as `create`. Returns an `sms.group` handle.

**Config table for `create`:**

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `name` | string | ✓ | — | Group name; auto-suffixed on collision |
| `position` | vec3 | ✓ | — | Group anchor in world coords |
| `country` | string | ✓ | — | e.g. `"USA"`, mapped to `country.id.*` via lookup |
| `category` | string | ✗ | `"ground"` | `"ground"`/`"airplane"`/`"helicopter"`/`"ship"` |
| `task` | string | ✗ | per-category default | DCS task preset string |
| `route` | table | ✗ | auto-default for aircraft | DCS route table; if absent and category is air, framework provides one |
| `units` | array | ✓ | — | Non-empty list of unit specs |

**Per-unit fields (universal):**

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `type` | string | ✓ | — | DCS internal type string |
| `name` | string | ✗ | `<resolved_group_name>-<i>` | Auto-suffixed on collision |
| `offset` | vec3 | ✗ | `{0,0,0}` | Relative to group `position`; final world pos = `position + offset` |
| `heading` | number (degrees) | ✗ | `0` | Converted to radians internally for DCS |
| `skill` | string | ✗ | `"Average"` | DCS skill preset |
| `livery_id` | string | ✗ | DCS default | Cosmetic |
| `onboard_num` | string | ✗ | DCS default | Side number |

**Per-unit fields (air-specific — blessed for v1):**

| Field | Type | Required for air | Default | Notes |
|---|---|---|---|---|
| `alt` | number (meters) | ✓ for air | — | Altitude. DCS-native meters; matches rest of framework. |
| `alt_type` | string | ✗ | `"BARO"` | `"BARO"` (MSL) or `"RADIO"` (AGL) |
| `speed` | number (m/s) | ✗ | `200` (airplane), `0` (helicopter) | For airborne airplane spawn, must be ≥ stall speed; airplanes need forward speed or they stall, helicopters can hover-spawn at 0 |
| `payload` | table | ✗ | type defaults | `{ pylons, fuel, flare, chaff, gun }` |
| `callsign` | table or number | ✗ | DCS auto | Numeric or `{name=..., 1, 1, 1}` |
| `frequency` | number (Hz) | ✗ | type-specific | Radio frequency |
| `modulation` | number | ✗ | `0` | `0`=AM, `1`=FM |
| `parking_id` | number | ✗ | none | For ramp/parking starts at airbases |

**Pass-through:** any unit-table key not in the blessed set is forwarded to DCS verbatim. Forward-compat with future DCS additions; user takes ownership of correctness.

**Overrides table for `clone`:**

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `name` | string | ✓ | — | New group name; auto-suffixed on collision |
| `position` | vec3 | ✓ | — | New anchor; original offsets are preserved relative to it |

v1 only `name` + `position` are overridable. Per-unit overrides defer.

**New smoke test `framework/test/smoke_spawn.sh`** — bridge-driven; exercises `sms.utils` conversions, `create` happy paths (ground single, ground multi-unit with offsets, air with altitude, heading-degrees-conversion), `create` failure paths, auto-suffix behavior, and `clone` against an ME-discovered template.

### Out of scope (v1)

- **Static objects** (`coalition.addStaticObject`). Different DCS API. Future `sms.static` sub-project.
- **Cargo objects.** Same as static.
- **Per-unit overrides on `clone`.** v1 only overrides `name` + `position`. Modifying unit types/payloads/positions of a cloned template requires `create` from scratch.
- **Live-API fallback for `clone`.** ME-defined templates only via `env.mission` walk. Runtime-spawned groups not cloneable in v1.
- **Late-activation control.** No `:activate()` / `:deactivate()` methods. Users pass `lateActivation = true` as a pass-through field if they need it.
- **Spawn limits / queues / throttling.** No `init_limit(N)`. Compose with `sms.timer` for rate-limiting.
- **Event hooks** (`on_spawn`, `on_dead`). Future `sms.events` sub-project.
- **Group-level `heading` default.** Each unit specifies its own heading.
- **Strict-name mode** (no `strict_name = true` opt-out). Auto-suffix is universal.
- **Output-side feet/degrees conversion.** Getters elsewhere in the framework still return DCS-native (meters/radians); users call `sms.utils.*` to convert.
- **Custom group categories** (e.g., spawning "static" via `addGroup`).
- **Validation of pass-through fields.** Unknown keys go to DCS as-is.
- **Aircraft route DSL.** No helper for building waypoint structures. Users construct `route` tables directly per DCS schema.
- **Triangle/polygon-shape-aware unit positioning.** Offsets are flat 2D xz pairs.
- **Programmatic registration of created groups.** No tracking; each `create` call independent.
- **`sms.spawn` namespace.** All factory functions live on `sms.group`.

## Constraints

- Lua 5.1 (DCS mission environment). No `goto`, no `//`, no Lua 5.2+ idioms.
- Must work under bridge-driven loading. No `require`. New globals: `sms.group.create`, `sms.group.clone`, plus four `sms.utils.*` conversion functions.
- Failure model: log + return safe value (`nil`) for all factory calls. Never throws. No `error()` calls in the new code.
- The framework's other modules (`group`, `unit`, `area`, etc.) are unchanged in behavior. The `sms.group` module gets two NEW keys (`create`, `clone`) — existing keys (`is_alive`, `get_name`, etc.) are untouched.
- The new code must NOT depend on the live "tester" / scratch state in the user's mission. All testing is hermetic relative to spawned fixtures.

## Architecture

### File layout

```
framework/
├── sms.lua              # unchanged
├── log.lua              # unchanged
├── utils.lua            # ADDS: 4 conversion functions
├── group.lua            # unchanged (sms.group keys ADDED externally by spawn.lua)
├── unit.lua             # unchanged
├── area.lua             # unchanged
├── timer.lua            # unchanged
├── spawn.lua            # NEW: ~500 lines
└── test/
    └── smoke_spawn.sh   # NEW: bridge-driven smoke test
```

Loading order: `sms.lua → log.lua → utils.lua → group.lua → unit.lua → area.lua → timer.lua → spawn.lua`.

### `framework/spawn.lua` internal structure

```lua
-- Module-private state and lookup tables
local _name_counters         -- table: base_name -> next-index hint for auto-suffix
local _country_lookup        -- table: "USA" -> country.id.USA, etc. Built lazily on first use.
local _category_map          -- table: "ground" -> Group.Category.GROUND, etc.
local _default_task_for      -- table: "ground" -> "Ground Nothing", "airplane" -> "Nothing", ...

-- Validation helpers
local _validate_create_config(cfg)         -- top-level required-field checks
local _validate_unit_spec(u, idx, category) -- per-unit checks (type required, alt for air, etc.)
local _resolve_country(s)                  -- "USA" -> int via lookup; nil + log on miss
local _resolve_category(s)                 -- string -> int; nil + log on miss

-- Core helpers
local _resolve_unique_name(base, getter)   -- collision-safe name generation; getter is Group.getByName or Unit.getByName
local _build_dcs_unit(u_spec, anchor, category, base_unit_name, idx)
                                             -- vec3+offset → DCS-2D x/y; deg→rad heading; pass-through unknowns
local _build_dcs_group_def(cfg)            -- assembles full DCS group_def from cfg
local _default_route_for_aircraft(cfg)     -- returns a route table if cfg has none and category is air
local _spawn(group_def, country_int, category_int)
                                             -- coalition.addGroup + Group.getByName verification

-- Clone-specific
local _find_template_in_mission(template_name)
                                             -- walks env.mission.coalition[*].country[*].<category>.group[]
                                             -- returns {def, country_int, category_int} or nil
local _decompose_to_offsets(template_def)  -- copies + computes anchor + per-unit offsets
local _reanchor_def(def, new_anchor, new_name)
                                             -- writes new x/y values from offsets + new_anchor

-- Public API (added to sms.group)
sms.group.create = function(cfg) ... end
sms.group.clone  = function(template_name, overrides) ... end
```

### Auto-suffix mechanism

```lua
local _name_counters = {}

local function _resolve_unique_name(base, getter)
  if not getter(base) then return base end
  local n = _name_counters[base] or 1
  while getter(base .. "-" .. n) do
    n = n + 1
  end
  _name_counters[base] = n + 1
  return base .. "-" .. n
end
```

Used twice:
- For group name with `getter = Group.getByName`
- For each unit name with `getter = Unit.getByName`

The counter is a hint. We always probe via the DCS getter for actual freeness. Counter just optimizes "next likely free index."

### Coordinate translation

DCS's `coalition.addGroup` schema uses a 2D coordinate system where `x` is north-south and `y` is east-west (i.e., DCS-2D-y == vec3-z, both representing the east-west axis). The framework's vec3 convention is `{x = north-south, y = altitude, z = east-west}`.

Translation in `_build_dcs_unit`:

```lua
local world_x = anchor.x + (u_spec.offset and u_spec.offset.x or 0)
local world_z = anchor.z + (u_spec.offset and u_spec.offset.z or 0)
-- DCS group_def expects:
--   unit.x = world_x   (east-west)
--   unit.y = world_z   (DCS-2D-y is our z)
-- For air units:
--   unit.alt = u_spec.alt (meters)
--   unit.alt_type = u_spec.alt_type or "BARO"
--   unit.speed = u_spec.speed (or 200 for airplanes; helicopters omit, defaulting to 0)
-- For all units:
--   unit.heading = sms.utils.deg_to_rad(u_spec.heading or 0)
--   unit.psi = -unit.heading  (DCS internal; compute from heading)
```

`offset.y` is ignored for ground units (terrain-snapped). For air units, `alt` overrides any altitude implication of `offset.y`.

### Default route for aircraft

If `category` is `"airplane"` or `"helicopter"` and no `route` field is provided, generate a default route with one waypoint 50km north of the spawn anchor:

```lua
{
  points = {
    [1] = {
      type = "Turning Point",
      action = "Turning Point",
      x = anchor.x,
      y = anchor.z + 50000,  -- DCS-2D-y == vec3-z
      alt = first_unit_alt or 5000,
      alt_type = "BARO",
      speed = 200,            -- ~720 km/h
      task = { id = "ComboTask", params = { tasks = {} } },
    },
  },
}
```

Aircraft will fly toward the waypoint and then no-op (likely stalling or running out of fuel). Documented as "v1 default; pass `route` for real flight planning."

### Clone strategy

Walk `env.mission.coalition[*].country[*].<category>.group[]` for a group with matching `name`. Sides are `red`/`blue`/`neutrals`; categories are `plane`/`helicopter`/`vehicle`/`ship`/`train` (DCS uses different category keys in the mission descriptor than `Group.Category.*` — note `vehicle` for ground, not `ground_units`).

Walk implementation:

```lua
local function _find_template_in_mission(template_name)
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  local category_keys = {
    plane      = "airplane",
    helicopter = "helicopter",
    vehicle    = "ground",
    ship       = "ship",
    train      = "train",
  }
  for _, side_key in ipairs(side_keys) do
    local side = env.mission.coalition[side_key]
    if side and side.country then
      for _, country in ipairs(side.country) do
        for cat_key, cat_string in pairs(category_keys) do
          local cat = country[cat_key]
          if cat and cat.group then
            for _, g in ipairs(cat.group) do
              if g.name == template_name then
                return {
                  def = g,
                  country_int = country.id,    -- numeric country id from mission
                  category_string = cat_string,
                }
              end
            end
          end
        end
      end
    end
  end
  return nil
end
```

Then re-anchor: compute the original anchor as `(g.units[1].x, 0, g.units[1].y)` (vec3 with z = DCS-2D-y), compute each unit's offset as `(unit.x - anchor.x, 0, unit.y - anchor.z)`, then write new positions as `new_anchor.x + offset.x`, `new_anchor.z + offset.z`.

### Failure mode summary

| Situation | Behavior |
|---|---|
| `sms.group.create()` with no/non-table arg | log `create: config must be a table`, return `nil` |
| Missing `name`, `position`, `country`, or `units` | log + nil |
| `position` not a vec3 (missing/non-number x/y/z) | log + nil |
| `country` not a string, or unknown | log + nil |
| `category` not a recognized string | log + nil |
| `units` not a table or empty | log + nil |
| Any unit missing `type` or with non-string `type` | log + nil |
| Unit `offset` present but not a vec3 | log + nil |
| Unit `heading` present but not a number | log + nil |
| Air category but a unit has no `alt` (or `alt` is not a number) | log + nil |
| `coalition.addGroup` succeeds but post-call verify fails | log `create: DCS rejected the spawn (check type/payload/route validity)`, return `nil` |
| `clone` template not found in `env.mission.*` | log `clone: template '<X>' not in mission`, return `nil` |
| `clone` overrides missing `name` or `position` | log + nil |
| Garbage input (numbers, booleans) | log + nil at the type-check step |

**No collision failures** — auto-suffix handles uniqueness universally. The returned handle's `:get_name()` is authoritative for the actual resolved name.

## Smoke test outline

`framework/test/smoke_spawn.sh`:

1. Hook status check.
2. Load framework files in order: `sms`, `log`, `utils`, `group`, `unit`, `area`, `spawn`. (timer not required for these tests but loading it is harmless.)
3. **`sms.utils` conversion sanity** — basic correctness of the 4 conversion functions including a meters↔feet round-trip.
4. **`sms.group.create` ground single-unit** — spawn one AAV-7, verify alive via `sms.unit:get_type()`.
5. **`sms.group.create` ground multi-unit with offsets** — spawn 3 AAV-7s with `offset.z = 0,20,40`. Verify each unit's world position equals `position + offset`.
6. **Heading-degrees conversion** — spawn one unit with `heading = 90` (degrees, east). Read back via `Unit.getByName(name):getPosition()` orientation matrix, extract yaw, verify ≈ π/2 radians (within tolerance).
7. **`sms.group.create` air** — spawn an F-16 at `alt = 5000`. Verify it's airborne (`unit:getPoint().y > 4000`).
8. **Auto-suffix** — three calls with `name = "tank"`. Verify resolved names are `"tank"`, `"tank-1"`, `"tank-2"`.
9. **`sms.group.create` negative paths**:
   - Missing `name` / `position` / `country` / `units` → nil
   - Bad country (`"WAKANDA"`) → nil
   - Bad category → nil
   - Unit missing `type` → nil
   - Air category with no `alt` → nil
   - Garbage input → nil
10. **`sms.group.clone`** — discover any ME-defined group via `env.mission`, clone with new name + position offset 1km east. Verify clone exists, unit count matches, first unit type matches.
11. **`sms.group.clone` auto-suffix** — clone same template twice with same `name` arg, verify second resolved name has `-1` suffix.
12. **`sms.group.clone` negative** — `clone("not_a_template", {...}) == nil`.
13. **Cleanup** — destroy every group spawned this run by name (collected from create/clone returns).
14. **Tail-log assertion** — at least one `[sms.spawn]` line for a known-failing case (e.g. `unknown country 'WAKANDA'`).
15. `smoke ok` and exit 0.

**Total runtime:** <10 seconds. No host-side sleeps.

**Prerequisite:** mission must have at least one ME-defined group (any kind). Same condition as `smoke_unit.sh`.

## Decisions (made autonomously, recorded for revisit)

- **Module: `sms.group` extended.** `create` and `clone` are added as named factory functions to the existing `sms.group` module by `spawn.lua` at load time. No new `sms.spawn` namespace.
- **Code lives in `framework/spawn.lua`.** Keeps `group.lua` focused on entity-method concerns; spawn surface in one focused file.
- **Public field names:** `position` (group anchor), `offset` (per-unit relative). Not `at`, not `coords`.
- **Heading in degrees, altitude in meters.** Asymmetric units. Heading converts at the boundary; alt passes through DCS-native.
- **Country and category are strings**, mapped internally via lookup. No raw `country.id.USA` or `Group.Category.GROUND` exposure.
- **Auto-suffix on name collision.** Counter-based with `Group.getByName` / `Unit.getByName` probe for actual freeness. Counter table `_name_counters` is module-local, lost on reload (which is fine — probe recovers).
- **Auto-suffix is universal**, no `strict_name` opt-out in v1.
- **Returned handle's `:get_name()` is authoritative** for the resolved name. Documented in code header.
- **`clone` walks `env.mission` only.** Full configuration fidelity for ME templates; runtime-spawned groups not cloneable. Live-API fallback deferred.
- **`clone` overrides limited to `name` + `position`.** Per-unit overrides defer.
- **Aircraft auto-default route** when `route` absent: single waypoint 50km north of spawn, speed ~200 m/s, alt = first unit's `alt` or 5000m. Aircraft fly toward it then no-op. Users wanting real routing pass `route`.
- **Pass-through unknown fields verbatim** to DCS at both group and unit level. Forward-compat.
- **`offset.y` ignored for ground units** (terrain-snapped). For air units, `alt` is the source of truth for altitude.
- **No registration/tracking of created groups.** Each `create` call independent.
- **Vec3 only for `position` and `offset`.** No accepting area handles or function-returning-vec3.
- **`psi` computed from `heading`** internally. Users don't set it.
- **Default `task` per category:** ground = `"Ground Nothing"`, airplane = `"Nothing"`, helicopter = `"Nothing"`, ship = `"Nothing"`. Users can override.
- **Default `skill` is `"Average"`** for any unit that doesn't specify.
- **Default `category` is `"ground"`** if absent. Most v1 use cases are ground.
- **The four `sms.utils` conversions ship together** — `deg_to_rad`, `rad_to_deg`, `feet_to_meters`, `meters_to_feet`. All four useful regardless of spawn.
- **`framework/spawn.lua` is the file name.** No `_spawn.lua`, no `factory.lua`. Reads as "this file is about spawning."

## Related issues

- **#2** — hook auto-injection (mechanism C). When this lands, `sms.log.module()` no-arg form will work and `framework/spawn.lua` can drop the explicit `"sms.spawn"` tag.
- **#3** — bridge auto-return-prepend ergonomics. Independent.
- (Future) Live-API fallback for `clone` if there's real demand. Issue to file post-merge if needed.
- (Future) Per-unit overrides on `clone`. File post-merge.
- (Future) `sms.events` for spawn-related events (`on_spawn`, `on_dead`).
- (Future) `sms.static` for static-object spawning.

## Open questions

None. All ambiguities resolved during brainstorming or recorded as decisions above.
