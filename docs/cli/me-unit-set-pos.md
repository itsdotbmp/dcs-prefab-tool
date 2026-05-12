# `dcs-sms me unit set-pos`

[← CLI reference index](README.md)

move a unit to a new north/east coordinate

## Usage

```
dcs-sms me unit set-pos [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--east` | float | `0` | meters east of theatre origin |
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--north` | float | `0` | meters north of theatre origin |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
