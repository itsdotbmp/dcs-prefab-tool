# `dcs-sms me resources set`

[← CLI reference index](README.md)

mutate an airbase or ship/structure warehouse — toggle unlimited, clear categories, set per-fuel / per-aircraft / per-weapon counts

## Usage

```
dcs-sms me resources set [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--airbase` | string | `""` | airbase name (mutually exclusive with --unit) |
| `--aircraft` | value | `""` | "DISPLAY NAME"=N — exact match against the warehouse's aircraft keys; repeatable |
| `--clear` | bool | `false` | zero all inventory and uncheck all unlimited flags |
| `--clear-aircrafts` | bool | `false` | zero aircraft counts (does not touch unlimited flag) |
| `--clear-fuel` | bool | `false` | zero fuel percentages (does not touch unlimited flag) |
| `--clear-munitions` | bool | `false` | zero weapon counts (does not touch unlimited flag) |
| `--fuel` | value | `""` | TYPE=N where TYPE in {jet_fuel,gasoline,diesel,methanol_mixture} and N is 0..100; repeatable |
| `--operating-level-air` | int | `0` | minimum-stock %% for aircraft replenishment (0..100) |
| `--operating-level-eqp` | int | `0` | minimum-stock %% for equipment replenishment (0..100) |
| `--operating-level-fuel` | int | `0` | minimum-stock %% for fuel replenishment (0..100) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--unit` | string | `""` | unit name or numeric unitId (mutually exclusive with --airbase) |
| `--unlimited` | bool | `false` | set all three unlimited flags (use --unlimited=false to unset all) |
| `--unlimited-aircrafts` | bool | `false` | set unlimitedAircrafts (use =false to unset) |
| `--unlimited-fuel` | bool | `false` | set unlimitedFuel (use =false to unset) |
| `--unlimited-munitions` | bool | `false` | set unlimitedMunitions (use =false to unset) |
| `--weapon` | value | `""` | "FRAGMENT"=N — substring match on weapon displayName (or full CLSID in {...} form); repeatable |

---

[← CLI reference index](README.md)
