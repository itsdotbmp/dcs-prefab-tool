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
