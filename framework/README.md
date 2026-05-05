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
