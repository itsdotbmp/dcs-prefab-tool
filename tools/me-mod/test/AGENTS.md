# tools/me-mod/test/AGENTS.md — running the ME-mod Lua test suite

The tests in this directory exercise pure-Lua modules from `tools/me-mod/lua/dcs_sms_me/` against stubbed DCS APIs. They run on a standalone **Lua 5.1** interpreter — no DCS install required. They are also our *only* automated coverage for prefab serialization, prefab-folder ops, the marquee hook, and `verbs.lua` route logic, so keep them passing.

This file tells future agents two things: (1) how to get a Lua 5.1 interpreter onto a machine that doesn't have one, and (2) how to invoke the suite.

## 1 — Install Lua 5.1

The runner (`run-tests.ps1`) looks for `lua.exe`, `lua5.1.exe`, or `lua51.exe` on `PATH`. The framework targets Lua 5.1.5 (matches DCS's embedded interpreter), so install that version specifically — not 5.4.

### Windows (recommended path: direct LuaBinaries zip)

Scoop's `lua-for-windows` *should* work via `scoop install lua-for-windows`, but its `innounp` dependency can fail to install on some PowerShell configurations (`Get-FileHash` not recognized). When that happens, grab the precompiled zip from LuaBinaries directly — no installer, no admin rights:

```powershell
$dest = "$env:USERPROFILE\bin\lua51"
$zip  = "$env:TEMP\lua-5.1.5_Win64_bin.zip"
# Direct mirror — the bare downloads.sourceforge.net URL serves an HTML
# redirect page that Invoke-WebRequest can't follow without JS.
$url  = 'https://master.dl.sourceforge.net/project/luabinaries/5.1.5/Tools%20Executables/lua-5.1.5_Win64_bin.zip?viasf=1'

New-Item -ItemType Directory -Force -Path $dest | Out-Null
Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -UserAgent 'Mozilla/5.0'
Expand-Archive -Path $zip -DestinationPath $dest -Force

# Persist on the user PATH so future shells (and run-tests.ps1) find it.
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $dest) {
    [Environment]::SetEnvironmentVariable('Path', "$dest;$userPath", 'User')
}
# Current session too (existing shells don't pick up the env-var change).
$env:Path = "$dest;$env:Path"

lua5.1.exe -v   # → Lua 5.1.5  Copyright (C) 1994-2012 Lua.org, PUC-Rio
```

The zip ships `lua5.1.exe`, `luac5.1.exe`, `lua5.1.dll`, and a couple of small helpers. Total install: ~1 MB, no admin required.

If you'd rather use the official SourceForge web page, the source project is [`luabinaries`](https://sourceforge.net/projects/luabinaries/files/) — pick `5.1.5/Tools Executables/lua-5.1.5_Win64_bin.zip`.

### macOS / Linux

```sh
# macOS
brew install lua@5.1
brew link --force lua@5.1     # exposes /usr/local/bin/lua5.1

# Debian/Ubuntu
sudo apt install lua5.1
```

Either gives you `lua5.1` on `PATH`, which the runner finds. (On macOS the brew binary is named `lua5.1`, not `lua.exe`; that's still one of the names `run-tests.ps1` checks.)

## 2 — Run the suite

```sh
cd tools/me-mod/test
pwsh ./run-tests.ps1            # or powershell.exe on Windows
```

Each `test_*.lua` is invoked in its own interpreter process. The runner aborts on the first non-zero exit code (set by individual `check()` calls via `os.exit(1)`).

To run a single test directly (faster feedback while iterating):

```sh
cd tools/me-mod/test
lua5.1 test_prefab_ops_rename_file.lua
```

## 3 — Conventions for new tests

- Place fixtures in `tools/me-mod/test/fixtures/` and reference them with relative paths.
- Use the `check(label, ok)` pattern (`if ok then PASS else FAIL + exit 1`) — every existing test does this, and `run-tests.ps1`'s pass/fail aggregation depends on it.
- Stub DCS modules via `package.preload[...]`. Common stubs: `lfs`, `dcs_sms_me.selection`, `Mission.AirdromeController`. Add the stub *before* requiring the module under test.
- **`os.tmpname()` is unsafe on the Windows LuaBinaries build.** It returns paths like `\s5vg.` rooted at `C:\` which the current user can't write to. If you need a temp file, prepend `%TEMP%` when the path is root-relative — see `test_prefab_ops_airbases.lua` for the pattern.
- Add the new test filename to the `$tests` array in `run-tests.ps1` so it's part of CI.

## 4 — When the harness isn't enough

If your verb hits heavy ME-internal APIs (panel refresh, map-object refresh, dictionary lifecycle), a pure-Lua test won't cover the full path. Add a manual checklist item in [`../../../docs/release-gate/me-mod-smoke.md`](../../../docs/release-gate/me-mod-smoke.md) instead. The Go side (`tools/cmd/dcs-sms/me_*_test.go`) is the right place for flag-parsing and CLI-shape coverage.
