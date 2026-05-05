# README restructure — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current top-level `README.md` (which mixes pitch, framework quick-start, and bridge install while pretending the ME-mod doesn't exist) with a thin landing-page router. Give each of the three real components — Framework, ME-mod, CLI — its own self-contained README next to its code. Move the manual smoke checklists out of user-facing pages into a dedicated `docs/release-gate/` directory. Delete `MISSION.md`, `tools/lua/README.md`, and the entire dead `tools/me-mod/ovgme/` skeleton.

**Architecture:** Pure documentation reshape. No code or behaviour changes. Each component's README lives next to its code (`framework/README.md`, `tools/me-mod/README.md`, `tools/cmd/dcs-sms/README.md`). The root `README.md` becomes a ~25-line router with three component links plus pointers to docs/api, CHANGELOG, and AGENTS. Smoke checklists relocate to `docs/release-gate/{bridge,me-mod}-smoke.md`, linked only from `AGENTS.md`. Cross-links are updated in `AGENTS.md` and `docs/api/README.md` to match the new layout.

**Tech Stack:** Markdown only. The implementer's job is to write file contents exactly as specified, verify them, and commit per task. No tests to run beyond the final stale-reference scan (a `git grep` against the deleted file paths).

**Spec:** [`docs/superpowers/specs/2026-05-05-readme-restructure-design.md`](../specs/2026-05-05-readme-restructure-design.md)

**Convention used in this plan:** because every file we create is itself a markdown document containing three-backtick code blocks, this plan wraps file-content blocks in **four-backtick fences**. The four-backtick outer fence lets the inner three-backtick fences render correctly. The bytes you write to disk are exactly what appears between the four-backtick fences (so the inner three-backtick fences are preserved as-is — no escape characters anywhere).

---

## Task 1: Create `tools/cmd/dcs-sms/README.md` (CLI / bridge)

**Files:**
- Create: `tools/cmd/dcs-sms/README.md`

- [ ] **Step 1: Verify the directory exists**

Run: `ls D:/git/dcs-sms/tools/cmd/dcs-sms/`
Expected: directory listing including `main.go` and other Go files. The directory must already exist.

- [ ] **Step 2: Create the README with EXACTLY the content between the four-backtick fences below**

````markdown
# dcs-sms.exe — host-side CLI

Single Go-built binary that installs both the framework hook and the ME-mod, executes Lua snippets in a running DCS mission, and generates the framework's data catalogs.

## Audience

Anyone using either the framework or the ME-mod. Both rely on `dcs-sms.exe` as the install / interaction tool.

## Install

