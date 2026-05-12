# `dcs-sms me zone create`

[← CLI reference index](README.md)

create a circular or quadrilateral zone in the open mission

## Usage

```
dcs-sms me zone create [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--color` | string | `""` | color: name (red/green/blue/yellow/cyan/magenta/white/black/orange/purple), hex "#rrggbb" (alpha 0.15), or "#rrggbbaa"; default = translucent white |
| `--east` | float | `0` | circle: meters east of theatre origin (east positive) |
| `--hidden` | bool | `false` | hide the zone in the ME view |
| `--name` | string | `""` | zone name (uniquified by ME if duplicate) |
| `--north` | float | `0` | circle: meters north of theatre origin (north positive) |
| `--pretty` | bool | `false` | indent JSON output |
| `--radius` | float | `0` | circle: radius in meters; quad: optional icon radius |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--type` | string | `""` | shape: circle \| quad |
| `--vertices` | string | `""` | quad: 4 corners as "n1,e1;n2,e2;n3,e3;n4,e4" (>= 3 corners actually allowed) |

---

[← CLI reference index](README.md)
