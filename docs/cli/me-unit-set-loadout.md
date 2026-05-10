# `dcs-sms me unit set-loadout`

[← CLI reference index](README.md)

apply a named loadout preset to a unit

## Usage

```
dcs-sms me unit set-loadout [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--loadout` | string | `""` | loadout name (e.g. "CAP", "CAS", "Empty") |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
