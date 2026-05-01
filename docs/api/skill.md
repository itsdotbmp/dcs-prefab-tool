# `sms.skill` — DCS unit skill levels

Hand-maintained enum of the seven DCS strings accepted on the `skill` field of unit specs:

```lua
sms.group.create({
  name = "blue-cap",
  position = {x = 0, y = 0, z = 0},
  country = sms.countries.USA,
  category = "airplane",
  units = {
    {type = sms.units.planes.F_16C_50, alt = 6000, heading = 90,
     skill = sms.skill.AVERAGE},
  },
})
```

Authoring `skill = sms.skill.AVERAGE` instead of `skill = "Average"` gets autocomplete (the table lists every value), prevents typos at edit time, and makes a future search-and-replace across mission scripts trivial. The framework's `sms.group.unit_spec.skill` field is annotated `sms.Skill|string`, so a raw-string `skill = "Average"` is also typo-checkable in LuaCATS-aware editors.

Values follow the invariant `sms.skill.X` resolves to the verbatim DCS string (`"Average"` etc., case-sensitive).

## Loading

Requires `sms.lua` and `log.lua`. Loaded automatically by `framework/load_all.lua` after `countries.lua`.

## Values

| Constant | DCS string | Use |
|---|---|---|
| `sms.skill.AVERAGE` | `"Average"` | Default for AI units. |
| `sms.skill.GOOD` | `"Good"` | Slightly above average. |
| `sms.skill.HIGH` | `"High"` | Skilled AI. |
| `sms.skill.EXCELLENT` | `"Excellent"` | Top tier. |
| `sms.skill.RANDOM` | `"Random"` | DCS picks a level at spawn time. |
| `sms.skill.PLAYER` | `"Player"` | **Special** — marks a unit slot as a player aircraft (single-player). |
| `sms.skill.CLIENT` | `"Client"` | **Special** — marks a unit slot as a multiplayer client (joinable). |

`PLAYER` and `CLIENT` aren't skill levels in the AI-difficulty sense — they're placeholder values DCS recognizes on the same `skill` field to mark a unit as human-controllable. Don't pass them to AI units.

## The `sms.Skill` alias

`sms.Skill` is a LuaCATS string-literal alias listing every value of `sms.skill`. The `skill` field on `sms.group.unit_spec` is annotated `sms.Skill|string`:

- `skill = sms.skill.AVERAGE` — autocompleted, type-safe.
- `skill = "Average"` — accepted, autocompleted from the alias.
- `skill = "average"` — accepted as `string`; **DCS skill strings are case-sensitive**, so DCS receives the literal `"average"` and falls back to its own default for an unrecognized skill string.

The `|string` half exists so authors can pass arbitrary strings (including any new skill DCS introduces) without editor red squiggles.

## See also

- [`sms.group.create`](group.md) — spawn factory whose `unit_spec.skill` field consumes this enum.
- [`sms.countries`](countries.md) — the parallel country enum.
