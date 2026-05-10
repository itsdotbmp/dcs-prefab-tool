# `dcs-sms me unit set-name`

[← CLI reference index](README.md)

rename a unit

## Usage

```
dcs-sms me unit set-name [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--new-name` | string | `""` | new unit name |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
