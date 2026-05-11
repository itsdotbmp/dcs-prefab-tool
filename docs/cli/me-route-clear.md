# `dcs-sms me route clear`

[← CLI reference index](README.md)

remove all waypoints from a group's route (air groups refused)

## Usage

```
dcs-sms me route clear [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
