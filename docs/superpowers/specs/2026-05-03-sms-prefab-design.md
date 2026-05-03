## sms.prefab — Design

**Date:** 2026-05-03
**Status:** Approved (brainstorm phase)
**Scope:** First sub-project of the prefab/objective track. A new framework module (`sms.prefab`) that consumes hello-world ME selection dumps, distills them into a portable prefab format (groups + statics + zones + drawings, anchor-relative), and respawns them at runtime anywhere on any map with translation, rotation, country override, and per-instance lifecycle tracking. Sub-project 1 of 3.

## Goal

Re-implement (and significantly improve) the user's MOOSE `OBJECTIVE_MANAGER` as a first-class part of dcs-sms:

1. Take a raw ME selection dump (the 60–600 KB Lua-table file the hello-world mod produces) and **distill** it into a clean prefab file: every ME-set property preserved verbatim, the cyclic `boss` back-reference graph stripped, all coordinates re-anchored relative to the selection's centroid, headings converted from radians to degrees, country captured before strip.
2. Load prefab files into a runtime registry: `sms.prefab.load(path)` and `sms.prefab.load_dir(dir)`.
3. Spawn registered prefabs at any world anchor + rotation + (optional) country override: `sms.prefab.spawn(name, opts)` returns an instance handle.
4. Cleanly destroy spawned instances together: `handle:destroy()`, `sms.prefab.destroy_all(name?)`.

The deliverable is the framework module + tests. The Mission Editor "Save selection as objective" button that produces these files is Sub-project 3 and is out of scope here. For v1, prefab files are produced either by manually invoking `sms.prefab.distill(...)` on a dump file, or hand-written.

## User value

The user's mental model: "Build a thing once in the ME — a FARP, a SAM site, a convoy with waypoints + ROE + payloads + Lua scripts at waypoints — save it as a prefab, then drop copies of it anywhere on any map." This sub-project delivers the **runtime spawn half** of that loop. Combined with the hello-world's selection dumping, an end-to-end "save → spawn elsewhere" path becomes possible (manual distill step today; one-click in Sub-project 3).

## Non-goals

