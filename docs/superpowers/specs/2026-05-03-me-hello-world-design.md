## Mission Editor Hello World — Design

**Date:** 2026-05-03
**Status:** Approved (brainstorm phase)
**Scope:** First sub-project of the Mission Editor mod track for `dcs-sms`. A minimal in-ME plugin that proves three primitives: (1) we can render a custom `dxgui` window inside the running Mission Editor, (2) we can read the user's current selection state, (3) we can write that state to a file on disk. Sub-project 2 of 3.

## Goal

Ship the smallest in-Mission-Editor mod that does something useful end-to-end:

1. A floating window appears inside the Mission Editor on launch.
2. The window has one button labelled "Print selection".
3. Clicking the button:
   - Reads whatever the user currently has selected in the ME (groups, statics, trigger zones, drawings, navigation points).
   - Writes the raw DCS-shaped tables to a `.lua` file under `Saved Games\DCS\dcs-sms\me\`.
   - Logs a one-line summary to `dcs.log`.
   - Updates an in-window status label with the same one-line summary.
4. Installs and uninstalls cleanly via either the `dcs-sms` CLI or an OvGME package.

The deliverable is the hello world only. Saving objectives, placing objectives back into the editor, runtime spawning, and a real Tools-menu integration are explicitly Sub-projects 1 and 3 and are out of scope here.

## Non-goals

- A real "save objective" feature. The dump is for inspection / proof of concept; the format is not yet the Sub-project 1 objective format.
- Coordinate normalization or anchor computation. The dump is verbatim DCS data.
- Sandboxed loading of dump files (these `.lua` files are arbitrary code; for this PoC the user only loads files they wrote themselves).
- Multi-DCS-version compatibility shims. Each DCS major version may need a small fix to `selection.lua`; this is accepted by design.
- Multi-language UI. Labels are English-only.
- A Tools-menu entry. The window is always-visible from ME launch (Sub-project 3 will move it behind a menu item).

## Context

This sub-project sits between two siblings:

- **Sub-project 1 — `sms.objective` (runtime spawn).** A new framework module that loads objective files (groups + statics + behavior bundled with an anchor) and respawns them at runtime. Successor to the user's MOOSE `OBJECTIVE_MANAGER`. Format will mirror raw DCS group/static tables. Designed and built in parallel; consumes the dump format this sub-project pioneers.
- **Sub-project 3 — Real ME features.** "Save selection as objective", "Place objective", an objective-library browser, Tools-menu integration. Builds on the foundation this sub-project lays.

The hello world's job is to derisk the in-ME plumbing so Sub-project 3 can focus on features.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  D:/Program Files/Eagle Dynamics/DCS World/                        │
│                                                                    │
│  MissionEditor/MissionEditor.lua    ← one-line patch:              │
│      ...existing ME bootstrap...      require('dcs_sms_me')        │
│                                                                    │
│  MissionEditor/modules/dcs_sms_me/  ← our mod (5 files)            │
│      ├── init.lua                                                  │
│      ├── window.lua                                                │
│      ├── selection.lua  ─────reads──> me_multiSelection,           │
│      │                                MapWindow, Mission, ...      │
│      ├── serializer.lua                                            │
│      └── paths.lua                                                 │
└────────────────────────────────────────────────────────────────────┘
                              │
                              │ writes
                              v
┌────────────────────────────────────────────────────────────────────┐
│  Saved Games/DCS/dcs-sms/        ← shared root with bridge         │
│      ├── inbox/   outbox/   state/   log/      (bridge subsystem)  │
│      └── me/                                   (this sub-project)  │
│          └── selection-2026-05-03T141728Z.lua                      │
└────────────────────────────────────────────────────────────────────┘
```

Lives entirely in the GUI Lua state. No bridge interaction, no socket, no external process. The hook environment and the ME environment are both unsandboxed and have full `lfs` / `io`, so the mod can do its own file I/O without going through `tools/`.

## Repo layout

New top-level directory `me-mod/`, mirroring how `tools/lua/` holds the hook script. Source of truth for the Lua lives under `lua/`; OvGME package is a build artifact mirrored from there.

