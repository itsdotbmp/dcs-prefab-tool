## ME Prefab Manager — Design

**Date:** 2026-05-03
**Status:** Approved (brainstorm phase)
**Scope:** Third and final sub-project of the prefab/objective track. Turns the existing ME hello-world mod into a full Prefab Manager: save selection as prefab, place prefab into the open mission at design-time (map-click or original-coords), library browser, narrow undo, Tools-menu integration. Sub-project 3 of 3.

## Goal

Ship the user-facing ME workflow that closes the prefab loop end-to-end. After Sub-project 2 (hello-world dump button) and Sub-project 1 (`sms.prefab` runtime), this sub-project gives users a single window inside the Mission Editor where they can:

1. Save the current ME selection as a portable prefab file.
2. Place a saved prefab back into the open mission at design-time so it appears in the ME and gets persisted to `.miz`.
3. Browse the library of saved prefabs (sorted, with metadata, with rename/delete).
4. Open and close the Manager via a Tools-menu entry rather than always-on launch.
5. Undo their last place operation (narrow scope — see Decisions).

The deliverable is the ME mod rewrite + a ME-side parity-tested copy of the framework's distill/serialize code + the parity-test harness. The framework runtime (`sms.prefab`) is unchanged; this sub-project does not touch the mission Lua state.

## User value

The user's mental model for prefabs (verbatim from the brainstorm): *"Build a thing once in the ME — a FARP, a SAM site, a convoy with waypoints + ROE + payloads + Lua scripts at waypoints — save it as a prefab, then drop copies of it anywhere on any map."*

Sub-project 1 delivered the runtime spawn half of that loop. This sub-project delivers the design-time half — the part the user actually clicks. Without this, prefab files have to be created either by hand-writing them or by manually invoking `sms.prefab.distill(...)` against a hello-world dump file in a running mission. Both options work but neither is the workflow.

The "Place at original location" mode (using `meta.world_anchor` directly) supports a second mental model the user surfaced during brainstorm: prefabs that integrate with map-fixed features. *"I might build something around buildings on the map. The prefab only works on that exact location since it works with the map objects."* For those, restoring the prefab where it was originally captured is the only correct operation.

## Non-goals

