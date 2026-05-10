# `dcs-sms me airbase get`

[← CLI reference index](README.md)

get an airbase's full info — metadata, frequencies, parking stands, runways

## Usage

```
dcs-sms me airbase get [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--filter` | string | `""` | stand filter: '' (all), plane, helicopter |
| `--name` | string | `""` | airbase name (case-insensitive, exact match preferred, substring fallback) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
