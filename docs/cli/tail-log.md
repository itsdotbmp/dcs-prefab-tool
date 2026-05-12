# `dcs-sms tail-log`

[← CLI reference index](README.md)

read recent lines from dcs.log

## Usage

```
dcs-sms tail-log [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--grep` | string | `""` | regex to filter lines |
| `--json` | bool | `false` | emit one JSON object per line |
| `--n` | int | `0` | emit only the last N matching lines |
| `--saved-games` | string | `""` | override Saved Games path |
| `--since` | string | `cursor` | "cursor" (default), "0" (whole file), or a duration like "30s" |

---

[← CLI reference index](README.md)
