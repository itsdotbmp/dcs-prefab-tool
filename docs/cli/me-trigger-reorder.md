# `dcs-sms me trigger reorder`

[← CLI reference index](README.md)

reorder triggers in the open mission

## Usage

```
dcs-sms me trigger reorder [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--after` | string | `""` | anchor: move source to just after this trigger name |
| `--before` | string | `""` | anchor: move source to just before this trigger name |
| `--name` | string | `""` | trigger name to move (the comment field) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--to-end` | bool | `false` | sugar for --to-index #trigrules |
| `--to-index` | int | `0` | 1-based final position in mission.trigrules |
| `--to-start` | bool | `false` | sugar for --to-index 1 |

---

[← CLI reference index](README.md)
