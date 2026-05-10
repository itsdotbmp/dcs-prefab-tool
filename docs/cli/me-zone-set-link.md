# `dcs-sms me zone set-link`

[← CLI reference index](README.md)

link a zone to a unit so it follows the unit

## Usage

```
dcs-sms me zone set-link [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--clear` | bool | `false` | unlink the zone |
| `--id` | int | `0` | zone id (mutually exclusive with --name) |
| `--name` | string | `""` | zone name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--unit` | string | `""` | target unit name (link by name) |
| `--unit-id` | int | `0` | target unit id (link by id) |

---

[← CLI reference index](README.md)
