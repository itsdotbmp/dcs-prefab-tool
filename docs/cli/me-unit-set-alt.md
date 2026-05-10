# `dcs-sms me unit set-alt`

[← CLI reference index](README.md)

set a unit's altitude in meters

## Usage

```
dcs-sms me unit set-alt [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--alt` | float | `0` | altitude in meters above sea level |
| `--alt-type` | string | `BARO` | altitude type: BARO \| RADIO |
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
