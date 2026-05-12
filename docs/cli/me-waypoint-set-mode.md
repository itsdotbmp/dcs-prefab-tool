# `dcs-sms me waypoint set-mode`

[← CLI reference index](README.md)

set a waypoint's type+action together via ME-style picker name (Landing, Takeoff from parking, Off road, Cone, …)

## Usage

```
dcs-sms me waypoint set-mode [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--mode` | string | `""` | ME UI mode name (case-insensitive); sets wpt.type and wpt.action together. AIR: "Turning point", "Fly over point", "Takeoff from runway", "Takeoff from parking", "Takeoff from parking hot", "Takeoff from ground", "Takeoff from ground hot", "Landing", "LandingReFuAr". GROUND: "Off road", "On road", "On railroads". GROUND FORMATIONS: "Rank" (= "Line abreast"), "Cone", "Vee", "Diamond", "Echelon left", "Echelon right", "Custom". |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
