# `dcs-sms me trigger reorder-condition`

[← CLI reference index](README.md)

move a condition to a new index in a trigger's condition list

## Usage

```
dcs-sms me trigger reorder-condition [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--after` | int | `0` | anchor: move source to just after this 1-based condition index |
| `--before` | int | `0` | anchor: move source to just before this 1-based condition index |
| `--index` | int | `0` | 1-based source condition index in t.rules |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--to-end` | bool | `false` | sugar for --to-index #rules |
| `--to-index` | int | `0` | 1-based final position in t.rules |
| `--to-start` | bool | `false` | sugar for --to-index 1 |
| `--trigger` | string | `""` | parent trigger name |

---

[← CLI reference index](README.md)
