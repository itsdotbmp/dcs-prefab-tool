# `dcs-sms me drawing create-arrow`

[← CLI reference index](README.md)

draw an arrow on the F10 map

## Usage

```
dcs-sms me drawing create-arrow [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--angle` | float | `0` | rotation in degrees (0 = pointing north, CW positive) |
| `--color` | string | `""` | outline color (default red, opaque) |
| `--east` | float | `0` | meters east of theatre origin (arrow anchor) |
| `--fill-color` | string | `""` | fill color (default red, half alpha) |
| `--hidden-on-planner` | bool | `false` | hide on mission planner |
| `--layer` | string | `""` | Red\|Blue\|Neutral\|Common\|Author (default Common) |
| `--length` | float | `0` | arrow length in meters |
| `--name` | string | `""` | drawing name (auto-allocated if empty) |
| `--north` | float | `0` | meters north of theatre origin (arrow anchor) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--style` | string | `""` | line style (default solid) |
| `--thickness` | float | `0` | outline thickness in pixels (default 2) |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
