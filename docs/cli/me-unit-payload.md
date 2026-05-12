# `dcs-sms me unit payload`

[← CLI reference index](README.md)

manage a unit's per-pylon weapon payload (sub-verbs: set, clear)

## Usage

```
dcs-sms me unit payload [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--pylon` | int | `0` | pylon number (per-airframe, see DB.unit_by_type[type].Pylons) |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--weapon` | string | `""` | weapon CLSID (e.g. "{GUID}") or display name (set sub-verb only) |

---

[← CLI reference index](README.md)
