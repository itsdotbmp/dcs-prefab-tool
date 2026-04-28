# dcs-sms Framework — `sms.static` v1

**Date:** 2026-04-26
**Status:** Approved (brainstorm phase)
**Scope:** First static-object capability in the framework. Adds the entity-wrapper module `sms.static` (handle + factories) and a single new predicate `sms.area:is_static_in()`. Stateless, plain-table-config API — sibling treatment to `sms.group` + `sms.group.create`/`clone`.

## Goal

Build a small static-object surface that:

- Exposes `sms.static("name")` as a lightweight entity handle (mirror of `sms.unit`), with `is_alive`, `get_name`, `get_position`, `get_coalition`, `get_country`, `get_type`, `destroy`.
- Adds `sms.static.create(cfg)` for from-scratch spawning via `coalition.addStaticObject`.
- Adds `sms.static.clone(template_name, overrides)` for ME-template-derived spawning.
- Adds `sms.area:is_static_in(static_handle)` next to `is_unit_in`.
- Hides DCS's static-spawn footguns: 2D-y-means-z translation, name uniqueness, radians/degrees mismatch on heading.
- Establishes auto-suffix on name collision so `create({name = "crate"})` always succeeds (yielding `crate`, `crate-1`, `crate-2`, …) rather than failing on uniqueness.

## User value

After this iteration the user can write:

```lua
-- Drop a hangar where the F-16 is parked
local hangar = sms.static.create({
  name     = "alpha-hangar",
  type     = "Hangar B",
  position = sms.area("Ramp"):get_random_point(),
  country  = "USA",
  heading  = 90,
})

-- Clone an ME-defined cargo container fixture
local crate = sms.static.clone("supply-crate-template", {
  name     = "crate-1",
  position = sms.area("DropZone"):get_random_point(),
})

-- Compose with sms.area
if sms.area("DropZone"):is_static_in(crate) then
  sms.log.info("crate landed in zone")
end

-- Inspect at runtime
hangar:is_alive()        -- true
hangar:get_type()        -- "Hangar B"
hangar:get_country()     -- "USA"
hangar:destroy()
```

…with no SPAWN class, no method chains, the same handle returned by `sms.static("name")` for downstream operations, and the area predicate composing naturally with the existing `sms.area` surface.

## Scope

### In scope (v1)

**New module file `framework/static.lua`** — entity wrapper + factories in one file (~250 lines). Loaded after `spawn.lua`. Internal helpers private to the file.

**Edit `framework/area.lua`** — add `sms.area.is_static_in(area, static_handle)`. Mirror of `is_unit_in`; resolves `sms.static` lazily at call time.

**New smoke test `framework/test/smoke_static.sh`** — bridge-driven; mirrors `smoke_spawn.sh` shape.

**Public API on `sms.static`:**

Entity-wrapper methods (mirror of `sms.unit` with `get_country` added):

| Method | Behavior |
|---|---|
| `is_alive(s)` | `StaticObject.getByName(name) ~= nil`; `false` for garbage input. **Diverges from `sms.unit`** which uses `isExist()`. Reason: dead-spawned statics (`cfg.dead = true`) are findable via `getByName` but return `false` from `isExist()`; gating methods on `isExist()` would make them unusable. Across frames, `getByName` clears for actually-destroyed statics, so the gate still fires correctly. |
| `get_name(s)` | accessor; nil-safe via `_name_of` normalizer |
| `get_position(s)` | `getPoint()` → vec3 `{x = north-south, y = altitude, z = east-west}` |
| `get_coalition(s)` | int → `"red"`/`"blue"`/`"neutral"` |
| `get_country(s)` | int from `getCountry()` → string (e.g. `"USA"`); reverse-lookup via cached `country.id` map |
| `get_type(s)` | `getTypeName()` |
| `destroy(s)` | `getByName(name):destroy()` → `true`; nil + log if not alive |

Factories:

- `sms.static.create(cfg) -> sms.static handle | nil + log`
- `sms.static.clone(template_name, overrides) -> sms.static handle | nil + log`

Sugar constructor: `sms.static("name") -> sms.static handle | nil + log`. Wired via `sms._make_callable_handle(sms.static, StaticObject.getByName, log)`.

