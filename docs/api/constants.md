# `sms`, `sms.targets`, `sms.designations`, `load_all` — root namespace, constants, loader

This page consolidates the four small foundational pieces of dcs-sms: the root namespace itself (`sms`), the two constants tables (`sms.targets` and `sms.designations`) used by task builders, and the framework bootstrap loader (`framework/load_all.lua`).

For the overarching error-handling contract that every function below participates in, see the [framework failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw). Dense surface map: [`AGENTS.md` §6–§7](../../AGENTS.md).

## Loading

The constants tables are populated by `framework/targets.lua` and `framework/designations.lua`. Load order (per `load_all.lua`): `sms.lua → log.lua → utils.lua → targets.lua → designations.lua → …`. There are no caller-visible load-order surprises — running `load_all.lua` once is enough.

---

## `sms` (root namespace)

The single global the framework owns. Created idempotently by `framework/sms.lua` (so reloading the framework after edits is safe).

### `sms.version`

**Synopsis** — string holding the framework version.

**Type** — `string` (semver, e.g. `"0.1.0"`).

**Example**

```lua
sms.log.info("running dcs-sms " .. sms.version)
```

### Internal helpers

The following are exposed on `sms` for use by entity-wrapper modules (`sms.group`, `sms.unit`, `sms.area`, `sms.static`, …). **Most users do not need them** — they're documented here only because they're visible on the global namespace.

- `sms._make_handle(module, name)` — internal. Builds a `{name = name}` handle whose metatable's `__index` is `module`, without verifying the entity exists. Used by event reporting paths that need a handle for an already-dead unit.
- `sms._make_callable_handle(module, dcs_getter, module_log)` — internal. Wires a `__call` metamethod on `module` so `module("name")` returns a handle (or `nil` + log if `dcs_getter(name)` returns `nil`). Used by `sms.group` and `sms.unit`.
- `sms._is_handle_of(value, module)` — internal. Returns `true` iff `value` is a table whose metatable's `__index` is exactly `module`. Used for cross-module strict handle-type validation (e.g. `sms.area` checking that an argument is a real `sms.unit` handle and not a bare table).

---

## `sms.targets` (target attribute constants)

Named constants for the DCS target-attribute strings consumed by enroute engagement task builders ([`sms.task.engage_en_route_*`](task.md), [`sms.task.escort`](task.md), and any other builder that filters targets by attribute).

Builders accept either these constants (recommended — typo-checked) or raw strings (forward-compat for new DCS attributes the framework hasn't catalogued yet).

| Constant | Resolves to | Used by |
|---|---|---|
| `sms.targets.AIR` | `"Air"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.PLANES` | `"Planes"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.HELICOPTERS` | `"Helicopters"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.GROUND_UNITS` | `"Ground Units"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.GROUND_VEHICLES` | `"Ground vehicles"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.SHIPS` | `"Ships"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.AIR_DEFENCE` | `"Air Defence"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.SAM` | `"SAM"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.AAA` | `"AAA"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.STATICS` | `"Static"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.BUILDINGS` | `"Buildings"` | enroute engagement task builders ([`sms.task`](task.md)) |
| `sms.targets.ALL` | `"All"` | enroute engagement task builders ([`sms.task`](task.md)) |

**Example**

```lua
-- Tell a CAP flight to engage any air target it sees enroute.
local cap = sms.group("blue-cap-1")
sms.task.engage_en_route_targets(cap, {
  target_types = { sms.targets.AIR },
  max_distance = 80000,           -- meters
})

-- Equivalent using the raw string (forward-compat path):
sms.task.engage_en_route_targets(cap, {
  target_types = { "Air" },
  max_distance = 80000,
})
```

**Notes** — DCS treats these as exact-match strings; the spelling and casing in the table above is what the engine expects. Prefer the constants so a typo is caught at parse time rather than silently producing a no-op task.

---

## `sms.designations` (FAC designation constants)

Named constants for the DCS FAC designation enum strings consumed by [`sms.task.fac_attack_group`](task.md) and [`sms.task.fac_engage_group`](task.md).

As with `sms.targets`, builders accept either these constants (recommended) or raw strings.

| Constant | Resolves to | Used by |
|---|---|---|
| `sms.designations.NO` | `"No"` | [`sms.task.fac_attack_group`](task.md), [`sms.task.fac_engage_group`](task.md) |
| `sms.designations.AUTO` | `"Auto"` | [`sms.task.fac_attack_group`](task.md), [`sms.task.fac_engage_group`](task.md) |
| `sms.designations.WP` | `"WP"` (white phosphorus marker) | [`sms.task.fac_attack_group`](task.md), [`sms.task.fac_engage_group`](task.md) |
| `sms.designations.IR_POINTER` | `"IR-Pointer"` | [`sms.task.fac_attack_group`](task.md), [`sms.task.fac_engage_group`](task.md) |
| `sms.designations.LASER` | `"Laser"` | [`sms.task.fac_attack_group`](task.md), [`sms.task.fac_engage_group`](task.md) |

**Example**

```lua
-- A JTAC marks an enemy convoy with a laser for a CAS flight to attack.
local jtac     = sms.group("blue-jtac-1")
local target_g = sms.group("red-convoy-1")

sms.task.fac_attack_group(jtac, target_g, {
  designation = sms.designations.LASER,
  frequency   = 30,         -- MHz
  modulation  = "AM",
})
```

---

## `load_all.lua` (framework loader)

`framework/load_all.lua` is a one-shot loader that `dofile`s every framework module in dependency order. Run it once at mission start to bring up the whole framework, or re-run it to reload every module after edits.

The fixed load order is:

1. `sms.lua`
2. `log.lua`
3. `utils.lua`
4. `targets.lua`
5. `designations.lua`
6. `group.lua`
7. `unit.lua`
8. `area.lua`
9. `timer.lua`
10. `group_spawn.lua`
11. `static.lua`
12. `events.lua`
13. `weapon.lua`
14. `task.lua`

After completion the loader prints a single `env.info` line of the form `[sms] framework loaded (N modules, version X.Y.Z)`.

### Invocation

There are two supported invocation paths:

**1. From a mission script (canonical):**

```lua
dofile("D:/git/dcs-sms/framework/load_all.lua")

-- After this call, every sms.* symbol is available:
sms.log.info("dcs-sms " .. sms.version .. " ready")
```

This is the only place in the API reference where `dofile(...)` appears — every other example assumes the framework is already loaded.

**2. Via the bridge:**

```
dcs-sms exec --file framework/load_all.lua
```

See the top-level [`README.md`](../../README.md) for bridge setup.

### `FALLBACK_DIR`

```lua
local FALLBACK_DIR = "D:/git/dcs-sms/framework/"
```

When loaded via `dofile`, the loader auto-derives its own directory from the chunkname (`debug.getinfo(1, "S").source`). When loaded via the bridge, `net.dostring_in` does not set a chunkname, so `FALLBACK_DIR` is used instead.

**If the repo lives somewhere other than `D:/git/dcs-sms/`, edit `FALLBACK_DIR` in `framework/load_all.lua`.** Mission-script `dofile` users are unaffected — only the bridge invocation depends on the constant.
