# `dcs-sms me waypoint add`

[← CLI reference index](README.md)

append a waypoint to a group's route (inherits unset fields from previous WP)

## Usage

```
dcs-sms me waypoint add [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--action` | string | `""` | waypoint action (sms.waypoint.ACTION enum; optional) |
| `--alt` | float | `0` | altitude meters (optional; inherits from previous WP or category default) |
| `--alt-type` | string | `""` | altitude reference: BARO or RADIO (optional) |
| `--east` | float | `0` | meters east of theatre origin (required) |
| `--eta` | float | `0` | estimated time of arrival, seconds (optional, >= 0) |
| `--eta-locked` | string | `""` | ETA-locked flag: true\|false (optional) |
| `--formation-template` | string | `""` | formation template string (optional) |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--name` | string | `""` | waypoint display name (optional) |
| `--north` | float | `0` | meters north of theatre origin (required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--speed` | float | `0` | speed m/s (optional; > 0) |
| `--speed-locked` | string | `""` | speed-locked flag: true\|false (optional) |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--type` | string | `""` | waypoint type (sms.waypoint.TYPE enum; optional) |

---

[← CLI reference index](README.md)
