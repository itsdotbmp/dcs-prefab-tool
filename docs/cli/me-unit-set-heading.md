# `dcs-sms me unit set-heading`

[← CLI reference index](README.md)

set a unit's heading in degrees

## Usage

```
dcs-sms me unit set-heading [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--heading` | float | `0` | heading in degrees (0 = north, clockwise positive) |
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
