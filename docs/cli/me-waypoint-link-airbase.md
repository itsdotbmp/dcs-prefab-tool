# `dcs-sms me waypoint link-airbase`

[← CLI reference index](README.md)

link a waypoint to a specific airbase (sets airdromeId + moves WP to airbase position)

## Usage

```
dcs-sms me waypoint link-airbase [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--airbase` | string | `""` | airbase name (case-insensitive, exact preferred, substring fallback). Sets wpt.airdromeId, moves the waypoint to the airbase position, and clears any conflicting helipad/grass-strip linkage. For TakeOffParking / TakeOffParkingHot waypoints, ALSO positions each unit at a parking stand at the airbase (via me_parking). For TakeOff (runway), positions the group at the runway threshold. Pair with `set-mode Landing` (or Takeoff*) to specify the flight phase first. |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
