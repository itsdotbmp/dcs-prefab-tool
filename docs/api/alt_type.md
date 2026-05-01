# `sms.alt_type` — DCS waypoint altitude reference

Hand-maintained enum for the `alt_type` field on unit specs and waypoint tables: `BARO` (above mean sea level) or `RADIO` (above ground level).

```lua
local wp = {
  x = 1234, y = 0, z = 5678,
  alt = 4500, alt_type = sms.alt_type.BARO,
  type = sms.waypoint.TYPE.TURNING_POINT,
  ...
}
```

Authoring `alt_type = sms.alt_type.BARO` instead of `alt_type = "BARO"` gives autocomplete on the two valid forms and catches `"baro"` / `"Baro"` / `"BARO_"` typos at edit time. The framework's `sms.group.unit_spec.alt_type` field is annotated `sms.AltType|string` so raw-string usage is typo-checkable too.

## Loading

Requires `sms.lua` and `log.lua`. Loaded automatically by `framework/load_all.lua` after `skill.lua`.

## Values

| Constant | DCS string | Use |
|---|---|---|
| `sms.alt_type.BARO` | `"BARO"` | Altitude above mean sea level. Default for fixed-wing aircraft. |
| `sms.alt_type.RADIO` | `"RADIO"` | Altitude above ground level (radar altimeter). Used for terrain-following routes and helicopter low-level. |

Values are upper-case; DCS rejects lower-case forms.

## The `sms.AltType` alias

`sms.AltType` is a LuaCATS string-literal alias enumerating `"BARO"` and `"RADIO"`. The `alt_type` field on `sms.group.unit_spec` is annotated `sms.AltType|string`:

- `alt_type = sms.alt_type.BARO` — autocompleted, type-safe.
- `alt_type = "BARO"` — accepted, autocompleted from the alias.
- `alt_type = "baro"` — passes the type checker (matches `string`) but **fails at runtime**; DCS expects upper-case.

## See also

- [`sms.waypoint`](waypoint.md) — waypoint type / action enums for the same waypoint tables.
- [`sms.group.create`](group.md) — spawn factory whose unit specs accept `alt_type`.
