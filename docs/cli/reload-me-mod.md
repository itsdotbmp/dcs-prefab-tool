# `dcs-sms reload-me-mod`

[← CLI reference index](README.md)

hot-reload the installed ME mod via the gui bridge (no DCS restart)

## Usage

```
dcs-sms reload-me-mod [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `10s` | wall-clock timeout |
| `--wait` | bool | `false` | if hook isn't ready, poll until it is or --timeout elapses |

---

[← CLI reference index](README.md)
