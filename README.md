# dcs-sms

**Digital Combat Simulator Simple Mission Scripting** — a focused Lua scripting framework for DCS missions, plus host-side tools for driving DCS programmatically.

- [`MISSION.md`](MISSION.md) — project vision and rationale.
- [`AGENTS.md`](AGENTS.md) — dense framework reference for AI agents and human contributors writing framework code.

## Repo layout

- `tools/` — host-side Go tooling. Currently: a CLI (`dcs-sms.exe`) that executes Lua snippets in a running DCS mission and reads back structured results. Hook for DCS lives at `tools/lua/dcs-sms-hook.lua` and is embedded into the binary.
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.group`, `sms.unit`, `sms.area`, `sms.timer`, `sms.spawn` (factories on `sms.group`), `sms.static`, `sms.events`. See [`AGENTS.md`](AGENTS.md) for the surface and conventions.
- `docs/superpowers/specs/` — design documents for each sub-project.
- `docs/superpowers/plans/` — implementation plans.

## Quick start (execution bridge)

Build the CLI:

```sh
cd tools
go build ./cmd/dcs-sms
```

Install the hook into your DCS Saved Games folder:

```sh
./dcs-sms install-hook
```

Edit `Scripts/MissionScripting.lua` in your DCS install dir to comment out the `sanitizeModule('os')`, `('io')`, and `('lfs')` lines. (The hook needs `lfs` to scan the mailbox; this is the same modification the older `dcs_code_injector` requires.)

Start DCS, load any mission, then:

```sh
./dcs-sms status                      # confirm hook is alive
./dcs-sms exec --code "return 1+1"    # run a snippet
./dcs-sms tail-log -n 20              # see the last 20 dcs.log lines
```

See `tools/lua/README.md` for the full install / smoke-test checklist.
