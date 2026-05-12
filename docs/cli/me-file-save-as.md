# `dcs-sms me file save-as`

[← CLI reference index](README.md)

save the open mission to a new .miz path

## Usage

```
dcs-sms me file save-as [flags]
```

## Flags

| Name | Type | Default | Description |
|---|---|---|---|
| `--path` | string | `""` | absolute path to write (.miz) |
| `--pretty` | bool | `false` | indent JSON output |
| `--reopen` | bool | `true` | re-open the file after save (matches DCS-native; refreshes title bar) |
| `--saved-games` | string | `""` | override Saved Games path |
| `--timeout` | duration | `30s` | wall-clock timeout |

---

[← CLI reference index](README.md)
