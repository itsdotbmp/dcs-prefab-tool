# `sms.area` — zones, drawings, and runtime areas

Unified abstraction over "an area on the map." A handle wraps either a **circle** or a **polygon**, and can be sourced four different ways:

1. From an ME-placed trigger zone (circle or quad) — `sms.area("ZoneName")`.
2. From an ME-placed freeform polygon drawing — `sms.area.from_drawing("DrawingName")`.
3. Constructed at runtime as a circle — `sms.area.create_circular(center, radius, name?)`.
4. Constructed at runtime as a polygon — `sms.area.create_polygon({vec3, ...}, name?)`.

**All four sources produce handles with the same method surface.** Once you have a handle you don't need to care where it came from — `:is_vec3_in`, `:is_unit_in`, `:get_random_point`, etc. all work the same way. Two methods are kind-specific: `:get_radius` is circles-only, `:get_vertices` is polygons-only; calling either on the wrong kind logs and returns nil.

A handle carries `kind` (`"circle"` or `"polygon"`) and a name (`string | nil` — anonymous runtime areas are allowed). See [`AGENTS.md` §5](../../AGENTS.md#5-entity-handles--the-universal-pattern) for the universal handle pattern.

All functions on this page follow the [framework failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw): bad input is logged and the function returns `nil` (or `false` for predicates). Nothing throws.

Vec3 convention throughout: `{x = north, y = altitude, z = east}`.

## Loading

`sms.area` requires `sms.lua`, `log.lua`, `utils.lua`, `group.lua`, and `unit.lua` before it loads. The cross-module strict handle checks in `:is_unit_in`, `:is_static_in`, `:is_any_of_group_in`, and `:is_all_of_group_in` resolve at call time, so as long as the full framework is loaded (e.g. via `load_all.lua`) before you call them, you're fine.

## `sms.area(name) → area | nil`

**Synopsis** — Look up an ME-placed trigger zone by name. Circle zones produce a circle handle; quad zones produce a polygon handle (DCS calls them quad zones but the framework treats them uniformly as 4-vertex polygons).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | The trigger zone name as it appears in the Mission Editor. |

**Returns** — area handle, or `nil` + log if the zone isn't found or has neither a `radius` nor a `verticies` field. (Yes, DCS spells it `verticies`. The framework reads that key as-is; you don't need to.)

**Example**

```lua
local range = sms.area("BombingRange")
if range then
  sms.log.info("range kind: " .. range:get_kind())  -- "circle" or "polygon"
end
```

## `sms.area.from_drawing(name) → area | nil`

**Synopsis** — Look up an ME-placed freeform **polygon** drawing by name. Returns a polygon area handle whose vertices are the drawing's points anchored at its `mapX/mapY` origin.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | The drawing object name as set in the Mission Editor. |

**Returns** — polygon area handle, or `nil` + log if drawings aren't available, the named drawing isn't found, the drawing isn't a polygon (`primitiveType ~= "Polygon"`), or it has fewer than 3 points.

**Example**

```lua
local kill_box = sms.area.from_drawing("KillBox-North")
if kill_box then
  local verts = kill_box:get_vertices()
  sms.log.info("kill box has " .. #verts .. " vertices")
end
```

**Notes** — Drawing points are 2D `{x, y}` in DCS's drawings format, where DCS-y is north-south. The framework converts them to vec3 with `z = DCS-y` so the resulting handle is consistent with everything else in the framework.

## `sms.area.create_circular(center, radius, name?) → area | nil`

**Synopsis** — Build a circular area handle at runtime, with no ME involvement. Useful for ad-hoc proximity checks, dynamic spawn rings, etc.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `center` | `vec3` | Center point. `y` is preserved on the handle but ignored by containment tests (which work on the xz-plane). |
| `radius` | `number` (m) | Strictly positive. Zero or negative is rejected. |
| `name` | `string` | (optional) Name for logging / lookup. Anonymous areas (`nil` name) are allowed. |

**Returns** — circle area handle, or `nil` + log if `center` isn't a vec3, `radius` isn't a positive number, or `name` is given but isn't a string.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
local pos = bandit:get_position()
local threat_ring = sms.area.create_circular(pos, 9000, "bandit-threat-ring")

