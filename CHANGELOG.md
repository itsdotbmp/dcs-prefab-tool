# Changelog

This project ships two parallel components on independent semver tracks:

- **Framework** (`framework/`) — the runtime `sms.*` API loaded into mission scripts. Tags: `framework-v0.X.Y`. Canonical version: `sms.version` in `framework/sms.lua`.
- **ME-mod** (`tools/me-mod/`) — the Mission Editor extension. Tags: `me-mod-v0.X.Y`. Canonical version: `tools/me-mod/lua/dcs_sms_me/version.lua`.

Format loosely follows [Keep a Changelog](https://keepachangelog.com). Both tracks live in 0.x — minor bumps may include breaking changes; major bump (1.0) is reserved for the moment the public surface stabilises.

---

## Framework

### [0.10.0] — 2026-05-05

This is the first tag after a long quiet period — `sms.version` had been frozen at `"0.1.0"` while nine `framework-v0.x.0` tags shipped through April 27. 0.10.0 catches the in-source string up to reality and folds in everything added since `framework-v0.9.0`.

**Added**
- `sms.task` — task spec builders covering move-to, attack, orbit, escort, refueling, and more, with per-category adaptation.
- `sms.options` — group options (ROE, alarm state, formation, …) wired through `sms.K` enums.
- `sms.commands` — runtime commands: start/stop firing, set frequency, set callsign.
- `sms.rule` — declarative AI rule API.
- `sms.K` — central enum namespace. Subsumes the previous standalone `sms.countries` / `sms.skill` / `sms.alt_type` / `sms.waypoint` / `sms.targets` / `sms.designations` modules and adds `sms.K.coalition`, `sms.K.category`, `sms.K.roe`, `sms.K.alarm_state`, `sms.K.formation`.
- `sms.K.units` and `sms.K.statics` — generated catalogs of every DCS unit and static type, written by `tools/dcs-sms.exe gen-units`.
- `sms.utils.serialize` — byte-stable Lua-data serializer; shared with the ME-mod's prefab format.
- `sms.prefab` — load and spawn prefabs from a mission script (rotation, country override, injection record).

**Changed**
- Country resolution now reads `boss.id` from the real ME selection shape (replaces an earlier heuristic).
- Drawing serialization preserves vertex deltas instead of absolute coords; place applies drawing rotation.

**Internal**
- Smoke test suite ported from bash to PowerShell.
- ACE skill level added to `sms.K.skill`.

### [0.9.0] — 2026-04-27
**Added**
- `sms.weapon` — wrapper with snapshot, polled tracker, impact extrapolation, `on_impact` and `WEAPON_IMPACT` bus delivery, destroy semantics.

### [0.8.0] — 2026-04-27
**Added**
- `sms.events` — pub/sub bus with entity-handle sugar, destroy emit, group-fully-dead semantic.

### [0.7.0] — 2026-04-27
**Added**
- `sms.static` — entity wrapper, `create`, `clone`.
- `sms.area:is_static_in`.

### [0.6.0] — 2026-04-26
**Added**
- `sms.group.create`, `sms.group.clone`.
- `sms.utils` conversions.

### [0.5.0] — 2026-04-26
**Added**
- `sms.area`.
- `_make_callable_handle` factory (internal).

### [0.4.0] — 2026-04-26
**Added**
- `sms.unit`.
- `sms.group:get_units()`.

### [0.3.0] — 2026-04-26
**Added**
- `sms.timer`.

### [0.2.0] — 2026-04-26
**Added**
- `sms.group`.

### [0.1.0] — 2026-04-25
**Added**
- `sms.log` (logger module).
- `sms.utils`.

---

## ME-mod

### [0.2.0] — 2026-05-06

The marquee feature: `dcs-sms.exe update`. Self-updates the host-side binary in place from GitHub Releases, so users never have to manually re-download `dcs-sms.exe` again — and never accidentally regress their installed mod by running `install-me-mod` from a stale older binary.

**Added**
- `dcs-sms.exe update` — fetches the latest release from GitHub and replaces the running binary in place (Windows only). The previous binary is renamed to `dcs-sms.exe.old`.
- `dcs-sms.exe update --check` — reports whether an update is available without downloading.

**Fixed**
- Released binaries now embed their tag version (e.g. `0.2.0`) via `-ldflags="-X main.version=$VERSION"` at build time. Previously every released binary identified as `0.1.0-dev`, which broke version comparison for the new `update` command.

**Internal**
- Inline semver comparator (no new module dependency — stdlib only).
- GitHub Releases API helper, asset-based release filter (robust to future release-track changes — only releases that actually ship `dcs-sms.exe` are considered).
- Binary-swap helper with rename-and-rollback safety on mid-write failures.

### [0.1.0] — 2026-05-05

First tracked ME-mod release. Wraps everything shipped to date into a single point-in-time tag.

**Added**
- Prefab Manager window: name + Save row, search/filter, sortable grid (Name / Theatre / Fixed Pos / AB / G / S / Z / D), action buttons (Reload / Undo / Rename / Delete), country dropdown with Combat/All toggle and coalition-colored dots, rotation dial + spinbox, Place at original location + Place at click, status bar.
- Save flow: distill the current selection (groups, statics, zones, drawings) into a prefab file under `<saved-games>/dcs-sms/prefabs/<name>.lua`. Prefab format at `PREFAB_VERSION = "0.3.0"`.
- Place flow: both Place-at-original-location and click-to-place. Cursor-following yellow bbox preview during click-place; right-drag pan, mouse-wheel zoom, Esc cancel; double-click a row to enter click-place for that prefab.
- Single-slot Undo for placed prefabs (groups + zones + drawings + airbase warehouse splices restored together).
- Airbase supplies: marquee-detect customised airbases inside a rect and bundle their warehouse data (coalition, fuel, aircrafts, weapons, operating levels) into the prefab. Apply on Place to the same-named airbase, with theatre-mismatch refusal and country-coalition override. Refuses to apply if the prefab predates theatre capture (older `0.2.0` saves).
- Per-ship warehouse capture + apply, ride inline on `unit._sms_warehouse` through serialization.
- Country override at place time with **catalog validation** — refuses placement if any prefab unit's type is missing from the chosen country's catalog (avoids the silent fallback to "Boat Armed Hi-Speed" for ships under unsupported countries).
- Rename, Delete, Reload-library actions.
- Live name+theatre search and click-to-sort grid columns.
- Native ME `MsgWindow` for confirmation prompts (Save-overwrite / Apply-airbase-supplies / Delete) — title bar, icons, button styling all match the editor.
- Severity-coloured status bar: info (white), warning (yellow), error (red), placement (green). Auto-clears info/warning after 6 s; the placement message stays for the duration of the mode.

**Tools**
- `tools/dcs-sms.exe install-me-mod` — copies the ME-mod into `<DCS install>/MissionEditor/modules/dcs_sms_me/` and patches `MissionEditor.lua` with a sentinel-marker `require` block. Idempotent; backs up `MissionEditor.lua` first.
- `tools/dcs-sms.exe uninstall-me-mod` — reverses the install.
