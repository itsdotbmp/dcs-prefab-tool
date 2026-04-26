# dcs-sms Framework — `sms.area` v1 (with `_make_callable_handle` refactor)

**Date:** 2026-04-26
**Status:** Approved (brainstorm phase)
**Scope:** Third entity-shaped abstraction in the dcs-sms framework, but with a different mental model than `sms.group`/`sms.unit`. Replaces what would have been "sms.zone" with a more general `sms.area` — a region on the map that can be a circle or a polygon, sourced from ME zones, ME drawings, or constructed at runtime. Includes a refactor that extracts the cargo-cult callable factory into a shared helper used by `sms.group`, `sms.unit`, and future entity wrappers.

## Goal

Build a unified "area on the map" abstraction that:

- Treats circles and polygons as first-class equals (no historical "zones must be circular" baggage).
- Unifies four construction paths (ME zone, ME drawing, runtime circle, runtime polygon) under one module.
- Establishes a shared `_make_callable_handle` factory so future cargo-cult entity wrappers (`sms.static`, etc.) get the construction pattern for free.

## User value

After this iteration the user can write mission code like:

```lua
-- Look up an ME zone (circle OR quad — both work)
local aoi = sms.area("AreaOfInterest")
if aoi:is_unit_in(my_jet) then ...

-- Look up an ME drawing (polygon)
local border = sms.area.from_drawing("CountryBorder")
if border:is_any_of_group_in(red_strike_package) then ...

-- Construct at runtime
local spawn_zone = sms.area.create_circular({x=1000, y=0, z=2000}, 500, "spawn-1")
local point = spawn_zone:get_random_point()

local triangle = sms.area.create_polygon({
  {x=0, y=0, z=0},
  {x=1000, y=0, z=0},
  {x=500, y=0, z=1000},
})
if triangle:is_vec3_in({x=400, y=0, z=200}) then ...
```

…with a single, consistent method surface across all four sources.

## Scope

### In scope (v1)

**Refactor (lands first within the branch):**

- Edit `framework/log.lua` to expose `tag` field on the logger returned by `sms.log.module(name)`. Single-line additive change; no breakage.
- Add `sms._make_callable_handle(module, dcs_getter, module_log)` to `framework/sms.lua`. Sets up `__call` metatable on `module` such that `module("name")` returns a `{name=name}` handle (or `nil + log`) based on `dcs_getter(name)` returning non-nil. Derives the entity-type string for the log message from `module_log.tag` (strips `sms.` prefix).
- Add `sms._is_handle_of(value, module)` to `framework/sms.lua`. Returns `true` iff `value` is a table whose metatable's `__index` is `module`. Used by `sms.area` for strict handle-type validation.
- Refactor `framework/group.lua`: replace its inline `setmetatable(sms.group, {__call = ...})` block with `sms._make_callable_handle(sms.group, Group.getByName, log)`.
- Refactor `framework/unit.lua`: same treatment, using `Unit.getByName`.
- All existing smoke tests (`smoke.sh`, `smoke_group.sh`, `smoke_unit.sh`, `smoke_timer.sh`) must continue to pass unchanged. They are the regression coverage that proves the refactor is behavior-preserving.

**New module: `framework/area.lua`** (~280 lines projected). Public API:

Constructors:

- `sms.area("ZoneName")` — callable. Looks up `trigger.misc.getZone(name)`. If DCS returns `{point, radius}` → circle area. If DCS returns `{point, verticies}` → polygon area. Otherwise log + nil.
- `sms.area.from_drawing("DrawingName")` — walks `env.mission.drawings.layers[*].objects[*]` for a freeform polygon drawing with that name. Logs + nil if absent or non-polygon.
- `sms.area.create_circular(vec3, radius, name?)` — runtime circle. `name` optional; when omitted, `:get_name()` returns `nil`.
- `sms.area.create_polygon(vertices, name?)` — runtime polygon. `vertices` is a list of vec3 tables (`y` ignored, projected to ground plane). Requires ≥3 vertices; log + nil otherwise. `name` optional.

Methods (all callable as `a:method()` AND as `sms.area.method(a, ...)`):

