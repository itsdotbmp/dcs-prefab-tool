# `dcs-sms me group set-late-activation`

[← CLI reference index](README.md)

toggle a group's lateActivation flag (deferred spawn)

## Usage

```
dcs-sms me group set-late-activation [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--enabled` | bool | `false` | true: group is dormant at mission start, spawns later via trigger / script; false: spawns immediately at start_time. Pass explicitly. |
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
