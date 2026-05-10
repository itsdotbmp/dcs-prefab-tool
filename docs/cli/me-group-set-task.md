# `dcs-sms me group set-task`

[← CLI reference index](README.md)

set a group's role/task (e.g. CAP, CAS, Escort)

## Usage

```
dcs-sms me group set-task [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--task` | string | `""` | group task (e.g. CAP, CAS, Escort, Nothing) |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
