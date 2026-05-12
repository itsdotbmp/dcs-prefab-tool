# `dcs-sms me group create-static`

[← CLI reference index](README.md)

spawn a new static object group at the given coordinates

## Usage

```
dcs-sms me group create-static [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--can-cargo` | bool | `false` | make cargo-pickup-able by helos |
| `--category` | string | `Fortifications` | static class: Cargos \| Fortifications \| Warehouses \| Trucks |
| `--country` | string | `""` | country in current mission |
| `--dead` | bool | `false` | spawn already-destroyed |
| `--east` | float | `0` | meters east of theatre origin |
| `--heading` | float | `0` | heading in degrees (0 = north, CW positive) |
| `--mass` | float | `0` | cargo mass in kg (when --can-cargo) |
| `--name` | string | `""` | group name (auto-allocated if empty) |
| `--north` | float | `0` | meters north of theatre origin |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--shape-name` | string | `""` | model id (often required; varies per static type) |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--type` | string | `""` | static id (e.g. "Container red 1", "FARP_Tent") |

---

[← CLI reference index](README.md)
