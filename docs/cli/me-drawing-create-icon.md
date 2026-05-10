# `dcs-sms me drawing create-icon`

[← CLI reference index](README.md)

place an icon on the F10 map

## Usage

```
dcs-sms me drawing create-icon [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--angle` | float | `0` | rotation in degrees (CW, 0 = unrotated) |
| `--color` | string | `""` | tint color (default white, opaque) |
| `--east` | float | `0` | meters east of theatre origin (icon anchor) |
| `--file` | string | `""` | icon filename within the icons folder |
| `--hidden-on-planner` | bool | `false` | hide on mission planner |
| `--layer` | string | `""` | Red\|Blue\|Neutral\|Common\|Author (default Common) |
| `--name` | string | `""` | drawing name (auto-allocated if empty) |
| `--north` | float | `0` | meters north of theatre origin (icon anchor) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--scale` | float | `1` | icon scale (default 1) |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
