# `dcs-sms me unit set-parking`

[← CLI reference index](README.md)

pin a unit to a specific named parking stand at an airbase (sets parking + parking_id, moves the unit to the stand)

## Usage

```
dcs-sms me unit set-parking [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--airbase` | string | `""` | airbase name (case-insensitive, exact preferred, substring fallback). The stand is looked up within this airbase's parking list. |
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--stand` | string | `""` | stand name as shown in the ME (e.g. "08", "21A"). Use `dcs-sms me airbase get --name <X> --filter plane\|helicopter` to list available stands. Validates that the stand's category matches the unit's group category — refuses on mismatch. |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
