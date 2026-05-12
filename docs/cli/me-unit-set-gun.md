# `dcs-sms me unit set-gun`

[← CLI reference index](README.md)

set a unit's gun ammunition percentage

## Usage

```
dcs-sms me unit set-gun [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--percent` | float | `-1` | gun ammo percent (0-100) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
