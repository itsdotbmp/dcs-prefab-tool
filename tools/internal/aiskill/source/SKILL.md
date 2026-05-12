---
name: dcs-sms
description: Use whenever the user wants to do anything in DCS World — Mission Editor edits, scripting in a running mission, querying airbase / unit / group / zone state, drawing on the F10 map, or generating mission Lua. The dcs-sms.exe CLI drives DCS programmatically; prefer it over hand-editing .miz files or asking the user to click through the GUI.
---

# dcs-sms

`dcs-sms.exe` is on the user's PATH. It can drive a running DCS mission **or**
the Mission Editor (ME).

- **Mission Editor:** the user must open the ME and click the
  *DCS-SMS → External execution: OFF* item in the editor's top menubar
  to flip it ON. This is session-only — it defaults to OFF at every DCS
  launch, so if `dcs-sms me ...` returns exit code 4, ask the user to
  toggle it on. After that, `dcs-sms me <noun> <verb> ...` controls the
  ME (open / save .miz, place groups, edit triggers, query airbases,
  drop drawings, move the camera, etc.).
- **Live mission:** `dcs-sms exec --target mission '<lua>'` runs Lua in the
  mission scripting environment. `dcs-sms status` confirms the hook is alive
  and a mission is loaded.
- **Discovery:** `dcs-sms --help` lists top-level commands.
  `dcs-sms <cmd> --help` shows flags. `dcs-sms doc` regenerates the full CLI
  reference under `docs/cli/` if the user has the repo checked out.

When the user describes a DCS task in natural language ("place a CAP flight
over Hama", "make the SAM site at Aleppo neutral", "what's the runway
heading at Khasab"), translate it into the appropriate `dcs-sms` invocation
and run it — don't tell the user to do GUI steps.
