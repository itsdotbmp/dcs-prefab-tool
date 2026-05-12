# `dcs-sms exec`

[← CLI reference index](README.md)

execute a Lua snippet (use --target mission|gui|auto, default auto)

## Usage

```
dcs-sms exec [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--code` | string | `""` | Lua code (inline) |
| `--file` | string | `""` | path to a .lua file |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--target` | string | `auto` | execution target: mission \| gui \| auto |
| `--timeout` | duration | `5s` | wall-clock timeout |
| `--wait` | bool | `false` | if hook isn't ready, poll until it is or --timeout elapses |

---

[← CLI reference index](README.md)
