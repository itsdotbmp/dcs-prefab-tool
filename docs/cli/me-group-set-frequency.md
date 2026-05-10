# `dcs-sms me group set-frequency`

[← CLI reference index](README.md)

set a group's radio frequency in MHz

## Usage

```
dcs-sms me group set-frequency [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--frequency` | float | `0` | frequency in MHz |
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
