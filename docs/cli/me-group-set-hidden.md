# `dcs-sms me group set-hidden`

[← CLI reference index](README.md)

toggle whether a group is hidden in the ME view

## Usage

```
dcs-sms me group set-hidden [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--hidden` | bool | `false` | hide (true) or show (false); pass explicitly |
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
