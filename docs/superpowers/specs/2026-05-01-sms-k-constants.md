# sms.K constants consolidation

> **Status:** spec, ready to plan.

## Goal

Collapse every enum-shaped public `sms.*` table (countries, skill, alt_type, waypoint, units, statics, targets, designations, options' enum sub-tables) into a single `sms.constants` module exposed under the short alias `sms.K`. New constants for previously-raw strings (coalition, category) come along for the ride. After this lands there is exactly one place to look for any "what string does DCS expect here" question.

## User value

- **One namespace to learn**: `sms.K.<thing>` instead of remembering whether countries is plural, skill is singular, waypoint is nested, or coalition / category are not catalogued at all.
- **Discoverable via autocomplete**: typing `sms.K.` lists every top-level constant table; one more dot lists every member. Editor surfaces the whole catalog without reading docs.
- **Magic strings disappear from the codebase**: docs, examples, framework internals, AGENTS.md prose, smoke tests — all mission-author-facing string literals that have a constant become `sms.K.<...>` references. A future refactor that renames a value can grep for the constant and miss nothing.
- **Smaller mental model**: today's index in AGENTS.md §7 has eight separate enum-shaped rows (countries / skill / alt_type / waypoint / units / statics / targets / designations) plus enum tables on `sms.options`. After this change there is a single `sms.K` row that points at one reference page.

## Scope

### In

- Create `framework/constants.lua` as the entry point and `framework/constants/` as the directory where each topic-file lives. Entry point requires (`dofile`s) every topic file and ends with `sms.K = sms.constants`.
- Delete the standalone modules that exist only to hold these tables: `framework/countries.lua`, `framework/skill.lua`, `framework/alt_type.lua`, `framework/waypoint.lua`, `framework/targets.lua`, `framework/designations.lua`. The runtime tables move to `framework/constants/<topic>.lua`. **No backward-compat aliases** — `sms.countries`, `sms.skill`, `sms.alt_type`, `sms.waypoint`, `sms.targets`, `sms.designations` cease to exist on the public surface.
- Move the auto-generated catalogs `framework/units.lua` and `framework/statics.lua` to `framework/constants/units.lua` and `framework/constants/statics.lua`. Update the generators in `tools/` to write to the new paths and assign into `sms.constants.units` / `sms.constants.statics`. The `origin_of` helpers move with their catalogs and are accessible as `sms.K.units.origin_of(...)` / `sms.K.statics.origin_of(...)`.
- Move every enum *table* (not the builder functions) off `sms.options` and onto `sms.K`: `sms.options.ROE` → `sms.K.roe`, `sms.options.REACTION_ON_THREAT` → `sms.K.reaction_on_threat`, `sms.options.RADAR_USING` → `sms.K.radar_using`, `sms.options.FLARE_USING` → `sms.K.flare_using`, `sms.options.ALARM_STATE` → `sms.K.alarm_state`, `sms.options.FORMATION` → `sms.K.formation`. The builder functions (`sms.options.roe(...)`, `sms.options.alarm_state(...)`, etc.) stay on `sms.options`.
- Add new enums for previously-raw wire-format strings:
  - `sms.K.coalition` — `RED = "red"`, `BLUE = "blue"`, `NEUTRAL = "neutral"`.
  - `sms.K.category` — `AIRPLANE = "airplane"`, `HELICOPTER = "helicopter"`, `GROUND = "ground"`, `SHIP = "ship"`, `TRAIN = "train"`.
- Update `framework/load_all.lua` to load `constants.lua` (which brings in the whole `framework/constants/` tree) immediately after `utils.lua`. Update the bridge's `net.dostring_in` load order to match.
- Sweep framework internal raw-string usages of constants now under `sms.K`:
  - `framework/group.lua` line 395 — `start.alt_type = "BARO"` → `sms.K.alt_type.BARO`.
  - `framework/group_spawn.lua` lines 174 & 214 — same `"BARO"` swap.
  - Anywhere category strings, coalition strings, ROE / alarm-state / formation values are compared or emitted as raw literals — switch to `sms.K.*`.
  - Update `---@field` annotations on internal types (`sms.group.unit_spec.skill`, `.alt_type`, etc.) to point at the new alias names where they moved.
- Sweep mission-author-facing example code:
  - Every Lua snippet in `docs/api/*.md` (especially `examples.md`, `group.md`, `static.md`, `units.md`, `statics.md`, `task.md`, `commands.md`, `options.md`, `events.md`, `utils.md`).
  - Every example block in `AGENTS.md`.
  - Every smoke test under `framework/test/*.sh` that contains Lua chunks (`smoke_*.sh` files have raw-string `country = "USA"`, `category = "ground"`, `skill = "Average"`, `alt_type = "BARO"`).
- Replace the eight separate enum-module rows in `AGENTS.md` §7 with a single `sms.K` (`sms.constants`) row, pointing at `docs/api/constants.md`.
- Rewrite `docs/api/`:
  - **Delete**: `docs/api/countries.md`, `docs/api/skill.md`, `docs/api/alt_type.md`, `docs/api/waypoint.md`, `docs/api/targets.md` (if it exists as a separate page), `docs/api/designations.md` (ditto). Inspect first — some may already be folded into `docs/api/constants.md`.
  - **Repurpose / create**: `docs/api/constants.md` becomes the single reference page covering every `sms.K.*` table, organized by topic (`sms.K.coalition`, `sms.K.category`, `sms.K.countries`, `sms.K.skill`, `sms.K.alt_type`, `sms.K.waypoint.type`, `sms.K.waypoint.action`, `sms.K.units`, `sms.K.statics`, `sms.K.targets`, `sms.K.designations`, `sms.K.roe`, `sms.K.alarm_state`, `sms.K.reaction_on_threat`, `sms.K.radar_using`, `sms.K.flare_using`, `sms.K.formation`).
  - **Keep but rewrite**: `docs/api/units.md` and `docs/api/statics.md` (the catalog overviews — describe the nested-category navigation pattern; the source-of-truth is now `sms.K.units` / `sms.K.statics`).
  - **Update README**: `docs/api/README.md`'s module-index table replaces the per-module rows with a single `constants.md` row.
- Rewrite `AGENTS.md` §4 conventions table:
  - The "Coalition strings" / "Categories" rows currently document the wire format as lowercase strings. Reframe them to describe the wire format briefly (one-clause "DCS reads lowercase strings on the wire") and point readers at `sms.K.coalition.*` / `sms.K.category.*` for authoring code. The wire-format strings still appear so the reader can debug what shows up in `dcs.log` — but the "use this in your code" form is the constant.
- Update LuaCATS aliases — they continue to live in `framework/constants/<topic>.lua` next to their runtime tables. The alias names stay top-level (`sms.Country`, `sms.Skill`, `sms.AltType`, `sms.WaypointType`, `sms.WaypointAction`, `sms.GroupSpawnType`); call sites that today annotate `sms.group.unit_spec.skill` as `sms.Skill|string` are unchanged.
- Add new aliases for the new enums: `sms.Coalition` (`"red"|"blue"|"neutral"`), `sms.Category` (`"airplane"|"helicopter"|"ground"|"ship"|"train"`).
- Smoke tests: extend `framework/test/smoke.sh` (or add a `smoke_constants.sh`) with an identity-style assertion sweep — for every flat enum, assert `sms.K.<topic>.<KEY> == "<expected DCS string>"` for at least one representative key per table; for the nested ones (`waypoint.type`, `waypoint.action`, `units.air_defence.aaa`, `statics.cargos`, etc.) assert one representative leaf per top-level category. The drift check from `framework/countries.lua` (walks `country.id` at load time and warns on unknown keys) survives — it moves into `framework/constants/countries.lua` unchanged.

### Out

- **No alias for the old module names.** `sms.countries.USA` returning anything is out of scope. Mission scripts that reference the old surface need to be updated by the user; the framework itself is the only consumer in this repo and we update it as part of the change.
- **No renaming of underlying DCS string values.** The wire-format strings stay verbatim — `"airplane"` is still lowercase, `"Turning Point"` still has the space, `"LandingReFuAr"` still has the typo. Only the *access pattern* in author-facing code changes.
- **No restructuring of the `units` / `statics` category trees.** They keep the existing `sms.units.<category>.<subcategory>.<key>` layout under `sms.K.units.*`. The auto-generators preserve the same shape; only the table name they emit changes.
- **No new module-level functionality.** `sms.K.units.origin_of(...)` exists because `sms.units.origin_of(...)` exists today — we move it, we don't redesign it. Anything beyond a verbatim move of existing helpers is a follow-up.
- **No general "magic-string sweep" beyond the constants we're introducing.** Strings like `"is_alive"` (event names), `"airplane"` (already covered by `sms.K.category`), waypoint task IDs, etc. — only sweep the strings that have a constant after this change. If a string is part of, say, the Lua-side payload `_sms_verb` field, it stays verbatim; that field is internal to the framework's apply machinery, not a wire-format value the user sets.
- **No re-export at top-level for ergonomics.** We don't add `sms.units = sms.K.units` shortcuts. The whole point is one access path. Mission scripts use `sms.K.units.<...>`; if a script wants to bind a local for brevity (`local U = sms.K.units`) that's idiomatic Lua.
- **No change to `sms.options` builder signatures.** `sms.options.roe("weapon_free")` continues to take a string and accept either a `sms.K.roe.WEAPON_FREE` constant or a literal string. The validation behavior (per-category dispatch) is unchanged. Only the *enum tables* move; the *builder functions* keep their current shape.

## Constraints

- **Lua 5.1.** No `goto`, no integer division operator, no bitops module — match what the rest of `framework/` does.
- **DCS mission environment.** No `os` / `io` / `lfs`. Logging via `sms.log.module(...)`. The constants modules don't perform I/O.
- **`framework/load_all.lua` already drives module load order via `dofile`.** The bridge also loads them via `net.dostring_in` in a hard-coded order — see `tools/lua/dcs-sms-hook.lua` and any wrapper script. Both must update to the new layout. `constants.lua` loads after `log.lua` and `utils.lua` (the drift check on `country.id` doesn't need utils, but utils is small and ordering after it is harmless).
- **Idempotent on reload.** Every constants file follows the existing pattern: `sms.constants = sms.constants or {}` / `sms.constants.<topic> = sms.constants.<topic> or {}` so re-running `load_all.lua` after edits doesn't blow up.
- **Failure model: log + nil, never throw.** The drift check in `countries.lua` already follows this; `origin_of` does too. New code preserves this.
- **AGENTS.md sync rule (CLAUDE.md).** Every plan that adds, removes, or renames public `sms.*` surface must update AGENTS.md §7 in the same change-set. This refactor removes eight module rows and adds one — explicit task in the plan.
- **`docs/api/` sync rule.** Same — per-page reference for the new `sms.K` surface lands in this PR.

## Decisions

**D1. Single namespace `sms.K` (alias for `sms.constants`).** Both names work; `sms.K` is the documented shorthand. Internal framework code uses `sms.K` for brevity. Docs and examples use `sms.K`. AGENTS.md mentions `sms.constants` once as "the long form" so a reader who notices the alias has a pointer.

**D2. Drop the standalone `sms.countries` / `sms.skill` / `sms.alt_type` / `sms.waypoint` / `sms.targets` / `sms.designations` modules entirely. No aliases.** The user's mission scripts may break — that's the explicit price. The framework's own usages move in this PR.

**D3. File structure: split-internally, single-namespace.** `framework/constants.lua` is a thin entry point that `dofile`s every file in `framework/constants/`. Each topic-file assigns into `sms.constants.<topic>`. The catalog files (`units.lua`, `statics.lua`) keep their auto-generated banner and stay self-contained. Editors load each file at its real size; users only ever see `sms.K`.

**D4. Topic-file list (all under `framework/constants/`):**
- `coalition.lua` (new)
- `category.lua` (new)
- `countries.lua` (moved; keeps the `country.id` drift check)
- `skill.lua` (moved)
- `alt_type.lua` (moved)
- `waypoint.lua` (moved; nested `sms.K.waypoint.type` + `sms.K.waypoint.action` — lowercase namespace, UPPER keys at leaf)
- `targets.lua` (moved)
- `designations.lua` (moved)
- `roe.lua` (moved from `sms.options.ROE`)
- `alarm_state.lua` (moved from `sms.options.ALARM_STATE`)
- `reaction_on_threat.lua` (moved from `sms.options.REACTION_ON_THREAT`)
- `radar_using.lua` (moved from `sms.options.RADAR_USING`)
- `flare_using.lua` (moved from `sms.options.FLARE_USING`)
- `formation.lua` (moved from `sms.options.FORMATION`)
- `units.lua` (moved + auto-generator path updated)
- `statics.lua` (moved + auto-generator path updated)

**D5. Naming convention under `sms.K`:**
- Topic namespace: lowercase, snake_case (`sms.K.alt_type`, `sms.K.alarm_state`, `sms.K.reaction_on_threat`).
- Topic namespace plural vs singular: keep what the source module already used (`sms.K.countries`, `sms.K.targets`, `sms.K.designations`, `sms.K.units`, `sms.K.statics` are plural; `sms.K.skill`, `sms.K.alt_type`, `sms.K.waypoint`, `sms.K.coalition`, `sms.K.category`, `sms.K.roe`, `sms.K.alarm_state`, `sms.K.formation`, `sms.K.reaction_on_threat`, `sms.K.radar_using`, `sms.K.flare_using` are singular). Picking based on existing usage avoids breaking the established muscle memory wherever it survives.
- Leaf keys: UPPER_SNAKE for flat enums (`sms.K.skill.AVERAGE`, `sms.K.alt_type.BARO`, `sms.K.coalition.BLUE`, `sms.K.formation.LINE_ABREAST`).
- Sub-namespaces inside a topic: lowercase (`sms.K.waypoint.type.TURNING_POINT`, `sms.K.units.armor.apc.AAV7`). UPPER for the leaf key, lowercase for navigation.

This means the move from `sms.waypoint.TYPE.TURNING_POINT` → `sms.K.waypoint.type.TURNING_POINT` is a case change on the middle segment. Same for `sms.options.ROE.WEAPON_FREE` → `sms.K.roe.WEAPON_FREE` (the table name becomes lowercase).

**D6. `sms.K.units.origin_of` and `sms.K.statics.origin_of`.** The helpers move with their catalogs as plain function members of the catalog table. Today's `sms.units.origin_of(...)` users call `sms.K.units.origin_of(...)` post-refactor. Same for statics. Auto-generator emits the helper with the catalog tables — no separate file.

**D7. Drift check on `country.id`.** Survives the move. `framework/constants/countries.lua` retains the bottom-of-file walk over `country.id` and the `log.warn` on unknown keys. The runtime-added entries land on `sms.K.countries`. No behavior change.

**D8. LuaCATS aliases.** Stay top-level (`sms.Country`, `sms.Skill`, `sms.AltType`, `sms.WaypointType`, `sms.WaypointAction`, `sms.GroupSpawnType`). New: `sms.Coalition`, `sms.Category`. Each alias declaration lives at the top of its corresponding `framework/constants/<topic>.lua` file. Call sites (`---@field skill sms.Skill|string`) are unchanged — the alias name didn't move.

**D9. AGENTS.md §4 conventions table.** Keep the table; rewrite the "Coalition strings" and "Categories" rows so the *Convention* column reads roughly:
> Lowercase strings on the wire (`"red"`, `"blue"`, `"neutral"`); use `sms.K.coalition.*` in code.

This preserves the wire-format reference (essential for debugging `dcs.log`) and points authoring readers at the constant. Same shape for categories. The "Coordinates / Headings / Altitudes / Naming / Auto-suffix / Log tags" rows are unchanged — they don't have constants.

**D10. AGENTS.md §7 module index.** Replace the eight enum-module rows (`sms.units`, `sms.statics`, `sms.countries`, `sms.skill`, `sms.alt_type`, `sms.waypoint`, `sms.targets`, `sms.designations`) with a single `sms.constants` (alias `sms.K`) row pointing at `docs/api/constants.md` and summarizing as: "Single namespace for every DCS enum / catalog / wire-format constant. `sms.K` is the alias."

**D11. Smoke-test sweep.** `framework/test/smoke.sh` already does identity assertions for the existing flat enums (`sms.countries.USA == "USA"`, `sms.skill.AVERAGE == "Average"`, etc.). Update those to assert against `sms.K.*`. Add at least one representative leaf for the new enums (`sms.K.coalition.BLUE == "blue"`, `sms.K.category.AIRPLANE == "airplane"`, `sms.K.roe.WEAPON_FREE == "weapon_free"`, `sms.K.alarm_state.RED == "red"`, `sms.K.formation.WEDGE == "wedge"`). Smoke tests for individual modules (`smoke_group.sh`, `smoke_unit.sh`, `smoke_events.sh`, `smoke_static.sh`, `smoke_weapon.sh`, `smoke_spawn.sh`) get their raw-string `country = "USA"` / `category = "ground"` / `skill = "Average"` / `alt_type = "BARO"` Lua chunks updated to `sms.K.*` form so the smoke suite itself models idiomatic usage.

**D12. AGENTS.md §4 wire-format tone.** When a doc page or AGENTS.md prose is *describing the protocol with DCS* (what string lands on the wire, what `dcs.log` will show, what raw value DCS expects from a non-framework script that's interoperating), the literal string is acceptable and clearer than the constant. When the same page or paragraph is *showing how a mission author writes code*, use the constant. The plan tasks call out specific files; the implementer applies this distinction.

**D13. `tools/` generator updates.** The `dcs-sms gen-units` and `dcs-sms gen-statics` commands today write to `framework/units.lua` / `framework/statics.lua` and emit `sms.units = sms.units or {}` / `sms.statics = sms.statics or {}` as the table prelude. After this refactor they write to `framework/constants/units.lua` / `framework/constants/statics.lua` and emit `sms.constants.units = sms.constants.units or {}` / `sms.constants.statics = sms.constants.statics or {}`. Files have a "do not edit by hand" banner that survives unchanged. The generator code lives in Go under `tools/cmd/gen-units/` (or similar — confirm during implementation); the Go-side string templates need the new path and table-prelude.

**D14. Task ordering for parallelism.** The first task creates `framework/constants.lua` + `framework/constants/` directory with a *minimal* implementation (just the entry point and the alias). After that lands and load_all.lua loads it, every subsequent topic-file move is independent: a subagent can move `countries.lua` while another moves `skill.lua` while another moves the option enum tables. The framework-internal sweep, doc sweep, smoke-test sweep, and `tools/` generator update can also run in parallel after the foundation is in place. Final tasks (delete the old files, update load_all.lua and the bridge load order, update AGENTS.md §7) serialize at the end.

**D15. Single doc page or split?** One page: `docs/api/constants.md`. The page is long but easily skimmable because each topic gets its own H2 with a small table of leaf values. Split-by-topic would re-create the very fragmentation we're collapsing. The README module-index points only at `constants.md`.

**D16. `sms.K` vs `sms.constants` precedence in code.** In framework internals, prefer `sms.K` (matches how mission authors will read the framework). In the constants files themselves, write `sms.constants.<topic>.<KEY> = "..."` because that *is* the assignment target — `sms.K = sms.constants` aliasing happens in `constants.lua` after the topic files have populated the table. Exception: declarations that need the alias bound first (`local K = sms.K` for brevity in a long internal sweep) are fine.

**D17. Backwards-compat shim during the in-flight refactor.** None. The plan tasks must move the runtime tables, the framework-internal usages, and the doc sweep together so each commit leaves the framework loadable and the smoke suite green. Subagent task ordering enforces this.

## Open questions

None at the time of writing. If any surface during implementation, the implementer pauses and asks.
