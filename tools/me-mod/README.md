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

## Manual smoke checklist

After install, run through this list to verify the mod works end-to-end.

1. **Install:** run `dcs-sms install-me-mod`. Verify
   `<DCS>\MissionEditor\MissionEditor.lua.dcs-sms.bak` exists. Verify the
   `require('dcs_sms_me.init')` line was appended (between sentinel markers).
   Verify `<DCS>\MissionEditor\modules\dcs_sms_me\` contains all five files.
2. **Cold start:** open the Mission Editor. Verify the small "dcs-sms ME"
   window appears in the upper right. Verify `dcs.log` shows
   `[sms.me] window opened`.
3. **Empty selection:** with nothing selected, click the button. Verify
   the in-window status reads "No selection — nothing dumped". Verify
   `dcs.log` shows a `WARNING` line. Verify NO file is written under
   `Saved Games\DCS\dcs-sms\me\`.
4. **Single group:** place one ground unit, select it, click the button.
   Verify a dump file appears. Open it in a text editor; confirm the unit
   table contains expected keys (`units`, `route`, `x`, `y`) and that
   mixed-key fields like `callsign` look right.
5. **Multi-selection:** open the multi-select panel, select several groups,
   a trigger zone, a drawing. Click. Verify all categories appear in the
   dump.
6. **Failure path:** rename `me_multiSelection.getSelectedObjects` (or stub
   it to throw) to simulate a DCS patch breakage. Click. Verify the status
   label shows "Failed: ..." and `dcs.log` shows the error. Verify the ME
   does not crash.
7. **Uninstall:** run `dcs-sms uninstall-me-mod`. Verify
   `MissionEditor.lua` is restored. Verify the modules dir is gone. Verify
   the `.bak` file is gone.

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
│       ├── init.lua            ← bootstrap (require window, show)
│       ├── window.lua          ← dxgui window + button + click handler
│       ├── selection.lua       ← ME selection-state lookup (patch-fragile)
│       ├── serializer.lua      ← Lua value → Lua chunk string
│       └── paths.lua           ← output dir constants
├── test/
│   ├── test_serializer.lua     ← pure-Lua test cases
│   └── run-tests.ps1           ← PowerShell driver
└── ovgme/
    └── dcs-sms-me-mod/         ← OvGME package skeleton (DIY, see above)
```
