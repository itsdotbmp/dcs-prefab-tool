# `dcs-sms me group remove-unit`

[← CLI reference index](README.md)

delete a unit from its group

## Usage

```
dcs-sms me group remove-unit [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
