# `dcs-sms me group set-country`

[← CLI reference index](README.md)

change a group's country/coalition

## Usage

```
dcs-sms me group set-country [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--country` | string | `""` | target country name (case-insensitive) |
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
