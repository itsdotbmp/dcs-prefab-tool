# `dcs-sms me group set-formation`

[← CLI reference index](README.md)

set a group's formation

## Usage

```
dcs-sms me group set-formation [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--formation` | string | `""` | formation alias (vee/cone/rank/...) or a DB.templates name (Custom) |
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--waypoint` | int | `1` | waypoint index (1-based); default 1 |

---

[← CLI reference index](README.md)
