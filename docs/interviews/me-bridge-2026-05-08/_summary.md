# Summary: Bridging dcs-sms to DCS while in the Mission Editor

**Date:** 2026-05-08
**Status:** Research complete; recommendation ready for user decision. No beads created (research-only request).

## Problem

dcs-sms today can execute Lua against DCS only while a mission is running. The user wants a Claude → DCS execution path that works while editing a mission in the Mission Editor (ME), so natural-language commands like "rename this group", "add 4 SAMs around this airbase", or "swap that flight's loadout" can be applied to the in-editor mission table directly.

## Answer

**Yes — and the path is short.**

DCS does not have three Lua VMs as I initially assumed. There is one shared VM for the GUI side (Hooks + ME + main menu); only the *mission scripting env* (the `MissionScripting.lua`-sandboxed one) is its own state. The dcs-sms ME-mod already runs in that shared VM, already reads/writes files, and — critically — already attaches to the per-frame tick that is the ME-state equivalent of `onSimulationFrame`: **`UpdateManager.add(fn)`**.

That is the missing primitive. The current hook polls the inbox from `onSimulationFrame`, which only fires inside a sim. Polling from `UpdateManager.add` instead works in the ME and the main menu, with no new dependencies.

The ME-mod already imports `UpdateManager` (`tools/me-mod/lua/dcs_sms_me/window.lua:49`) and already registers a tick on it (`window.lua:1487-1491`, for the status-bar auto-clear). A bridge listener slots in alongside.

**No existing tool does this.** Every comparable project (DCS-gRPC, dcs_code_injector, Quaggles' Lua Connector, Olympus, Witchcraft, DCSServerBot) is gated by `onSimulationFrame` and dies at the main menu. Quaggles' `luaEnv` request field (`"gui"` vs mission) is the closest precedent for the env-routing UX, but the listener itself is mission-only. The ME-side bridge is genuinely unexplored ground.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where the bridge listener lives | ME-mod (`tools/me-mod/lua/dcs_sms_me/`) | Only env that reaches the editable mission table; already runs at ME open; `UpdateManager` already imported |
| Tick source | `UpdateManager.add(poll_inbox)` | Equivalent of `onSimulationFrame` for the ME state; 30-60 Hz foregrounded; already used by the mod |
| Transport | File mailbox (reuse hook protocol) | 80% reusable from `tools/lua/dcs-sms-hook.lua`; debuggable with plain `type`/`cat`; zero new deps; latency 16-200 ms is fine for human-driven edits |
| Request schema change | Add `target` field: `"mission"` (default, current behavior) or `"me"` | Lets one CLI route to either env; mirrors Quaggles' `luaEnv` precedent |
| Execution model in ME | Direct `loadstring(code)` + `pcall` in ME state | No `dostring_in` indirection — the ME *is* the destination state |
| Security | Local file-mailbox only; no network listener | Matches existing hook posture; follow-up TCP listener is Phase 2 |
| Future option | TCP localhost listener (Phase 2) | Sub-ms latency if/when command rate or streaming use cases appear; same `UpdateManager` driver |

## Architecture sketch

```
External (Claude / CLI / dcs-sms.exe)
  │ writes <SavedGames>\DCS\dcs-sms\inbox\<id>.req.json with {"target": "me", "code": "..."}
  ▼
[ disk ]
  ▲
  │ poll on every UpdateManager tick
ME-mod bridge module (new)
  ├─ ensure_dirs, sweep_stale, write_heartbeat (copy of hook helpers)
  ├─ on each tick:
  │     for each *.req.json:
  │         dispatch by target: "me" → loadstring+pcall in ME state
  │                              "mission" → ignore (the hook still owns that)
  │         capture print/output, errors, return value
  │         atomic-write <id>.res.json to outbox
  └─ heartbeat file with state ("at_main_menu" | "in_mission_editor" | "loading" | …)
```

The hook keeps doing what it does today; the ME-mod adds a peer listener that handles `target=me`. They share the disk substrate but are independent. The CLI picks one based on user intent; eventually it can default-route based on which heartbeat is freshest.

### Module placement (proposed)

```
tools/me-mod/lua/dcs_sms_me/
  bridge.lua           ← new: poll_inbox, dispatch, response writer
  bridge_paths.lua     ← new: <SavedGames>/dcs-sms/inbox|outbox|state, namespaced if needed
  init.lua             ← add: bridge.install()
```

`init.lua` already wraps everything in a top-level `pcall`, so a bridge load failure doesn't break the rest of the mod. The bridge is opt-out (or opt-in) via a setting — useful for users who don't want their ME accepting external code.

## Open security question (must decide before implementation)

The mailbox is implicitly *whoever-can-write-to-the-folder* execution. That's the same posture the in-mission hook has today, and the hook env is *less* sandboxed than the ME (it has `lfs`, `os.execute`, etc.). But the ME-state can rewrite the user's mission, save it, modify warehouses, and so on — different blast radius.

Two reasonable postures:

1. **Same posture as the hook** — anyone with write access to `<SavedGames>/DCS/dcs-sms/inbox` can run code. Simplest. Matches expectations from the existing hook.
2. **Opt-in per session** — ME-mod menu has an "Allow external execution" toggle that defaults off. User flips it on per session when they want Claude driving. Slight friction; meaningful guard.

Recommended default: **(1) for parity, but ship the menu toggle from day one** so users who care can flip it off. Document the trust model in the ME-mod README.

## Phasing (for if/when we build)

- **Phase 1 — minimal viable bridge.** Mailbox + `UpdateManager` poller + `target` field + ME-mod menu toggle. ~150 lines of Lua + small CLI flag. Ships independently of other framework work.
- **Phase 2 — Claude UX.** A natural-language wrapper (skill or slash command) that takes user intent, generates Lua against the `mission` table, sends via the bridge, and explains the result. Lives in the user's `.claude/` setup, not the framework.
- **Phase 3 (optional) — TCP localhost listener.** Same `UpdateManager` driver, sockets instead of disk, sub-ms latency. Only if usage justifies it.

YAGNI cuts already applied: dropped hook-side handoff (regression of Phase 1), named pipes (needs C ext), shared memory (overkill), WebSocket (only useful if a browser UI lands).

## Cross-cutting items if we proceed

- **AGENTS.md §7** — add a one-line entry for the new ME-side bridge module if it ends up exposed as `sms.me_bridge` or similar (or note it as ME-mod-internal if not).
- **`docs/api/`** — only if the bridge module exposes user-facing Lua API. The CLI flag would go in the ME-mod README.
- **`docs/superpowers/specs/`** — write a design doc before implementing, per CLAUDE.md convention. Spec name: `2026-05-08-me-execution-bridge-design.md`.
- **CHANGELOG.md + version bump** — ME-mod track (`me-mod-v0.5.0` candidate) when shipped.

## Files Created

- `_interview-index.md` — orientation doc for this research session
- `_summary.md` — this file
- `research/me-bridge-agent1-dcs-surfaces.md` — DCS Lua surfaces outside mission runtime
- `research/me-bridge-agent2-existing-tools.md` — survey of existing tools and their gating
- `research/me-bridge-agent3-ipc-patterns.md` — IPC pattern tradeoffs with comparison table

## Recommended next step

If you want to proceed: I'd write the spec under `docs/superpowers/specs/2026-05-08-me-execution-bridge-design.md` first (Phase 1 only), then a small implementation plan, then the actual code. ~150 LOC Lua + a CLI flag — well under a day's work.

If you'd rather sit on it: the research is committed in `research/` and `docs/interviews/`, so a future session can pick it up cold.
