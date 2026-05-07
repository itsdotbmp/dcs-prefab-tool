# `sms.prefab`

Portable bundles of DCS entities — groups, statics, trigger zones, map drawings — distilled from a Mission Editor selection and respawnable at runtime anywhere on any map.

A prefab is a `.prefab` file (a Lua chunk that returns a table) produced by `sms.prefab.distill(...)` from a hello-world ME selection dump. Once loaded into the runtime registry via `sms.prefab.load(path)`, you can `sms.prefab.spawn("name", {anchor=..., rotation=..., country=...})` as many times as you want; each call returns an instance handle for lifecycle management.

See [the design spec](../superpowers/specs/2026-05-03-sms-prefab-design.md) for the file format details and design rationale.

## Quick example

```lua
-- One-time setup: distill a captured ME selection dump into a prefab.
local prefab = sms.prefab.distill(
    "C:/Users/.../Saved Games/DCS/dcs-sms/me/selection-2026-05-03T091254Z.lua",
    { name = "farp_alpha", theatre = "Caucasus" }
)
sms.prefab.save(prefab, "C:/Users/.../Saved Games/DCS/dcs-sms/prefabs/farp_alpha.prefab")

-- Per-mission: load the registry, spawn copies.
sms.prefab.load("C:/Users/.../Saved Games/DCS/dcs-sms/prefabs/farp_alpha.prefab")

local north = sms.prefab.spawn("farp_alpha", {
    anchor   = { x = 12000, z = -3500 },
    rotation = 90,
})

local south = sms.prefab.spawn("farp_alpha", {
    anchor   = { x = -8000, z = 5000 },
    rotation = -45,
    country  = sms.K.countries.RUSSIA,
})

-- Later, clean up.
north:destroy()
sms.prefab.destroy_all("farp_alpha")  -- destroys remaining south
```

## Functions

### `sms.prefab.distill(dump_or_path, opts) → prefab_table | nil`

Walks an ME selection dump, drops back-references (the `boss` cycle), partitions statics out of groups, captures country before strip, converts headings rad → deg, and rebases every coordinate relative to the centroid of the selection. Pure data — no DCS dependencies.

- `dump_or_path` — either an in-memory dump table or a path string to a `.lua` dump file.
- `opts.name` (string, required) — the prefab's registered name (`meta.name`).
- `opts.theatre` (string, optional) — informational; stored as `meta.theatre`.

Returns a prefab table (the same shape as a saved prefab file), or `nil` + log on bad input.

### `sms.prefab.save(prefab_table, path) → boolean`

Serializes `prefab_table` via `sms.utils.serialize` and writes to `path`. Returns `true` on success, `false` + log on failure (e.g., `io.open` failed). Requires `io` to be available — fails gracefully in environments where it's nilled.

### `sms.prefab.load(path) → template_table | nil`

`dofile`s the file at `path`, validates that it has `meta.name`, registers it in the registry under that name. Re-loading the same name logs a warning and overwrites. Returns the loaded template or `nil` + log on failure.

### `sms.prefab.load_dir(dir) → number`

Recursively loads every `*.prefab` and `*.lua` under `dir`. The `.lua` extension is accepted for backward compatibility — files written by older releases of the ME-mod use it. Per-file failures log + continue. Returns the count of successful loads. Requires `lfs`.

### `sms.prefab.register(name, template) → template_table | nil`

Registers a template directly (without `dofile`). Useful for programmatically constructed prefabs and for tests. Sets `template.meta.name = name` and adds to the registry. Returns the template, or `nil` + log on bad input.

### `sms.prefab.unload(name) → boolean`

Removes `name` from the registry. Does NOT destroy spawned instances. Returns `true` if `name` was registered, `false` otherwise.

### `sms.prefab.list() → string[]`

Returns the names of all currently-registered prefabs, sorted.

### `sms.prefab.get(name) → template_table | nil`

Returns the registered template table for `name`, or `nil`.

### `sms.prefab.spawn(name, opts) → handle | nil`

Spawns a new instance of the registered prefab `name`. Returns a handle (see "Handle methods" below) or `nil` + log on failure.

`opts`:

- `anchor` (vec2 / vec3, required unless `keep_position=true`) — world anchor `{x = world_x, z = world_y}`. Also accepts `{x, y}` for callers passing 2D.
- `rotation` (number, optional, default `0`) — degrees, clockwise from north.
- `country` (number or string, optional) — override every unit's country. `nil` preserves per-unit country from the prefab. Strings resolved via `sms.utils.resolve_country`.
- `name_prefix` (string, optional) — prepended to every spawned entity's name (before auto-suffix).
- `keep_position` (boolean, optional) — if `true`, ignores `opts.anchor` and `opts.rotation`; spawns at `meta.world_anchor` with rotation 0 (the original placement).

Naming: candidate name is `(opts.name_prefix or "") .. file_name`. If a name is already taken, the spawner appends `-1`, `-2`, ... per the framework convention.

### `sms.prefab.list_instances(name?) → handle[]`

Returns all live handles, optionally filtered by template name.

### `sms.prefab.destroy_all(name?) → number`

Calls `:destroy()` on every live handle (or those matching `name`). Returns count destroyed.

## Handle methods

The handle returned by `spawn(...)` is callable via `handle:method()` style.

| Method | Returns |
|---|---|
| `handle:get_name()` | template name (string) |
| `handle:get_id()` | instance id (number, unique per spawn) |
| `handle:get_anchor()` | resolved world anchor used at spawn (`{x, z}`) |
| `handle:get_rotation()` | degrees applied at spawn |
| `handle:get_groups()` | array of `sms.group` handles |
| `handle:get_statics()` | array of `sms.static` handles |
| `handle:get_zones()` | array of zone tables (data-only; not real DCS trigger zones) |
| `handle:get_drawings()` | array of `{name, mark_id, kind}` (mark ids are DCS runtime) |
| `handle:get_group(template_name)` | the spawned `sms.group` for the given original (template) name |
| `handle:get_static(template_name)` | the spawned `sms.static` for the given original (template) name |
| `handle:get_zone(name)` | zone table by name |
| `handle:is_alive()` | `true` if at least one entity from this spawn still exists |
| `handle:destroy()` | destroys all spawned entities, removes drawings; idempotent |

## Notes and limitations

- **Zones don't get realized** in DCS — there's no runtime trigger-zone-creation API. They're stored on the handle for custom in-zone checks (`sms.area.is_in_polygon` etc.).
- **Drawings get realized** via `trigger.action.markup*` — they appear on the F10 map. v1 supports `Line`, `Polygon`, `Circle`, `TextBox`, `Icon`. Other kinds skip with a warning.
- **Same-prefab cross-references aren't rewritten.** If group A's escort task references group B and you spawn the prefab twice, the second spawn's A-equivalent still references the first spawn's B. Documented limitation; revisit in v2 if it bites real users.
- **Loading prefab files is `dofile`** — arbitrary code execution. v1 is for files you wrote or trust. Sandboxed loader will land before community sharing is encouraged.
- **Random pools** (per-entity spawn-chance) are not yet supported. Designed-around in the format so they can be added in v2.
- **Names are preserved verbatim** in the file — auto-suffix happens at spawn time, not save time.
- **Headings in the file are degrees** — internal rad-to-deg conversion happens during distill; deg-to-rad happens during spawn before handing to DCS.
