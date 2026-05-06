# Licensing

This repository is split-licensed. The two trees have different protection profiles, so they ship under different licenses.

## `framework/` — MIT

The in-DCS Lua scripting framework is licensed under the [MIT License](framework/LICENSE).

Mission makers — including authors of paid campaigns sold on the ED store — may freely embed framework code in their `.miz` files, modify it, and distribute their missions under whatever terms they choose. No share-back requirement.

## `tools/` — GNU GPL v3

Everything under `tools/` (the `dcs-sms.exe` CLI, the Mission Editor extension, the in-DCS hook, and supporting Go packages) is licensed under the [GNU General Public License, version 3](tools/LICENSE).

Anyone may use, modify, and distribute this code, but derivative works must also be licensed under GPL v3 and ship with corresponding source. The intent is to keep the editor mod and host-side tooling open: contributors who improve them must share those improvements back, and the code cannot be rolled into a closed-source product.

## Why the split

The framework is infrastructure — wide adoption is the point, and copyleft would create real friction for anyone shipping a paid mission. The `tools/` tree is standalone software; protecting it as copyleft costs nothing for end users and keeps the ecosystem healthy.

Copyright © 2026 Niels Vaes.
