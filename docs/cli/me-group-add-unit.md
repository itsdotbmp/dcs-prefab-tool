# `dcs-sms me group add-unit`

[← CLI reference index](README.md)

add a unit to an existing group

## Usage

```
dcs-sms me group add-unit [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--alt` | float | `0` | altitude in meters (air only; defaults to last unit's) |
| `--alt-type` | string | `""` | BARO \| RADIO (air only; defaults to last unit's) |
| `--callsign` | string | `""` | radio callsign label (auto-allocates if empty) |
| `--frequency` | float | `0` | frequency MHz (ship only) |
| `--group` | string | `""` | group name (mutually exclusive with --group-id) |
| `--group-id` | int | `0` | group id (mutually exclusive with --group) |
| `--heading` | float | `0` | heading in degrees (defaults to last unit's) |
| `--livery` | string | `""` | livery id (defaults to last unit's) |
| `--offset-east` | float | `0` | meters east of group anchor (positive = east) |
| `--offset-north` | float | `0` | meters north of group anchor (positive = north) |
| `--onboard-num` | string | `""` | onboard number (insert_unit auto-allocates if empty) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--skill` | string | `""` | AI skill (defaults to last unit's) |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--type` | string | `""` | unit type (defaults to last unit's type) |

---

[← CLI reference index](README.md)
