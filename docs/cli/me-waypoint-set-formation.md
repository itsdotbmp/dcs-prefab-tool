# `dcs-sms me waypoint set-formation`

[← CLI reference index](README.md)

set a waypoint's formation_template (name of saved Custom formation; preset formations use --action)

## Usage

```
dcs-sms me waypoint set-formation [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--formation-template` | string | `""` | name of a saved CUSTOM formation template (vehicle/ship). Only meaningful when the waypoint's --action is "Custom"; for preset formations like Cone/Vee/Diamond/Rank/EchelonL/EchelonR/Off Road/On Road, use --action directly and leave this empty. Empty string is the default and is legal for every preset action. |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
