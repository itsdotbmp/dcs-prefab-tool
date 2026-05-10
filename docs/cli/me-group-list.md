# `dcs-sms me group list`

[← CLI reference index](README.md)

list all groups in the open mission

## Usage

```
dcs-sms me group list [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--category` | string | `""` | filter by category: plane \| helicopter \| vehicle \| ship \| static |
| `--country` | string | `""` | filter by country (case-insensitive exact match) |
| `--name` | string | `""` | filter by group-name substring (case-insensitive) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--side` | string | `""` | filter by side: red \| blue \| neutrals |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
