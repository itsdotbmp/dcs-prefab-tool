# `dcs-sms me unit set-skill`

[← CLI reference index](README.md)

set a unit's AI skill (Average, Good, High, Excellent, Random, Player)

## Usage

```
dcs-sms me unit set-skill [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | unit id (mutually exclusive with --name) |
| `--name` | string | `""` | unit name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--skill` | string | `""` | skill: Average \| Good \| High \| Excellent \| Random \| Player \| Client |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
