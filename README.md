<p align="center">
  <img src="assets/logo.png" alt="Coconut Cockpit" width="160">
</p>

# dcs-sms

[![Release ME-mod](https://github.com/nielsvaes/dcs-sms/actions/workflows/release-me-mod.yml/badge.svg)](https://github.com/nielsvaes/dcs-sms/actions/workflows/release-me-mod.yml)
[![Discord — Coconut Cockpit](https://img.shields.io/badge/discord-Coconut_Cockpit-5865F2?logo=discord&logoColor=white)](https://discord.gg/8tbdGY45hM)
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/F1F4PYTO7)

DCS scripting framework, Mission Editor extension, and host-side tooling.

## Components

- **Framework** — in-DCS Lua scripting framework (`sms.*`). [`framework/README.md`](framework/README.md)
- **ME-mod** — DCS Mission Editor extension (Prefab Manager and more). [`tools/me-mod/README.md`](tools/me-mod/README.md)
- **CLI / bridge** — host-side `dcs-sms.exe` for installing the above and live-poking a running mission. [`tools/cmd/dcs-sms/README.md`](tools/cmd/dcs-sms/README.md)

## More

- [`docs/api/`](docs/api/) — framework API reference.
- [`CHANGELOG.md`](CHANGELOG.md) — release history (two parallel tracks).
- [`AGENTS.md`](AGENTS.md) — contributor rules and conventions.

## Licensing

This repo is split-licensed. See [`LICENSE.md`](LICENSE.md) for the rationale.

- **`framework/`** — [MIT](framework/LICENSE). Free for any use, including paid missions and ED-store campaigns.
- **`tools/`** — [GNU GPL v3](tools/LICENSE). Covers the CLI, the ME-mod, and the in-DCS hook. Derivative works must remain GPL v3.
