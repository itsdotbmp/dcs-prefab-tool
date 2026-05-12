# `dcs-sms me unit set-flare`

[← CLI reference index](README.md)

set a unit's flare count

## Usage

```
dcs-sms me unit set-flare [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--count` | int | `-1` | flare count (>= 0) |
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
