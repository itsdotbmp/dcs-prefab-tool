# `dcs-sms me unit set-livery`

[← CLI reference index](README.md)

set a unit's livery id

## Usage

```
dcs-sms me unit set-livery [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--livery` | string | `""` | livery id (airframe-specific; empty = default) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