```
me-mod/
├── README.md                        — install instructions (CLI + OvGME paths)
├── Makefile                         — sync lua/ → ovgme/.../modules/
├── lua/
│   └── dcs_sms_me/
│       ├── init.lua
│       ├── window.lua
│       ├── selection.lua
│       ├── serializer.lua
│       └── paths.lua
├── ovgme/
│   └── dcs-sms-me-mod/              — OvGME-ready package layout
│       └── MissionEditor/
│           ├── MissionEditor.lua    — patched copy for current DCS version
│           └── modules/
│               └── dcs_sms_me/      — synced from ../../../lua/dcs_sms_me/
└── test/
    ├── test_serializer.ps1          — driver
    └── test_serializer.lua          — unit cases
```

### Install model — both CLI and OvGME

**CLI (preferred):**

- `dcs-sms install-me-mod` — detects the DCS install dir (cached config or `--dcs-path` flag), then:
  1. Backs up `<DCS>/MissionEditor/MissionEditor.lua` → `MissionEditor.lua.dcs-sms.bak`. Refuses if a backup already exists (so re-running can't overwrite an earlier backup).
  2. Appends `require('dcs_sms_me')` to `MissionEditor.lua` (at EOF; exact placement to be confirmed during implementation by reading the file).
  3. Copies `me-mod/lua/dcs_sms_me/` → `<DCS>/MissionEditor/modules/dcs_sms_me/`.
  4. Idempotent: re-running upgrades the modules dir but does not re-patch `MissionEditor.lua` (detects the already-present `require` line).
- `dcs-sms uninstall-me-mod` — restores `MissionEditor.lua` from the backup and deletes the modules dir.

**OvGME (secondary path):**

- Ship `me-mod/ovgme/dcs-sms-me-mod/` as a standard mod folder. Includes a *patched copy* of `MissionEditor.lua` for the current DCS version.
- Documented as the second-class path: works, but goes stale across DCS versions. CLI is recommended.

The CLI patches the user's *current* `MissionEditor.lua` and so survives DCS minor patches that don't touch that file. OvGME ships a frozen copy that breaks the moment ED edits the file.

## Components

### `paths.lua`

Constants and dir helpers. Tiny.

```lua
local lfs = require('lfs')
local M = {}
M.ROOT       = lfs.writedir() .. 'dcs-sms\\'    -- shared with the bridge
M.OUTBOX_DIR = M.ROOT .. 'me\\'                 -- our subdir
M.LOG_TAG    = 'sms.me'

function M.ensure_outbox()
    lfs.mkdir(M.ROOT)
    lfs.mkdir(M.OUTBOX_DIR)
end
return M
```

Nests under `Saved Games\DCS\dcs-sms\` alongside the bridge's `inbox/`, `outbox/`, `state/`, `log/` so the user only has one root dir to know about.

### `serializer.lua`

Pure function, Lua value → Lua chunk string. Roughly 40 lines. One public symbol:

```lua
M.serialize(value, opts) -- returns "return { ... }\n"
-- opts.indent     = "  "    (default)
-- opts.sort_keys  = true    (default; stable byte-identical output across runs)
```

Behavior:

- Handles `number`, `string`, `boolean`, `nil`, and tables with arbitrarily mixed numeric and string keys.
- Numeric keys always emitted as `[1]` (not bare `1` or implicit array form). This is required to preserve mixed-key tables like the DCS `callsign` shape `{[1]=3, [2]=1, [3]=1, name="Uzi11"}` losslessly.
- String keys always emitted as `["foo"]`. Consistent with the rest of the format and with what DCS itself emits in `.miz` files.
- Cycles detected via a visited-table set; on hit, emit `nil --[[ cycle ]]` and continue.
- `function` / `userdata` / `thread` values emit `nil --[[ <type> ]]` and continue. (Shouldn't appear in DCS group tables, but defensive.)

### `selection.lua`

The patch-fragile bit, isolated. All ME-internal API access lives here and only here. Public contract:

```lua
M.snapshot() -- returns:
-- {
--   ok            = boolean,
--   error         = string?,         -- present iff ok=false
--   timestamp_utc = string,          -- ISO-8601 UTC
--   selection_mode = "multi"|"single",
--   groups        = GroupTable[],    -- raw DCS-shaped tables
--   zones         = ZoneTable[],
--   drawings      = DrawingTable[],
--   nav_points    = NavPointTable[],
--   raw           = table,           -- whatever ME handed us, verbatim
-- }
```

**Two selection modes the ME exposes (both must be handled):**

1. **Multi-selection mode** — `me_multiSelection.lua`. Detect with `me_multiSelection.isVisible()`. Read selection with `me_multiSelection.getSelectedObjects()`, which returns `{selectGroups, selectTriggerZones, selectDrawObjects}`.
2. **Single-selection mode** — the "old" path used by `me_copy_paste.onEditCopyOld`. Read with `MapWindow.getSelectedGroups()` for groups; `MapController.getSelectedObjectId()` + `MissionData.getObjectType(id)` to dispatch to `TriggerZoneController.getTriggerZone(id)` or `NavigationPointController.getNavigationPoint(id)`; `panel_draw.getCurrObject()` for the current draw object.

**Statics:** in the ME's internal model, statics are single-unit "groups" (see `me_mission.lua:4298` accessing `w.units[1].type` off a static "group"). Initial assumption is that they ride along inside `selectGroups` / `MapWindow.getSelectedGroups()`. If implementation finds otherwise, add a separate path; the `raw` field is the safety net in the meantime.

**Defensive layering:**

```lua
function M.snapshot()
    local ok, result = pcall(function()
        if multiSelection.isVisible() then
            return collect_multi()
        else
            return collect_single()
        end
    end)
    if not ok then
        return { ok = false, error = tostring(result),
                 timestamp_utc = utc_now(), groups = {}, zones = {},
                 drawings = {}, nav_points = {}, raw = {} }
    end
    result.ok = true
    result.timestamp_utc = utc_now()
    return result
end
```

Each `collect_*` internally wraps each per-source call (`getSelectedObjects`, `getCurrObject`, etc.) in its own `pcall` so a single broken sub-API degrades to an empty array for that category, not a whole-snapshot failure.

**`raw` insurance field** — always populated, even on success. For multi mode contains the unmodified `getSelectedObjects()` return; for single mode contains the `MapWindow.getSelectedGroups()` return, the selected-object-id, and the current draw object. If normalization misses something, the user can still see what DCS gave us.

### `window.lua`

dxgui construction, button handler, status label. Single public symbol `M.show()`. The window contains a "Print selection" button and a `Static` label that mirrors the last action's outcome.

Construction style for v1: **imperative** widget creation (`Button.new`, `Static.new`) rather than `DialogLoader.spawnDialogFromFile(<.dlg>)`. With one button and one label there is no real layout to speak of. Sub-project 3 will switch to `.dlg` files when there is a real layout to describe.

`M.show()` logs `INFO 'window opened'` on successful construction. Two private helpers used by the click handler:

- `is_empty(snap)` — returns true when `snap.ok` is true *and* `#snap.groups + #snap.zones + #snap.drawings + #snap.nav_points == 0`. (`raw` is not counted; it is always populated.)
- `envelope(snap)` — composes the final output table: a `meta` block (version, timestamp, mode, ok, error) plus the data sections (`groups`, `zones`, `drawings`, `nav_points`, `raw`) copied from `snap`.

Click handler outline:

```lua
function M._on_print_clicked()
    local snap = selection.snapshot()

    -- (1) Empty selection: no file, just log + status.
    if snap.ok and is_empty(snap) then
        log.write('sms.me', log.WARNING, 'no selection — nothing dumped')
        M._set_status('No selection — nothing dumped')
        return
    end

    -- (2) Open file. Failure means we can't write anything, return.
    paths.ensure_outbox()
    local filename = 'selection-' .. utc_filename_stamp() .. '.lua'
    local fullpath = paths.OUTBOX_DIR .. filename
    local f, err   = io.open(fullpath, 'w')
    if not f then
        local msg = 'open failed: ' .. tostring(err)
        log.write('sms.me', log.ERROR, msg)
        M._set_status('Failed: ' .. truncate(msg, 80) .. ' (see dcs.log)')
        return
    end
    f:write(serializer.serialize(envelope(snap)))
    f:close()

    -- (3) Snapshot itself failed: file written with ok=false, surface that to the user.
    if not snap.ok then
        local msg = 'selection lookup failed: ' .. tostring(snap.error)
        log.write('sms.me', log.ERROR, msg .. ' (file: ' .. fullpath .. ')')
        M._set_status('Failed: ' .. truncate(snap.error or '', 80) .. ' (see dcs.log)')
        return
    end

    -- (4) Success.
    local summary = summarize(snap, fullpath)
    log.write('sms.me', log.INFO, 'selection dumped to ' .. fullpath
                                   .. ' (' .. summary .. ')')
    M._set_status('Dumped ' .. summary .. ' → ' .. filename)
end
```

`M._set_status` is itself wrapped in `pcall` so a failure to update the label cannot bubble.

### `init.lua`

Bootstrap. Trivial.

```lua
-- Loaded by the require() line patched into MissionEditor.lua.
local ok, err = pcall(function()
    local window = require('dcs_sms_me.window')
    window.show()
end)
if not ok then
    log.write('sms.me', log.ERROR, 'init failed: ' .. tostring(err))
end
```

The outer `pcall` is the last-line defense: even if our `require` chain is broken, the ME continues loading normally.

## Output format

**File location:** `lfs.writedir() .. 'dcs-sms\\me\\selection-<UTC-timestamp>.lua'`
**Filename format:** `selection-2026-05-03T141728Z.lua` (ISO-8601 UTC, no colons — Windows-safe).
**Encoding:** UTF-8, no BOM, LF line endings.

**File shape:**

```lua
return {
    ["meta"] = {
        ["dcs_sms_me_version"] = "0.1.0",
        ["timestamp_utc"]      = "2026-05-03T14:17:28Z",
        ["selection_mode"]     = "multi",        -- or "single"
        ["ok"]                 = true,
        ["error"]              = nil,            -- set iff ok=false
    },
    ["groups"]     = { [1] = { ... }, [2] = { ... } },  -- raw DCS group tables
    ["zones"]      = { [1] = { ... } },
    ["drawings"]   = { [1] = { ... } },
    ["nav_points"] = {},
    ["raw"]        = {
        ["mode"]                = "multi",
        ["multi_get_objects"]   = { ... },        -- multi-mode raw
        ["single_get_groups"]   = nil,            -- single-mode raw
        ["single_object_id"]    = nil,
        ["single_draw_object"]  = nil,
    },
}
```

Key choices:

- **Top-level `return { ... }`** — `dofile()`-loadable, one value, no globals leaked.
- **All keys quoted as strings** (`["meta"]` not `meta`) — consistent with mixed-key tables, matches DCS's own `.miz` format.
- **All numeric keys explicit** (`[1]` not implicit array) — required for round-tripping mixed-key tables (the callsign problem).
- **Empty sections present and empty** rather than `nil` — predictable shape for any consumer.
- **`raw` always present** — insurance against incomplete normalization.

**Empty-selection behavior:** no file is written. The status label and `dcs.log` `WARNING` are the only outputs. (Decision: a zero-content file on every click is more noise than signal.)

**Failure-with-error behavior:** the file *is* written, with `meta.ok=false` and `meta.error` populated, and all data sections empty. The user can grep the `me/` dir for `["ok"] = false` to find failures.

**Summary line format** (the `dcs.log` line):
```
[sms.me] selection dumped to <full path> (mode=multi, groups=3, zones=1, drawings=0, nav_points=0)
```
Stable `key=value` format so it stays grep-friendly.

## Failure model

The framework rule is **log + nil + never throw**. Same here, with one stake: this code runs in the ME's shared GUI Lua state. An uncaught throw can crash the user's editor session and lose unsaved work. That outcome is not allowed.

| Failure point | Containment | User experience |
|---|---|---|
| `init.lua` `require` chain | Outer `pcall` in `init.lua`. | ME loads normally, no window. Error in `dcs.log`. |
| `window.show()` — dxgui construction | `pcall` inside `show`. Sets `window=nil` so retries possible. | ME loads normally, no window. Error in `dcs.log`. |
| `selection.snapshot()` — ME-internal API breaks | Outer `pcall` + per-source `pcall`. Returns `{ok=false, error=...}`. | Button works, dump file appears with `ok=false`. Status label says "Failed: ...". |
| `serializer.serialize(value)` — cycle, function, userdata | Cycle-set + per-type fallthrough. Never throws. | Dump file appears with `nil --[[ ... ]]` placeholders. |
| `io.open` — path missing, permission, disk full | Explicit return-value check. | No dump file. Status label says "Failed: ...". `dcs.log` has the OS error. |
| `paths.ensure_outbox()` — `lfs.mkdir` fails | `lfs.mkdir` returns `nil + err`; logged and continue (the `io.open` will then fail and report). | Same as above. |
| `M._set_status` itself throws (dxgui broken) | Inner `pcall`. | The label stays stale, but `dcs.log` is still authoritative. |

**Invariant:** no code path inside `dcs_sms_me` is allowed to bubble a Lua error up to the ME. Every entry point (bootstrap, button click, any callback we register with dxgui) sits at the top of a `pcall`.

**Logging:** all messages go through DCS's GUI `log.write('sms.me', log.<LEVEL>, msg)`. Levels:

- `INFO` — normal operation (window opened, selection dumped). Verbose by design; the user clicked something and we record it.
- `WARNING` — caller-induced empty state (no selection at click time).
- `ERROR` — anything our `pcall`s catch, plus failed file writes.

**In-window status label** — single line below the button, always shows the outcome of the most recent click. Truncates errors to ~80 chars and points at `dcs.log` for full detail. Best-effort: a failure to update the label is itself `pcall`-contained.

**Explicitly NOT done:**

- No on-screen error dialogs.
- No retries — one click = one attempt.
- No telemetry, no error reporting beyond `dcs.log` and the status label.

## Testing

There is no automated way to test a window inside a running DCS Mission Editor. Testing splits into **unit-testable seams** (run in CI) and **a manual smoke checklist** (run by the author after each significant change).

### Unit-testable seams

Run via standalone Lua 5.1 against a small driver in `me-mod/test/`. Same harness pattern as `framework/test/_smoke.psm1`.

`test_serializer.lua`:

- Round-trip `{1, 2, 3}` → string → `loadstring()` → table-equal.
- Round-trip the callsign shape `{[1]=3, [2]=1, [3]=1, name="Uzi11"}` → string → load → table-equal. (Regression test for the MOOSE pain point.)
- Cycle: a self-referencing table emits the cycle marker rather than infinite-looping.
- Function/userdata in a table emits the placeholder, doesn't throw.
- `sort_keys=true` produces byte-identical output across two runs over the same input.

`paths.lua` and `selection.lua` are not unit-testable (require the ME / `lfs.writedir`); covered by manual smoke.

### Manual smoke checklist

Lives in `me-mod/README.md`. Stays runnable by hand.

1. **Install:** run `dcs-sms install-me-mod`. Verify `<DCS>/MissionEditor/MissionEditor.lua.dcs-sms.bak` exists. Verify the `require('dcs_sms_me')` line was appended. Verify `<DCS>/MissionEditor/modules/dcs_sms_me/` contains all five files.
2. **Cold start:** open the Mission Editor. Verify the window appears. Verify `dcs.log` shows `[sms.me] window opened`.
3. **Empty selection:** with nothing selected, click the button. Verify the status label reads "No selection — nothing dumped". Verify `dcs.log` shows a `WARNING` line. Verify NO file is written under `Saved Games\DCS\dcs-sms\me\`.
4. **Single group:** place one ground unit, select it, click. Verify a dump file appears. Open it; confirm the unit table contains the expected `units`, `route`, `x`, `y` and that mixed-key fields (callsign, etc.) look right.
5. **Multi-selection:** open the multi-select panel, select several groups + a trigger zone + a drawing. Click. Verify all categories appear in the dump.
6. **Failure path:** rename `me_multiSelection.getSelectedObjects` (or stub it to throw) to simulate a DCS patch breakage. Click. Verify the status label shows "Failed: ..." and `dcs.log` shows the error. Verify the ME does not crash.
7. **Uninstall:** run `dcs-sms uninstall-me-mod`. Verify `MissionEditor.lua` is restored from backup. Verify the modules dir is gone.

CI runs only the unit tests. The manual checklist is a release gate.

## Open implementation questions (not blockers)

Items deferred to implementation rather than spec:

- Exact line in `MissionEditor.lua` where the `require` is appended — the file ends with the actual ME bootstrap, so EOF is probably fine but read it first.
- Whether `me_multiSelection.getSelectedObjects()` returns plain DCS group tables or wrapped editor objects with extra fields. Either is acceptable; the `raw` field captures whichever it is.
- Whether statics ride inside `selectGroups` (current assumption) or need a separate path.
- Default window size and on-screen position. Cosmetic; pick something reasonable and let the user drag it.
- Whether to prefix `WARNING`/`ERROR` lines in `dcs.log` so they're easier to grep, or rely on DCS's own level prefixing.

## Cross-cutting commitments

- **Updates `AGENTS.md` §7 module index?** No — this sub-project does not add a public `sms.*` module. The `dcs-sms` framework runtime is unchanged.
- **Updates `docs/api/`?** No, same reason.
- **Adds a smoke test?** Yes (`me-mod/test/test_serializer.ps1` + `.lua`).
- **Adds CLI subcommands?** Yes (`dcs-sms install-me-mod`, `dcs-sms uninstall-me-mod`). README and CLI help text updated in the same PR.
