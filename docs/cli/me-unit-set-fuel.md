# `dcs-sms me unit set-fuel`

[← CLI reference index](README.md)

set a unit's fuel level (0..1 or absolute kg)

## Usage

```
dcs-sms me unit set-fuel [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--fuel` | float | `-1` | fuel mass in kg (>= 0) |
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