**Config table for `create`:**

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `name` | string | ✓ | — | Auto-suffixed on collision (probes `StaticObject.getByName` only) |
| `type` | string | ✓ | — | DCS model key (e.g. `"Hangar B"`, `"iso_container"`, `"FARP"`). Empirically required by `coalition.addStaticObject`. |
| `position` | vec3 | ✓ | — | Group anchor in world coords |
| `country` | string | ✓ | — | e.g. `"USA"`, mapped to `country.id.*` via lookup |
| `heading` | number (degrees) | ✗ | `0` | Converted to radians internally. |
| `category` | string | ✗ | nil (DCS infers from type) | Pass-through string (e.g. `"Fortifications"`, `"Cargos"`, `"Heliports"`, `"Warehouses"`); not validated against an enum. |
| `dead` | bool | ✗ | DCS default | Spawn as wreckage |
| `mass` | number (kg) | ✗ | DCS default | Cargo weight |
| `canCargo` | bool | ✗ | DCS default | Sling-load flag |
| `shape_name` | string | ✗ | none | Auxiliary model hint; **does not substitute for `type`** (verified empirically) |
| `livery_id` | string | ✗ | DCS default | Cosmetic |

**Pass-through:** any unknown field on `cfg` is forwarded to DCS verbatim.

**Overrides table for `clone`:**

| Field | Type | Required | Default | Notes |
|---|---|---|---|---|
| `name` | string | ✓ | — | New unique name; auto-suffixed on collision |
| `position` | vec3 | ✓ | — | New anchor (DCS-2D translation applied) |

v1 only `name` + `position` are overridable. `type`/`heading`/`dead` swaps deferred.

### Out of scope (v1)

- **Per-field overrides on `clone` beyond `name` + `position`.** No `type` / `heading` / `dead` swap.
- **Live-API fallback for `clone`.** ME-defined templates only via `env.mission` walk. Runtime-spawned statics not cloneable.
- **Static-specific events** (`on_dead`, `on_cargo_lifted`, …). Defer to `sms.events` sub-project.
- **A separate `sms.cargo` namespace.** Cargo IS a static; `mass` + `canCargo` are blessed fields on `sms.static.create`.
- **Bulk creation** (`create_batch`, `create_many`). Compose with a loop.
- **Combined ME mission walker** for groups + statics. Each module has its own walker.
- **Validation of `category` against a known enum.** Pass-through string; DCS rejects garbage at the `addStaticObject` boundary which we surface as `nil + log`.
- **Strict-name mode** (no `strict_name = true` opt-out). Auto-suffix is universal, same as spawn.
- **Probing group/unit namespaces during static name resolution.** Empirically verified: statics live in their own namespace (groups, units, and statics named "X" coexist).
- **Output-side feet/degrees conversion.** Getters return DCS-native (meters/radians); users call `sms.utils.*` to convert.
- **`sms.spawn_static` namespace.** Factories live on `sms.static`, not on a separate spawn-style module.
- **Aircraft-static distinction.** Planes spawned as statics (e.g. for scenery) use the same API as buildings.

## Constraints

- Lua 5.1 (DCS mission environment). No `goto`, no `//`, no Lua 5.2+ idioms.
- Must work under bridge-driven loading. No `require`. New global: `sms.static` (with all its methods/factories), plus `sms.area.is_static_in`.
- Failure model: log + return safe value (`nil` for factories/handle ops, `false` for predicates). Never throws. No `error()` calls in the new code.
- `coalition.addStaticObject` may error on invalid input. Wrap calls in `pcall` (mirror of `_spawn` in `spawn.lua`).
- Other framework modules unchanged in behavior. `framework/area.lua` gains exactly one new method; everything else in area.lua untouched.
- New code must not depend on the live "tester" / scratch state in the user's mission. All testing is hermetic relative to spawned fixtures.
- Loading order: `sms.lua → log.lua → utils.lua → group.lua → unit.lua → area.lua → timer.lua → spawn.lua → static.lua`. Static loads last; `area.lua`'s reference to `sms.static` resolves lazily at call time (same pattern as `is_unit_in` → `sms.unit`).

## Architecture

### File layout

