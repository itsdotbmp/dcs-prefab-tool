# Changelog

This project ships two parallel components on independent semver tracks:

- **Framework** (`framework/`) — the runtime `sms.*` API loaded into mission scripts. Tags: `framework-v0.X.Y`. Canonical version: `sms.version` in `framework/sms.lua`.
- **ME-mod** (`tools/me-mod/`) — the Mission Editor extension. Tags: `me-mod-v0.X.Y`. Canonical version: `tools/me-mod/lua/dcs_sms_me/version.lua`.

Format loosely follows [Keep a Changelog](https://keepachangelog.com). Both tracks live in 0.x — minor bumps may include breaking changes; major bump (1.0) is reserved for the moment the public surface stabilises.

---

## Framework

### [0.11.0] — 2026-05-07

**Changed**
- `sms.prefab.load_dir` now accepts both `.prefab` and `.lua` files. Saves still go through `sms.prefab.save` with whatever path you pass; the canonical extension going forward is `.prefab`.

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

## Tools / Hook

### [hook 0.2.0] — 2026-05-08

**Added**
- `target` field on requests: `"mission"` (default — runs in the in-mission scripting env via `net.dostring_in`) or `"gui"` (handed off to the ME-mod's bridge — runs in the shared GUI/ME Lua state and reaches the editable mission table).
- `dcs-sms exec --target gui|mission|auto`. Default is `auto` — picks `mission` if a sim is running, `gui` if the user is in the ME / main menu (and the ME-mod toggle is on).
- New heartbeat fields: `state`, `gui_bridge_enabled`, `tick_source`, plus `last_tick`/`last_tick_at` aliasing `last_frame`/`last_frame_at`.
- ME-mod writes its own heartbeat to `state/me.json`. CLI's `hookstatus.ReadMerged` fuses both heartbeats so the routing layer sees a unified view (mission state from the hook, gui state from the ME-mod).
- New CLI exit code 4 (`exec`): `target=gui` requested but the ME-mod's "External execution" toggle is off.

**Changed**
- `dcs-sms exec` no longer rejects `mission_loaded=false` outright — `--target gui` works in the ME without a running mission. Routing decisions live in `RouteForTarget`.
- The hook itself stays single-tick (`onSimulationFrame` only — Hooks/ env has no per-frame tick outside sim, runtime-tested). The `target=gui` poller lives in the ME-mod's `bridge.lua`, driven by `UpdateManager.add` in the ME env where it's actually wired.
- The hook now skips `target=gui` requests in the inbox (leaves them for the ME-mod's poller to pick up) instead of trying to handle them itself.

**Compatibility**
- Heartbeat keeps `last_frame` / `last_frame_at` populated alongside `last_tick` / `last_tick_at` for one release.
- Requests without a `target` field are treated as `target=mission` (today's behavior).

---

## ME-mod

### [0.6.0] — 2026-05-10

**Added**
- `me trigger reorder` — move a trigger to a new position in `mission.trigrules` (by name).
- `me trigger reorder-condition` — move a condition to a new position in a trigger's `rules` list.
- `me trigger reorder-action` — move an action to a new position in a trigger's `actions` list.
- `me trigger add-condition --predicate or` — pseudo-predicate that connects two surrounding conditions with logical OR. ED's panel exposes this via the OR button between rules; the bridge now resolves it through `add-condition`. Discoverable via `me trigger list-predicates` / `describe-predicate or`.
- `dcs-sms screenshot [--out PATH] [--title SUBSTR]` — capture the running DCS window to a PNG via `PrintWindow + PW_RENDERFULLCONTENT`. Works in windowed, borderless windowed, and (verified) true exclusive fullscreen. Default output is `%TEMP%/dcs-sms-screenshot.png`. Windows-only.
- `me camera focus { --name N | --lat L --lon L | --x X --y Y } [--scale S]` — pan the ME map to a point, optionally setting zoom (meters per screen unit) at the same time. `--name` resolves against `Mission.AirdromeController.getAirdromes()` (case-insensitive, exact match preferred, substring fallback). Coords use DCS world meters (x = north, y = east), same convention as the airdrome controller and the `Terrain.convertLatLonToMeters` return values.
- `me camera get` — return the current map center as `{ x, y, lat, lon, scale }`.

All three reorder verbs accept the same five mutually-exclusive position flags: `--to-index N`, `--before X`, `--after X`, `--to-start`, `--to-end`. For `me trigger reorder`, `X` is a trigger name; for `reorder-condition` / `reorder-action`, `X` is a 1-based index into the parent trigger's list. Self-targeting (e.g. `--before T` where `T` is the source itself, or `--to-index <where-source-already-is>`) is an idempotent no-op (`moved: false`), not an error.

**Fixed**
- Trigger ref fields (unit / vehicle / aircarrier / drawObject combos) now resolve names to numeric ids before storage. Previously, `me trigger add-condition --predicate unit-altitude-lower unit=b1-1 ...` stored `entry.unit = "b1-1"` (a string), which the ME panel's combo couldn't match — and a subsequent panel interaction would nil the field via the bound `onChange` callback. Closes [#45](https://github.com/nielsvaes/dcs-sms/issues/45).

### [0.5.0] — 2026-05-08

**Added**
- `bridge.lua` — an inbox poller running in the ME's Lua state, driven by `UpdateManager.add`. Handles `target=gui` execution requests from the `dcs-sms.exe` CLI: runs the user's Lua snippet directly via `loadstring + xpcall`, captures `print` output, returns results through the standard file-mailbox protocol. Writes its own heartbeat to `<SavedGames>/DCS/dcs-sms/state/me.json`.
- "External execution: ON/OFF" item under the DCS-SMS top menu. Flipping it on enables the bridge's `target=gui` path so external tools (the `dcs-sms exec --target gui` CLI, Claude, etc.) can run Lua against the editable mission table from outside DCS. Default off at every DCS launch (session-only; no persistence).

### [0.4.2] — 2026-05-07

**Changed**
- Prefab files are saved with a `.prefab` extension instead of `.lua`. Existing `.lua` files in your prefabs directory are silently renamed to `.prefab` the first time the Prefab Manager scans the directory; the file content is unchanged. Both extensions remain readable indefinitely.

### [0.4.1] — 2026-05-07

Adds an OVGME-friendly install path for users whose browser blocks `dcs-sms.exe` as "unsigned" (Edge SmartScreen / Windows Defender). No runtime mod changes — packaging only.

**Added**
- The `Release ME-mod` GitHub Actions workflow now also builds and uploads `dcs-sms-me-mod-vX.Y.Z.zip` alongside the existing `dcs-sms.exe`. The zip contains the OVGME-shaped `dcs-sms-me-mod/MissionEditor/modules/dcs_sms_me/` mod tree plus a `README.md` walking the user through the install. Because the mod needs one line appended to `MissionEditor.lua` and OVGME can't surgically edit files, the README instructs the user to do that one-line edit by hand on their own copy. We deliberately do *not* ship a pre-patched `MissionEditor.lua` — DCS EULA §3.1(a) prohibits redistributing modified ED files; users editing their own copy on their own machine is permitted.
- Release notes now include an "Alternative install (OVGME / no .exe)" section pointing at the zip and summarising the four install steps.

The `dcs-sms.exe install-me-mod` path remains the recommended install — it patches `MissionEditor.lua` automatically and supports `update` / `uninstall` subcommands. The OVGME zip is the fallback for users who can't run unsigned binaries.

### [0.4.0] — 2026-05-07

Three Prefab Manager fixes / UX improvements driven by [#37](https://github.com/nielsvaes/dcs-sms/issues/37) and follow-up testing feedback.

**Fixed**
- `Place at original location` now preserves the source unit's `parking` / `parking_id` / `parking_landing` / `parking_landing_id` instead of stripping them. The on-disk prefab format already carried these fields; the place pipeline was unconditionally nilling them — mirroring vanilla ME's `me_copy_paste.lua:331-334` strip — but skipping vanilla's compensating call to `panel_route.attractToAirfield(wpt, group)` (`me_copy_paste.lua:393-398`). Result was a unit with the right `(x, y)` for the editor display but no parking binding for DCS at mission start, so DCS picked the nearest free slot at runtime instead of the one the user originally chose.
- Placements at a non-original anchor now run a "Pass F" that mirrors vanilla ME's airfield re-attraction: for every placed group's airfield-type waypoints (`TakeOffParking` / `TakeOff` / `Landing` / `LandingReFuAr`) without a live `linkUnit`, `panel_route.attractToAirfield(wpt, group)` is called to assign a free parking/runway slot at the destination airfield. Carrier-deck takeoffs are detected by their live `linkUnit` and left to Pass E's `linkWaypoint` dance — Pass F skips them so the unlink/relink dance isn't clobbered.
- Pass F also fires when a placed group has any unit with `parking_id == nil`, even at the original anchor. This handles prefabs distilled from pre-mid-2024 source missions: ED started writing `parking_id` on parked aircraft around then, and ME doesn't migrate the field at load time — only at save time. A 2024 `.miz` opened in current ME and turned into a prefab without an intervening File → Save inherits the un-migrated shape, so Prong 1 has nothing to preserve and the place pipeline must run `attractToAirfield` to assign a spot at the unit's saved `(x, y)`. The fast user-side workaround remains "open the source mission in current DCS, save, re-make the prefab" — that bakes `parking_id` into the prefab data and lets Prong 1 preserve the exact original spot rather than relying on attract's nearest-free-spot heuristic.
- Trigger zone color is now preserved through the prefab round-trip. ME's `TriggerZone` class stores color as four separate fields (`red` / `green` / `blue` / `alpha` — `Mission/TriggerZone.lua:38`) but the `.miz` save format and `addTriggerZone` API expect a single `color = {r, g, b, a}` table (`Mission/TriggerZoneData.lua:559`). `selection.lua` captures the live zone object, `prefab_distill` walks it via `pairs()`, so the four separate fields landed in the prefab but `inject_zone` reads `zone.color` and got `nil`. Distill now synthesizes the `color` table during normalisation; `inject_zone` carries a backward-compat fallback that synthesises from `red/green/blue/alpha` for prefabs saved by ME-mod ≤ v0.3.2.

**Added**
- New `<keep prefab countries>` entry in the country dropdown, selected by default. When this entry is active, place uses each unit's stored country verbatim — supporting mixed-coalition prefabs (e.g. an airbase package with US, UK, and CJTF Blue units in one save) without forcing the user to leave the dropdown blank. Picking any other dropdown entry continues to override every unit to that country, matching the old behavior.

### [0.3.2] — 2026-05-06

Two small UX fixes for the Prefab Manager.

**Changed**
- The Reload button now also re-populates the country dropdown. Users who change coalition assignments mid-session in `Customize → Coalitions` can pick up the change without closing and reopening the window. Status bar message updated to "Library and countries reloaded."
- The Prefab Manager now auto-closes when the current mission is torn down — `File → New` or `File → Open` — matching the behavior of the ME's own panels (`coords_info`, `flightPlans`, `multiTemplate`, `managerDTC`). Wraps `me_toolbar.newMission` and `me_toolbar.loadMission` via a small `new_mission_hook` module that mirrors `marquee_hook`'s reload-safe subscriber pattern.

### [0.3.1] — 2026-05-06

Fixes a placement bug where intra-prefab unit/group references were destroyed: statics linked to a carrier no longer followed the AC after spawn, aircraft set to start on a carrier deck spawned at world coordinates instead, and the carrier's own TACAN / ICLS / Link 4 task params, Link 16 datalinks, and Escort / EPLRS task references all kept the source-mission ids and broke at runtime.

**Fixed**
- `Place` now does a four-pass injection (allocate → remap → inject → relink). A prefab-wide old→new id map is built across every group BEFORE any insertion, then every known id-bearing field (`linkUnit.unitId`, `helipadId`, `missionUnitId`, ActivateBeacon / ActivateICLS / ActivateLink4 `unitId`, Escort / EPLRS `groupId`) is rewritten via the map. Ids that don't resolve in-prefab are nilled (matches the pre-fix safety for cross-mission references). `airdromeId` is preserved when placing at the original anchor (`Place at original location`) and nilled otherwise (would otherwise bind aircraft to a far-away airbase at click-anchor placements).
- After insertion, every linked waypoint has its runtime link re-established via `Mission.linkWaypoint` — same dance `me_copy_paste.duplicateGroup` does. This populates the host unit's `linkChildren` list, which is what the ME's delete-cascade walks. Without this step, the data on disk was correct but the runtime didn't know about the link: moving the host unit didn't move its dependents until the mission was saved (forcing a re-parse), and deleting the host left orphans that broke `File > New`. `helipadId` / `airdromeId` are stashed around the relink because `unlinkWaypoint` clears them as a side effect.
- `unit.linkChildren` and `unit.linkChildrenTZone` are now cleared on every placed unit before relinking. The source mission may have populated them with live runtime waypoint references; distill strips the `boss` back-refs, so the entries survive into the placed unit half-dead. ME's drag handler walks the list and nil-indexes on `wpt.boss`, breaking ME state to the point where `File > New` errors out. Mirrors `me_copy_paste.duplicateGroup` lines 337–338.

### [0.3.0] — 2026-05-06

The mod's chrome now identifies the project. New About dialog with the Coconut Cockpit logo, plus a branded window title.

**Added**
- `Tools → DCS-SMS → About` menu entry — opens a small dialog with the 128×128 Coconut Cockpit logo, the mod version, and the project's GitHub and Discord URLs. The logo PNG is bundled into the mod and rendered via the existing `staticSkin` + `picture` override pattern (the same trick `dtc_skins.icon_static` already uses for warning/question glyphs).

**Changed**
- Prefab Manager window title now reads `Coconut Cockpit · DCS-SMS — Prefab Manager v0.3.0` instead of `dcs-sms — Prefab Manager v…`.

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
