# `dcs-sms me unit set-onboard-num`

[← CLI reference index](README.md)

set a unit's display onboard number

## Usage

```
dcs-sms me unit set-onboard-num [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--onboard-num` | string | `""` | onboard number string (e.g. "010") |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