```
framework/
├── sms.lua              # unchanged
├── log.lua              # unchanged
├── utils.lua            # unchanged
├── group.lua            # unchanged
├── unit.lua             # unchanged
├── area.lua             # ADDS: is_static_in method (~15 lines)
├── timer.lua            # unchanged
├── spawn.lua            # unchanged
├── static.lua           # NEW: ~250 lines (entity + create + clone)
└── test/
    └── smoke_static.sh  # NEW: bridge-driven smoke test
```

### `framework/static.lua` internal structure

```lua
-- Module-private state and lookup tables
local _name_counters       -- base_name -> next-index hint for auto-suffix
local _country_reverse     -- int country id -> string (e.g. 2 -> "USA"); built lazily

-- DCS coalition int -> normalized lowercase string (mirror of group.lua)
local _coalition_str       -- {[0]="neutral", [1]="red", [2]="blue"}

-- Helpers
local _name_of(s)                          -- handle | string -> name | nil (mirror of group/unit)
local _is_vec3(v)
local _resolve_country(s)                  -- "USA" -> int via country.id; nil + log on miss
local _resolve_country_int_to_string(int)  -- 2 -> "USA"; uses cached reverse map
local _resolve_unique_name(base)           -- collision-safe; probes ONLY StaticObject.getByName
local _name_taken(name)                    -- StaticObject.getByName(name) ~= nil

-- Internal builder
local _build_def(cfg, resolved_name)       -- vec3 -> DCS-2D, deg -> rad, blessed + pass-through
local _spawn(def, country_int, name)       -- pcall coalition.addStaticObject + post-call verification

-- Validation
local _validate_create_config(cfg)

-- Clone-specific
local _find_template_in_mission(name)      -- walks env.mission.coalition[red/blue/neutrals]
                                            --       .country[*].static.group[]
                                            -- returns {def_unit, country_int, group_name} or nil
local _deep_copy(t)

-- Public API on sms.static (entity wrapper)
sms.static.is_alive       = function(s) ... end
sms.static.get_name       = function(s) ... end
sms.static.get_position   = function(s) ... end
sms.static.get_coalition  = function(s) ... end
sms.static.get_country    = function(s) ... end
sms.static.get_type       = function(s) ... end
sms.static.destroy        = function(s) ... end

-- Public API on sms.static (factories)
sms.static.create = function(cfg) ... end
sms.static.clone  = function(template_name, overrides) ... end

-- Sugar constructor
sms._make_callable_handle(sms.static, StaticObject.getByName, log)
```

### Auto-suffix mechanism

Same shape as `spawn.lua`'s `_resolve_unique_name`, but probing only `StaticObject.getByName`:

```lua
local _name_counters = {}

local function _name_taken(name)
  return StaticObject.getByName(name) ~= nil
end

local function _resolve_unique_name(base)
  if not _name_taken(base) then return base end
  local n = _name_counters[base] or 1
  while _name_taken(base .. "-" .. n) do
    n = n + 1
  end
  _name_counters[base] = n + 1
  return base .. "-" .. n
end
```

Counter is a hint; probe is the source of truth. Counter table is module-local and lost on reload — same trade-off as spawn.

**Empirical justification:** statics share name namespace with neither groups nor units. Spawning `static "X"` and `group "X"` in the same mission both succeed and both are findable via their respective getByName functions. Probing `Group.getByName` or `Unit.getByName` would generate spurious suffixes for genuinely-free names.

### DCS def builder

`coalition.addStaticObject(country_int, def)` accepts a flat def (no `units` array — statics are single-object).

```lua
local function _build_def(cfg, resolved_name)
  local heading_deg = cfg.heading or 0
  local heading_rad = sms.utils.deg_to_rad(heading_deg) or 0

  local def = {
    name    = resolved_name,
    type    = cfg.type,
    -- DCS-2D: x = vec3.x (east), y = vec3.z (north)
    x       = cfg.position.x,
    y       = cfg.position.z,
    heading = heading_rad,
  }

  -- Blessed optional fields
  if cfg.category   ~= nil then def.category   = cfg.category   end
  if cfg.dead       ~= nil then def.dead       = cfg.dead       end
  if cfg.mass       ~= nil then def.mass       = cfg.mass       end
  if cfg.canCargo   ~= nil then def.canCargo   = cfg.canCargo   end
  if cfg.shape_name ~= nil then def.shape_name = cfg.shape_name end
  if cfg.livery_id  ~= nil then def.livery_id  = cfg.livery_id  end

  -- Pass-through unknown fields verbatim (forward-compat).
  local known = {
    name = true, type = true, position = true, country = true, heading = true,
    category = true, dead = true, mass = true, canCargo = true,
    shape_name = true, livery_id = true,
  }
  for k, v in pairs(cfg) do
    if not known[k] and def[k] == nil then
      def[k] = v
    end
  end

  return def
end
```

