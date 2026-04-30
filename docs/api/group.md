# `sms.group` — group entity wrapper, spawn factories, event sugar

A *group* is the DCS-native unit of organization for AI: every unit belongs to a group, and most AI behavior (route, task, ROE) is set at the group level. `sms.group` wraps DCS's `Group.*` calls in the framework's [callable-handle pattern](../../AGENTS.md#5-entity-handles--the-universal-pattern) and adds runtime spawn factories (`create` / `clone`), event sugar (`g:connect`), and the apply API for [`sms.task`](task.md) / [`sms.commands`](commands.md) / [`sms.options`](options.md) builders.

A handle is a tiny `{name = ...}` table — cheap to build and discard. Handles do **not** cache: every method re-resolves the group through DCS, so a handle stays correct after the underlying group dies (`:is_alive()` flips to false). All methods accept either a handle or a raw name string.

All methods follow the framework's [failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw) — log + return `nil` (or `false`) on bad input or missing groups; never throw.

## Loading

`sms.group` is defined across `framework/group.lua` and `framework/group_spawn.lua`. Both load via `framework/load_all.lua`. `g:connect` references `sms.events` and `set_task` / `push_task` reference `sms.timer`, both resolved at call time — finish loading the whole framework (e.g. via `load_all.lua`) before invoking those methods.

## `sms.group(name)` — constructor

**Synopsis** — look up an existing group by name; return a handle or `nil`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | DCS group name. Names are case-sensitive. |

**Returns** — `sms.group` handle, or `nil` + log if no group with that name exists.

**Example**

```lua
local armor = sms.group("red-armor-1")
if armor then
  sms.log.info(armor:get_name() .. " is at " .. armor:get_position().x)
end
```

---

## Instance methods

### `g:is_alive() → bool`

**Synopsis** — `true` if the group still exists in DCS and has at least one live unit.

**Returns** — `bool`. Silent: returns `false` for missing groups, garbage input, or destroyed handles without logging. (This is the one method that doesn't log on miss — every other method calls `is_alive` internally and logs from there.)

**Example**

```lua
local convoy = sms.group("convoy-1")
sms.timer.every(1.0, function()
  if not convoy:is_alive() then return false end   -- self-cancel when group dies
  sms.log.info("convoy still rolling")
end)
```

### `g:get_name() → string`

**Synopsis** — return the handle's `name` field. No DCS call, no validation.

**Returns** — `string`, or `nil` for non-handle / non-string input.

**Example**

```lua
local group = sms.group.create({...})           -- auto-suffix may rename
sms.log.info("spawned as " .. group:get_name()) -- always trust this over the input
```

### `g:get_coalition() → "red" | "blue" | "neutral"`

**Synopsis** — coalition of the group as a lowercase string.

**Returns** — `"red"`, `"blue"`, or `"neutral"`. `nil` + log if the group is missing or DCS returns an unknown coalition int.

**Example**

```lua
if sms.group("strike-1"):get_coalition() == "red" then
  sms.log.info("red strike package live")
end
```

### `g:get_category() → "ground" | "airplane" | "helicopter" | "ship" | "train"`

**Synopsis** — category of the group as a lowercase string.

**Returns** — one of the five category strings, or `nil` + log on missing group / unknown DCS category.

**Example**

```lua
local patrol = sms.group("patrol-1")
if patrol:get_category() == "airplane" then
  patrol:set_task(sms.task.orbit(orbit_pt, {altitude = 6000, pattern = "Anchored"}))
end
```

### `g:get_position() → vec3`

**Synopsis** — leader unit's position as a `{x, y, z}` vec3 (`x` = north, `y` = altitude, `z` = east — DCS-native).

**Returns** — `vec3`, or `nil` + log if the group is missing or has no units.

**Example**

```lua
local pos = sms.group("convoy-1"):get_position()
if pos then
  sms.log.info(string.format("lead at (%.0f, %.0f) alt %.0fm", pos.x, pos.z, pos.y))
end
```

### `g:get_units() → { sms.unit, ... }`

**Synopsis** — list of [`sms.unit`](unit.md) handles, in DCS unit order.

**Returns** — array of `sms.unit` handles. `nil` + log if the group is missing.

**Example**

```lua
for i, unit in ipairs(sms.group("flight-1"):get_units() or {}) do
  sms.log.info(i .. ": " .. unit:get_type() .. " at " .. unit:get_altitude() .. "m")
end
```

### `g:destroy() → true`

**Synopsis** — remove the group from the world. Does **not** fire DEAD events for the group's units (use `unit:destroy({emit_event = true})` per-unit if you want events).

**Returns** — `true` on success; `nil` + log if the group is already gone.

**Example**

```lua
local scratch = sms.group("scratch-spawn")
if scratch then scratch:destroy() end
```

### `g:connect(event_name, fn) → Connection`

**Synopsis** — subscribe to an entity-scoped event filtered to this group. Wraps [`sms.events.connect`](events.md). The callback fires only when `evt.initiator_group_name == g:get_name()`.

For `sms.events.DEAD` specifically, the callback fires **once** when the *last* unit of the group dies — see [`events.md`](events.md) for the last-unit-latch semantics. For all other entity-scoped events (HIT, TAKEOFF, LAND, etc.), it fires per-unit.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `event_name` | `string` | One of the `sms.events.*` constants. Must be entity-scoped — see [`events.md`](events.md) for the whitelist. |
| `fn` | `function(evt)` | Callback. `evt` is the normalized event payload documented in [`events.md`](events.md). |

**Returns** — `Connection` handle (use `sms.events.disconnect(conn)` to unsubscribe), or `nil` + log on bad input or non-entity-scoped event names.

**Example**

```lua
local armor = sms.group("red-armor")
armor:connect(sms.events.DEAD, function(evt)
  sms.log.info("red armor wiped at t=" .. evt.time)
end)

armor:connect(sms.events.HIT, function(evt)
  -- fires per-unit-hit; evt.initiator is the unit that took the hit
  sms.log.info(evt.initiator:get_name() .. " hit by " .. (evt.weapon_type or "?"))
end)
```

### `g:set_task(task)` / `g:push_task(task)`

**Brief** — apply a task built by an [`sms.task`](task.md) builder. `set_task` replaces the current task; `push_task` pushes onto the task stack with partially-LIFO semantics. Both validate category-restriction flags (e.g. air-only verbs against ground groups) and reject mismatches with `log.warn + false`.

These methods live on `sms.group`'s metatable but their full behavior — DCS Mission-task quirks, the one-frame deferred dispatch, partial-LIFO caveats, and the per-builder examples — is documented on the task page.

See the [task apply API](task.md#apply-api) for full reference and runnable examples.

---

## Static factories

### `sms.group.create(cfg) → sms.group`

**Synopsis** — build and add a new group at runtime. Returns an `sms.group` handle, with the resolved (possibly auto-suffixed) name.

**Auto-suffix on collision.** If `cfg.name` is already taken by any group *or* unit (DCS shares one namespace), the framework appends `-1`, `-2`, … until a free slot is found. **Always trust the returned handle's `:get_name()`** for follow-up operations — the input string may not match the resolved name.

**Aircraft 4-unit cap.** `airplane` and `helicopter` groups are capped at 4 units. DCS silently truncates aircraft groups above 4 units (units 5+ vanish without any error from `coalition.addGroup`), so the framework rejects oversized configs up-front with `log.warn + nil` rather than auto-truncating. Split into multiple groups if you need more. The cap does **not** apply to `ground` / `ship` / `train`.

**Arguments**

`cfg` (table) — the group config. Required and optional fields:

| Key | Type | Default | Description |
|---|---|---|---|
| `name` | `string` (required) | — | Group name. Auto-suffixed on collision. |
| `position` | `vec3` (required) | — | Group anchor `{x, y, z}` (`x` = north, `y` = altitude, `z` = east). Per-unit `offset` is added to this. |
| `country` | `string` (required) | — | Any value from `country.id` as a string; case-insensitive, spaces become underscores (`"United Kingdom"` → `country.id.UNITED_KINGDOM`). |
| `category` | `string` | `"ground"` | One of `"ground"`, `"airplane"`, `"helicopter"`, `"ship"`, `"train"`. |
| `units` | `{unit_spec, ...}` (required) | — | Non-empty array of unit specs (see below). For `airplane` / `helicopter` capped at 4. |
| `task` | `string` | category default (`"Ground Nothing"` for ground; `"Nothing"` otherwise) | DCS group-level task string passed verbatim. |
| `route` | DCS route table | for air: a single waypoint 50 km north of `position` at the first unit's `alt`; otherwise none | DCS-native route table. Passed verbatim — the framework does not introspect it. |

Any extra top-level keys are passed through verbatim into the DCS group_def.

**Per-unit `unit_spec` table:**

| Key | Type | Default | Description |
|---|---|---|---|
| `type` | `string` (required) | — | DCS unit type name (e.g. `"M-1 Abrams"`, `"FA-18C_hornet"`). |
| `name` | `string` | `<group_name>_<i>` | Unit name. Auto-suffixed on collision. Auto-generated names use `_<i>` to avoid colliding with group `-<n>` suffixes. |
| `offset` | `vec3` | `{x=0, y=0, z=0}` | Position relative to group `position`. Added to the anchor; only `x` and `z` are used (DCS-2D). |
| `heading` | `number` (degrees) | `0` | Facing in **degrees**, 0 = north, 90 = east. Converted to radians internally. |
| `skill` | `string` | `"Average"` | DCS skill: `"Average"`, `"Good"`, `"High"`, `"Excellent"`, `"Random"`, `"Player"`, `"Client"`. Passthrough. |
| `livery_id` | `string` | — | DCS livery override. Passthrough. |
| `onboard_num` | `string` | — | DCS onboard number. Passthrough. |

For `airplane` and `helicopter` units, `alt` is **required**, plus these optional fields:

| Key | Type | Default | Description |
|---|---|---|---|
| `alt` | `number` (meters, required for air) | — | Altitude in **meters**. |
| `alt_type` | `string` | `"BARO"` | `"BARO"` (mean sea level) or `"RADIO"` (above ground level). |
| `speed` | `number` (m/s) | `200` for airplanes; unset (hover) for helicopters | Initial speed at spawn. |
| `payload` | table | DCS default for type | DCS payload table. Passthrough. |
| `callsign` | `string` / table | — | DCS callsign. Passthrough. |
| `frequency` | `number` | — | Radio frequency (Hz). Passthrough. |
| `modulation` | `number` | — | Radio modulation. Passthrough. |
| `parking_id` | `string` | — | Ramp parking spot ID. Passthrough. |

Any extra unit keys are passed through verbatim.

**Returns** — `sms.group` handle, or `nil` + log on validation failure (missing required field, unknown country, unknown category, oversized aircraft group, missing `alt` on air units, etc.) or on a DCS rejection from `coalition.addGroup`.

**Example — ground**

```lua
local tanks = sms.group.create({
  name     = "tank-section",
  position = {x = 0, y = 0, z = 0},
  country  = "USA",
  category = "ground",                            -- default; can be omitted
  units    = {
    { type = "M-1 Abrams" },
    { type = "M-1 Abrams", offset = {x = 0, y = 0, z = 20} },
    { type = "M-1 Abrams", offset = {x = 0, y = 0, z = 40}, heading = 90 },
  },
})
sms.log.info("spawned as " .. tanks:get_name())   -- e.g. "tank-section" or "tank-section-1"
```

**Example — aircraft**

```lua
sms.group.create({
  name     = "f18-cap",
  position = airfield_pos,
  country  = "USA",
  category = "airplane",
  units    = {
    { type = "FA-18C_hornet", alt = 6000, heading = 90 },
    { type = "FA-18C_hornet", alt = 6000, heading = 90, offset = {x = -50, y = 0, z = -50} },
  },
  -- route omitted -> default 50km-north waypoint at the first unit's alt
})
```

### `sms.group.clone(template_name, overrides) → sms.group`

**Synopsis** — clone a Mission-Editor-placed group at a new name and (optionally) a new position. Reads the template definition from `env.mission.coalition[*].country[*].<cat>.group[]`, deep-copies it, strips IDs and late-activation flags, re-anchors every unit, and spawns it. Works against late-activated templates too — the mission descriptor is read regardless of activation state.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `template_name` | `string` | Name of the ME-placed group to copy. |
| `overrides` | `table` | At minimum `{name = "..."}`. See keys below. |

**`overrides` keys:**

| Key | Type | Default | Description |
|---|---|---|---|
| `name` | `string` (required) | — | New group name. Auto-suffixed on collision; per-unit names also auto-suffixed (with `_<i>` separator). |
| `position` | `vec3` | template's leader unit's ME position | New anchor `{x, y, z}`. The relative shape of all units (and the first route waypoint) is preserved — every unit gets re-anchored, not just the leader. |

**Returns** — `sms.group` handle, or `nil` + log on validation failure or missing template.

**Example — clone at a new position**

```lua
sms.group.clone("MY_TEMPLATE_GROUP", {
  name     = "spawned-instance",
  position = some_vec3,
})
```

**Example — clone repeatedly into a random point inside a zone**

```lua
local box = sms.area("SpawnBox")
sms.timer.every(60, function()
  if sms.group("patrol-1"):is_alive() then return end
  sms.group.clone("PATROL_TEMPLATE", {
    name     = "patrol-1",
    position = box:get_random_point(),
  })
end)
```

**Example — clone at the template's own ME position**

```lua
-- Position omitted -> spawns at the template's leader-unit ME position.
sms.group.clone("LATE_ACTIVATED_TEMPLATE", { name = "spawned-instance" })
```

**Notes**

- Clone strips `groupId`, every unit's `unitId`, and `lateActivation` from the copy. DCS assigns fresh IDs to the spawned instance.
- v1 only re-anchors the *first* route waypoint to the new position; subsequent waypoints keep their template-relative coordinates. For complex re-routing, use `create` with an explicit `route` instead.

---

## See also

- [`sms.unit`](unit.md) — per-unit getters and event sugar; `g:get_units()` returns these.
- [`sms.task`](task.md) — task builders; `g:set_task` / `g:push_task` apply them.
- [`sms.events`](events.md) — `g:connect` is sugar over `sms.events.connect` with group-scoped filtering and the DEAD-event last-unit latch.
- [`sms.area`](area.md) — `area:is_any_of_group_in(g)` / `area:is_all_of_group_in(g)` for containment tests.
- [`AGENTS.md` §3 failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw), [§4 conventions](../../AGENTS.md#4-conventions-and-units), [§5 entity handles](../../AGENTS.md#5-entity-handles--the-universal-pattern) — cross-cutting rules every method follows.
