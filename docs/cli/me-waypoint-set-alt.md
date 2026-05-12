# `dcs-sms me waypoint set-alt`

[← CLI reference index](README.md)

set a waypoint's altitude (optionally also its alt-type)

## Usage

```
dcs-sms me waypoint set-alt [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--alt` | float | `0` | altitude meters above sea level (required, >= 0) |
| `--alt-type` | string | `""` | altitude reference: BARO or RADIO (optional) |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
