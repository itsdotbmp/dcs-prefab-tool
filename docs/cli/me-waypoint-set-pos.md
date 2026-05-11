# `dcs-sms me waypoint set-pos`

[← CLI reference index](README.md)

move a waypoint to a new north/east coordinate

## Usage

```
dcs-sms me waypoint set-pos [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--east` | float | `0` | meters east of theatre origin (required) |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--north` | float | `0` | meters north of theatre origin (required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
