<p align="center">
  <img src="../../assets/logo.png" alt="Coconut Cockpit" width="160">
</p>

# dcs-sms — Mission Editor mod

Custom in-editor extension that adds a **Prefab Manager** to DCS World's Mission Editor. Save a selection of groups / statics / zones / drawings to a reusable prefab; place them later by click or at their original location. Supports rotation, country override, airbase warehouse capture, per-ship warehouses, and undo.

<p align="center">
  <img src="../../assets/prefab-manager.png" alt="dcs-sms Prefab Manager — library on the left, click-to-place in progress on the map" width="900">
</p>

## Audience

You design DCS missions in the Mission Editor and want to reuse pieces of one mission in another.

## Install

```powershell
dcs-sms.exe install-me-mod --dcs-path "D:\Program Files\Eagle Dynamics\DCS World"
```

The `--dcs-path` argument is cached to `%AppData%\dcs-sms\config.toml` after the first run, so subsequent installs/uninstalls don't need it. You can also set the `DCS_SMS_DCS_INSTALL` environment variable.

What this does:

1. Backs up `<DCS>\MissionEditor\MissionEditor.lua` → `MissionEditor.lua.dcs-sms.bak`. Refuses if a backup already exists (run `dcs-sms uninstall-me-mod` first to clean up).
2. Appends a `require('dcs_sms_me.init')` block (delimited by sentinel comments) to `MissionEditor.lua`.
3. Copies the mod files to `<DCS>\MissionEditor\modules\dcs_sms_me\`.

Re-running the install is safe — it re-copies module files, but does not re-patch `MissionEditor.lua` if the markers are already present.

After installing, **restart DCS** (a full restart, not just closing the Mission Editor — Lua files in `MissionEditor.lua` load once at DCS start). Open the Mission Editor; you should see **DCS-SMS** in the top menu bar.

For the binary itself, see [`tools/cmd/dcs-sms/README.md`](../cmd/dcs-sms/README.md).

## Uninstall

```powershell
dcs-sms.exe uninstall-me-mod
```

Removes the patch block from `MissionEditor.lua` (surgically, by markers; falls back to backup-restore if the markers were edited away), deletes the modules directory, and deletes the backup.

## Features

- **Prefab Manager window.** Tools menu → DCS-SMS Prefab Manager (or floating-button fallback on builds without the menu API).
- **Save flow.** Distill a selection of groups, statics, zones, and drawings into a single prefab file under `<Saved Games>\DCS\dcs-sms\prefabs\<name>.lua`. Multi-selection supported.
- **Place flow.** Place at original location, or click-to-place with a yellow bbox preview. Right-drag pan, mouse-wheel zoom, Esc to cancel. Double-click a library row to enter click-place for that prefab.
- **Rotation.** Rotation dial + spinbox; rotation applies to groups, statics, drawings, and zones together.
- **Country override.** Pick a country at place time; placement is refused if any unit type is missing from the chosen country's catalog (avoids silent fallbacks like ships becoming "Boat Armed Hi-Speed").
- **Airbase warehouse capture.** Marquee-detect customised airbases inside a rect at save time and bundle their warehouse data (coalition, fuel, aircraft, weapons, operating levels) into the prefab. Apply on Place to the same-named airbase, with theatre-mismatch refusal and country-coalition override.
- **Per-ship warehouses.** Capture and apply per-ship warehouse data, riding inline on `unit._sms_warehouse` through serialization.
- **Single-slot Undo.** Press **Ctrl-Z** with the Prefab Manager focused to undo the most recent place (groups + zones + drawings + airbase splices restored together).
- **Library actions.** Reload, Rename, Delete; live name+theatre search; click-to-sort grid columns.
- **Native ME confirmations.** Save-overwrite, Apply-airbase-supplies, Delete confirmations use DCS's `MsgWindow` — same look as the rest of the editor.
- **Severity-coloured status bar.** Info (white), warning (yellow), error (red), placement (green). Auto-clears after 6 s except during place mode.

## Versioning

The ME-mod ships under tags `me-mod-v0.x.y`. The canonical version string lives at [`lua/dcs_sms_me/version.lua`](lua/dcs_sms_me/version.lua). See [`AGENTS.md` §11](../../AGENTS.md#11-versioning-and-releases) for the full rules.

- [`CHANGELOG.md`](../../CHANGELOG.md) — release history; the **ME-mod** section tracks `me-mod-v*` tags.

## Manual smoke checklist

For the release-gate procedure (run before tagging a `me-mod-v*` release), see [`docs/release-gate/me-mod-smoke.md`](../../docs/release-gate/me-mod-smoke.md).
