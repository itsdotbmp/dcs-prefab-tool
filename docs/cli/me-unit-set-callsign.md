# `dcs-sms me unit set-callsign`

[← CLI reference index](README.md)

set a unit's radio callsign

## Usage

```
dcs-sms me unit set-callsign [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--callsign` | string | `""` | callsign label (e.g. "Enfield11") |
| `--flight` | int | `0` | flight number (optional; preserves existing if 0) |
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--plane` | int | `0` | plane number (optional; preserves existing if 0) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--squadron` | int | `0` | squadron number (optional; preserves existing if 0) |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
