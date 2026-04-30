# dcs-sms

**Digital Combat Simulator Simple Mission Scripting** — a focused Lua scripting framework for DCS missions, plus host-side tools for driving DCS programmatically.

- [`MISSION.md`](MISSION.md) — project vision and rationale.
- [`docs/api/`](docs/api/) — per-module reference with worked code examples (start here if you're writing missions).
- [`docs/api/examples.md`](docs/api/examples.md) — copy-and-paste cookbook of cross-module recipes.
- [`AGENTS.md`](AGENTS.md) — framework rules, conventions, and contributor workflow for AI agents and humans writing framework code.

## Repo layout

- `tools/` — host-side Go tooling. Currently: a CLI (`dcs-sms.exe`) that executes Lua snippets in a running DCS mission and reads back structured results. Hook for DCS lives at `tools/lua/dcs-sms-hook.lua` and is embedded into the binary.
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.targets`, `sms.designations`, `sms.group` (+ `sms.spawn` factories), `sms.unit`, `sms.area`, `sms.timer`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`, `sms.commands`, `sms.options`. See [`AGENTS.md`](AGENTS.md) for cross-cutting rules and conventions, or [`docs/api/`](docs/api/) for per-function detail.
- `docs/api/` — user-facing API reference, one page per module.
- `docs/superpowers/specs/` — design documents for each sub-project.
- `docs/superpowers/plans/` — implementation plans.

## Quick start (mission framework)

Load the framework into a running mission. From a mission script:

```lua
dofile("D:/git/dcs-sms/framework/load_all.lua")
-- sms is now available globally
sms.log.info("framework version " .. sms.version)
```

Or via the host-side bridge (see below):

```sh
./dcs-sms exec --file framework/load_all.lua
```

Once loaded, every doc snippet in [`docs/api/`](docs/api/) and [`docs/api/examples.md`](docs/api/examples.md) assumes `sms` is the global namespace. A first taste:

```lua
local cap = sms.group.create({
  name = "f18-cap",
  position = {x = 0, y = 0, z = 0},
  country = "USA",
  category = "airplane",
  units = { {type = "FA-18C_hornet", alt = 6000, heading = 90} },
})

cap:set_task(sms.task.orbit({x = 50000, y = 0, z = 0}, {
  altitude = 6000, speed = 200, pattern = "Circle",
}))

cap:connect(sms.events.DEAD, function(evt)
  sms.log.info("CAP wiped at " .. evt.time)
end)
```

For the full surface, see [`docs/api/`](docs/api/).

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
