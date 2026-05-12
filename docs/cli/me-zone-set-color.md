# `dcs-sms me zone set-color`

[← CLI reference index](README.md)

change a zone's outline / fill color

## Usage

```
dcs-sms me zone set-color [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--color` | string | `""` | color: name (red/green/blue/yellow/cyan/magenta/white/black/orange/purple), hex "#rrggbb" (alpha 0.15), or "#rrggbbaa" |
| `--id` | int | `0` | zone id (mutually exclusive with --name) |
| `--name` | string | `""` | zone name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
