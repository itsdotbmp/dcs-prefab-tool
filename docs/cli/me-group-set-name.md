# `dcs-sms me group set-name`

[← CLI reference index](README.md)

rename a group

## Usage

```
dcs-sms me group set-name [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--new-name` | string | `""` | new group name |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
