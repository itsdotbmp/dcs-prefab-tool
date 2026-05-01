# `sms.countries` — DCS country enum

Hand-maintained table of every well-known DCS `country.id` key, exposed as `sms.countries.<KEY>`. Mission code uses these constants instead of magic-string `country = "USA"` literals — autocomplete in any LuaCATS-aware editor lists every supported country, and a typo (`sms.countries.USAa`) becomes a static type error instead of a runtime resolve failure.

The framework's `country` spawn-config field is annotated with the `sms.Country` alias, so `country = "USA"` literals are typo-checkable in LuaCATS-aware editors too.

All entries follow the invariant `sms.countries.X == "X"` — values are the upper-snake form `country.id` itself uses. `sms.utils.resolve_country` is case-insensitive and folds spaces to underscores, so `country = sms.countries.UNITED_KINGDOM`, `country = "United Kingdom"`, and `country = "united kingdom"` all resolve to the same DCS country int.

## Loading

Requires `sms.lua` and `log.lua`. Loaded automatically by `framework/load_all.lua` after `utils.lua`.

## Usage

```lua
local cap = sms.group.create({
  name     = "blue-cap",
  position = {x = 0, y = 0, z = 0},
  country  = sms.countries.USA,
  category = "airplane",
  units    = { {type = sms.units.planes.FA_18C_hornet, alt = 6000, heading = 90} },
})

local convoy = sms.group.create({
  name     = "red-convoy",
  position = {x = 50000, y = 0, z = 0},
  country  = sms.countries.RUSSIA,
  category = "ground",
  units    = { {type = sms.units.unarmed.Ural_4320T, heading = 270} },
})
```

## The `sms.Country` alias

`sms.Country` is a LuaCATS string alias listing every key in `sms.countries`. The `country` field on `sms.group.create` and `sms.static.create` configs is annotated `sms.Country|string`, so:

- `country = sms.countries.USA` — autocompleted, type-safe.
- `country = "USA"` — accepted, autocompleted from the alias.
- `country = "United Kingdom"` — accepted as `string` (the alias doesn't enumerate display variants); resolves at runtime.
- `country = "USAa"` — accepted as `string` by the type checker, but `resolve_country` returns nil and the spawn fails with a `log.warn` per the [framework failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw).

The `|string` half of the union exists because `resolve_country` is case-and-space-tolerant and we don't want LSP red squiggles on `"united kingdom"`.

## Runtime drift check

DCS occasionally adds new countries (`country.id` keys) between releases. `framework/countries.lua` runs a one-time check at load time:

1. Walk `country.id` keys.
2. For each key not in the static `sms.countries` table, add it to the table at runtime AND log a single `warn` line:

   ```
   [sms.countries] country.id key 'NEW_COUNTRY' not in static list — added at runtime; update framework/countries.lua to keep autocomplete in sync
   ```

This means spawn calls keep working forever — the framework never blocks on a stale country list — but the missing key is visible in `dcs.log` so the static list (and the autocomplete) gets updated when someone notices.

## Why upper-snake?

`country.id` itself is a hash keyed by upper-snake names (`country.id.USA`, `country.id.UNITED_KINGDOM`). Mirroring those keys gives:

- The `sms.countries.X == "X"` invariant — easy to reason about.
- `sms.utils.resolve_country(sms.countries.X)` is identical to `sms.utils.resolve_country("X")` — no surprises.
- Round-trip with `country.id` is trivial; no string-form translation needed.

Display variants like `"United Kingdom"` aren't first-class — `resolve_country` accepts them, but the enum picks the one canonical form.

## Handling unknown countries

There is no `sms.countries.from_int(n)` reverse lookup. If a unit handle gives you a country int and you need a human-readable name, walk `country.id` directly:

```lua
local function name_from_int(n)
  for k, v in pairs(country.id) do
    if v == n then return k end
  end
end
```

This is intentionally not framework code — the use case is rare, the helper is three lines, and inlining keeps the framework surface small.

**See also** — [`sms.utils.resolve_country`](utils.md#smsutilsresolve_countrys--integer--nil) for the runtime resolution helper, [`sms.units`](units.md) for the parallel unit-type catalog, [`sms.group.create`](group.md) for the spawn config that consumes `country`.
