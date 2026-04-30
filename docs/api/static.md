# `sms.static` — static-object wrapper plus `create` / `clone` factories

Lightweight handles for DCS static objects (hangars, FARP fuel depots, sling-loadable cargo, wreckage). Sibling of [`sms.unit`](unit.md): a callable lookup constructor for existing statics, plus two factories on the same module — no separate `sms.spawn_static`. Methods accept either a handle (`{name="..."}` table) or a raw name string interchangeably.

All public calls follow the [framework failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw): bad input or missing entity is logged through `[sms.static]` and returns `nil` / `false`. Nothing in this module ever throws.

> **Heads up — `is_alive` semantics differ from [`sms.unit`](unit.md).** Statics spawned with `dead = true` are still addressable via `StaticObject.getByName` even though `:isExist()` returns `false` (they're in the world as wreckage). This module gates on `getByName`-presence so dead-spawned wreckage statics remain usable through the framework — see [`is_alive`](#smsstaticis_alives--bool) below for the rationale.

See also: [`AGENTS.md` §3 failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw), [`AGENTS.md` §4 conventions](../../AGENTS.md#4-conventions-and-units), [`AGENTS.md` §5 entity handles](../../AGENTS.md#5-entity-handles--the-universal-pattern).

## Loading

`sms.static` lives at the tail end of the framework dependency chain (after `sms`, `sms.log`, `sms.utils`, `sms.group`, `sms.unit`, `sms.area`, `sms.timer`, `sms.group_spawn`). The standard `framework/load_all.lua` covers it; nothing extra needed.

## `sms.static("name")` — constructor

**Synopsis** — looks up a static currently in the world by name and returns a handle.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | DCS static name. |

**Returns** — `handle` (a `{name = "<name>"}` table whose `__index` is `sms.static`), or `nil` + log if no static with that name is currently addressable via `StaticObject.getByName`.

**Example**

```lua
local hangar = sms.static("RangeHangar-1")
if hangar then
  sms.log.info("found " .. hangar:get_type() .. " for " .. hangar:get_coalition())
end
```

**Notes** — the auto-suffix probe used by [`create`](#smsstaticcreatecfg--handle) and [`clone`](#smsstaticclonetemplate_name-overrides--handle) only checks `StaticObject.getByName`. Statics live in their own DCS name namespace (separate from groups and units), so a static and a group with the same name can coexist.

## Methods

### `sms.static:is_alive(s) → bool`

**Synopsis** — true if the static is still addressable in the world.

**Returns** — `bool`. Silent: returns `false` for `nil`, garbage, or a name DCS no longer knows. **Does not** use `:isExist()` — addressability is gated on `StaticObject.getByName(name) ~= nil`.

**Why not `:isExist()`?** Statics spawned with `dead = true` are findable via `getByName` (they are in the scene as wreckage), but `isExist()` returns `false` for them. If `is_alive` gated on `isExist()`, every method on a dead-spawned handle (`get_position`, `destroy`, …) would log + nil out even though the static is in the world. Gating on `getByName` keeps wreckage statics usable. DCS clears `getByName` lookups across frames after a real `destroy()`, so `is_alive` still correctly returns `false` for actually-destroyed statics in subsequent frames.

**Example**

```lua
local depot = sms.static("FuelDepot-A")
if depot and depot:is_alive() then
  sms.log.info("depot still standing")
end
```

### `sms.static:get_name(s) → string | nil`

**Synopsis** — returns the handle's stored name without touching DCS.

**Returns** — `string` for a handle / name-string input; `nil` for any other input (no log on this path — it mirrors `_name_of`'s normalization). Always trust this over the name you passed to `create` / `clone`, since auto-suffix may have renamed the spawn.

**Example**

```lua
local fuel_tank = sms.static.create({
  name     = "fuel-tank",
  type     = "FARP Fuel Depot",
  position = anchor,
  country  = "USA",
})
sms.log.info("spawned as " .. fuel_tank:get_name())   -- may be "fuel-tank-1" on collision
```

### `sms.static:get_coalition(s) → "red" | "blue" | "neutral" | nil`

**Synopsis** — coalition of the static, as a lowercase string.

**Returns** — `"red"`, `"blue"`, or `"neutral"`. `nil` + log if the static isn't alive or DCS returned an unknown coalition int (the latter logs at `error` level — it's a DCS-shape surprise, not caller misuse).

**Example**

```lua
local hangar = sms.static("RangeHangar-1")
if hangar:get_coalition() == "red" then
  -- enemy infrastructure
end
```

### `sms.static:get_country(s) → string | nil`

**Synopsis** — country of the static, as a lowercase string (e.g. `"usa"`, `"russia"`, `"united_kingdom"`).

**Returns** — lowercase country name (`country.id` reverse lookup). `nil` + log if the static isn't alive or DCS returned an unknown country int.

**Example**

```lua
local cargo = sms.static("Cargo-7")
sms.log.info("owned by " .. (cargo:get_country() or "?"))
```

### `sms.static:get_position(s) → vec3 | nil`

**Synopsis** — world position of the static.

**Returns** — `vec3 = {x = north, y = altitude, z = east}` (DCS-native 3D). `nil` + log if not alive.

**Example**

```lua
local depot = sms.static("FuelDepot-A")
local pos = depot:get_position()
if pos then
  sms.log.info(string.format("at %.0f, %.0f", pos.x, pos.z))
end
```

### `sms.static:get_type(s) → string | nil`

**Synopsis** — DCS type-name string (e.g. `"Hangar B"`, `"FARP Fuel Depot"`, `"iso_container"`).

**Returns** — DCS type name. `nil` + log if not alive.

**Example**

```lua
local hangar = sms.static("RangeHangar-1")
if hangar:get_type() == "Hangar B" then
  -- destroy with a 500-pounder
end
```

### `sms.static:destroy(s) → true | nil`

**Synopsis** — removes the static from the world.

**Returns** — `true` on success. `nil` + log if not alive (already destroyed, never existed, or garbage input).

**Example**

```lua
local wreckage = sms.static("OldWreckage")
if wreckage then wreckage:destroy() end
```

**Notes** — DCS does not reflect `destroy()` within the same frame: `StaticObject.getByName` may still return the object until the next frame. The `is_alive` gate fires correctly across frames; if you need synchronous "is it gone" checks within the same `exec` call, that's a DCS quirk, not a framework one.

## Factories

### `sms.static.create(cfg) → handle | nil`

**Synopsis** — spawn a fresh static at runtime. Wraps `coalition.addStaticObject` with input validation, country lookup, name auto-suffix on collision, and the framework's failure model.

**Arguments** — `cfg` is a single table. Required keys are checked first; bad types in optional keys are rejected at the framework boundary (`log.warn` + `nil`, no DCS call).

| Key | Type | Default | Description |
|---|---|---|---|
| `name` | `string` (non-empty) | required | Logical name. Auto-suffixed (`name-1`, `name-2`, …) if already taken in the static namespace. |
| `type` | `string` (non-empty) | required | DCS static type name (e.g. `"Hangar B"`, `"FARP Fuel Depot"`, `"iso_container"`). |
| `position` | `vec3` (`{x, y, z}`, all numbers) | required | World anchor. The framework translates to DCS-2D internally (`def.x = position.x`, `def.y = position.z`). |
| `country` | `string` | required | Any value from `country.id` (case-insensitive; spaces become underscores: `"United Kingdom"` → `country.id.UNITED_KINGDOM`). Resolved via [`sms.utils.resolve_country`](utils.md). |
| `heading` | `number` (degrees) | `0` | Facing in framework-public **degrees**, 0 = north, 90 = east, clockwise. Converted to radians internally before the DCS call. |
| `category` | `string` | (DCS-derived) | Pass-through DCS category string (e.g. `"Cargos"` for sling-loadable crates). |
| `dead` | `boolean` | `false` | `true` spawns the static as wreckage. See [`is_alive`](#smsstaticis_alives--bool) for the addressability quirk. |
| `mass` | `number` (kg) | `nil` | Sling mass. Only meaningful with `canCargo = true`. |
| `canCargo` | `boolean` | `nil` | Marks the static as slingable cargo. |
| `shape_name` | `string` | `nil` | DCS shape override (advanced; normally inferred from `type`). |
| `livery_id` | `string` | `nil` | DCS livery override. |

Unknown keys are passed through to the DCS def verbatim (forward-compatibility for fields the framework hasn't catalogued).

**Returns** — `sms.static` handle, or `nil` + log on:

- bad input (missing required key, wrong type for optional key)
- unknown country
- DCS rejecting the spawn (`addStaticObject` raised — caught via `pcall` and logged at `error` level)
- DCS accepting the call but the static not appearing in `getByName` post-call (e.g. invalid `type` / `category` combination)

**Example — hangar**

```lua
local hangar = sms.static.create({
  name     = "rangetower",
  type     = "Hangar B",
  position = {x = 28000, y = 0, z = -190000},
  country  = "USA",
  heading  = 45,                          -- degrees
})
sms.log.info("spawned " .. hangar:get_name() .. " of type " .. hangar:get_type())
```

**Example — sling-loadable cargo**

```lua
local crate = sms.static.create({
  name     = "ammo-crate",
  type     = "iso_container",
  position = lz_pos,
  country  = "USA",
  category = "Cargos",
  mass     = 1000,                        -- kg
  canCargo = true,
})
```

**Example — wreckage (`dead = true`)**

```lua
-- Pre-place wreckage as set-dressing for a downed-aircraft scenario.
local wreck = sms.static.create({
  name     = "su27-wreck",
  type     = "Su-27",                     -- aircraft type used as static
  position = crash_site,
  country  = "RUSSIA",
  dead     = true,
})
-- wreck:is_alive() returns true (addressable via getByName), even though
-- internally StaticObject.getByName(name):isExist() is false. This is
-- intentional — it lets you destroy / inspect wreckage normally.
```

**Notes** — auto-suffix probes only `StaticObject.getByName`, so a static named `"foo"` and a group named `"foo"` can coexist without collision. Always read the returned handle's `:get_name()` for follow-up operations.

### `sms.static.clone(template_name, overrides) → handle | nil`

**Synopsis** — clone an ME-placed static at a new position with a new name. Walks `env.mission.coalition[red/blue/neutrals].country[*].static.group[*]` to find the template, deep-copies its def, strips the ME-assigned `unitId` / `groupId`, re-anchors to the new position, renames, and spawns.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `template_name` | `string` (non-empty) | Name of an ME-placed static (the wrapping "group" name in the mission descriptor — in DCS each static is a single-unit static-group). |
| `overrides` | `table` | Required keys: `name` (non-empty string) and `position` (vec3). The framework does not currently apply any other override keys at this layer. |

**Returns** — `sms.static` handle, or `nil` + log on:

- non-string / empty `template_name`
- non-table `overrides`, or missing / empty `overrides.name`, or non-vec3 `overrides.position`
- template not found in `env.mission`
- DCS rejecting the spawn (same paths as `create`)

**Example**

```lua
-- ME mission has a static named "FUEL_TEMPLATE" placed wherever you want
-- the canonical config (type / heading / livery / country baked in).
local fuel = sms.static.clone("FUEL_TEMPLATE", {
  name     = "forward-fuel-1",
  position = {x = 30000, y = 0, z = -185000},
})
if fuel then
  sms.log.info("cloned " .. fuel:get_name() .. " (" .. fuel:get_type() .. ")")
end
```

**Notes**

- Country, type, heading, livery, and other ME-set fields come from the template — `clone` does not currently expose per-field overrides beyond `name` and `position`. If you need to vary the type or country at runtime, use [`create`](#smsstaticcreatecfg--handle) instead.
- Auto-suffix applies to `overrides.name` exactly like `create`.

## See also

- [`sms.unit`](unit.md) — sibling wrapper for units (note the `is_alive` semantic difference described above).
- [`sms.group`](group.md) — group entity wrapper and group-level spawn factories.
- [`sms.area`](area.md) — `area:is_static_in(static_handle)` for containment tests.
- [`sms.utils`](utils.md) — `resolve_country`, `is_vec3`, `coalition_int_to_str`, `deg_to_rad` (used internally by this module).
