# `dcs-sms me group set-uncontrolled`

[← CLI reference index](README.md)

toggle a group's uncontrolled flag (spawns without AI controller)

## Usage

```
dcs-sms me group set-uncontrolled [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--enabled` | bool | `false` | true: group spawns but DCS gives it no AI controller (parking-cold aircraft sit on the ramp until a trigger's GROUP AI ON action / script's startCommand fires); false: spawns under AI control. Only meaningful for plane / helicopter / vehicle / ship / train groups; statics ignore it. Pass explicitly. |
| `--id` | int | `0` | group id (mutually exclusive with --name) |
| `--name` | string | `""` | group name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