`offset` is intentionally **not** a `create` field — statics are single objects with no per-unit-relative positioning concept.

### Coordinate translation

DCS's `coalition.addStaticObject` uses 2D coords: `def.x` = north-south, `def.y` = east-west (DCS-2D-y == vec3-z, both east-west). Framework vec3 convention is `{x = north-south, y = altitude, z = east-west}`. The builder maps `def.x = cfg.position.x` and `def.y = cfg.position.z`. `cfg.position.y` (altitude) is ignored — statics are terrain-snapped.

### Spawn execution

```lua
local function _spawn(def, country_int, resolved_name)
  local ok, err = pcall(coalition.addStaticObject, country_int, def)
  if not ok then
    log.error("DCS rejected the spawn: " .. tostring(err))
    return nil
  end
  if not StaticObject.getByName(resolved_name) then
    log.error("DCS accepted addStaticObject but static '" .. resolved_name ..
              "' not found post-call (check type/category validity)")
    return nil
  end
  return sms.static(resolved_name)
end
```

Mirror of `spawn.lua`'s `_spawn`. Returns the handle from the same callable lookup so it round-trips with `sms.static("name")`.

### Clone strategy

Walk `env.mission.coalition[red/blue/neutrals].country[*].static.group[]` for a "group" with matching `name`. In the ME mission descriptor, each static is wrapped in a single-unit "group" structure with `groupId` and `units[1]` containing the actual static def fields.

Walk implementation:

```lua
local function _find_template_in_mission(template_name)
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country_entry in ipairs(side.country) do
        if country_entry.static and country_entry.static.group then
          for _, sg in ipairs(country_entry.static.group) do
            if sg.name == template_name and sg.units and sg.units[1] then
              return {
                def_unit    = sg.units[1],   -- the actual static def
                country_int = country_entry.id,
                group_name  = sg.name,
              }
            end
          end
        end
      end
    end
  end
  return nil
end
```

Then re-anchor: deep-copy `found.def_unit`, strip `unitId` (and any `groupId` artifact if present at the unit level), set `def.name = resolved_name` from overrides, set `def.x/y` from `overrides.position` (DCS-2D translation), and call `_spawn`.

```lua
local def = _deep_copy(found.def_unit)
def.unitId = nil  -- let DCS assign fresh
def.x = overrides.position.x
def.y = overrides.position.z
def.name = resolved_name
return _spawn(def, found.country_int, resolved_name)
```

Original heading and all other fields (category, type, dead, mass, etc.) preserved verbatim from the template. Only name + position change.

### get_country implementation

```lua
local _country_reverse  -- built lazily

local function _build_country_reverse()
  if _country_reverse then return end
  _country_reverse = {}
  for k, v in pairs(country.id) do
    _country_reverse[v] = k  -- e.g. _country_reverse[2] = "USA"
  end
end

sms.static.get_country = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_country: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local int = StaticObject.getByName(name):getCountry()
  _build_country_reverse()
  local s_str = _country_reverse[int]
  if not s_str then
    log.error("get_country: '" .. tostring(name) .. "' returned unknown country " .. tostring(int))
    return nil
  end
  return s_str
end
```

The reverse map is cached on first call. `country.id` is stable across the mission lifetime.

### Edit to `framework/area.lua`

Add `is_static_in` next to `is_unit_in`. Pattern is identical except the handle-type check and position fetch use `sms.static` instead of `sms.unit`.

```lua
sms.area.is_static_in = function(a, s)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_static_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(s, sms.static) then
    log.error("is_static_in: target must be an sms.static handle")
    return false
  end
  local p = sms.static.get_position(s)
  if not p then return false end
  if a.kind == "circle" then
    return _point_in_circle(a._data, p.x, p.z)
  end
  return _point_in_polygon(a._data.vertices, p.x, p.z)
end
```

