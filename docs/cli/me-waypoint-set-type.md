# `dcs-sms me waypoint set-type`

[← CLI reference index](README.md)

set a waypoint's type (sms.waypoint.TYPE enum)

## Usage

```
dcs-sms me waypoint set-type [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--type` | string | `""` | waypoint type — the flight-phase / arrival/departure mode. Legal: "Turning Point" (used by every turning-point + ground-formation mode), "TakeOff" (from runway), "TakeOffParking", "TakeOffParkingHot", "TakeOffGround", "TakeOffGroundHot", "Land", "LandingReFuAr", "On Railroads". Ground formations (Off Road, Cone, Vee, Diamond, Rank, EchelonL/R, Custom) are NOT here — they're in --action. |

---

[← CLI reference index](README.md)
