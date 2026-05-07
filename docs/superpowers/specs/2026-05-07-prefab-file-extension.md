## Prefab file extension — `.lua` → `.prefab` — Design

**Date:** 2026-05-07
**Status:** Brainstorm
**Scope:** Switch the on-disk extension for prefab files from `.lua` to `.prefab`. ME-mod writes new files as `.prefab`, both ME-mod and framework loaders accept either extension, and ME-mod silently migrates existing `.lua` prefabs to `.prefab` as it scans the prefabs directory. The file *content* (a Lua chunk that returns a table) does not change.

## Goal

A user browsing `Saved Games/DCS/dcs-sms/prefabs/` in Explorer should see `farp_alpha.prefab`, not `farp_alpha.lua`. The `.lua` extension confuses users into thinking these are editable Lua scripts (one user already hit this). The new extension is a no-op semantically — `dofile` ignores the suffix — but it carries the right signal: "this is a dcs-sms data file, not source you edit".

## Non-goals

- **Format change.** The file content stays a Lua chunk returning `{ meta = {...}, groups = {...}, ... }`. We are not switching to JSON / TOML / a binary format. Doing so would break the "accept either extension" path because `.lua` files would still need `dofile`.
- **Windows file association / custom icon.** Out of scope. `.prefab` is just an extension to us; the OS treats it as unknown, which is fine.
- **Renaming the prefabs directory.** `Saved Games/DCS/dcs-sms/prefabs/` stays as-is.
- **Auto-migration in framework runtime code.** `sms.prefab.load_dir` reads-only; it does not rename files on disk. Migration is an ME-mod concern (where users actively manage their library).

## Affected sites

ME-mod:
- `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua:20` — `prefab_path()` builds save target with `.lua`. Switch to `.prefab`.
- `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua:186-187` — `scan_dir`'s entry filter currently matches `%.lua$` and strips it. Change to match `%.lua$` *or* `%.prefab$`, and strip whichever extension the entry actually has (so the display name "foo" comes out the same regardless).
- `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua:171-207` — extend `scan_dir` to attempt `os.rename` on `.lua` entries before loading them.
- `tools/me-mod/lua/dcs_sms_me/window.lua:1241` — rename-file builds new path with `.lua`. Switch to `.prefab` (and ideally route through the `prefab_path` helper rather than reconstructing).

Framework:
- `framework/prefab.lua:103` — `load_dir`'s entry filter (`%.lua$`). Accept both `.lua` and `.prefab`. No rename — read-only.

Tests:
- `tools/me-mod/test/fixtures/prefabs_dir/sam_site.lua` — keep this fixture under its `.lua` name to exercise the legacy-read path. Add a sibling `*.prefab` fixture so both extensions are covered. Tests for `scan_dir` should additionally verify the rename behavior (write a `*.lua` fixture into a temp dir, scan, assert `.prefab` exists and `.lua` doesn't).
- Existing tests that assert `path` strings ending in `.lua` need updating to match the new save extension.

Docs:
- `docs/api/prefab.md` — example paths switch to `.prefab`. One-sentence note that `.lua` is still read for back-compat.
- `CHANGELOG.md` — entry under both ME-mod and framework sections.

Versions:
- ME-mod: `0.4.1 → 0.4.2` (user-visible change in saved files; back-compat preserved).
- Framework: `sms.version` `0.10.0 → 0.11.0` (new accepted extension in `load_dir`; back-compat preserved).
- This spec touches public surface (the file format users see + a framework loader's accepted inputs), so AGENTS.md / docs/api updates land in the same change-set per the project's sync rule. AGENTS.md §7 module index does *not* change (no new `sms.*` module).

## Migration behavior (ME-mod `scan_dir`)

For each `*.lua` entry encountered while walking `prefabs/`:

1. Compute `new_path = prefabs_dir .. name .. '.prefab'`.
2. If `new_path` already exists on disk: log a `WARNING` at `sms.me.prefab` ("collision: foo.lua and foo.prefab both present, leaving as-is") and proceed to load the `.lua` file under its original name. Both files will appear in the Manager's list (visually duplicated since they share the same display name); the user can resolve manually. This is not expected to occur in practice.
3. Otherwise call `os.rename(old_path, new_path)`.
4. If rename fails (locked file, permissions, AV interference): log `WARNING`, fall through, load the file under its original `.lua` path. Next scan retries.
5. On success: load from `new_path`. The Manager row reflects the new extension transparently.

The migration is silent in the UI — no banner, no status-bar count, no toast. The display name (no extension) is unchanged from the user's perspective. We log each rename at `INFO` for diagnosability ("migrated foo.lua → foo.prefab"), but no user-visible chrome.

## Test plan

ME-mod (Lua, run via `tools/me-mod/test/run-tests.ps1`):
- `test_prefab_ops_save.lua` — assert saved path ends in `.prefab`, file content unchanged.
- `test_prefab_ops_load.lua` — load a `.prefab` fixture, load a `.lua` fixture, both succeed.
- New: `test_prefab_ops_scan_migrate.lua` — set up a temp prefabs dir with one `.lua` file, run `scan_dir`, assert (a) file now ends in `.prefab`, (b) row appears in result, (c) original `.lua` is gone. Also test the collision case (both files present → warning logged, both still readable).

Framework (Lua, run via `framework/test/run_distill_tests.ps1` or equivalent):
- Extend any `load_dir` test to verify both extensions are walked. If no `load_dir` test exists, add a minimal one.

Manual smoke (post-merge):
- Save a prefab via the Manager → confirm `.prefab` extension on disk.
- Drop an old `.lua` prefab into the dir → open Manager → confirm it's renamed to `.prefab` and listed correctly.
- Open a mission with `sms.prefab.load_dir(...)` against a directory containing both extensions → confirm both load.

## Open questions

None. Migration policy (auto-rename on scan), collision policy (skip + warn), and framework-side policy (read both, never rename) are settled.