`sms.static` resolves at call time. Same lazy-resolution pattern as `is_unit_in` → `sms.unit`. Static.lua loads after area.lua, so by the first `is_static_in` call, `sms.static` is populated.

### Failure mode summary

| Situation | Behavior |
|---|---|
| `sms.static("nope")` — no such static in DCS | log `couldn't find static 'nope'`, return `nil` |
| `_name_of` given garbage (number, bool, table-without-name) | returns `nil`; downstream `is_alive` returns `false`; standard log+nil path triggers |
| Handle method on dead/destroyed static | log `<method>: '<name>' no longer exists in mission`, return `nil` |
| `create()` with non-table cfg | log + nil |
| `create()` missing `name`, `type`, `position`, or `country` | log specific error, return `nil` |
| `create()` `position` not a vec3 | log + nil |
| `create()` `country` not a string, or unknown | log + nil |
| `create()` `type` not a non-empty string | log + nil |
| `create()` `heading` present but not a number | log + nil |
| `coalition.addStaticObject` errors | log `create: DCS rejected the spawn: <err>`, return `nil` |
| `coalition.addStaticObject` succeeds but post-call verify fails | log `DCS accepted addStaticObject but static '<name>' not found post-call (check type/category validity)`, return `nil` |
| `clone()` template_name not a non-empty string | log + nil |
| `clone()` overrides not a table | log + nil |
| `clone()` overrides missing `name` or `position` | log + nil |
| `clone()` template not in `env.mission` | log `clone: template '<X>' not in mission`, return `nil` |
| `clone()` template found but has no units / unit[1] | log + nil |
| `is_static_in` called with non-area or non-static handle | log + return `false` |
| `get_country` on a static whose `getCountry()` returns an int not in `country.id` | log + return `nil` |

**No collision failures** — auto-suffix on name handles uniqueness universally. Returned handle's `:get_name()` is authoritative.

## Smoke test outline

`framework/test/smoke_static.sh` — bridge-driven, mirrors `smoke_spawn.sh` shape.

1. **Hook status check** + load framework files in order through `static.lua`.
2. **Entity wrapper basic** — spawn a static via `create`, confirm `sms.static("<resolved_name>")` returns a handle with `:is_alive() == true`, `:get_name()`, `:get_type()`, `:get_position()` (vec3 with x/y/z numbers), `:get_coalition()` returns `"red"`/`"blue"`/`"neutral"`, `:get_country()` returns the input country string.
3. **`sms.static.create` Hangar B happy path** — confirm post-spawn it's alive and at the requested vec3 (DCS-2D translation: `def.x == cfg.position.x`, `def.y == cfg.position.z`).
4. **Heading-degrees conversion** — spawn with `heading = 90`, read back via `StaticObject.getByName(name):getPosition()` matrix, derive heading ≈ π/2 rad (within tolerance).
5. **Cargo with `mass` + `canCargo`** — spawn an `iso_container` with `mass = 1000, canCargo = true, category = "Cargos"`. Verify alive.
6. **`dead = true`** — spawn a wreckage variant; `is_alive()` is true (the static object exists), but the visual state is dead per DCS.
7. **Auto-suffix** — three calls with `name = "crate"`. Verify resolved names via the returned handles' `:get_name()` are `"crate"`, `"crate-1"`, `"crate-2"`.
8. **Namespace separation** — spawn `sms.static.create({name = "ns_test", ...})` and `sms.group.create({name = "ns_test", ...})`. Both must succeed; static `:get_name() == "ns_test"` (no suffix); group's resolved name handling is its own. Proves we're not over-probing.
9. **`create` negative paths** (each independent):
    - Missing `name` → nil
    - Missing `type` → nil
    - Missing `position` → nil
    - Missing `country` → nil
    - Bad country (`"WAKANDA"`) → nil
    - Non-vec3 `position` → nil
    - Non-string `type` → nil
    - Non-table cfg → nil
    - Garbage cfg (number, bool) → nil
