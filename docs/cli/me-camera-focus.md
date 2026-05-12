# `dcs-sms me camera focus`

[← CLI reference index](README.md)

focus the ME camera on a coordinate / lat-lon / airdrome name

## Usage

```
dcs-sms me camera focus [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--lat` | float | `0` | latitude (decimal degrees) |
| `--lon` | float | `0` | longitude (decimal degrees) |
| `--name` | string | `""` | airdrome name (case-insensitive, substring) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--scale` | float | `0` | map scale (meters per screen unit; 0 = keep current) |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--x` | float | `0` | DCS world meters, north axis |
| `--y` | float | `0` | DCS world meters, east axis |

---

[← CLI reference index](README.md)