**Recommended:** download `dcs-sms.exe` from the latest [Release](https://github.com/nielsvaes/dcs-sms/releases). The binary is self-contained — no Go toolchain needed at runtime.

**From source:**

```sh
cd tools
go build ./cmd/dcs-sms
```

Produces `tools/dcs-sms.exe` (Windows) or `tools/dcs-sms` (Linux/macOS — supported for the bridge subcommands; the ME-mod installer is Windows-only because DCS only ships on Windows).

## Required setup for bridge subcommands

The bridge (`exec`, `status`, `tail-log`) relies on the Lua hook running inside DCS. The hook needs filesystem access to scan its inbox and write responses, which DCS sandboxes by default.

Edit `Scripts\MissionScripting.lua` in your DCS *install* directory (not Saved Games) and comment out the `os` / `io` / `lfs` sanitizers:

```lua
do
  -- sanitizeModule('os')
  -- sanitizeModule('io')
  -- sanitizeModule('lfs')
  ...
end
```

This is the same modification `dcs_code_injector` requires. The `install-me-mod` and `gen-units` subcommands do not need this edit; only the bridge subcommands do.

## Subcommands

### Bridge — host ↔ running DCS mission

#### `install-hook`

Writes `dcs-sms-hook.lua` into `<Saved Games>\DCS*\Scripts\Hooks\` (auto-detected, or pass `--saved-games <path>` to override). Run once after installing or updating the binary.

```sh
dcs-sms.exe install-hook
```

#### `status`

Reports whether the hook is loaded and a mission is running. Exit 0 if everything is healthy.

```sh
dcs-sms.exe status
# mission loaded: true
# fresh: true
# theatre: Caucasus
```

#### `exec`

Runs a Lua snippet inside the current mission. `--code` for inline, `--file` to send a script file. Returns JSON with `ok`, `return_value`, captured `print` output, and any error.

```sh
dcs-sms.exe exec --code "return 1+1"
dcs-sms.exe exec --file framework/load_all.lua
```

`--timeout 2s` caps wait time. **Note:** if the snippet hangs DCS (e.g. infinite loop), the timeout will return but DCS itself needs to be killed via Task Manager. This is a documented limitation.

#### `tail-log`

Prints the last N lines of `dcs.log` (default 50).

```sh
dcs-sms.exe tail-log -n 20
```

### ME-mod — install / uninstall the Mission Editor extension

#### `install-me-mod`

Patches `MissionEditor.lua` and copies the mod files. See [`tools/me-mod/README.md`](../../me-mod/README.md) for full install behaviour.

```sh
dcs-sms.exe install-me-mod --dcs-path "D:\Program Files\Eagle Dynamics\DCS World"
```

`--dcs-path` is cached to `%AppData%\dcs-sms\config.toml` on first use; subsequent runs don't need it.

#### `uninstall-me-mod`

Reverses the install — removes the patch block, deletes the modules directory, deletes the backup.

```sh
dcs-sms.exe uninstall-me-mod
```

### Framework data — for contributors

#### `gen-units`

Regenerates the unit / static catalogs (under `framework/constants/`) from `dcs-lua-datamine`. End users don't need to run this; it's a developer tool used when DCS adds or renames units.

```sh
dcs-sms.exe gen-units --datamine-root D:/git/dcs-lua-datamine
```

## Versioning

The CLI binary is bundled with each ME-mod release (`me-mod-v0.x.y` tag). It does not have its own version track. See [`AGENTS.md` §11](../../../AGENTS.md#11-versioning-and-releases).

## Manual smoke checklist

For the release-gate procedure (run before tagging), see [`docs/release-gate/bridge-smoke.md`](../../../docs/release-gate/bridge-smoke.md).
````

- [ ] **Step 3: Verify the file is well-formed**

Run: `head -3 D:/git/dcs-sms/tools/cmd/dcs-sms/README.md`
Expected first line: `# dcs-sms.exe — host-side CLI`

Run: `git -C D:/git/dcs-sms grep -c "^#" tools/cmd/dcs-sms/README.md`
Expected: a count >= 6 (one H1 plus several H2 / H3 / H4 headings).

Run (sanity check the file does not contain literal backslashes immediately followed by a backtick — those would mean the four-backtick convention got mangled):

```sh
grep -c '\\`' D:/git/dcs-sms/tools/cmd/dcs-sms/README.md
```

Expected: `0`.

- [ ] **Step 4: Commit**

```sh
git -C D:/git/dcs-sms add tools/cmd/dcs-sms/README.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs(cli): add tools/cmd/dcs-sms/README.md

Audience-tailored README for the dcs-sms.exe binary: install path,
required MissionScripting.lua sandbox edit, and a subcommand index
grouped by purpose (bridge / me-mod / framework data).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `framework/README.md`

**Files:**
- Create: `framework/README.md`

- [ ] **Step 1: Verify the directory exists**

Run: `ls D:/git/dcs-sms/framework/load_all.lua`
Expected: the file exists. Confirms we're targeting the right directory.

- [ ] **Step 2: Create the README with EXACTLY the content between the four-backtick fences below**

````markdown
# dcs-sms — framework

In-DCS Lua scripting framework. Loaded once per mission; everything else is the `sms.*` namespace.

## Audience

You write `.lua` mission scripts that run inside DCS World. You want a smaller, focused alternative to MOOSE — fewer abstractions, no inheritance, every public symbol documented with a runnable example.

## Install

Load the framework once per mission. From a mission script (Triggers → Do Script File or `dofile` from your own loader):

```lua
dofile("D:/git/dcs-sms/framework/load_all.lua")
-- sms is now available globally
sms.log.info("framework version " .. sms.version)
```

Or via the host-side bridge (see [`tools/cmd/dcs-sms/README.md`](../tools/cmd/dcs-sms/README.md)):

```sh
dcs-sms.exe exec --file framework/load_all.lua
```

## First taste

```lua
local cap = sms.group.create({
  name     = "f18-cap",
  position = {x = 0, y = 0, z = 0},
  country  = sms.K.countries.USA,
  category = "airplane",
  units    = { {type = "FA-18C_hornet", alt = 6000, heading = 90} },
})

local orbit_task = sms.task.orbit({x = 50000, y = 0, z = 0}, {
  altitude = 6000, speed = 200, pattern = "Circle",
})
cap:set_task(orbit_task)

cap:connect(sms.events.DEAD, function(evt)
  sms.log.info("CAP wiped at " .. evt.time)
end)
```

## Reference

- [`docs/api/`](../docs/api/) — per-module reference with runnable examples for every public symbol.
- [`AGENTS.md`](../AGENTS.md) — rules, conventions, and the failure model (log + return nil, never throw).
- [`CHANGELOG.md`](../CHANGELOG.md) — release history; the **Framework** section tracks `framework-v*` tags.

## Versioning

The framework ships under tags `framework-v0.x.y`. The canonical version string is `sms.version` in [`sms.lua`](sms.lua). See [`AGENTS.md` §11](../AGENTS.md#11-versioning-and-releases) for the full versioning rules.
````

- [ ] **Step 3: Verify the snippet uses current symbol names**

Run: `git -C D:/git/dcs-sms grep -c "sms.K.countries.USA" framework/README.md`
Expected: 1

Run: `git -C D:/git/dcs-sms grep -c "sms.countries.USA" framework/README.md`
Expected: 0 (the old name must not appear)

Run: `grep -c '\\`' D:/git/dcs-sms/framework/README.md`
Expected: 0 (no backslash-backtick escapes leaked through).

- [ ] **Step 4: Commit**

```sh
git -C D:/git/dcs-sms add framework/README.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs(framework): add framework/README.md

Self-contained landing page for the in-DCS Lua framework: install
path, a first-taste snippet using current sms.K.* symbol names, and
links to docs/api, AGENTS.md, and the CHANGELOG.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create `docs/release-gate/bridge-smoke.md`

Extract the bridge smoke checklist from `tools/lua/README.md` into its own release-gate page.

**Files:**
- Create: `docs/release-gate/bridge-smoke.md`

- [ ] **Step 1: Create the directory if it doesn't exist**

Run: `mkdir -p D:/git/dcs-sms/docs/release-gate`
Expected: directory now exists.

Run: `ls D:/git/dcs-sms/docs/release-gate/`
Expected: empty (or about to contain `bridge-smoke.md`).

- [ ] **Step 2: Create the file with EXACTLY the content between the four-backtick fences below**

````markdown
# Bridge — manual smoke checklist

Run before tagging a release that touches the bridge (`dcs-sms.exe` host↔DCS subcommands). ~5 minutes.

For installation instructions and subcommand reference, see [`tools/cmd/dcs-sms/README.md`](../../tools/cmd/dcs-sms/README.md). This page is the release-gate procedure only.

## Steps

1. **Build:** `cd tools && go build ./cmd/dcs-sms` — should complete with no warnings.
2. **Install hook:** `./dcs-sms install-hook` — should report success.
3. **Start DCS** and load any single-player mission.
4. **Status:** `./dcs-sms status` — should report `mission loaded: true` and `fresh: true`. Exit code 0.
5. **Smoke exec:** `./dcs-sms exec --code "return 1+1"` — stdout JSON should contain `"ok":true` and `"return_value":2`. Exit code 0.
6. **Print capture:** `./dcs-sms exec --code "print('hello'); return 'world'"` — `output` should be `"hello"`, `return_value` should be `"world"`.
7. **Lua error:** `./dcs-sms exec --code "error('boom')"` — `ok` should be `false`, `error.message` should contain `"boom"`. Exit code 1.
8. **Timeout:** `./dcs-sms exec --code "while true do end" --timeout 2s` — should exit code 2 with a timeout message *and DCS should be hung*. Kill DCS via Task Manager. (Documented limitation, not a regression.)
9. **Tail log:** `./dcs-sms tail-log -n 20` — should print 20 recent dcs.log lines.
10. **Restart DCS** and load a different mission. `./dcs-sms status` should report the new mission name.

If any step misbehaves, check `<Saved Games>\DCS*\dcs-sms\log\hook.log` and `<Saved Games>\DCS*\Logs\dcs.log` for diagnostics.
````

- [ ] **Step 3: Verify the file**

Run: `head -3 D:/git/dcs-sms/docs/release-gate/bridge-smoke.md`
Expected first line: `# Bridge — manual smoke checklist`

Run: `grep -c '\\`' D:/git/dcs-sms/docs/release-gate/bridge-smoke.md`
Expected: 0.

- [ ] **Step 4: Commit**

```sh
git -C D:/git/dcs-sms add docs/release-gate/bridge-smoke.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs(release-gate): extract bridge smoke checklist

Move the manual smoke procedure currently embedded in
tools/lua/README.md into its own release-gate page so the
user-facing CLI README stays focused on install + reference.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create `docs/release-gate/me-mod-smoke.md`

Extract the ME-mod smoke checklist from the current `tools/me-mod/README.md` into its own release-gate page.

**Files:**
- Create: `docs/release-gate/me-mod-smoke.md`

- [ ] **Step 1: Create the file with EXACTLY the content between the four-backtick fences below**

````markdown
# ME-mod — manual smoke checklist

CI runs the parity + unit tests under `tools/me-mod/test/run-tests.ps1`. This checklist is the release-gate before tagging a `me-mod-v*` release; run by hand against a fresh DCS install.

For installation instructions and feature overview, see [`tools/me-mod/README.md`](../../tools/me-mod/README.md). This page is the release-gate procedure only.

## Setup

1. Run `tools/dcs-sms.exe install-me-mod`. Open the ME. Verify the Tools menu has a "DCS-SMS Prefab Manager" entry. Verify the window does NOT appear automatically.
   - If the floating-button fallback fires instead (visible in `dcs.log` as `Tools menu API unavailable; using floating-button fallback`), that's expected on builds where the menu API isn't exposed — verify the floating button appears at top-right and clicking it opens the Manager.
2. Open Tools → "DCS-SMS Prefab Manager". Window appears with all panels (Save / Library / Action / Status).

## Save flow

3. Place one A-10C in the ME. Select it. Type `test_jet` in the name field. Click **Save**. Verify file at `Saved Games\DCS\dcs-sms\prefabs\test_jet.lua` and the library refreshes to show it.
4. With nothing selected, click **Save** with name `empty`. Status: `No selection — nothing to save`. No file written.
5. With selection, click **Save** with name `test_jet` (collision). Modal appears with **Overwrite / Rename / Cancel**. Pick Cancel — no change. Pick Overwrite — file overwritten.
6. Multi-selection: select two groups + one trigger zone + one drawing. Save as `complex_test`. Open the saved file and verify all four sections are populated.

## Place flow — at click

7. Library shows `test_jet` sorted A-Z. Select it, set rotation 0, click **Place at click**. Verify the title bar text changes to `Click on map to place test_jet (Esc to cancel)` and the button text becomes `Cancel`.
8. Click somewhere on the map. Verify the A-10C appears at that location, status confirms placement, **Ctrl-Z** removes it (group disappears from the ME).
9. Re-place `test_jet`. Save the `.miz`, close the ME, reopen the `.miz`. Verify the placed group survived (no dcs-sms-specific state needed at runtime).
10. Place at click with rotation 90. Verify the group is rotated 90° from how it was saved.
11. Place at click then press **Esc**. Verify exit from place-pending, no entity injected.

## Place flow — at original

12. Save a prefab that includes a group near a specific map building. Click **Place at original location**. Verify it lands at the original `meta.world_anchor`, not at any clicked location.

## Best-effort partial-failure

13. Manually corrupt a prefab file to have one valid group + one group with a bogus DCS type. Place it. Verify status: `Placed N of M entities — see dcs.log`. The valid group is in the mission; the corrupt one is logged.

## Library

14. Save 3 prefabs with names `a`, `m`, `z`. Verify the grid is sorted A-Z and shows the documented columns (Name / Theatre / Fixed Pos / AB / G / S / Z / D).
15. Verify the **Theatre** column shows the current theatre name (e.g. `Caucasus`) for prefabs saved under this branch — *not* `?`.
16. Click a row. Verify it highlights and the status bar shows `Selected: <name>`. Click another. Selection moves.
17. Rename `m` to `middle`. Verify the file is renamed AND `meta.name` is updated inside (open the file).
18. Delete `middle`. Confirmation modal. Confirm. Verify file gone, list refreshed.
19. Manually drop a malformed `.lua` file into the prefabs dir. Click **Reload**. Verify it appears as a row with `[ERROR] <name>` in the Name column and a truncated error message in the Theatre column.

## Undo

20. Place a prefab. Press **Ctrl-Z** (window focused). Verify removal.
21. Press **Ctrl-Z** again. Status: `Nothing to undo.`
22. Place. Click somewhere outside the Prefab Manager window to remove its focus. Press **Ctrl-Z**. Verify nothing happens (window not focused — broad ME-wide undo is [issue #25](https://github.com/nielsvaes/dcs-sms/issues/25)).

## Dev reload

23. With the Prefab Manager window focused, press **Ctrl+Shift+R**. Verify the window briefly disappears and reopens (status bar shows `Ready.`). `dcs.log` should contain `dev reload triggered` → `cleared N modules from package.loaded` → `dev reload completed`. Subsequent edits to the mod's Lua files are picked up by another Ctrl+Shift+R, no DCS restart required.

## Cleanup

24. Run `tools/dcs-sms.exe uninstall-me-mod`. Verify everything removed (modules dir gone, `MissionEditor.lua` patch reverted from backup).
````

- [ ] **Step 2: Verify the file**

Run: `head -3 D:/git/dcs-sms/docs/release-gate/me-mod-smoke.md`
Expected first line: `# ME-mod — manual smoke checklist`

Run: `grep -c '\\`' D:/git/dcs-sms/docs/release-gate/me-mod-smoke.md`
Expected: 0.

- [ ] **Step 3: Commit**

```sh
git -C D:/git/dcs-sms add docs/release-gate/me-mod-smoke.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs(release-gate): extract me-mod smoke checklist

Move the 24-step manual smoke procedure currently embedded in
tools/me-mod/README.md into its own release-gate page so the
user-facing ME-mod README stays focused on install + features.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Rewrite `tools/me-mod/README.md`

Replace the current README (which still references the OvGME DIY path, embeds the smoke checklist, and includes a layout-tree section) with a focused user-facing page.

**Files:**
- Modify: `tools/me-mod/README.md`

- [ ] **Step 1: Replace the file with EXACTLY the content between the four-backtick fences below**

Use the Write tool to overwrite `tools/me-mod/README.md` (the file already exists; previous content is replaced wholesale). The new file content is:

````markdown
# dcs-sms — Mission Editor mod

Custom in-editor extension that adds a **Prefab Manager** to DCS World's Mission Editor. Save a selection of groups / statics / zones / drawings to a reusable prefab; place them later by click or at their original location. Supports rotation, country override, airbase warehouse capture, per-ship warehouses, and undo.

## Audience

You design DCS missions in the Mission Editor and want to reuse pieces of one mission in another. You don't need to write any Lua.

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
````

- [ ] **Step 2: Verify the OvGME content is gone and the smoke checklist is no longer embedded**

Run: `git -C D:/git/dcs-sms grep -ic "OvGME" tools/me-mod/README.md`
Expected: `0`.

Run: `git -C D:/git/dcs-sms grep -c "Manual smoke" tools/me-mod/README.md`
Expected: `1` (only the section heading that links to docs/release-gate, not the embedded checklist).

Run: `git -C D:/git/dcs-sms grep -c "## Save flow" tools/me-mod/README.md`
Expected: `0` (the embedded checklist's section headings are gone).

Run: `grep -c '\\`' D:/git/dcs-sms/tools/me-mod/README.md`
Expected: `0`.

- [ ] **Step 3: Commit**

```sh
git -C D:/git/dcs-sms add tools/me-mod/README.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs(me-mod): rewrite README — drop OVGME and smoke embed

Replace the older README that referenced the dead OvGME DIY path
and embedded the 24-step manual smoke checklist. New shape: install
+ uninstall + a feature overview, with the smoke checklist linked
out to docs/release-gate/.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Rewrite root `README.md` as the router

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Replace the file with EXACTLY the content between the four-backtick fences below**

Use the Write tool to overwrite `README.md` with:

````markdown
# dcs-sms

DCS scripting framework, Mission Editor extension, and host-side tooling.

## Components

- **Framework** — in-DCS Lua scripting framework (`sms.*`). [`framework/README.md`](framework/README.md)
- **ME-mod** — DCS Mission Editor extension (Prefab Manager and more). [`tools/me-mod/README.md`](tools/me-mod/README.md)
- **CLI / bridge** — host-side `dcs-sms.exe` for installing the above and live-poking a running mission. [`tools/cmd/dcs-sms/README.md`](tools/cmd/dcs-sms/README.md)

## More

- [`docs/api/`](docs/api/) — framework API reference.
- [`CHANGELOG.md`](CHANGELOG.md) — release history (two parallel tracks).
- [`AGENTS.md`](AGENTS.md) — contributor rules and conventions.
````

- [ ] **Step 2: Verify the size and shape**

Run: `wc -l D:/git/dcs-sms/README.md`
Expected: under 20 lines.

Run: `git -C D:/git/dcs-sms grep -c "MISSION.md" README.md`
Expected: `0` (the old MISSION.md link is gone).

Run: `git -C D:/git/dcs-sms grep -c "tools/lua/README" README.md`
Expected: `0`.

Run: `grep -c '\\`' D:/git/dcs-sms/README.md`
Expected: `0`.

- [ ] **Step 3: Commit**

```sh
git -C D:/git/dcs-sms add README.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs: rewrite root README as a router

Three component links (Framework, ME-mod, CLI), three more-pointers
(docs/api, CHANGELOG, AGENTS). No pitch text — that retires to git
history along with MISSION.md.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Update `docs/api/README.md` cross-link

The framework API index currently routes readers to the old root README for bridge setup. After the restructure that pointer should target the new CLI README.

**Files:**
- Modify: `docs/api/README.md` (line 15)

- [ ] **Step 1: Read the current line to confirm the exact text**

Run: `git -C D:/git/dcs-sms grep -n "for bridge setup" docs/api/README.md`
Expected output (or close to it):

```
docs/api/README.md:15:(Or via the bridge: `./dcs-sms exec --file framework/load_all.lua`. See the top-level [`README.md`](../../README.md) for bridge setup.)
```

- [ ] **Step 2: Edit the line**

In `docs/api/README.md`, replace the entire line that starts with `(Or via the bridge:` so that the new line reads:

```
(Or via the bridge: `./dcs-sms exec --file framework/load_all.lua`. See [`tools/cmd/dcs-sms/README.md`](../../tools/cmd/dcs-sms/README.md) for bridge setup.)
```

The only change is the link target: `../../README.md` → `../../tools/cmd/dcs-sms/README.md`, and the link text changes from `the top-level [`README.md`]` to `[`tools/cmd/dcs-sms/README.md`]`.

- [ ] **Step 3: Verify**

Run: `git -C D:/git/dcs-sms grep -n "tools/cmd/dcs-sms/README.md" docs/api/README.md`
Expected: one match on line 15 (or whichever line the bridge-setup pointer ended up on).

Run: `git -C D:/git/dcs-sms grep -n "the top-level" docs/api/README.md`
Expected: no output (the old reference is gone).

- [ ] **Step 4: Commit**

```sh
git -C D:/git/dcs-sms add docs/api/README.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs(api): redirect bridge-setup pointer to new CLI README

The bridge install instructions moved out of the root README into
tools/cmd/dcs-sms/README.md. Update the cross-link in the API index
to match.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Update `AGENTS.md`

Two edits:
- Remove the `MISSION.md` line from the companion-documents block (the file is being deleted in Task 9).
- Replace the `tools/lua/README.md` reference at line 280 with a pointer to the new release-gate page.

**Files:**
- Modify: `AGENTS.md`

- [ ] **Step 1: Remove the MISSION.md companion line**

In `AGENTS.md`, locate the companion-documents block near the top of the file, which currently reads:

```
> **Companion documents:**
> - [`MISSION.md`](MISSION.md) — vision and rationale.
> - [`docs/api/`](docs/api/) — per-module reference: signatures, options tables, runnable examples, see-also.
> - [`docs/superpowers/specs/`](docs/superpowers/specs/) — per-module design docs (canonical "why is it shaped this way").
> - [`docs/superpowers/plans/`](docs/superpowers/plans/) — implementation plans, often with helpful context.
> - This file is a *summary*. When the spec disagrees with this file, the spec wins.
```

Delete the `MISSION.md` line so the block reads:

```
> **Companion documents:**
> - [`docs/api/`](docs/api/) — per-module reference: signatures, options tables, runnable examples, see-also.
> - [`docs/superpowers/specs/`](docs/superpowers/specs/) — per-module design docs (canonical "why is it shaped this way").
> - [`docs/superpowers/plans/`](docs/superpowers/plans/) — implementation plans, often with helpful context.
> - This file is a *summary*. When the spec disagrees with this file, the spec wins.
```

- [ ] **Step 2: Replace the tools/lua/README.md reference**

In `AGENTS.md`, locate the paragraph in section 10 (the `tools/` overview) that currently ends with the sentence:

```
Agents writing or testing framework code typically use `dcs-sms exec` to run snippets against a running mission. See [`tools/lua/README.md`](tools/lua/README.md) for the full smoke checklist and the one required edit to `Scripts/MissionScripting.lua`.
```

Replace that sentence with:

```
Agents writing or testing framework code typically use `dcs-sms exec` to run snippets against a running mission. See [`tools/cmd/dcs-sms/README.md`](tools/cmd/dcs-sms/README.md) for installation and the required `Scripts/MissionScripting.lua` edit, and [`docs/release-gate/bridge-smoke.md`](docs/release-gate/bridge-smoke.md) for the manual smoke checklist run before each release.
```

- [ ] **Step 3: Verify both edits**

Run: `git -C D:/git/dcs-sms grep -c "MISSION.md" AGENTS.md`
Expected: `0`.

Run: `git -C D:/git/dcs-sms grep -c "tools/lua/README" AGENTS.md`
Expected: `0`.

Run: `git -C D:/git/dcs-sms grep -n "docs/release-gate/bridge-smoke" AGENTS.md`
Expected: one match in the framework-testing paragraph.

Run: `git -C D:/git/dcs-sms grep -n "tools/cmd/dcs-sms/README.md" AGENTS.md`
Expected: one match in the framework-testing paragraph.

- [ ] **Step 4: Commit**

```sh
git -C D:/git/dcs-sms add AGENTS.md
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs(agents): drop MISSION.md, redirect bridge-smoke pointer

MISSION.md retires to git history; the standalone tools/lua/README
likewise. The framework-testing paragraph now points at the new
CLI README for setup and at docs/release-gate/bridge-smoke.md for
the release procedure.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Delete dead files

Three deletions: `MISSION.md`, `tools/lua/README.md`, and the entire `tools/me-mod/ovgme/` skeleton tree (which includes its README and an empty MissionEditor scaffold).

**Files:**
- Delete: `MISSION.md`
- Delete: `tools/lua/README.md`
- Delete: `tools/me-mod/ovgme/` (entire directory)

- [ ] **Step 1: Verify all three exist before deletion**

Run: `ls D:/git/dcs-sms/MISSION.md D:/git/dcs-sms/tools/lua/README.md D:/git/dcs-sms/tools/me-mod/ovgme/`
Expected: all three exist; no errors.

- [ ] **Step 2: Verify nothing in tracked code currently references the to-be-deleted paths beyond what we already updated**

Run:

```sh
git -C D:/git/dcs-sms grep -nE "(^|[^/])MISSION\.md|tools/lua/README|tools/me-mod/ovgme" -- '*.md' '*.lua' '*.go' '*.yml' '*.yaml' ':!docs/superpowers/'
```

Expected: NO matches. (Tasks 6 + 8 removed the only live references; the `:!docs/superpowers/` exclusion ignores historical specs/plans, which legitimately reference these paths and should not be edited.)

If this command produces matches, STOP. Investigate the match and update the referencing file before proceeding to deletion.

- [ ] **Step 3: Delete the three paths**

```sh
git -C D:/git/dcs-sms rm MISSION.md
git -C D:/git/dcs-sms rm tools/lua/README.md
git -C D:/git/dcs-sms rm -r tools/me-mod/ovgme
```

- [ ] **Step 4: Verify all three are gone from working tree and from the index**

Run: `ls D:/git/dcs-sms/MISSION.md 2>/dev/null && echo STILL_PRESENT || echo gone`
Expected: `gone`.

Run: `ls D:/git/dcs-sms/tools/lua/`
Expected: directory exists but no README.md inside (other Lua files in `tools/lua/` are unrelated and stay).

Run: `ls -d D:/git/dcs-sms/tools/me-mod/ovgme 2>/dev/null && echo STILL_PRESENT || echo gone`
Expected: `gone`.

Run: `git -C D:/git/dcs-sms status --short | head -20`
Expected: three (or more, due to the ovgme subtree) `D` entries for the deletions.

- [ ] **Step 5: Commit**

```sh
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs: delete MISSION.md, tools/lua/README, tools/me-mod/ovgme

Pitch retires to git history. Bridge install content folded into
tools/cmd/dcs-sms/README.md. OVGME install path was officially
dropped when dcs-sms.exe became the canonical installer.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Final stale-reference scan

Catch any remaining live references to the deleted paths or any cross-link that points at the old root README structure.

**Files:**
- Possibly modify any file flagged by the grep (most likely none, since Tasks 6/8 cleared the known cases).

- [ ] **Step 1: Run a comprehensive grep for stale references**

```sh
git -C D:/git/dcs-sms grep -nE "(^|[^/])MISSION\.md|tools/lua/README|tools/me-mod/ovgme" -- '*.md' '*.lua' '*.go' '*.yml' '*.yaml' ':!docs/superpowers/'
```

Expected: NO matches.

If matches appear, fix each one (delete the line if the reference is no longer meaningful, or redirect to the new location).

- [ ] **Step 2: Verify the new structure resolves on disk**

Run:

```sh
ls D:/git/dcs-sms/README.md \
   D:/git/dcs-sms/framework/README.md \
   D:/git/dcs-sms/tools/me-mod/README.md \
   D:/git/dcs-sms/tools/cmd/dcs-sms/README.md \
   D:/git/dcs-sms/docs/release-gate/bridge-smoke.md \
   D:/git/dcs-sms/docs/release-gate/me-mod-smoke.md
```

Expected: all six files exist.

- [ ] **Step 3: Verify the root README router links resolve**

```sh
git -C D:/git/dcs-sms grep -E "\(framework/README\.md\)|\(tools/me-mod/README\.md\)|\(tools/cmd/dcs-sms/README\.md\)" README.md
```

Expected: one match per component link (three lines of output total).

- [ ] **Step 4: Verify component READMEs cross-link forward and back correctly**

Run:

```sh
git -C D:/git/dcs-sms grep -nE "\.\./.*README\.md|\.\./AGENTS\.md|\.\./CHANGELOG\.md|\.\./docs/" framework/README.md tools/me-mod/README.md tools/cmd/dcs-sms/README.md
```

Expected: every line printed contains a relative path. Spot-check 2-3 of them by resolving the relative path against the file's location and confirming the target exists on disk.

- [ ] **Step 5: If Steps 1–4 produced any fixes, commit them. If not, report no-op and skip the commit.**

If commits are needed:

```sh
git -C D:/git/dcs-sms add -A
git -C D:/git/dcs-sms commit -m "$(cat <<'EOF'
docs: stale-reference fixups after README restructure

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If no commits are needed, report: "Final scan: no stale references; nothing to commit."

---

## Self-review notes

- **Spec coverage** — every decision in the spec's Decisions section maps to a concrete task: CLI gets its own README (Task 1), READMEs co-located with code (Tasks 1+2+5), no pitch on landing page (Tasks 6+9), smoke checklists move to `docs/release-gate/` (Tasks 3+4), OVGME tree deleted (Task 9), `tools/lua/README.md` deleted with content folded into Task 1, `docs/api/` left alone except for the line-15 fix (Task 7).
- **Placeholder scan** — every file's contents are written out in full inside the plan; no "TBD" / "TODO" / "fill in" steps. Verification commands are exact `git grep` / `ls` / `wc` invocations with explicit expected output.
- **Type / name consistency** — the framework first-taste snippet uses `sms.K.countries.USA` (matches the actual constant defined at `framework/constants/countries.lua`); the `gen-units` blurb references `framework/constants/` rather than naming a specific output file (matches the actual catalog directory). The CLI README's relative paths (`../../me-mod/README.md`, `../../../AGENTS.md`) are computed against the file's location at `tools/cmd/dcs-sms/README.md`.
- **Commit boundaries** — each task ends in a single commit; ten tasks → up to ten commits (Task 10 may be a no-op). All messages follow the project's `docs(<scope>):` conventional-commit style.