10. **`clone` happy path** — discover any ME-defined static via `env.mission` walk; if none found, log `[smoke] no ME static found, skipping clone tests` and skip steps 10–11. Otherwise: clone with new name + position offset 1km east. Verify clone exists, `:get_type()` matches template's type.
11. **`clone` auto-suffix** — clone same template twice with the same `name` arg, verify second resolved name has `-1` suffix.
12. **`clone` negative** — `clone("not_a_template", {name="x", position=...}) == nil`. `clone("template", "not_a_table") == nil`. `clone("template", {position=...})` (missing name) == nil.
13. **`sms.area:is_static_in`** — create an ad-hoc circular area via `sms.area.create_circular`, spawn a static at its center. Assert `:is_static_in(handle) == true`. Spawn a second static outside the radius. Assert `:is_static_in(handle2) == false`.
14. **`is_static_in` negative** — pass non-handle args (string, nil, sms.unit handle). Assert all return `false` and produce a log entry.
15. **Cleanup** — `:destroy()` every static spawned by this run (collected from `create` / `clone` returns). Confirm post-cleanup `:is_alive() == false` and subsequent method calls log + return nil.
16. **Tail-log assertion** — log file contains at least one `[sms.static]` line for a known-failing case (e.g. `unknown country 'WAKANDA'`).
17. `smoke ok` and exit 0.

**Total runtime:** <10 seconds. No host-side sleeps.

**Prerequisites:**
- DCS hook fresh.
- Mission has at least one ME-defined **static** for the clone test (steps 11–12). If absent, those steps log a skip message and continue. Same forgiving pattern as `smoke_area.sh` for missing zones. (User's `tempMission` currently has no ME statics — clone tests will skip until one is added.)

## Decisions (made autonomously, recorded for revisit)

- **Module: `sms.static`.** Entity wrapper + factories share a single namespace (mirror of how `sms.group.create`/`clone` live on `sms.group`). No `sms.spawn_static` namespace.
- **File: single `framework/static.lua`** (~250 lines). Split isn't earned — no units array, route, or task. Mirrors `area.lua` (which holds methods + constructors).
- **`type` is required, `category` is optional pass-through.** Empirically verified: `coalition.addStaticObject` accepts spawns without `category`. We pass it through verbatim when present, don't validate against an enum.
- **`shape_name` is auxiliary, not a `type` substitute.** Empirically verified: spawning with `shape_name` only (no `type`) fails. Pass-through optional.
- **Auto-suffix probes ONLY `StaticObject.getByName`.** Empirically verified: statics live in their own namespace; groups/units/statics named "X" coexist. Probing more would invent constraints DCS doesn't have.
- **Auto-suffix is universal**, no `strict_name` opt-out (mirror of spawn).
- **Counter `_name_counters` is module-local, lost on reload.** Counter is a hint; probe is the source of truth. Same trade-off as spawn.
- **Clone walks `env.mission.coalition[*].country[*].static.group[]` only.** ME templates only. Live-API fallback deferred (consistent with `sms.group.clone` v1).
- **Clone overrides limited to `name` + `position`.** Mirror of `sms.group.clone` v1. `type`/`heading`/`dead` swap deferred.
- **Methods on `sms.static`:** `is_alive`, `get_name`, `get_position`, `get_coalition`, `get_country`, `get_type`, `destroy`. Mirror of `sms.unit` minus skill, plus `get_country` (cargo/country flows care).
- **`get_country` reverse map is cached lazily** on first call. `country.id` is stable.
- **`is_static_in` lives in `framework/area.lua`** next to `is_unit_in`. Discoverability: area.lua is the canonical place for area predicates. Same lazy `sms.static` resolution as `is_unit_in`'s `sms.unit` reference.
- **Loading order:** `... → area.lua → ... → spawn.lua → static.lua`. Static loads last; `area.lua`'s reference to `sms.static` resolves at call time.
- **`offset` is intentionally not a `create` field.** Statics are single objects; no per-unit-relative positioning concept. `position` is the only spatial input.
- **`cfg.position.y` (altitude) is ignored** for statics — terrain-snapped by DCS.
- **`heading` in degrees, converted at the boundary.** Mirror of spawn's heading convention. Output-side conversions (radians→degrees on getters) deferred.
- **Failure model: log + return nil/false. Never throws.** Framework-wide invariant. No `error()` in new code. `pcall` wraps `coalition.addStaticObject`.
- **Returned handle from `create`/`clone` round-trips** with `sms.static("<resolved_name>")` lookup — same handle shape via `_make_callable_handle`.

## Open questions

None. All ambiguities resolved during brainstorming or recorded as decisions above.
