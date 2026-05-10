# `dcs-sms me drawing create-oval`

[← CLI reference index](README.md)

draw an oval on the F10 map

## Usage

```
dcs-sms me drawing create-oval [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--angle` | float | `0` | rotation in degrees (CW around center, 0 = aligned with north/east) |
| `--color` | string | `""` | outline color (default red, opaque) |
| `--east` | float | `0` | meters east of theatre origin (oval center) |
| `--fill-color` | string | `""` | fill color (default red, half alpha) |
| `--hidden-on-planner` | bool | `false` | hide on mission planner |
| `--layer` | string | `""` | Red\|Blue\|Neutral\|Common\|Author (default Common) |
| `--name` | string | `""` | drawing name (auto-allocated if empty) |
| `--north` | float | `0` | meters north of theatre origin (oval center) |
| `--pretty` | bool | `false` | indent JSON output |
| `--r1` | float | `0` | first semi-axis in meters (along local north pre-rotation) |
| `--r2` | float | `0` | second semi-axis in meters (along local east pre-rotation) |
| `--saved-games` | string | `""` | override Saved Games path |
| `--style` | string | `""` | line style (default solid) |
| `--thickness` | float | `0` | outline thickness in pixels (default 2) |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
