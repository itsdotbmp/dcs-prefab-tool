# dcs-sms hook — install and smoke checklist

This document covers (a) installing `dcs-sms-hook.lua` into DCS and (b) the manual smoke tests that should pass before any release.

## Install

The hook is embedded into the `dcs-sms` binary. The recommended install path:

```sh
dcs-sms install-hook
```

This writes `dcs-sms-hook.lua` into `<Saved Games>\DCS*\Scripts\Hooks\` (auto-detected, or pass `--saved-games <path>` to override).

You also need to edit `Scripts\MissionScripting.lua` in your DCS *install* directory (not Saved Games). Comment out:

```lua
do
  -- sanitizeModule('os')
  -- sanitizeModule('io')
  -- sanitizeModule('lfs')
  ...
end
```

This is the same modification `dcs_code_injector` requires — the hook needs `lfs.dir` to scan its inbox, and `os.rename` to write responses atomically.

## Manual smoke checklist

Run before each release. ~5 minutes.

1. **Build:** `cd tools && go build ./cmd/dcs-sms` — should complete with no warnings.
2. **Install hook:** `./dcs-sms install-hook` — should report success.
3. **Start DCS** and load any single-player mission.
4. **Status:** `./dcs-sms status` — should report `mission loaded: true` and `fresh: true`. Exit code 0.
5. **Smoke exec:** `./dcs-sms exec --code "return 1+1"` — stdout JSON should contain `"ok":true` and `"return_value":2`. Exit code 0.
6. **Print capture:** `./dcs-sms exec --code "print('hello'); return 'world'"` — `output` should be `"hello"`, `return_value` should be `"world"`.
7. **Lua error:** `./dcs-sms exec --code "error('boom')"` — `ok` should be `false`, `error.message` should contain `"boom"`. Exit code 1.
8. **Timeout:** `./dcs-sms exec --code "while true do end" --timeout 2s` — should exit code 2 with a timeout message *and DCS should be hung*. Kill DCS via Task Manager. (This is a documented limitation, not a regression.)
9. **Tail log:** `./dcs-sms tail-log -n 20` — should print 20 recent dcs.log lines.
10. **Restart DCS** and load a different mission. `./dcs-sms status` should report the new mission name.

If any step misbehaves, check `<Saved Games>\DCS*\dcs-sms\log\hook.log` and `<Saved Games>\DCS*\Logs\dcs.log` for diagnostics.
