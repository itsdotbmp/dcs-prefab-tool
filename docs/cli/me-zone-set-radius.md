# `dcs-sms me zone set-radius`

[← CLI reference index](README.md)

change a zone's radius in meters

## Usage

```
dcs-sms me zone set-radius [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | zone id (mutually exclusive with --name) |
| `--name` | string | `""` | zone name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--radius` | float | `0` | radius in meters |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