if threat_ring:is_unit_in(sms.unit("Player-1")) then
  sms.log.warn("player inside bandit's threat ring")
end
```

## `sms.area.create_polygon(vertices, name?) → area | nil`

**Synopsis** — Build a polygon area handle at runtime from a list of vec3 vertices. Polygon may be concave; vertices are stored in the order given.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `vertices` | `list of vec3` | At least 3 vec3 entries. The list is deep-copied so external mutation can't corrupt the handle. |
| `name` | `string` | (optional) Name for logging. Anonymous areas (`nil` name) are allowed. |

**Returns** — polygon area handle, or `nil` + log if `vertices` isn't a list, has fewer than 3 entries, contains a non-vec3 entry, or `name` is given but isn't a string.

**Example**

```lua
-- 1 km square centered at origin.
local box = sms.area.create_polygon({
  {x =    0, y = 0, z =    0},
  {x = 1000, y = 0, z =    0},
  {x = 1000, y = 0, z = 1000},
  {x =    0, y = 0, z = 1000},
}, "spawn-box")

local drop = box:get_random_point()
sms.log.info(string.format("dropping at x=%.1f z=%.1f", drop.x, drop.z))
```

## Methods

The methods below are callable both as `area:method(...)` and as `sms.area.method(area, ...)`.

### `area:get_name() → string | nil`

**Synopsis** — Return the name the handle was constructed with. `nil` for anonymous runtime areas.

**Returns** — `string` or `nil`. Returns `nil` + log if the argument isn't an `sms.area` handle.

**Example**

```lua
local area = sms.area.create_circular({x=0,y=0,z=0}, 500, "rt")
sms.log.info(area:get_name())  -- "rt"

local anon = sms.area.create_circular({x=0,y=0,z=0}, 500)
sms.log.info(tostring(anon:get_name()))  -- "nil"
```

### `area:get_kind() → "circle" | "polygon"`

**Synopsis** — Return which underlying shape the handle wraps. Useful for branching when you didn't construct the handle yourself (e.g. it came back from `sms.area("SomeZone")` and could be either).

**Returns** — `"circle"` or `"polygon"`. Returns `nil` + log if the argument isn't an `sms.area` handle.

**Example**

```lua
local range_box = sms.area("RangeBox")
if range_box:get_kind() == "circle" then
  sms.log.info("radius: " .. range_box:get_radius())
