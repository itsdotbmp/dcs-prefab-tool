# `dcs-sms me zone set-hidden`

[← CLI reference index](README.md)

toggle whether a zone is hidden in the ME view

## Usage

```
dcs-sms me zone set-hidden [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--hidden` | bool | `false` | hide (true) or show (false); pass explicitly |
| `--id` | int | `0` | zone id (mutually exclusive with --name) |
| `--name` | string | `""` | zone name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
