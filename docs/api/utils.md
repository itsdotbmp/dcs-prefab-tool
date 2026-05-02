# `sms.utils` — numeric helpers, vec3 maths, and shared lookups

`sms.utils` is the framework's small grab-bag of pure-functional helpers that other modules either need internally or want to expose to mission code. Scope is deliberately narrow: unit conversions (deg/rad, ft/m), vec3 maths (length, distance, bearing), heading wrapping, plus a handful of shared validation and lookup helpers (`is_vec3`, `resolve_country`, `coalition_int_to_str`, `deep_copy`). This is **not** a generic stdlib — new helpers land here only when there are real in-tree callers and the helper is DCS-shaped enough to deserve a public name.

All functions follow the framework's [failure model: log + nil, never throw](../../AGENTS.md#3-failure-model-log--nil-never-throw). A handful are intentionally **silent** on bad input — they return `nil` without logging because callers craft their own contextual error message. These are called out per-function below.

**Units (public API):** headings in **degrees** (0=north, 90=east, clockwise); altitudes in **meters**; coalitions as lowercase strings (`"red"` / `"blue"` / `"neutral"`). See [`AGENTS.md` §4](../../AGENTS.md#4-conventions-and-units).

## Loading

`sms.utils` only requires `sms.lua` and `sms.log` to be loaded first. `framework/load_all.lua` handles this; in practice every other framework module already depends on it, so by the time you have any other `sms.*` symbol available, `sms.utils` is too.

## Functions

### `sms.utils.add_numbers(a, b) → number`

**Synopsis** — adds two numbers. This exists as a smoke-test exerciser for the bridge / loader pipeline (it logs at `info` so a successful call proves logging, module loading, and the bridge round-trip all work). It is trivial but real public surface.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `a` | `number` | First addend. |
| `b` | `number` | Second addend. |

**Returns** — `number`. Does not validate input; if you pass non-numbers, Lua will throw the usual `attempt to perform arithmetic` error. (This is the one helper in this module that does not implement the log-and-nil pattern, because its purpose is to be a one-liner smoke test.)

**Example**

```lua
sms.log.info("bridge ok: 2 + 3 = " .. tostring(sms.utils.add_numbers(2, 3)))
```

---

### `sms.utils.deg_to_rad(deg) → number`

**Synopsis** — converts degrees to radians. The framework's public API takes headings in degrees (pilot-friendly), but DCS internally works in radians; these helpers exist to cross that boundary cleanly.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `deg` | `number` | Angle in degrees. |

**Returns** — `number` (radians). Logs at `warn` and returns `nil` if `deg` is not a number.

**Example**

```lua
local rad = sms.utils.deg_to_rad(90)
sms.log.info("90 deg = " .. tostring(rad) .. " rad")  -- ~1.5708
```

---

### `sms.utils.rad_to_deg(rad) → number`

**Synopsis** — inverse of [`deg_to_rad`](#smsutilsdeg_to_raddeg--number). Mostly useful when you've pulled a raw radian value out of DCS (e.g. a unit's heading from a low-level call) and want to display it.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `rad` | `number` | Angle in radians. |

**Returns** — `number` (degrees). Logs at `warn` and returns `nil` if `rad` is not a number.

**Example**

```lua
local deg = sms.utils.rad_to_deg(math.pi)  -- 180
```

---

### `sms.utils.feet_to_meters(ft) → number`

**Synopsis** — converts feet to meters. The framework's public API takes altitudes in meters (DCS-native), but pilots think in feet — this helper is for user code, not internal calls.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `ft` | `number` | Altitude / distance in feet. |

**Returns** — `number` (meters). Logs at `warn` and returns `nil` if `ft` is not a number.

**Example**

```lua
local cap = sms.group("blue-cap-1")
sms.task.orbit(cap, {
  pattern  = "Circle",
  altitude = sms.utils.feet_to_meters(25000),  -- FL250 → ~7620 m
  speed    = 220,
})
```

---

### `sms.utils.meters_to_feet(m) → number`

**Synopsis** — inverse of [`feet_to_meters`](#smsutilsfeet_to_metersft--number). Use when displaying altitudes you read back from the framework / DCS.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `m` | `number` | Altitude / distance in meters. |

**Returns** — `number` (feet). Logs at `warn` and returns `nil` if `m` is not a number.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
sms.log.info(bandit:get_name() .. " at " ..
             string.format("%.0f", sms.utils.meters_to_feet(bandit:get_altitude())) ..
             " ft ASL")
```

---

### `sms.utils.is_vec3(v) → bool`

**Synopsis** — silent structural check: returns true iff `v` is a table with numeric `x`, `y`, and `z` fields. Used by every cfg-validation path that takes a vec3 (`sms.group.create` / `sms.static.create` positions, `sms.area:is_vec3_in`, etc.).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `v` | `any` | Candidate value. |

**Returns** — `bool`. **Silent** on failure — never logs, returns `false` for nil / wrong type / partial tables. Callers craft their own contextual error message.

**Example**

```lua
local pos = {x = 1234, y = 0, z = 5678}
if sms.utils.is_vec3(pos) then
  sms.log.info("ok, looks like a vec3")
end
```

---

### `sms.utils.vec3_length(v) → number`

**Synopsis** — 3D Euclidean length of a DCS vec3 (`sqrt(x² + y² + z²)`). DCS vec3 axes are x = north, y = altitude, z = east; this is the full 3D length, not the horizontal-plane length, because vec3 is a 3D vector and vertical components matter.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `v` | `vec3` | Table with numeric `x`, `y`, `z`. |

**Returns** — `number`. Logs at `warn` and returns `nil` if `v` is not a vec3 (per `is_vec3`).

**Example**

```lua
local velocity = {x = 100, y = 0, z = 100}
local speed_mps = sms.utils.vec3_length(velocity)  -- ~141.42
```

---

### `sms.utils.vec3_distance(a, b) → number`

**Synopsis** — 3D Euclidean distance between two DCS vec3s. Pure maths — does **not** duck-type entity handles. If you have a unit / group / static handle, call `:get_position()` on it first and pass the resulting vec3.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `a` | `vec3` | First point. |
| `b` | `vec3` | Second point. |

**Returns** — `number` (meters). Logs at `warn` and returns `nil` if either argument is not a vec3.

**Example**

```lua
local bandit = sms.unit("Bandit-1")
local target = sms.unit("CAP-1")
local distance = sms.utils.vec3_distance(bandit:get_position(), target:get_position())
sms.log.info("separation: " .. string.format("%.0f", distance) .. " m")
```

---

### `sms.utils.normalize_heading(deg) → number`

**Synopsis** — wraps a heading in degrees to the canonical `[0, 360)` range. Lua 5.1's `%` is mathematical modulo (not C remainder), so a single `deg % 360` handles negatives correctly: `-90 % 360 == 270`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `deg` | `number` | Heading in degrees, any sign / magnitude. |

**Returns** — `number` in `[0, 360)`. Logs at `warn` and returns `nil` if `deg` is not a number.

**Example**

```lua
sms.utils.normalize_heading(-90)   -- 270
sms.utils.normalize_heading(450)   -- 90
sms.utils.normalize_heading(360)   -- 0
```

---

### `sms.utils.bearing_to(from, to) → number`

**Synopsis** — compass bearing from one vec3 to another, in **degrees**, 0=north, 90=east, clockwise (DCS convention). Computed on the horizontal plane (xz); altitude (y) is ignored.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `from` | `vec3` | Origin point. |
| `to`   | `vec3` | Target point. |

**Returns** — `number` in `[0, 360)`. Logs at `warn` and returns `nil` if either argument is not a vec3.

**Example**

```lua
local me    = sms.unit("CAP-1")
local bogey = sms.unit("Bandit-1")
local bearing = sms.utils.bearing_to(me:get_position(), bogey:get_position())
sms.log.info(string.format("bandit bears %03.0f", bearing))
```

---

### `sms.utils.resolve_country(s) → integer | nil`

**Synopsis** — public country string → DCS `country.id` integer. Case-insensitive; spaces are converted to underscores so users can pass `"United Kingdom"` and have it resolve to `country.id.UNITED_KINGDOM`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `s` | `string` | Country name. Case and spacing don't matter. |

**Returns** — `integer` (DCS `country.id` value) on success, `nil` otherwise. **Silent** on failure (non-string input or unknown country): callers craft their own contextual error message — typically something like `"create: unknown country '...'"`.

**Example**

```lua
local id = sms.utils.resolve_country("united kingdom")
-- id == country.id.UNITED_KINGDOM

local bad = sms.utils.resolve_country("Atlantis")
-- bad == nil, no log; caller decides how loud to be
if not bad then
  sms.log.warn("create: unknown country 'Atlantis'")
end
```

---

### `sms.utils.coalition_int_to_str(c) → "red" | "blue" | "neutral" | nil`

**Synopsis** — DCS coalition integer → normalized lowercase string. Mapping is `0 → "neutral"`, `1 → "red"`, `2 → "blue"`. Used by every entity wrapper (`unit`, `group`, `static`, `weapon`) so they all expose coalitions the same way.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `c` | `integer` | DCS coalition integer (`coalition.side.*` value). |

**Returns** — `"red"`, `"blue"`, `"neutral"`, or `nil`. **Silent** on unknown int — callers do their own log message with context (most call sites log at `error` because an unknown coalition coming back from DCS is genuinely unexpected).

**Example**

```lua
local side = sms.utils.coalition_int_to_str(1)  -- "red"
local huh  = sms.utils.coalition_int_to_str(99) -- nil, no log
```

---

### `sms.utils.deep_copy(t) → any`

**Synopsis** — recursive deep copy of a table. Non-table values pass through unchanged. Used by `sms.group.clone` / `sms.static.clone` to duplicate mission descriptors before mutating them.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `t` | `any` | Value to copy. Tables are recursed; everything else returns unchanged. |

**Returns** — a deep-copied value of the same shape. Always succeeds for the inputs the framework actually uses (mission descriptors are plain trees of tables / numbers / strings / bools).

**Notes**

- **Does not preserve metatables.** Mission-descriptor cfg tables don't use them; if you need metatable preservation, write your own copier.
- **Does not handle cycles.** A self-referential table will recurse until the Lua stack overflows. Mission descriptors are trees, so this hasn't been a problem in practice.
- Functions, userdata, and threads pass through by reference (the non-table fast path).

**Example**

```lua
local template = {
  name     = "red-cas-1",
  country  = sms.K.countries.RUSSIA,
  category = sms.K.category.AIRPLANE,
  units = {
    {type = "Su-25T", x = 0, z = 0, payload = {pylons = {}}},
  },
}

local cfg = sms.utils.deep_copy(template)
cfg.name      = "red-cas-2"
cfg.units[1].x = 5000
-- template is untouched; cfg can be mutated freely before sms.group.create(cfg)
```
