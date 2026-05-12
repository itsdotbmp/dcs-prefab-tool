# `dcs-sms me waypoint insert`

[← CLI reference index](README.md)

insert a waypoint at index N (shifts subsequent WPs up; --before K appends)

## Usage

```
dcs-sms me waypoint insert [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--action` | string | `""` | waypoint action (optional) |
| `--alt` | float | `0` | altitude meters (optional) |
| `--alt-type` | string | `""` | BARO or RADIO (optional) |
| `--before` | int | `-1` | insertion index (0-based; --before K appends) |
| `--east` | float | `0` | meters east of theatre origin (required) |
| `--eta` | float | `0` | ETA seconds (optional) |
| `--eta-locked` | string | `""` | eta-locked: true\|false (optional) |
| `--formation-template` | string | `""` | formation template (optional) |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--name` | string | `""` | waypoint display name (optional) |
| `--north` | float | `0` | meters north of theatre origin (required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--speed` | float | `0` | speed m/s (optional) |
| `--speed-locked` | string | `""` | speed-locked: true\|false (optional) |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--type` | string | `""` | waypoint type (optional) |

---

[← CLI reference index](README.md)