- `:get_name()` — string or `nil` for anonymous runtime areas.
- `:get_kind()` — `"circle"` or `"polygon"`.
- `:get_position()` — vec3 (center for circle, centroid for polygon).
- `:get_radius()` — number for circles. `nil + log` on polygon.
- `:get_vertices()` — list of vec3 for polygons (copies, not the internal store). `nil + log` on circle.
- `:is_vec3_in(vec3)` — bool. `false + log` on garbage input.
- `:is_unit_in(sms.unit handle)` — bool. Strict handle-type check; `false + log` on wrong type.
- `:is_any_of_group_in(sms.group handle)` — bool. Strict handle-type check.
- `:is_all_of_group_in(sms.group handle)` — bool. Strict handle-type check.
- `:get_random_point()` — vec3 inside the area. Circle: sqrt-corrected uniform. Polygon: rejection sampling within the bounding box, capped retries (~100), centroid fallback + log on degenerate input.

**New smoke test: `framework/test/smoke_area.sh`.** Conditional/hermetic — exercises all paths if the user's mission has prerequisites (an ME zone, optionally an ME drawing named `_sms_test_area_drawing`); skips drawing-specific assertions with a clear "to enable, add a drawing named X" message if the drawing is absent.

### Out of scope (v1)

- **Triangulation-based `get_random_point` for polygons** — tracked in [#4](https://github.com/nielsvaes/dcs-sms/issues/4). v1 ships rejection sampling.
- **Self-intersecting polygons.** Document as undefined behavior; we expect simple (non-self-intersecting) polygons. No detection or rejection at construction.
- **Polygons with holes.**
- **3D volumes** (cubes, spheres). Areas always project to the ground plane.
- **Boolean operations** (union/intersection/difference/buffering).
- **Drawing on the F10 map / smoke / flare / bound** — visual debugging.
- **Caching of `is_*_in` results.**
- **`is_static_in(sms.static handle)`** — `sms.static` doesn't exist yet.
- **Snapshot invalidation / `:refresh()` method.** Areas snapshot their data at construction; ME data doesn't change at runtime, runtime data is user-owned.
- **Auto-detection of drawing layers other than freeform polygon** (lines, text, icons). Only freeform polygon drawings are supported.

## Constraints

- Lua 5.1 (DCS mission environment). No `goto`, no `//`, no Lua 5.2+ idioms.
- Must work under bridge-driven loading. No `require`. Globals: `sms.area` (and sub-keys), plus the new `sms._make_callable_handle` and `sms._is_handle_of` keys.
- Failure model: log + return safe value (`nil` for getters/constructors, `false` for `is_*_in` predicates). Never throws.
- The refactor must NOT change the externally-observable behavior of `sms.group` or `sms.unit`. Existing smoke tests are the regression bar.

## Architecture

### `framework/log.lua` change

Single edit to the table returned by `sms.log.module(name)`: add a `tag = tag` field so the captured tag is publicly readable. No change to `info` / `error` behavior.

### `framework/sms.lua` additions

```lua
sms._make_callable_handle = function(module, dcs_getter, module_log)
  local type_name = module_log.tag:match("^sms%.(.+)$") or module_log.tag
  setmetatable(module, {
    __call = function(_, name)
      if not dcs_getter(name) then
        module_log.error("couldn't find " .. type_name .. " '" .. tostring(name) .. "'")
        return nil
      end
      return setmetatable({name = name}, {__index = module})
    end,
  })
end

sms._is_handle_of = function(value, module)
  if type(value) ~= "table" then return false end
  local mt = getmetatable(value)
  return (mt and mt.__index == module) or false
end
```

### `framework/group.lua` refactor

Replace the trailing `setmetatable(sms.group, {__call = ...})` block (currently ~9 lines) with:

```lua
sms._make_callable_handle(sms.group, Group.getByName, log)
```

### `framework/unit.lua` refactor

Same shape, using `Unit.getByName`.

### `framework/area.lua` shape

Three-section file:

1. **Local helpers** (private):
   - `_name_of(a)` — handle/string normalizer (mirrors group/unit, but only used by methods that accept handle-or-name; constructors are explicit).
   - `_data_of(a)` — extract `{kind=, ...}` from handle or by name lookup. For `sms.area` v1, name-based lookup means re-fetching from DCS — but since constructors snapshot data on the handle, this only fires when the user passes a raw string (which is fine for one-off lookups).

   Actually, simpler: methods always operate on handles (per the strict-typing decision). `_name_of` is unnecessary; `_data_of(handle)` just reads `handle._data`.

   Final shape:
   - `_xz_dist_sq(a, b)` — squared 2D distance helper (unused if we inline it in containment).
   - `_point_in_circle(data, x, z)` — `(x - cx)² + (z - cz)² ≤ r²`.
   - `_point_in_polygon(vertices, x, z)` — ray-casting: count xz-plane edge crossings to the right of the point.
   - `_bbox_of_polygon(vertices)` — `{min_x, max_x, min_z, max_z}`. Used for rejection sampling.
   - `_centroid_of_polygon(vertices)` — average of vertex coordinates. Used as `get_position()` for polygons and as fallback in `get_random_point`.
   - `_random_in_circle(data)` — sqrt-corrected uniform.
   - `_random_in_polygon(vertices)` — rejection sampling with retry cap (100); fallback to centroid + log on miss.
   - `_resolve_unit_xz(unit_handle)` — returns `{x, z}` from a live unit, or nil.
   - `_resolve_group_units_xz(group_handle)` — returns list of `{x, z}` from live group's units, or nil.

2. **Constructors:**
   - The `__call` metatable on `sms.area`: looks up via `trigger.misc.getZone(name)`, dispatches to circle or polygon based on returned shape.
   - `sms.area.from_drawing(name)` — searches `env.mission.drawings.layers[*].objects[*]` for `primitiveType == "Polygon"` (or DCS's variant) with matching name.
   - `sms.area.create_circular(vec3, radius, name?)` — validates inputs, creates handle.
   - `sms.area.create_polygon(vertices, name?)` — validates ≥3 vertices, copies vertex list, creates handle.

3. **Methods** (each operating on `handle._data`).

### Handle representation

```lua
-- Circle
{
  name = "Foo" or nil,
  kind = "circle",
  _data = {
    center = {x=0, y=0, z=0},
    radius = 500,
  },
}

-- Polygon
{
  name = "Bar" or nil,
  kind = "polygon",
  _data = {
    vertices = {{x=0,y=0,z=0}, {x=1,y=0,z=0}, ...},  -- copies, immutable from user POV
    centroid = {x=0.5, y=0, z=0},                     -- precomputed
    bbox = {min_x=0, max_x=1, min_z=0, max_z=1},     -- precomputed
  },
}
```

Metatable: `{__index = sms.area}`. So `handle:method()` dispatches to `sms.area.method(handle)`.

### Algorithms

**Point-in-polygon (ray-casting):**

```lua
local function _point_in_polygon(verts, x, z)
  local inside = false
  local n = #verts
  local j = n
  for i = 1, n do
    local vi, vj = verts[i], verts[j]
    if ((vi.z > z) ~= (vj.z > z)) and
       (x < (vj.x - vi.x) * (z - vi.z) / (vj.z - vi.z) + vi.x) then
      inside = not inside
    end
    j = i
  end
  return inside
end
```

Standard horizontal-ray-from-the-right algorithm. Handles concave polygons. Edge cases: points exactly on edges are nondeterministic (one or the other, depending on floating-point) — acceptable for v1; the user shouldn't rely on edge containment.

**Polygon `get_random_point` (rejection sampling):**

```lua
for attempt = 1, 100 do
  local x = bbox.min_x + math.random() * (bbox.max_x - bbox.min_x)
  local z = bbox.min_z + math.random() * (bbox.max_z - bbox.min_z)
  if _point_in_polygon(verts, x, z) then
    return {x = x, y = centroid.y, z = z}
  end
end
log.error("get_random_point: 100 attempts failed for polygon '" .. tostring(name) .. "', returning centroid")
return {x = centroid.x, y = centroid.y, z = centroid.z}
```

**`is_all_of_group_in`:** call `sms.group.get_units(g)`. If result is nil (dead group) or empty, return `false` (pragmatic — empty-set vacuous-truth would be confusing). For each unit, get position via `sms.unit.get_position(u)`; if any unit fails to resolve OR is outside the area, return `false`. Otherwise `true`.

**`is_any_of_group_in`:** iterate units; first one inside the area → `true`. None → `false`. Dead group / no units → `false`.

### Coalition coupling

Areas don't have coalitions. No `get_coalition` method.

### Loading order

`sms.lua` → `log.lua` → `group.lua` → `unit.lua` → `area.lua`. `area.lua` requires `sms.unit` and `sms.group` to be loaded by the time `is_unit_in` / `is_*_of_group_in` are *called* (not at load time). Documented in the file header.

## Failure model

| Situation | Behavior |
|---|---|
| `sms.area("typo")` | log `couldn't find area 'typo'` (using shared helper); return `nil` |
| `sms.area.from_drawing("typo")` | log `from_drawing: drawing 'typo' not found`; return `nil` |
| `sms.area.from_drawing("LineDrawing")` (non-polygon) | log `from_drawing: 'LineDrawing' is not a polygon drawing`; return `nil` |
| `sms.area.create_circular(garbage, ...)` | log + return `nil` for invalid vec3 / radius |
| `sms.area.create_polygon({})` or `<3 vertices` | log + return `nil` |
| `sms.area.create_polygon` with malformed vertex (not a vec3) | log + return `nil` |
| `:get_radius()` on polygon | log `get_radius: area '<name>' is a polygon, no radius`; return `nil` |
| `:get_vertices()` on circle | log `get_vertices: area '<name>' is a circle, no vertices`; return `nil` |
| `:is_vec3_in(garbage)` | log + return `false` |
| `:is_vec3_in({x=0, y=0})` (vec2) | log `is_vec3_in: target must be a vec3 with x/y/z numbers`; return `false` |
| `:is_unit_in(non-handle)` or wrong handle type | log + return `false` |
| `:is_unit_in(sms.unit handle on dead unit)` | `sms.unit.get_position` already logs+nil; we propagate `false` |
| `:is_*_of_group_in(non-handle)` or wrong handle type | log + return `false` |
| `:is_all_of_group_in(empty/dead group)` | `false` (pragmatic over vacuously true) |
| `:get_random_point()` on polygon, 100 rejection misses | log + return centroid (best-effort) |

Garbage input to any module function flows through type checks → log+safe path. Never throws.

## Smoke test outline

`framework/test/smoke_area.sh`. Hermetic where possible; relies on the user's mission for one ME zone (any existing) and optionally an ME drawing named `_sms_test_area_drawing`.

1. `dcs-sms.exe status` — confirm hook + mission.
2. Load framework files: `sms.lua`, `log.lua`, `group.lua`, `unit.lua`, `area.lua`. All `ok:true`.
3. **Discover an existing ME zone** — iterate `env.mission.triggers.zones[]` for any circle zone. Bail with clear instructions if none found.
4. **Spawn fixture group inside zone** (Soldier M4 at zone center) and a fixture group outside zone (zone center + radius*2 east). Two groups: `_sms_test_area_inside_group` / `_sms_test_area_outside_group`.

5. **Circle-from-ME assertions:**
   - `sms.area("<discovered name>"):get_kind()` → `"circle"`
   - `:get_position()` returns vec3
   - `:get_radius()` returns positive number
   - `:is_vec3_in(zone center)` → `true`
   - `:is_vec3_in(zone center + 2*radius east)` → `false`
   - `:is_vec3_in({x=0, y=0})` (vec2) → `false`
   - `:is_unit_in(inside_unit_handle)` → `true`
   - `:is_unit_in(outside_unit_handle)` → `false`
   - `:is_unit_in(inside_group_handle)` (wrong type) → `false`
   - `:is_any_of_group_in(inside_group)` → `true`
   - `:is_all_of_group_in(inside_group)` → `true` (single unit, in zone)
   - `:is_all_of_group_in(outside_group)` → `false`
   - `:get_vertices()` on circle → `nil`
   - `:get_random_point()` returns vec3, and `is_vec3_in(rp)` → `true` (run 5x)
   - `sms.area("_definitely_not_a_zone") == nil` → `true`

6. **Runtime circle assertions:**
   - `sms.area.create_circular({x=0, y=0, z=0}, 500, "rt-circle"):get_radius()` → `500`
   - `:is_vec3_in({x=100, y=0, z=100})` → `true` (well inside)
   - `:is_vec3_in({x=1000, y=0, z=1000})` → `false`
   - `sms.area.create_circular("not a vec3", 500) == nil` → `true`
   - `sms.area.create_circular({x=0,y=0,z=0}, -1) == nil` → `true`

7. **Runtime polygon assertions:**
   - Build a 1km square: `{(0,0), (1000,0), (1000,1000), (0,1000)}` (vec3 with y=0).
   - `:get_kind()` → `"polygon"`
   - `:get_vertices()` returns 4-element list
   - `:get_radius()` → `nil`
   - `:get_position()` returns centroid `{x=500, y=0, z=500}` (approximately)
   - `:is_vec3_in({x=500, y=0, z=500})` → `true` (center)
   - `:is_vec3_in({x=999, y=0, z=999})` → `true` (near corner, inside)
   - `:is_vec3_in({x=1500, y=0, z=500})` → `false` (outside)
   - `:get_random_point()` returns vec3 with `is_vec3_in()` → `true` (5 trials)
   - `sms.area.create_polygon({}) == nil` → `true` (too few vertices)
   - `sms.area.create_polygon({{x=0,y=0,z=0}, {x=1,y=0,z=0}}) == nil` → `true` (only 2 verts)

8. **`from_drawing` assertions** (conditional on `_sms_test_area_drawing` existing):
   - If drawing exists: `sms.area.from_drawing("_sms_test_area_drawing"):get_kind()` → `"polygon"`; `:get_vertices()` returns the drawing's vertex count.
   - If drawing absent: print `"==> from_drawing: skipping (add a polygon drawing named _sms_test_area_drawing to mission to enable)"` and continue.
   - `sms.area.from_drawing("_no_such_drawing") == nil` → always tested.

9. **Cleanup:** destroy both fixture groups.

10. **Tail-log assertion:** `[sms.area]` line containing `couldn't find area '_definitely_not_a_zone'` (using the shared helper's log format).

11. Print `smoke ok` and exit 0.

## Decisions (made autonomously, recorded for revisit)

- **Module name: `sms.area`, not `sms.zone`.** Unifies ME zones, ME drawings, runtime circles, runtime polygons. Free of historical "zone = circle" baggage.
- **Two shape kinds: `circle`, `polygon`.** ME quad zones (newer DCS feature) are normalized to polygons. No separate "quad" kind.
- **Snapshot data on construction.** Areas don't change at runtime (ME static, runtime user-controlled). No re-fetch in methods. Cleaner than group/unit's re-resolve pattern.
- **`_make_callable_handle` ships, used by group/unit. Area's callable is custom** — 4 construction paths and snapshot logic don't fit through the helper.
- **`_is_handle_of` ships in `sms.lua`.** Used by area for strict handle typing; also available to future modules.
- **Strict handle typing on `is_unit_in` / `is_*_of_group_in`.** No string-name acceptance. Error logged on wrong handle type. Forces user to wrap in `sms.unit("...")` or `sms.group("...")`.
- **Polygon `get_random_point` v1 uses rejection sampling.** Triangulation tracked in [#4](https://github.com/nielsvaes/dcs-sms/issues/4). Centroid fallback on 100-attempt timeout.
- **`is_all_of_group_in(empty/dead group)` returns `false`.** Pragmatic over vacuously true.
- **Vertices passed to `create_polygon` are vec3 with `y` ignored.** Projected to ground plane for all geometry. `y` is preserved on the stored vertex list (so `get_vertices()` returns what the user passed).
- **Anonymous runtime areas (no `name` arg) → `:get_name()` returns `nil`.** Not a generated string.
- **`is_vec3_in` requires all three of `x`, `y`, `z` to be numbers.** vec2 input (`{x, y}` with `y` meaning ground-north) is rejected — too easy to confuse with altitude-bearing vec3.
- **No `get_coalition` on areas.** Areas don't have coalitions.
- **`from_drawing` searches all layers** in `env.mission.drawings.layers[*]`. The first matching freeform-polygon drawing wins. If schema differs from this assumption (DCS version variation), the implementation must adapt at smoke-test time — but the API doesn't change.
- **Log message format from the shared helper:** `[sms.area] couldn't find area '<name>'`. Type-name `"area"` is derived from `module_log.tag` ("sms.area") by stripping the `sms.` prefix.
- **Refactor lands BEFORE `sms.area`** within the branch. Existing smoke tests prove the refactor is behavior-preserving before any new code is added.
- **The smoke test for `from_drawing` is conditional**, not hard-required. Shipping `from_drawing` with optional smoke coverage is acceptable because the implementation is mostly mission-descriptor walking — easy to manually verify if the schema is right.
- **Helper placement: `framework/sms.lua`.** Both `_make_callable_handle` and `_is_handle_of` go in the root file. The `_` prefix marks them as framework-internal-ish.

## Related issues

- **#4** — earclipping triangulation for polygon `get_random_point` (future replacement of v1's rejection sampling).
- **#2** — hook auto-injection (mechanism C). When this lands, `sms.log.module()` no-arg form will work and area.lua/group.lua/unit.lua can drop the explicit `"sms.X"` tag.
- **#3** — bridge auto-return-prepend ergonomics. Independent.

## Open questions

None. All ambiguities resolved during brainstorming or recorded as decisions above.
