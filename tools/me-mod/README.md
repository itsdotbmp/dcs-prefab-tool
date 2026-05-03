# dcs-sms Mission Editor mod (hello-world)

A custom dxgui window that lives inside the DCS Mission Editor. One button:
**Print selection**. Click it, and whatever you have selected in the ME
(groups, statics, trigger zones, drawings, navigation points) is dumped to a
Lua-table file under `Saved Games\DCS\dcs-sms\me\`.

This is the **hello world** for the ME mod track. The full feature set
("save objective", "place objective", an objective library) lands in
follow-up sub-projects. See [`docs/superpowers/specs/2026-05-03-me-hello-world-design.md`](../../docs/superpowers/specs/2026-05-03-me-hello-world-design.md).

## Install (recommended path)

```powershell
dcs-sms install-me-mod --dcs-path "D:\Program Files\Eagle Dynamics\DCS World"
```

The `--dcs-path` is cached to `%AppData%\dcs-sms\config.toml` after the first
run, so subsequent installs/uninstalls don't need it. You can also set
`DCS_SMS_DCS_INSTALL` instead of using the flag.

What this does:

1. Backs up `<DCS>\MissionEditor\MissionEditor.lua` →
   `MissionEditor.lua.dcs-sms.bak`. Refuses if a backup already exists (run
   `dcs-sms uninstall-me-mod` first to clean up).
2. Appends a `require('dcs_sms_me.init')` block (delimited by sentinel
   comments) to `MissionEditor.lua`.
3. Copies the mod files to `<DCS>\MissionEditor\modules\dcs_sms_me\`.

Re-running the install is safe — it re-copies the module files but does not
re-patch `MissionEditor.lua` if the markers are already present.

## Uninstall

```powershell
dcs-sms uninstall-me-mod
```

Removes the patch block from `MissionEditor.lua` (surgically, by markers;
falls back to backup-restore if the markers were edited away), deletes the
modules dir, deletes the backup.

## OvGME (DIY for v1)

The folder `tools/me-mod/ovgme/dcs-sms-me-mod/` is the OvGME-package
skeleton. To assemble a usable OvGME mod by hand:

1. Copy `tools/me-mod/lua/dcs_sms_me/*` into
   `ovgme/dcs-sms-me-mod/MissionEditor/modules/dcs_sms_me/`.
2. Copy your CURRENT `<DCS>\MissionEditor\MissionEditor.lua` into
   `ovgme/dcs-sms-me-mod/MissionEditor/MissionEditor.lua` and append the
   patch block (`-- dcs-sms-me-mod begin` … `require('dcs_sms_me.init')` …
   `-- dcs-sms-me-mod end`).
3. Drop `dcs-sms-me-mod/` into your OvGME mods folder and enable it.

Automation for this is deferred. The CLI is the supported install path.

## Manual smoke checklist (Sub-project 3 — Prefab Manager)

CI runs the parity + unit tests under `tools/me-mod/test/run-tests.ps1`. This checklist is the release gate; run by hand against a fresh DCS install before merging significant changes to the mod.

### Setup

1. Run `tools/dcs-sms.exe install-me-mod`. Open the ME. Verify the Tools menu has a "DCS-SMS Prefab Manager" entry. Verify the window does NOT appear automatically.
   - If the floating-button fallback fires instead (visible in `dcs.log` as `Tools menu API unavailable; using floating-button fallback`), that's expected on builds where the menu API isn't exposed — verify the floating button appears at top-right and clicking it opens the Manager.
2. Open Tools → "DCS-SMS Prefab Manager". Window appears with all panels (Save / Library / Action / Status).

### Save flow

3. Place one A-10C in the ME. Select it. Type `test_jet` in the name field. Click **Save**. Verify file at `Saved Games\DCS\dcs-sms\prefabs\test_jet.lua` and the library refreshes to show it.
4. With nothing selected, click **Save** with name `empty`. Status: `No selection — nothing to save`. No file written.
5. With selection, click **Save** with name `test_jet` (collision). Modal appears with **Overwrite / Rename / Cancel**. Pick Cancel — no change. Pick Overwrite — file overwritten.
6. Multi-selection: select two groups + one trigger zone + one drawing. Save as `complex_test`. Open the saved file and verify all four sections are populated.

### Place flow — at click

7. Library shows `test_jet` sorted A-Z. Select it, set rotation 0, click **Place at click**. Verify the title bar text changes to `Click on map to place test_jet (Esc to cancel)` and the button text becomes `Cancel`.
8. Click somewhere on the map. Verify the A-10C appears at that location, status confirms placement, **Ctrl-Z** removes it (group disappears from the ME).
9. Re-place `test_jet`. Save the `.miz`, close the ME, reopen the `.miz`. Verify the placed group survived (no dcs-sms-specific state needed at runtime).
10. Place at click with rotation 90. Verify the group is rotated 90° from how it was saved.
11. Place at click then press **Esc**. Verify exit from place-pending, no entity injected.

### Place flow — at original

12. Save a prefab that includes a group near a specific map building. Click **Place at original**. Verify it lands at the original `meta.world_anchor`, not at any clicked location.

### Best-effort partial-failure

13. Manually corrupt a prefab file to have one valid group + one group with a bogus DCS type. Place it. Verify status: `Placed N of M entities — see dcs.log`. The valid group is in the mission; the corrupt one is logged.

### Library

14. Save 3 prefabs with names `a`, `m`, `z`. Verify the grid is sorted A-Z and shows six columns: **Name / Theatre / G / S / Z / D**.
15. Verify the **Theatre** column shows the current theatre name (e.g. `Caucasus`) for prefabs saved under this branch — *not* `?`. Prefabs saved before this change still show `?` until re-saved.
16. Click a row. Verify it highlights and the status bar shows `Selected: <name>`. Click another. Selection moves.
17. Rename `m` to `middle`. Verify the file is renamed AND `meta.name` is updated inside (open the file).
18. Delete `middle`. Confirmation modal. Confirm. Verify file gone, list refreshed.
19. Manually drop a malformed `.lua` file into the prefabs dir. Click **Reload**. Verify it appears as a row with `[ERROR] <name>` in the Name column and a truncated error message in the Theatre column (rather than breaking the list).

### Undo

20. Place a prefab. Press **Ctrl-Z** (window focused). Verify removal.
21. Press **Ctrl-Z** again. Status: `Nothing to undo.`
22. Place. Click somewhere outside the Prefab Manager window to remove its focus. Press **Ctrl-Z**. Verify nothing happens (window not focused — broad ME-wide undo is [issue #25](https://github.com/nielsvaes/dcs-sms/issues/25)).

### Dev reload

23. With the Prefab Manager window focused, press **Ctrl+Shift+R**. Verify the window briefly disappears and reopens (status bar shows `Ready.`). `dcs.log` should contain `dev reload triggered` → `cleared N modules from package.loaded` → `dev reload completed`. Subsequent edits to the mod's Lua files are picked up by another Ctrl+Shift+R, no DCS restart required.

### Cleanup

24. Run `tools/dcs-sms.exe uninstall-me-mod`. Verify everything removed (modules dir gone, `MissionEditor.lua` patch reverted from backup).

## Running the unit tests

The Lua serializer has a standalone test suite:

```powershell
pwsh tools/me-mod/test/run-tests.ps1
```

Requires `lua.exe` (Lua 5.1) on `PATH`. If you don't have one, install from
https://luabinaries.sourceforge.net/ or run the test file inside DCS via
`dcs-sms exec --file tools/me-mod/test/test_serializer.lua`.

## Layout

```
tools/me-mod/
├── README.md                   ← you are here
├── lua/
│   ├── embed.go                ← Go embed package for the mod files
│   └── dcs_sms_me/
│       ├── init.lua            ← bootstrap (registers Customize-menu entry)
│       ├── menu.lua            ← Customize-menu install + floating-button fallback
│       ├── window.lua          ← Prefab Manager window (Save / Library / Place / Undo)
│       ├── selection.lua       ← ME selection-state lookup (patch-fragile)
│       ├── prefab_distill.lua  ← anchor-rebase + boss-strip; mirror of framework copy
│       ├── prefab_ops.lua      ← save / load / scan_dir / place + ME-API injection
│       ├── undo.lua            ← single-slot undo for the most recent place
│       ├── serializer.lua      ← Lua value → Lua chunk string
│       ├── dtc_skins.lua       ← DTC-dialog-style button + grid skin builders
│       └── paths.lua           ← output dir constants (me/, prefabs/)
├── test/
│   ├── fixtures/
│   │   ├── dump_synthetic_aerial.lua   ← shared with framework parity test
│   │   └── prefabs_dir/                ← farp_alpha / sam_site / broken
│   ├── test_serializer.lua             ← serializer round-trip
│   ├── test_serializer_parity.lua      ← framework ↔ me-mod output parity
│   ├── test_distill_parity.lua         ← framework ↔ me-mod distill parity
│   ├── test_prefab_ops_save.lua        ← save_selection envelope + path logic
│   ├── test_prefab_ops_load.lua        ← scan_dir + load + error rows
│   ├── test_prefab_ops_place.lua       ← place math (rotate + translate + anchor)
│   ├── test_undo.lua                   ← undo single-slot + partial-failure
│   └── run-tests.ps1                   ← PowerShell driver (runs all of the above)
└── ovgme/
    └── dcs-sms-me-mod/         ← OvGME package skeleton (DIY, see above)
```
