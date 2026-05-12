# `dcs-sms me drawing create-textbox`

[← CLI reference index](README.md)

place a text label on the F10 map

## Usage

```
dcs-sms me drawing create-textbox [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--angle` | float | `0` | rotation in degrees (CW, 0 = upright) |
| `--border-thickness` | int | `-1` | border thickness in pixels (default 4) |
| `--color` | string | `""` | text color (default green, opaque) |
| `--east` | float | `0` | meters east of theatre origin (textbox anchor) |
| `--fill-color` | string | `""` | background fill (default red, half alpha) |
| `--font` | string | `""` | font ttf filename (default DejaVuLGCSansCondensed.ttf) |
| `--font-size` | int | `0` | font size in pixels (default 24) |
| `--hidden-on-planner` | bool | `false` | hide on mission planner |
| `--layer` | string | `""` | Red\|Blue\|Neutral\|Common\|Author (default Common) |
| `--name` | string | `""` | drawing name (auto-allocated if empty) |
| `--north` | float | `0` | meters north of theatre origin (textbox anchor) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--text` | string | `""` | text content |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
