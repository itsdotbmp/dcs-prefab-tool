# `dcs-sms me resources get`

[← CLI reference index](README.md)

read the warehouse / resources entry for an airbase or a ship/structure unit

## Usage

```
dcs-sms me resources get [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--airbase` | string | `""` | airbase name (mutually exclusive with --unit) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--unit` | string | `""` | unit name or numeric unitId (mutually exclusive with --airbase) |

---

[← CLI reference index](README.md)
