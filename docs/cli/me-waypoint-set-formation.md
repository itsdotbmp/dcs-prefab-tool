# `dcs-sms me waypoint set-formation`

[← CLI reference index](README.md)

set a waypoint's formation_template string

## Usage

```
dcs-sms me waypoint set-formation [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--formation-template` | string | `""` | formation template string (empty allowed) |
| `--group-id` | int | `0` | group id (mutually exclusive with --group-name) |
| `--group-name` | string | `""` | group name (mutually exclusive with --group-id) |
| `--index` | int | `-1` | waypoint index (0-based; required) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