else
  sms.log.info("vertices: " .. #range_box:get_vertices())
end
```

### `area:get_position() → vec3`

**Synopsis** — Return the area's "center." For circles, the center point. For polygons, the centroid (arithmetic mean of vertices).

**Returns** — fresh `vec3` (safe to mutate; doesn't alias internal state). Returns `nil` + log if the argument isn't an `sms.area` handle.

**Example**

```lua
local zone = sms.area("BombingRange")
local pos  = zone:get_position()
sms.log.info(string.format("zone center: x=%.1f z=%.1f", pos.x, pos.z))
```

### `area:get_radius() → number | nil`

**Synopsis** — Circles only. Return the radius in meters.

**Returns** — `number` for circles. Polygons log + return `nil` (this is expected, not an error condition; check `:get_kind()` first if you don't know what you have).

**Example**

```lua
local bombing_range = sms.area("BombingRange")
if bombing_range:get_kind() == "circle" then
  sms.log.info("radius (m): " .. bombing_range:get_radius())
end
```

### `area:get_vertices() → list of vec3 | nil`

**Synopsis** — Polygons only. Return a **deep copy** of the polygon's vertices, in construction order. Mutating the returned list does not affect the handle.

**Returns** — list of `vec3` for polygons. Circles log + return `nil`.

**Example**

```lua
local kill_box = sms.area.from_drawing("KillBox-North")
for i, v in ipairs(kill_box:get_vertices()) do
  sms.log.info(string.format("vertex %d: x=%.1f z=%.1f", i, v.x, v.z))
end
```

### `area:is_vec3_in(vec3) → bool`

**Synopsis** — Test whether a vec3 lies inside the area. Containment is computed on the xz-plane only; `y` (altitude) is ignored.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `vec3` | `vec3` | Point to test. Must have numeric `x`, `y`, `z` (a 2D `{x, y}` table is rejected). |

**Returns** — `bool`. Returns `false` + log if the area handle is invalid or the input isn't a vec3.

**Example**

```lua
local bombing_range = sms.area("BombingRange")
local impact = {x = 1234, y = 0, z = 5678}
if bombing_range:is_vec3_in(impact) then
  sms.log.info("impact inside range")
end
```

**Notes** — Polygon containment uses ray-casting on the xz-plane and handles concave polygons. Edge-on-vertex cases are nondeterministic in v1 — don't rely on the exact result for points sitting on a vertex.

### `area:is_unit_in(unit) → bool`

**Synopsis** — Test whether an [`sms.unit`](unit.md) handle's current position lies inside the area.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `unit` | [`sms.unit`](unit.md) handle | Strict handle check — passing a name string or a handle of a different kind is rejected. |

**Returns** — `bool`. Returns `false` + log if the area handle is invalid, `unit` isn't an `sms.unit` handle, or the unit's position can't be resolved (e.g. it's dead).

**Example**

```lua
local zone   = sms.area("BombingRange")
local bandit = sms.unit("Bandit-1")
if zone:is_unit_in(bandit) then
  sms.log.info("bandit is in the range")
end
```

### `area:is_static_in(static) → bool`

**Synopsis** — Test whether an [`sms.static`](static.md) handle's position lies inside the area.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `static` | [`sms.static`](static.md) handle | Strict handle check. |

**Returns** — `bool`. Returns `false` + log if the area handle is invalid, `static` isn't an `sms.static` handle, or the static's position can't be resolved.

**Example**

```lua
local depot = sms.area.create_circular({x=12000, y=0, z=4000}, 1500, "depot")
local crate = sms.static("supply-crate-1")
if depot:is_static_in(crate) then
  sms.log.info("crate is at the depot")
end
```

### `area:is_any_of_group_in(group) → bool`

**Synopsis** — `true` if **at least one** unit of the given [`sms.group`](group.md) is inside the area. Short-circuits on first hit. Dead units are skipped silently.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `group` | [`sms.group`](group.md) handle | Strict handle check. |

**Returns** — `bool`. Returns `false` + log if the area handle is invalid or `group` isn't an `sms.group` handle. Returns `false` (no log) if the group has no units or none can be resolved.

**Example**

```lua
local trigger_zone = sms.area("AmbushTrigger")
local convoy       = sms.group("RedConvoy")
if trigger_zone:is_any_of_group_in(convoy) then
  sms.log.info("convoy entered ambush trigger; springing trap")
  -- ... fire the ambush ...
end
```

### `area:is_all_of_group_in(group) → bool`

**Synopsis** — `true` if **every** unit of the given [`sms.group`](group.md) is inside the area. Short-circuits on first miss.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `group` | [`sms.group`](group.md) handle | Strict handle check. |

**Returns** — `bool`. Returns `false` + log if the area handle is invalid or `group` isn't an `sms.group` handle. Returns `false` (no log) if the group is empty, any unit is missing, or any unit's position is outside the area.

**Example**

```lua
local landed_zone = sms.area("LandingPad")
local heli_flight = sms.group("Huey-Flight")
if landed_zone:is_all_of_group_in(heli_flight) then
  sms.log.info("entire flight has landed; cuing next phase")
end
```

### `area:get_random_point() → vec3`

**Synopsis** — Return a uniform-random vec3 inside the area. For circles, uses the standard `r = sqrt(random()) * radius` distribution so points are uniform in area (not clustered near the center). For polygons, uses **rejection sampling** within the bounding box, capped at 100 attempts.

**Returns** — `vec3` inside the area. Returns `nil` + log if the argument isn't an `sms.area` handle.

For circles, the returned `y` matches the center's `y`. For polygons, it matches the centroid's `y`.

**Example**

```lua
-- Spawn 5 ground units at random positions inside a polygon area.
local box = sms.area("SpawnBox")
for i = 1, 5 do
  local point = box:get_random_point()
  sms.log.info(string.format("unit %d: x=%.1f z=%.1f", i, point.x, point.z))
end
```

**Notes** — On degenerate polygons (e.g. very thin slivers where 100 random bounding-box samples all miss the interior), `get_random_point` logs an error and falls back to the centroid. A triangulation-based replacement that removes this corner case is tracked in framework issue #4.
