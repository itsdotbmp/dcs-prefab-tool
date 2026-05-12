# `dcs-sms me waypoint set-action`

[← CLI reference index](README.md)

set a waypoint's action (sms.waypoint.ACTION enum)

## Usage

```
dcs-sms me waypoint set-action [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--action` | string | `""` | waypoint action (sms.waypoint.ACTION: Turning Point, Fly Over Point, From Parking Area, From Parking Area Hot, From Ground Area, From Ground Area Hot, From Runway, Landing, LandingReFuAr, Off Road, On Road) |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
