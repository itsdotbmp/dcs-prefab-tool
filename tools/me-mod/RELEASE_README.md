# dcs-sms ME-mod — OVGME release

This zip is the ME-mod's Lua files wrapped in an OVGME-compatible tree. Installing the mod takes two parts: copying the files (OVGME does this) and adding a one-line bootstrap to `MissionEditor.lua` (a small helper does this — OVGME can't, see below).

## Install (recommended)

1. Drop this folder into your OVGME mods directory, then enable it in OVGME. OVGME copies `MissionEditor/modules/dcs_sms_me/` into your DCS install.
2. Download `dcs-sms.exe` from the same GitHub release and run:

   ```
   dcs-sms.exe install-me-mod
   ```

   The .exe finds your DCS install and patches `<DCS install>/MissionEditor/MissionEditor.lua` with a single bootstrap line, bracketed by sentinel comments so it can be cleanly removed.

3. Restart the Mission Editor. You should see "DCS-SMS" in the top menu bar.

## Install (no OVGME)

If you don't use OVGME, you don't need this zip. Just download `dcs-sms.exe` and run `dcs-sms.exe install-me-mod` — the Lua files are embedded in the .exe, so it copies them into place AND patches `MissionEditor.lua` in one shot.

## Uninstall

```
dcs-sms.exe uninstall-me-mod
```

Removes the patch block from `MissionEditor.lua` and deletes the modules directory. If you used OVGME, also disable the mod there.

## Update

1. Replace this OVGME mod with the new release version.
2. Re-run `dcs-sms.exe install-me-mod` from the new release. The patch is idempotent — if `MissionEditor.lua` already has the bootstrap line, nothing changes.

## Why isn't the bootstrap line managed by OVGME?

`MissionEditor.lua` is part of the DCS install and gets updated by Eagle Dynamics. If we shipped a replacement copy through OVGME, it would clobber DCS patches and conflict with any other ME mod that touches the same file. Keeping the patch out-of-band — managed by `dcs-sms.exe` — means OVGME stays clean and the bootstrap survives DCS updates.
