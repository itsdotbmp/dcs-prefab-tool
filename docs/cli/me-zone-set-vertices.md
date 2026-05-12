# `dcs-sms me zone set-vertices`

[← CLI reference index](README.md)

replace a quad zone's 4 corners

## Usage

```
dcs-sms me zone set-vertices [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--id` | int | `0` | zone id (mutually exclusive with --name) |
| `--name` | string | `""` | zone name (mutually exclusive with --id) |
| `--pretty` | bool | `false` | indent JSON output |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |
| `--vertices` | string | `""` | 4 corners as "n1,e1;n2,e2;n3,e3;n4,e4" (>= 3 corners actually allowed) |

---

[← CLI reference index](README.md)
