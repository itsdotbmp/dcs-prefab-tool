<p align="center">
  <img src="../../../assets/logo.png" alt="Coconut Cockpit" width="160">
</p>

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

Writes `dcs-sms-hook.lua` into `<Saved Games>\DCS*\Scripts\Hooks` (auto-detected, or pass `--saved-games <path>` to override). Run once after installing or updating the binary.

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