- Broad ME-wide undo/redo. Tracked separately in [issue #25](https://github.com/nielsvaes/dcs-sms/issues/25). The narrow undo here covers only place operations launched from this window.
- Footprint-preview cursor during place-pending mode. Documented as v2 stretch goal.
- Persistent window position across ME sessions. Position resets when ME restarts.
- Library operations beyond rename/delete (no Duplicate, no source-dump-on-hover, no recent-first sort).
- Trigger-system integration (the prefab format already excludes mission flags / triggers / conditions per Sub-project 1 spec).
- Any change to the framework runtime — `sms.prefab.spawn` and friends stay exactly as merged.
- Coordinate-entry placement mode. Map-click and place-at-original cover the use cases.

## Context

This sub-project is the third of three:

- **Sub-project 2 (done, on `main`):** ME hello world. Custom dxgui window with one "Print selection" button that dumps verbatim ME selection data to `Saved Games\DCS\dcs-sms\me\selection-*.lua`. Source: `tools/me-mod/lua/dcs_sms_me/`.
- **Sub-project 1 (done, on `main`):** `sms.prefab` framework module. Distills dumps into prefabs, loads them into a registry, spawns instances at runtime. Source: `framework/prefab.lua`, `framework/prefab_distill.lua`, `framework/utils_serialize.lua`.
- **Sub-project 3 (this spec):** Replaces the hello-world button with the full Prefab Manager. Bridges the GUI Lua state (where ME selection lives) and the on-disk prefab format (which the framework runtime can already consume).

## Architecture

### The two-VM constraint (load-bearing)

The ME mod runs in DCS's GUI Lua state. The framework's `sms.prefab` runs in the mission Lua state. They are separate Lua VMs with no shared memory. "Save selection as prefab" needs to distill at click time, in the GUI VM — otherwise the file the user just saved isn't a prefab, it's a raw dump that requires a second mission-side step. So the distill and serialize code must exist in *both* VMs as parallel copies.

```
┌─────────────────────────────────────────────────────────────────────┐
│  DCS GUI Lua state (Mission Editor)                                 │
│                                                                     │
│  tools/me-mod/lua/dcs_sms_me/                                       │
│    ├── init.lua          — Tools-menu entry registration           │
│    ├── window.lua        — Prefab Manager (one window, all panels) │
│    ├── selection.lua     — (existing) read user's ME selection     │
│    ├── prefab_distill.lua — NEW, lifted from framework/             │
│    ├── serializer.lua    — (existing) Lua-table → Lua-chunk         │
│    ├── prefab_ops.lua    — NEW, save / load / place                 │
│    ├── undo.lua          — NEW, "last place" reversal               │
│    ├── menu.lua          — NEW, Tools-menu hook                     │
│    └── paths.lua         — (existing, extended for prefabs/ dir)    │
└──────────────┬──────────────────────────────────────────────────────┘
               │ writes / reads
               v
┌─────────────────────────────────────────────────────────────────────┐
│  Saved Games\DCS\dcs-sms\                                           │
│    ├── prefabs\<name>.lua       NEW — bundle files, registry-ready  │
│    └── me\selection-*.lua       (existing — the dump format)        │
└──────────────┬──────────────────────────────────────────────────────┘
               │ sms.prefab.load() at mission runtime
               v
┌─────────────────────────────────────────────────────────────────────┐
│  DCS mission Lua state (runtime)                                    │
│  framework/prefab.lua, prefab_distill.lua, utils_serialize.lua      │
│  — unchanged. The format is identical; both VMs produce/consume     │
│  the same on-disk file.                                             │
└─────────────────────────────────────────────────────────────────────┘
```

### Drift control

`framework/prefab_distill.lua` and `framework/utils_serialize.lua` are canonical. The me-mod copies (`tools/me-mod/lua/dcs_sms_me/prefab_distill.lua` and `serializer.lua`) are byte-identical mirrors. CI runs **parity tests** that load both copies into the same standalone Lua VM (under different module names), run all existing fixture cases through both, and assert byte-identical output. Drift on either side fails CI.

The `serializer.lua` parity case is essentially zero-cost — the file is already byte-identical between the two locations as of Sub-project 1's merge. The parity test just turns that property into an enforced invariant.

The `prefab_distill.lua` parity case is new: this sub-project introduces the me-mod copy.

### No bridge involvement

The Prefab Manager doesn't talk to the running mission. Saving and placing are entirely GUI-state operations against ME-internal mutation APIs. The mission runtime only enters the picture when the user *plays* a `.miz` that contains a placed prefab — at which point the prefab is just an ordinary group / static / zone / drawing in the mission file, not something dcs-sms-specific.

## Components

All paths under `tools/me-mod/lua/dcs_sms_me/` unless noted.

### `menu.lua` (NEW)

Registers a "DCS-SMS Prefab Manager" entry in the ME's Tools menu. Single public symbol `M.install()` called from `init.lua`.

```
M.install() -- registers the menu entry; returns true on success, false on fallback
```

The exact ME menu API symbol is TBD at implementation time — first try `MainWindow.getToolsMenu()` / `Menu.add()` family; if no Tools-menu API turns out to be exposed cleanly, fall back to a small floating "Open Prefab Manager" toggle button at a corner of the screen. Either way, the always-on hello-world window from Sub-project 2 goes away.

On entry click: `window.toggle()`.

### `window.lua` (heavily rewritten)

Replaces today's hello-world button entirely. Vertical layout, one window, all panels visible at once:

```
┌──────────────────────────────────────────────────────┐
│  dcs-sms — Prefab Manager                       × │  ← title bar (bg color shifts in place mode)
├──────────────────────────────────────────────────────┤
│  Save current selection                              │
│  Name: [______________________]   [ Save ]           │
├──────────────────────────────────────────────────────┤
│  Prefabs (3)                              ↻ Reload  │
│  ┌────────────────────────────────────────────────┐ │
│  │ farp_alpha       Caucasus · 4g 2s    (selected)│ │
│  │ sam_site_sa6     Caucasus · 1g 3s              │ │
│  │ convoy_trucks    Syria    · 2g 0s              │ │
│  └────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────┤
│  Rotation: [ 0 ]°                                    │
│  [Place at click] [Place at original]                │
│  [Rename] [Delete] [Undo last place]                 │
├──────────────────────────────────────────────────────┤
│  Status: Ready.                                      │
└──────────────────────────────────────────────────────┘
```

Public surface:
```
M.toggle()         -- show if hidden, hide if shown
M.show()           -- idempotent
M.hide()           -- idempotent
```

Internal state machine: **idle** ↔ **place-pending**. Clicking "Place at click" enters place-pending: title bar text changes to "Click on map to place `<name>` (Esc to cancel)", title-bar background color shifts (e.g., to a blue tint), the "Place at click" button is replaced with a "Cancel" button. Receiving a map click, Esc, or the Cancel button returns to idle.

All callbacks (button clicks, keyboard handlers, map-click handler, library-row selection) are at the top of a `pcall` — same containment invariant as Sub-project 2. No code path inside the window may bubble an error to the ME.

Keyboard hook for Ctrl-Z routes to `undo.undo()` only when this window has focus — see `undo.lua` below.

### `prefab_distill.lua` (NEW, lifted from framework)

Byte-identical mirror of `framework/prefab_distill.lua`. Same public surface — `M.distill(dump_or_path, opts)`. Runnable in standalone Lua 5.1 (no DCS deps). Tested for byte-identical output against the framework copy via the parity-test harness.

### `serializer.lua` (existing)

Already byte-identical to `framework/utils_serialize.lua` as of Sub-project 1. Parity test extended in this sub-project to cover this pair too.

### `prefab_ops.lua` (NEW)

Three operation groups in one file (collapsed from earlier `save`/`load`/`place` per brainstorm decision).

**Save:**
```
M.save_selection(name) -> ok, path | nil, error_string
M.exists(name)         -> boolean
```

`save_selection` reads the current ME selection via `selection.snapshot()`, wraps it in the dump-envelope shape that distill expects, calls `prefab_distill.distill()`, calls `serializer.serialize()`, writes to `<saved-games>\dcs-sms\prefabs\<name>.lua`. Empty selection: returns `nil, "no selection"`. Distill returning nil: returns `nil, "<reason from distill>"`. `io.open` failure: returns `nil, "<OS error>"`. Otherwise overwrites unconditionally — collision-checking lives in the caller (window) so the user-facing flow can pop a modal first.

`exists(name)` returns true iff `<prefabs-dir>\<name>.lua` exists.

**Load / scan:**
```
M.scan_dir() -> array of {name, path, theatre, group_count, static_count, zone_count, drawing_count, source_dump?, error?}
M.load(path) -> prefab_table | nil, error_string
```

`scan_dir` recursively scans the prefabs dir for `*.lua`, `dofile`s each (per-file `pcall`), and returns one row per file. On per-file failure: row's `error` field is set, all data fields nil; the window greys it out in the list rather than dropping it silently.

**Place:**
```
M.place(prefab_table, opts) -> injection_record | nil, error_string
  opts = {
    anchor        = {x, y} | nil,         -- nil iff keep_position=true
    rotation      = number,                -- degrees, default 0
    keep_position = boolean,               -- ignore anchor, use prefab.meta.world_anchor
  }
```

Returns an `injection_record` shape that `undo.lua` consumes:

```
injection_record = {
  prefab_name = string,
  groups      = array of { orig_name, runtime_id },
  statics     = array of { orig_name, runtime_id },
  zones       = array of { orig_name, runtime_id },
  drawings    = array of { orig_name, runtime_id },
  errors      = array of error strings,
}
```

Best-effort per entity: each group / static / zone / drawing is `pcall`-wrapped; failures append to `errors`, successes append to the matching array. If every entity fails, returns `nil` + summary (no record produced — no undo will be available for that place attempt). Otherwise returns the partial record + warning logged.

ME-internal mutation APIs targeted (exact symbols resolved at implementation time):
- Groups: `Mission.addGroup(country_id, category_id, group_table)` family; `Mission.removeGroup(id)` for inverse.
- Statics: `Mission.addStaticObject(country_id, static_table)` family; `Mission.removeStaticObject(id)` for inverse.
- Trigger zones: `TriggerZoneController.add(...)` or `Mission.addTriggerZone(...)` family; matching remove for inverse.
- Drawings: `panel_draw` add functions; matching remove for inverse.

Per the brainstorm decision, every entity type is in scope for v1. If any individual ME API turns out not to exist or behave differently than expected, that becomes a bug-fix iteration on this branch rather than a deferral.

Map-click capture for "Place at click": at implementation time, first try hooking a map-click event from `MapWindow` / `me_map_window`. If no such hook is exposed, fall back to a transparent dxgui overlay sized to the map area that captures the click and converts via the ME's screen→world coord helper (likely `MapWindow.screenToWorld(x, y)` or similar). The fallback is documented in the implementation; the spec does not commit to one approach.

### `undo.lua` (NEW)

Single-slot undo. Holds the most recent `injection_record`; older records are discarded.

```
M.record(injection_record) -- replaces the slot
M.undo() -> ok, error_string
M.has_record() -> boolean
M.clear()
```

`undo()` walks the slot's arrays and calls the matching ME remove API for each entry. Per-entity `pcall` — partial failure logs but doesn't abort the rest. Slot is cleared after undo regardless of partial errors (we tried).

Window's Ctrl-Z keyboard hook routes here when window is focused. Outside the window, Ctrl-Z is unaffected — broad undo is [issue #25](https://github.com/nielsvaes/dcs-sms/issues/25). Status label after undo: "Undid place of `<name>` (`<n_errors>` errors — see dcs.log)" or "Undid place of `<name>`" on clean success.

After a successful place, `record()` is called from inside `prefab_ops.place()` (or from the window callback after place returns — implementation detail). After successful undo, the slot is empty and Ctrl-Z is a no-op until the next place.

### `paths.lua` (existing, extended)

Adds:
```
M.PREFABS_DIR     = M.ROOT .. 'prefabs\\'
M.ensure_prefabs() -- mkdir -p
```

### `init.lua` (rewritten)

Replaces today's auto-show of the hello-world window with menu registration:

```lua
local ok, err = pcall(function()
    local menu = require('dcs_sms_me.menu')
    menu.install()
end)
if not ok then
    log.write('sms.me', log.ERROR, 'init failed: ' .. tostring(err))
end
```

The window is no longer constructed eagerly. It's constructed lazily on the first `M.show()`/`M.toggle()` call from the menu handler.

## Data flow

### Save selection as prefab

```
[user types name "farp_alpha", clicks Save]
  ↓
window.lua reads name from input field
  ↓
prefab_ops.exists("farp_alpha") → true
  ↓
window.lua: modal "Prefab 'farp_alpha' already exists. Overwrite / Rename / Cancel"
  ↓ (user picks Overwrite)
prefab_ops.save_selection("farp_alpha")
  ├── selection.snapshot()                          (existing me-mod code)
  ├── wrap in dump-envelope shape
  ├── prefab_distill.distill(dump, {name="farp_alpha"})
  ├── serializer.serialize(prefab)
  └── io.open(<saved-games>\dcs-sms\prefabs\farp_alpha.lua, 'w'):write(...)
  ↓
window.lua: prefab_ops.scan_dir() → refresh library list
  ↓
status label: "Saved farp_alpha (4 groups, 2 statics)"
```

### Place at click

```
[user selects "farp_alpha" in library, sets rotation=45, clicks "Place at click"]
  ↓
window.lua: enter place-pending state
  - title bar bg → blue, text → "Click on map to place farp_alpha (Esc to cancel)"
  - "Place at click" button → "Cancel"
  - hook map-click + Esc handlers
  ↓
[user clicks at map screen pos (530, 412)]
  ↓
place handler: convert screen → world coords
  ↓
prefab_ops.load(<path>)  (cached after first load this session)
  ↓
prefab_ops.place(prefab, {anchor={x=mapX, y=mapY}, rotation=45})
  for each group:
    transform anchor-relative coords → world (rotate by 45°, add anchor)
    pcall Mission.addGroup(country, category, group_table)
    on success: append {orig_name, runtime_id} to record.groups
    on failure: append err to record.errors
  for each static / zone / drawing: same pattern
  ↓
undo.record(injection_record)
  ↓
window.lua: exit place-pending state, status: "Placed farp_alpha (4g 2s 1z 0d) at (12345, 67890)"
```

### Place at original location

Same flow as above but bypasses place-pending entirely. Click "Place at original" → `prefab_ops.place(prefab, {keep_position=true, rotation=<current_field_value>})` → same injection path. Anchor comes from `prefab.meta.world_anchor`. Useful for prefabs tied to map-fixed features (the "buildings" use case).

### Undo last place

```
[user presses Ctrl-Z (window focused), or clicks "Undo last place"]
  ↓
undo.undo()
  - read slot's injection_record
  - for each {_, runtime_id} in groups: pcall Mission.removeGroup(runtime_id)
  - for statics / zones / drawings: matching remove API
  - clear slot
  ↓
window.lua: status: "Undid place of farp_alpha"
```

### Rename / Delete

**Rename:** modal with text field pre-filled. On confirm: load the prefab file, rewrite `meta.name`, write to new path, delete old path. If any step fails, roll back (delete partial new file if it exists; keep original). Refresh list.

**Delete:** confirmation modal "Delete `<name>`? This cannot be undone." → `os.remove(path)` → refresh list. Failed remove logs and shows in status; list refreshes anyway.

## Failure model

Same framework rule: **log + nil + never throw**. Reinforced for the ME context: no code path may bubble a Lua error to the editor.

Logging tag: `sms.me.prefab` for the prefab-specific operations, alongside the existing `sms.me` tag for window/menu plumbing.

| Boundary | Failure | Behavior |
|---|---|---|
| `menu.install` — Tools menu API not found | `pcall` at module load; falls back to floating toggle button | Window still reachable. `ERROR` in `dcs.log`. |
| `window.show` — dxgui construction | `pcall` (existing pattern) | Window doesn't appear. `ERROR` logged. ME continues. |
| Any window callback | each handler at top of `pcall` | Status label: "Failed: …", `dcs.log` has detail. ME survives. |
| `prefab_ops.save_selection` — empty selection | early return `nil, "no selection"` | Status: "No selection — nothing to save", no file written, `WARNING` logged. |
| `prefab_ops.save_selection` — name collision | caller checks `exists()` first and pops modal | User picks Overwrite / Rename / Cancel; no silent overwrite. |
| `prefab_ops.save_selection` — distill returns nil | propagate error | Status: "Save failed: distill returned nil — see dcs.log", file not written. |
| `prefab_ops.save_selection` — `io.open` fails | propagate error | Same as above with OS error in `dcs.log`. |
| `prefab_ops.scan_dir` — dir missing | `ensure_prefabs()` first, then scan | Empty list. |
| `prefab_ops.scan_dir` — per-file load failure | row appears with `error` field set; greyed in UI | Bad file marked as unusable but rest of library works. |
| `prefab_ops.place` — anchor missing AND not keep_position | early return | Status: "Place failed: no anchor"; place-pending cancelled. |
| `prefab_ops.place` — per-entity ME API call raises | per-entity `pcall`; record stays partial | Success path produces handle with the entities that did inject; `errors` array holds failures. UI: "Placed N of M entities — see dcs.log". |
| `prefab_ops.place` — every entity fails | returns `nil` + error | Status: "Place failed for all entities — see dcs.log". No undo record. |
| Map-click hook fails to install | place-pending exits immediately on enter | Status: "Place at click unavailable — see dcs.log. Try Place at original or restart." |
| `undo.undo` — slot empty | no-op + WARNING | Status: "Nothing to undo." |
| `undo.undo` — per-entity remove raises | per-entity `pcall`, log + continue | Status: "Undid place of `<name>` (with N errors — see dcs.log)". Slot cleared regardless. |
| Rename — partial failure mid-rewrite | atomic-ish: write new, delete old; rollback on any step failure | Status: "Rename failed", original preserved. |
| Delete — `os.remove` fails | log error, leave file alone, refresh list anyway | Status: "Delete failed — see dcs.log". |

**Cross-coupling note:** the injection record is the *only* state shared between `place` and `undo`. If place returns a partial record, undo reverses exactly the entities that did inject — never more, never less. If place returns nil (all failed), no record is created, so there's nothing for undo to do.

**Explicitly NOT done** (consistent with Sub-project 2):
- No on-screen error dialogs. Status label + `dcs.log` carry all error info; modals are reserved for *decisions* (name collision, delete confirmation, rename input), not error reporting.
- No retries.
- No telemetry.

## Testing

Three test surfaces.

### Pure-Lua parity tests (CI)

`tools/me-mod/test/`. Driven by standalone Lua 5.1.

**`test_serializer_parity.lua`** — NEW. Loads `framework/utils_serialize.lua` and `tools/me-mod/lua/dcs_sms_me/serializer.lua` in the same VM under different module names. Runs all cases from `framework/test/test_utils_serialize.lua` through both. Asserts byte-identical output. Drift = build break.

**`test_distill_parity.lua`** — NEW. Same idea for distill. Loads both copies, runs all cases from `framework/test/test_prefab_distill.lua` through both, asserts deep-equal output. Includes the synthetic dump fixture `framework/test/fixtures/dump_synthetic_aerial.lua`.

These run on every PR via the existing PowerShell test driver pattern (`framework/test/run_distill_tests.ps1` style).

### Pure-Lua unit tests for new logic (CI)

**`test_prefab_ops.lua`** — NEW. Tests the parts of `prefab_ops.lua` that don't touch DCS APIs:
- `save_selection` envelope wrapping is correct shape (synthetic snapshot input).
- `scan_dir` row composition: builds the correct row record from a file (driven by a small fixture dir).
- `scan_dir` error handling: per-file `pcall`, error rows still appear in output.
- Coordinate transformation math for place: `(rel_x, rel_y) → world` matches expected for given anchor + rotation, parity with the framework's existing rotate logic.

The injection itself is not unit-testable (requires DCS); covered by manual smoke.

### Manual smoke checklist

`tools/me-mod/README.md` — release gate, runnable by hand against a fresh DCS install.

**Setup:**
1. Run `dcs-sms install-me-mod`. Open the ME. Verify Tools menu has "DCS-SMS Prefab Manager" entry. Verify window does NOT appear automatically.
2. Open Tools → "DCS-SMS Prefab Manager". Window appears. Verify all panels present and library list is empty (or shows existing prefabs from prior sessions).

**Save flow:**
3. Place one A-10C in the ME. Select it. Type "test_jet" in the name field. Click Save. Verify file at `Saved Games\DCS\dcs-sms\prefabs\test_jet.lua` and library refreshes to show it.
4. With nothing selected, click Save with name "empty". Status: "No selection — nothing to save". No file written.
5. With selection, click Save with name "test_jet" (collision). Modal: Overwrite / Rename / Cancel. Pick Cancel — no change. Pick Overwrite — file overwritten.
6. Multi-selection: select two groups + one trigger zone + one drawing. Save as "complex_test". Verify all four sections present in the saved file (open it, inspect).

**Place flow — at click:**
7. Library shows "test_jet" sorted A-Z. Select it, set rotation 0, click "Place at click". Verify title bar changes color, button text becomes "Cancel".
8. Click somewhere on the map. Verify A-10C appears at that location, status confirms placement, Ctrl-Z works to remove it.
9. Re-place "test_jet". Save the .miz, close the ME, reopen the .miz. Verify the placed group survived (no dcs-sms-specific state needed).
10. Place at click with rotation 90. Verify the group is rotated 90° from how it was saved.
11. Place at click then press Esc. Verify exit from place-pending, no entity injected.

**Place flow — at original:**
12. Save a prefab that includes a group near a specific map building. Click "Place at original". Verify it lands at the original `meta.world_anchor`, not at any clicked location.

**Best-effort partial-failure:**
13. Manually corrupt a prefab file to have one valid group + one group with a bogus DCS type. Place. Verify status: "Placed N of M entities — see dcs.log". Valid group is in the mission, corrupt one is in the errors log.

**Library:**
14. Save 3 prefabs with names a/m/z. Verify list is sorted A-Z.
15. Rename "m" to "middle". Verify file renamed AND `meta.name` updated inside (open the file).
16. Delete "middle". Confirmation modal. Confirm. Verify file gone, list refreshed.
17. Manually drop a malformed `.lua` into the prefabs dir. Click Reload. Verify it appears greyed out with an error indicator, doesn't break the list.

**Undo:**
18. Place a prefab. Press Ctrl-Z (window focused). Verify removal.
19. Press Ctrl-Z again. Status: "Nothing to undo".
20. Place. Switch focus to a different ME panel. Press Ctrl-Z. Verify nothing happens (window not focused — broad undo is issue #25).

**Cleanup:**
21. Run `dcs-sms uninstall-me-mod`. Verify everything removed.

CI runs only the parity + unit tests. Manual checklist is a release gate.

## Decisions

Choices recorded for reference. Most were made during the brainstorm; the rest are implementation-detail picks.

- **All four sub-features in scope.** Save + Place + Library + Tools-menu + narrow undo, one PR. User explicitly rejected scoping down. *("we're not half-assing this. A")*
- **Map-click placement is the v1 default**, with "Place at original location" as the parallel option for map-fixed prefabs. *("A. But we should also have the option to place the prefab on the coordinates its saved on.")*
- **Inline name field, modal warning on collision.** No auto-naming. Empty save name falls back to `prefab-<UTC-timestamp>.lua` with a warning logged.
- **One window with all features visible**, behind a single Tools-menu entry that toggles it.
- **Distill code duplicated into the ME mod with CI parity tests** as the drift control. Framework copy is canonical; me-mod copy is a byte-identical mirror. Same applies to `serializer.lua`.
- **All four entity types injected best-effort**, iterate to make each one work. Partial-success returns a partial record; failure of every entity returns nil.
- **Library v1 = sort A-Z + metadata in row + Reload button.** No Duplicate, no source-dump-on-hover. Skipped.
- **Place-mode feedback = title bar text + bg color change + cursor change** (cursor change "if dxgui makes it easy"; otherwise drop cursor and keep title-bar-only).
- **Footprint preview during place-pending** is a v2 stretch goal, not v1.
- **Narrow undo only.** Single-slot, only covers operations launched from this window. Broad ME undo is [issue #25](https://github.com/nielsvaes/dcs-sms/issues/25).
- **Ctrl-Z is hooked when the window has focus.** Outside the window, Ctrl-Z is unaffected.
- **Single `prefab_ops.lua` file** rather than separate `save` / `load` / `place` modules. Three operation groups in one file, public API surface unchanged.
- **No persistent window position across ME sessions.** Position resets on ME restart; window remembers position across toggles within a single session.
- **Empty-save-name fallback is a logged warning, not a modal.** Reasoning: pop-up budget is reserved for collision and delete confirmation.
- **Reload button in v1 is included**, even though `scan_dir` is also called automatically after save/rename/delete. Useful when the user manually edits a file in the prefabs dir.
- **Branch:** `feat/me-prefab-manager`.

## Open implementation questions (not blockers)

These are items deferred to implementation rather than the spec. None block the brainstorm.

- Exact ME menu API symbol (`MainWindow.getToolsMenu` vs `Menu.add` vs another path). Resolution: read `MissionEditor/modules/` Lua source at impl start; commit to whichever symbol works; document the fallback path.
- Map-click capture mechanism. Resolution: try `MapWindow` event hook first, fall back to transparent dxgui overlay + screen→world helper. Spec commits to that ordering; impl resolves the rest.
- Exact ME mutation API symbols for `addGroup` / `removeGroup` / `addStaticObject` / `addTriggerZone` / `panel_draw add`. Resolution: Sub-project 2's selection code already finds groups and zones via `Mission.getGroup` and `TriggerZoneController.getTriggerZone` — the symmetric add functions are likely on the same modules. Impl reads source.
- Cursor-change API in dxgui. Resolution: spec allows dropping cursor change if the API isn't trivially exposed; title-bar feedback alone is sufficient.
- Whether to make the modals "real" dxgui modals or in-window overlay panels. Resolution: implementation decides based on what's cleanest; both are acceptable as long as Esc cancels and Enter confirms.

## Cross-cutting commitments

- **Updates `AGENTS.md` §7 module index?** No — this sub-project does not add a public `sms.*` module. Framework runtime is unchanged.
- **Updates `docs/api/`?** No — no public framework API changes.
- **Updates `tools/me-mod/README.md`?** Yes — manual smoke checklist replaced/extended for the new features; install/uninstall sections unchanged from Sub-project 2.
- **Adds parity tests?** Yes — `test_serializer_parity.lua` and `test_distill_parity.lua` plus driver scripts.
- **Adds unit tests?** Yes — `test_prefab_ops.lua`.
- **Adds CLI subcommands?** No — install/uninstall already exist from Sub-project 2.
- **Updates `framework/load_all.lua`?** No — framework runtime unchanged.

## Future work (post-v1)

Tracked here so it's easy to find when it comes time:

- Footprint preview during place-pending (v2).
- Library: Duplicate operation, source-dump-on-hover, recent-first sort, search/filter for large libraries.
- Multi-slot or stack-based undo for our own operations.
- Persistent window position + last-selected prefab across ME sessions.
- Broad ME-wide Ctrl-Z — separate sub-project 4, [issue #25](https://github.com/nielsvaes/dcs-sms/issues/25).
- Coordinate-entry placement mode (power-user / scripted workflows).
- Sandboxed loading of prefab files for community sharing (currently `dofile`-based; prefab files are arbitrary code).