- A real "Save selection as prefab" Mission Editor button. Sub-project 3.
- A "Place prefab" ME button (drop a prefab back into the open mission at design time). Sub-project 3.
- Sandboxed loading of prefab files. They are loaded via `dofile`, so an untrusted prefab file is arbitrary code execution. v1 is for files the user wrote or trusts. Sandboxed loader (`setfenv` + restricted env) lands before the project encourages community sharing.
- Random pools / per-entity spawn-chance variations. Deferred to v2; the file format leaves room to add them without breaking compatibility.
- Cross-reference rewriting between intra-prefab entity names (e.g., group A's escort task referencing group B). Names are preserved verbatim per Section 2; same-prefab-twice cross-reference contamination is a known and accepted limitation.
- Trigger-system integration (mission flags, conditions, actions referencing the prefab's groups by name). Triggers live at a different scope than the group table and aren't captured by `Mission.getGroup`.
- Map-level data (weather, time of day, mission options).
- Navigation points (the dump captures them; we deliberately drop them — they're per-flight per-mission concerns, not bundle content).
- Realizing trigger zones at runtime — DCS has no API for it. Zones travel as data only, accessible via `handle:get_zone(name)` for custom in-zone checks.

## Context

This sub-project sits in the middle of a three-part track:

- **Sub-project 2 (done, on `main`):** ME hello world. A custom dxgui window in the Mission Editor with a "Print selection" button that dumps `Mission.getGroup(id)` output verbatim to `Saved Games\DCS\dcs-sms\me\selection-*.lua`. The dump is the *input* this sub-project consumes.
- **Sub-project 1 (this spec):** `sms.prefab` — distill + load + spawn + lifecycle.
- **Sub-project 3 (future):** ME features. "Save selection as prefab" button (writes files this sub-project consumes), "Place prefab" button (drops one into the open mission at design-time), prefab library browser, real Tools-menu integration.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  ME hello-world dump (Saved Games\DCS\dcs-sms\me\selection-*.lua)   │
│  Raw Mission.getGroup(id) tables — full incl. boss back-refs        │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ sms.prefab.distill(dump_table, opts)
                           v
┌─────────────────────────────────────────────────────────────────────┐
│  Prefab table (in-memory or written to disk)                        │
│  Verbatim-minus-back-refs, anchor-relative coords, meta block       │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ sms.prefab.save(prefab, path)
                           v
┌─────────────────────────────────────────────────────────────────────┐
│  Prefab file (e.g. Saved Games\DCS\dcs-sms\prefabs\farp_alpha.lua)  │
│  Lua chunk: return { meta=..., groups=..., statics=..., ... }       │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ sms.prefab.load(path)  →  registry
                           │ sms.prefab.spawn(name, opts)
                           v
┌─────────────────────────────────────────────────────────────────────┐
│  Spawned instance handle                                            │
│  Methods: :destroy(), :get_groups(), :get_statics(), :get_anchor()  │
│  All groups/statics auto-suffixed for collision, addressable as     │
│  regular sms.group("...") / sms.static("...") handles.              │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

Two files in `framework/`, mirroring the existing `group.lua` + `group_spawn.lua` "continuation file" pattern.

### `framework/prefab_distill.lua`

Pure-data transformation. **No DCS dependencies.** Runnable in standalone Lua 5.1 like the serializer. Public symbol exposed under `sms.prefab.distill`.

```
sms.prefab.distill(dump_or_path, opts) → prefab_table | nil
  dump_or_path: string (file path) | table (in-memory dump)
  opts = {
    name      = string,           -- required; meta.name in the output
    theatre   = string?,          -- optional; meta.theatre
  }
```

Algorithm:
1. Load `dump_or_path`: if string, `dofile()`; else use as-is.
2. Walk every entity in `dump.groups`, `dump.statics` (the dump rolls statics into `groups`; we partition during distill by inspecting `category` / `unit count` / `type`), `dump.zones`, `dump.drawings`. Each entity is a table.
3. Per entity, **walk with a visited-set**: any sub-table re-encountered is dropped (nil), not emitted. The `boss` field is **explicitly dropped at every depth** as defense-in-depth even when the visited-set wouldn't yet flag it (it's the canonical back-ref into mission-global state).
4. **Capture country** for each unit before stripping `boss` — read `entity.boss.country.id` (or fall back to a lookup) and write it to the entity table as `country` (numeric id). This is the only enrichment the distill step adds.
5. **Convert headings rad → deg** at every depth where a `heading` field appears (group level, unit level, static level, route waypoint level if present).
6. **Compute the centroid** of all top-level entity positions (groups + statics + zones + drawings; one position contribution per entity, the entity's own `x, y`).
7. **Re-anchor coordinates**: subtract centroid from every `x, y` at every depth (group, unit, waypoint, static, zone center, drawing point). The file is now coordinate-free of world position.
8. Emit the result with a `meta` block containing `sms_prefab_version`, `name` (from opts), `created_utc`, `source_dump` (filename if given), `world_anchor` (the centroid), `theatre` (from opts).

Returns `nil` and logs a warning on bad input (nil dump, dump with no entities, malformed dump).

### `framework/prefab.lua`

Public `sms.prefab.*` namespace. Touches DCS API.

**Registry**

```
sms.prefab.load(path)              → template_table | nil
sms.prefab.load_dir(dir)           → number_of_loaded_prefabs
sms.prefab.unload(name)            → boolean (true if was registered)
sms.prefab.list()                  → array of registered names
sms.prefab.get(name)               → template_table | nil
```

`load_dir` recursively scans for `*.lua` and tries to load each. Per-file failures log + continue.

**Save**

```
sms.prefab.save(prefab_table, path) → boolean
```

Serializes via `serializer.serialize` (the same Lua-table serializer the hello-world mod ships, copied/adapted into framework — see Decisions). Writes via `io.open` if available; logs + returns false otherwise (mission environment may have `io` nilled).

**Spawn**

```
sms.prefab.spawn(name, opts) → handle | nil
  opts = {
    anchor        = vec3 | vec2,    -- required unless keep_position=true; {x, z} or {x, y, z}
    rotation      = number,         -- degrees, default 0
    country       = number?,        -- sms.K.countries.* override; nil = preserve per-unit
    name_prefix   = string?,        -- prepended to every spawned entity's name
    keep_position = boolean,        -- if true, anchor + rotation ignored, spawn at meta.world_anchor with rotation 0
  }
```

Math at spawn:
1. Resolve effective anchor: `keep_position` → `meta.world_anchor` + rotation 0; else `opts.anchor` + `opts.rotation`.
2. For every coord: `(rx, ry) = rotate((rel_x, rel_y), rotation_deg)`; `(world_x, world_y) = (anchor_x + rx, anchor_z + ry)` (note: framework convention 2D-y = 3D-z).
3. For headings: `world_heading_deg = (file_heading_deg + rotation_deg) mod 360`. Convert deg→rad before handing to DCS.
4. For DCS APIs that want vec3: `{x = world_x, y = alt, z = world_y}`.

Country override: if `opts.country` is set, every unit's `country` is rewritten to it before calling `coalition.addGroup`. Reject unknown countries up front (return nil).

Naming: candidate name is `(opts.name_prefix or "") .. file_name`. If a name is already taken in the running mission, append `-1`, `-2`, ... until unique. Same convention as `sms.group.create` already uses (per AGENTS.md §4).

**What gets created in DCS:**

| Entity type | DCS API | Notes |
|---|---|---|
| `airplane` / `helicopter` / `vehicle` / `ship` | `coalition.addGroup(country, category, group_table)` | Whole group table passed through, with coords + heading rewritten and (optionally) country swapped. Category derived from group `type`. |
| static objects | `coalition.addStaticObject(country, static_table)` | Single call per static. |
| drawings | `trigger.action.markupToAll` / `lineToAll` / `circleToAll` / `quadToAll` / `textToAll` (whichever fits the drawing's `primitiveType`) | Realized on the F10 map at the new world coords. Each drawing's runtime mark id is tracked on the handle. |
| zones | *not realized* | DCS has no runtime "create trigger zone" API. Stored on the handle; accessible via `handle:get_zone(name)` for custom in-zone checks. |

**Handle**

`sms.prefab.spawn(...)` returns a prefab instance handle. Same callable/method pattern as the rest of the framework (a small table with metatable `__index = sms.prefab`).

```
handle:get_name()         → template name (string)
handle:get_id()           → instance id (number, unique per spawn)
handle:get_anchor()       → resolved world anchor used at spawn (vec2)
handle:get_rotation()     → degrees applied at spawn (number)

handle:get_groups()       → array of sms.group handles
handle:get_statics()      → array of sms.static handles
handle:get_zones()        → array of {name, x, y, radius?, vertices?, properties} (data-only)
handle:get_drawings()     → array of {name, mark_id, kind, ...}

handle:get_group(template_name)  → sms.group handle (looks up by ORIGINAL name; resolves auto-suffix)
handle:get_static(template_name) → sms.static handle
handle:get_zone(template_name)   → zone table

handle:is_alive()         → true if at least one entity from this spawn still exists
handle:destroy()          → destroys all spawned entities, removes drawings; idempotent
```

**Multi-instance helpers**

```
sms.prefab.list_instances(name?)     → array of live handles, optionally filtered by template name
sms.prefab.destroy_all(name?)        → destroys every live handle (or filtered by template name); returns count
```

## File format

A prefab file is a Lua chunk that returns a single table. Default location: `Saved Games\DCS\dcs-sms\prefabs\<name>.lua` (the loader takes any path).

```lua
return {
    ["meta"] = {
        ["sms_prefab_version"] = "0.1.0",
        ["name"]               = "farp_alpha",
        ["created_utc"]        = "2026-05-03T14:17:28Z",
        ["source_dump"]        = "selection-2026-05-03T091254Z.lua",
        ["world_anchor"]       = { x = 80069.88, y = -139429.53 },
        ["theatre"]            = "Caucasus",
    },
    ["groups"]   = { [1] = { ... }, [2] = { ... } },  -- DCS group tables, anchor-relative, headings in degrees
    ["statics"]  = { [1] = { ... } },                  -- DCS static tables, anchor-relative, headings in degrees
    ["zones"]    = { [1] = { ... } },                  -- ME trigger zone tables, anchor-relative
    ["drawings"] = { [1] = { ... } },                  -- ME drawing object tables, anchor-relative
}
```

**Coordinate convention:** 2D `{x, y}` everywhere in the file (matches DCS's mission-descriptor format). Anchor-relative — every coord is delta from `meta.world_anchor`. Spawner converts to 3D `{x = world_x, y = alt, z = world_y}` when calling DCS APIs.

**Headings:** degrees in the file (converted from radians by distill). Spawner converts to radians before handing to DCS.

**Names:** original ME names preserved verbatim in the file. Spawner auto-suffixes at runtime if needed.

**Cross-references:** intra-prefab references (group A references group B by name) are preserved verbatim, NOT rewritten. Same-prefab-spawned-twice yields cross-reference contamination — documented limitation.

## Loading order

`framework/load_all.lua` modules list is extended:

```
sms.lua → log.lua → utils.lua → constants.lua → group.lua → unit.lua → area.lua →
timer.lua → rule.lua → group_spawn.lua → static.lua → events.lua → weapon.lua →
task.lua → commands.lua → options.lua → prefab_distill.lua → prefab.lua
```

`prefab_distill.lua` exposes `sms.prefab.distill` so `prefab.lua` can re-export from it. `prefab.lua` asserts the dependencies it actually uses (`sms.utils`, `sms.log`, `sms.constants`, `sms.group`, `sms.static`).

## Failure model

Same framework rule: **log + nil + never throw.** Logger tag `sms.prefab` for the main module, `sms.prefab.distill` for the distill helper.

| Boundary | Failure | Behavior |
|---|---|---|
| `distill(dump, opts)` | dump is nil / not a table | log.warn + return nil |
| | dump.groups + dump.statics + dump.zones + dump.drawings all empty | log.warn + return nil |
| | per-entity malformed (can't extract country, etc.) | log.warn for entity, skip it, continue |
| `load(path)` | file missing | log.warn + return nil |
| | dofile parse / syntax error | pcall'd; log.error + return nil |
| | returned value not a table, no meta.name | log.warn + return nil |
| | name already in registry | log.warn ("overwriting") + overwrite + return template |
| `load_dir(dir)` | dir doesn't exist | log.warn + return 0 |
| | per-file failures | log.warn each; continue; return successful count |
| `spawn(name, opts)` | template name not registered | log.warn + return nil |
| | opts.anchor missing AND not keep_position | log.warn + return nil |
| | opts.country invalid | log.warn + return nil |
| | per-group / per-static / per-drawing addGroup/addStaticObject/markup raises | per-entity pcall; log.error each; continue with the rest |
| | every entity failed | log.error + return nil (no half-dead handle) |
| `handle:destroy()` | already destroyed | no-op (idempotent) |
| | per-entity destroy raises | per-entity pcall + log.warn + continue |
| `handle:get_*()` after destroy | — | return empty array / nil; log.warn |
| `handle:is_alive()` after destroy | — | return false |

**Partial-success principle:** the spawner is best-effort across the bundle. If 9 groups spawn and one fails, you get a handle with 9 groups + a logged error about the 10th. The handle's `get_*` methods reflect what's actually there.

## Decisions made during spec-writing

These are points where the conversation didn't fully nail an answer, or where implementation reality required a small judgement call. Recorded so they're easy to find and revisit.

- **Serializer reuse.** `framework/prefab.lua`'s `save()` needs the same Lua-table-to-Lua-chunk serializer as the hello-world mod (`tools/me-mod/lua/dcs_sms_me/serializer.lua`). Two options: (a) duplicate the serializer into `framework/utils_serialize.lua` (pure code, no DCS deps); (b) have `framework/` and `tools/me-mod/` both depend on a shared source location. We pick **(a) — duplicate** for v1: the file is ~100 lines, the duplication is one-time, the framework gains a public `sms.utils.serialize` symbol that's useful for other things (saving runtime state, debugging), and the alternative requires resolving `tools/` ↔ `framework/` cross-tree dependencies that don't exist anywhere else in the project. Long-term, the canonical home is `framework/utils_serialize.lua` and `tools/me-mod/lua/dcs_sms_me/serializer.lua` becomes a copy that's verified against it in CI.
- **Statics partition during distill.** The hello-world dump puts statics inside `groups` because the ME models them as single-unit groups. The distill function splits them out by inspecting each entry: if the entry's `units[1].type` resolves to a static-category type (via `sms.K.statics` lookup) OR if the entry has fields like `dead` and `category` at top level (static-only fields), it's classified as a static; otherwise as a group. The split lives in distill; the prefab file's `groups` and `statics` arrays are clean.
- **Country capture.** `Mission.getGroup` returns groups with `boss → country → id`. Distill walks `boss.country.id` once per group before stripping `boss`, then writes `country` directly on the group entry (and propagates to each unit if not already present). This is the only enrichment the distill step does on top of strip-and-anchor.
- **`name_prefix` opt** — kept for v1. Useful for "spawn the same prefab twice with different display names". One line of code; carries its weight.
- **`keep_position` opt** — kept (matches MOOSE behavior). When true, `opts.anchor` and `opts.rotation` are ignored; spawn happens at `meta.world_anchor` with rotation 0.
- **Drawings realized via `trigger.action.markup*`**, zones data-only. Asymmetry is real (DCS has no zone-creation API) and explicit in the spec.
- **No cross-reference rewriting.** Names preserved verbatim. Same-prefab-twice contamination is a known limitation; revisit in v2 if real users hit it.
- **No sandboxed loading in v1.** `dofile()` is used. Documented as a known risk for community sharing of prefab files; sandboxing lands before the project encourages such sharing.
- **Random pools deferred to v2.** Format leaves room (e.g., a future `meta.random_pools` block) but v1 doesn't reserve any specific shape — designing the random mechanism is itself a brainstorm.
- **Default prefab dir.** `Saved Games\DCS\dcs-sms\prefabs\`. Created lazily on first save. Documented but not hard-required — `load(path)` takes any path.
- **Filename ↔ name correspondence.** Recommended convention `<name>.lua`. Not enforced; the registry keys off `meta.name` from the file content, not the filename.
- **Spec/plan AGENTS.md sync.** This spec adds a public `sms.prefab` module; `AGENTS.md` §7 module index gets a new line. `docs/api/prefab.md` is created with worked examples.

## Testing

Two distinct test surfaces.

### `prefab_distill.lua` — pure-Lua unit tests

`framework/test/test_prefab_distill.lua` driven by `framework/test/run_distill_tests.ps1`. Standalone Lua 5.1, no DCS. Runs in CI.

Fixture: a captured selection dump copied into `framework/test/fixtures/dump_single_aerial.lua` (the user's 60 KB single-A-10C dump) plus small synthetic dumps inline in the test file for math-checking cases.

Cases:

1. `boss` is gone everywhere in the output (recursive scan for the key).
2. No cycles in the output (visited-set scan).
3. Centroid math: synthetic dump with three groups at known positions → centroid is the mean → output coords are anchor-relative.
4. Headings rad → deg conversion at every depth (group, unit, static).
5. Country captured: synthetic dump's `boss.country.id = 11` (Belgium) → output entity has `country = 11` and no `boss`.
6. Static fidelity: synthetic static with `livery_id`, `shape_name`, `dead`, `category` round-trips with anchor-relative coords.
7. Zone fidelity: circle and quad zones round-trip with anchor-relative center, `properties` preserved verbatim.
8. Drawing fidelity: polygon drawing with multiple vertices round-trips with each vertex anchor-relative.
9. Empty input → nil + warn.
10. Real-world dump fixture loads end-to-end: `meta.world_anchor` populated, `groups[1].units[1].callsign.name == "Enfield11"`, payload preserved.
11. Statics-vs-groups partition: synthetic dump containing both → output `groups` has only real groups, `statics` has the rest.

### `prefab.lua` — smoke tests via the bridge

`framework/test/smoke_prefab.ps1`. Driven by `tools/dcs-sms.exe exec` against a running DCS, same harness as the rest of the smokes. Manual only; not in CI.

Cases:

1. Load a fixture prefab; verify it appears in `sms.prefab.list()`.
2. Spawn at a known anchor; verify position math (group at relative `(100, 0)` ends up at `anchor + (100, 0)`).
3. Spawn a second instance; verify name auto-suffix (`"Aerial-1-1"` exists alongside `"Aerial-1"`).
4. Country override: spawn with `opts.country = sms.K.countries.RUSSIA`; verify spawned coalition is red.
5. Rotation: spawn with `opts.rotation = 90`; verify a unit at `(100, 0)` ends up at `(0, 100)` relative to anchor.
6. `keep_position = true`: verify spawn at `meta.world_anchor`, not `opts.anchor`.
7. Destroy: `h:destroy()`; verify `Group.getByName(...)` returns nil for every spawned group, drawing marks gone, `h:is_alive() == false`.
8. Idempotent destroy: second call no-ops without error.
9. Partial success: fixture with one valid + one invalid group → handle has the valid one, log shows the error for the invalid one.
10. `destroy_all(name)`: spawn 3 of one prefab + 2 of another, destroy all of one → only those 3 are gone.

## Cross-cutting commitments

- **Updates `AGENTS.md` §7 module index?** Yes — adds one line for `sms.prefab`. Per CLAUDE.md sync rule, lands in same change-set as the implementation.
- **Updates `docs/api/`?** Yes — new `docs/api/prefab.md` with signatures, options tables, runnable examples, see-also.
- **Adds smoke tests?** Yes — both unit (`framework/test/test_prefab_distill.lua` + driver) and smoke (`framework/test/smoke_prefab.ps1`).
- **Adds CLI subcommands?** No — the distill function is callable from the bridge directly (`dcs-sms exec`), and Sub-project 3 will add a "Save selection as prefab" ME button later.
- **Updates `framework/load_all.lua`?** Yes — appends `prefab_distill.lua` and `prefab.lua` to the modules list.
