# `dcs-sms me drawing create-rect`

[← CLI reference index](README.md)

draw a rectangle on the F10 map

## Usage

```
dcs-sms me drawing create-rect [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--angle` | float | `0` | rotation in degrees (CW around center, 0 = aligned with north/east) |
| `--color` | string | `""` | outline color (default red, opaque) |
| `--east` | float | `0` | meters east of theatre origin (rect center) |
| `--fill-color` | string | `""` | fill color (default red, half alpha) |
| `--height` | float | `0` | rect height in meters |
| `--hidden-on-planner` | bool | `false` | hide on mission planner |
| `--layer` | string | `""` | Red\|Blue\|Neutral\|Common\|Author (default Common) |
| `--name` | string | `""` | drawing name (auto-allocated if empty) |
| `--north` | float | `0` | meters north of theatre origin (rect center) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--style` | string | `""` | line style (default solid) |
| `--thickness` | float | `0` | outline thickness in pixels (default 2) |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--width` | float | `0` | rect width in meters |

---

[← CLI reference index](README.md)
