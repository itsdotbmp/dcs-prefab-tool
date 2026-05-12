# Interview: Bridge to DCS outside mission runtime (Main Menu / Mission Editor)
**Date:** 2026-05-08
**Status:** In Progress

## Context

The user wants to explore extending dcs-sms so Claude (or any external client) can execute Lua against DCS while the user is **in the main menu or Mission Editor** — not just during a running mission. The goal use-case is natural-language-driven editing: "rename this group", "add 4 SAMs around this airbase", "swap that flight's loadout", spoken/typed at Claude, executed live in the Mission Editor.

### What exists today (verified by reading code)

Three Lua environments in DCS:

1. **GUI hook env** (`Saved Games/DCS/Scripts/Hooks/dcs-sms-hook.lua`) — runs continuously while DCS.exe is up. Has `lfs`, full `io.*`, `net.*` (incl. `net.dostring_in`, `net.json2lua`, `net.lua2json`). Receives `DCS.setUserCallbacks` events: `onMissionLoadEnd`, `onSimulationFrame`, `onSimulationStop`, etc. **The current dcs-sms-hook gates inbox processing on `mission_loaded` AND drives polling from `onSimulationFrame`** — so today it's *technically* alive in the menu but sleeps there.

2. **Mission scripting env** — sandboxed by `Scripts/MissionScripting.lua`. Where the `sms.*` framework runs. Reached from the hook env via `net.dostring_in('mission', ...)` + `a_do_script(...)` indirection. Only exists while a mission simulation is running.

3. **Mission Editor (ME) env** — loaded once at DCS startup via `MissionEditor.lua`. The dcs-sms ME-mod (`tools/me-mod/lua/dcs_sms_me/`) already runs here today, manipulates the mission table, places groups/statics/zones, has access to `MissionEditor.lua`'s API surface.

The ME-mod proves bidirectional file I/O from ME-env to disk works (it reads/writes prefab .lua files, patches the in-memory mission, can register hooks like marquee selection and File>New). It currently has no "execute arbitrary Lua from outside DCS" path — it is GUI-driven only.

### The actual question

Can we open a Claude → DCS execution channel *outside* mission runtime, and if so, where should the code land?

- **Option A:** ME-only — code runs in the ME Lua env. Maximum value for the stated use case ("editing a mission"). No mission-runtime gating. Direct access to the editable mission.
- **Option B:** Always-on hook — extend the existing GUI hook to process the inbox without `mission_loaded` and without `onSimulationFrame`. But: hook env can't reach the ME mission table; only a running mission is reachable via `dostring_in('mission', ...)`.
- **Option C:** Both, with Claude/CLI choosing the env per request.

The ME-mod's existence is the strongest evidence that **A is feasible today** — what's missing is the request/response transport equivalent of the hook's mailbox.

## Synergies

- **Existing hook mailbox** (`tools/lua/dcs-sms-hook.lua` + `tools/internal/mailbox/`) — the inbox/outbox/heartbeat protocol is already designed and working. Same pattern can be reused for ME-env, just rooted at a different folder or namespaced by `target` field.
- **Existing ME-mod** (`tools/me-mod/lua/dcs_sms_me/`) — already has file I/O, init hooks, undo stack, paths helper, serializer. A "bridge listener" sub-module slots in next to `marquee_hook.lua` / `new_mission_hook.lua`.
- **Existing CLI** (`tools/cmd/dcs-sms/`) — already speaks the mailbox protocol. Adding a `--target=me` flag (or a sibling subcommand) is incremental.
- **AGENTS.md §7** — needs an entry if a new public surface is introduced (e.g. `sms.bridge` or an ME-side equivalent).

No collisions found — there is no open epic or research doc on this topic.

## Themes Discovered

1. **Single Lua VM for the GUI side.** Hook env, ME env, and main menu share one Lua state. Globals persist across menu→ME→sim→ME→menu. Only the mission scripting env is sandboxed and torn down per mission. (Source: agent1 report; verified against `<DCS>/Scripts/UserHooks.lua`.)
2. **`UpdateManager.add(fn)` is the per-frame primitive that ticks in the ME and main menu** — the equivalent of `onSimulationFrame` for non-mission state. The dcs-sms ME-mod already uses it (`window.lua:49`, `:1487-1491`). Verified by direct grep of the codebase.
3. **No existing tool does external→ME execution.** Every comparable tool (DCS-gRPC, dcs_code_injector, Quaggles' Connector, Olympus, Witchcraft, DCSServerBot) is gated by `onSimulationFrame` and goes silent at the main menu. Quaggles' `luaEnv` request field is the closest precedent for env-routing.
4. **The path forward is short.** File mailbox + `UpdateManager.add` poller in the ME-mod; ~150 LOC, 80% copy-paste from the existing hook, no new dependencies. TCP listener is a clear Phase 2 if latency or streaming becomes important.

## Status: Research complete

Auto mode active — collapsed the multi-round interview into a single recommendation in `_summary.md`. User can course-correct from there.

## Files Created

- `_interview-index.md` (this file)
- `_summary.md` — recommendation + phasing + open questions
- `../../research/me-bridge-agent1-dcs-surfaces.md`
- `../../research/me-bridge-agent2-existing-tools.md`
- `../../research/me-bridge-agent3-ipc-patterns.md`
