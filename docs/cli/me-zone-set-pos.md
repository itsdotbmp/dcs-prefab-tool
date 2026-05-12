# `dcs-sms me zone set-pos`

[← CLI reference index](README.md)

move a zone to a new north/east coordinate

## Usage

```
dcs-sms me zone set-pos [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--east` | float | `0` | meters east of theatre origin (east positive) |
| `--id` | int | `0` | zone id (mutually exclusive with --name) |
| `--name` | string | `""` | zone name (mutually exclusive with --id) |
| `--north` | float | `0` | meters north of theatre origin (north positive) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
