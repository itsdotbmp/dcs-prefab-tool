# `dcs-sms me trigger reorder-action`

[← CLI reference index](README.md)

move an action to a new index in a trigger's action list

## Usage

```
dcs-sms me trigger reorder-action [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--after` | int | `0` | anchor: move source to just after this 1-based action index |
| `--before` | int | `0` | anchor: move source to just before this 1-based action index |
| `--index` | int | `0` | 1-based source action index in t.actions |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--to-end` | bool | `false` | sugar for --to-index #actions |
| `--to-index` | int | `0` | 1-based final position in t.actions |
| `--to-start` | bool | `false` | sugar for --to-index 1 |
| `--trigger` | string | `""` | parent trigger name |

---

[← CLI reference index](README.md)
