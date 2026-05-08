# dcs-sms ME Execution Bridge — Design

**Date:** 2026-05-08
**Status:** Draft (research-backed; pending implementation plan)
**Scope:** Extend the existing execution bridge so it works while DCS is at the main menu or in the Mission Editor, not just inside a running mission. Adds a `target` field to the request schema and a menu toggle in the ME-mod that gates external execution.
**Companion research:**
- `docs/interviews/me-bridge-2026-05-08/_summary.md`
- `research/me-bridge-agent1-dcs-surfaces.md`
- `research/me-bridge-agent2-existing-tools.md`
- `research/me-bridge-agent3-ipc-patterns.md`

## Goal

Today the CLI's `dcs-sms exec` only works while a mission is running. Make it also work while the user is in the Mission Editor, so an external client (Claude, a script, the user) can run Lua against the editable mission table — read groups/zones/airbases, mutate them, save the .miz — without launching the sim.

The motivating use case is natural-language-driven mission editing: "rename this group", "add 4 SAMs around this airbase", "swap that flight's loadout", typed at Claude and applied live.

## Non-goals

- **TCP / WebSocket listener.** Future option (covered in `research/me-bridge-agent3-ipc-patterns.md`); not in this spec. File mailbox only.
- **Breaking the existing protocol.** Existing `target`-less request files keep working unchanged; default routing is `mission`.
- **A new Lua public surface (`sms.*` module).** The bridge is hook-level / mod-level infrastructure, not framework API. No `docs/api/` page is added.
- **Cross-state Lua execution from the mission env.** This spec only adds bridge → ME execution. The mission env keeps doing what it already does.
- **Multi-DCS-instance support.** Same constraint as the original bridge.
- **Streaming output / sub-frame latency.** Same target as the original: 1–2 ticks of round-trip is fine.

## Background — what the research established

Three findings drove this design and are load-bearing:

1. **GUI hook env and ME env share one Lua VM.** `<DCS>/Scripts/UserHooks.lua` runs first and `dofile`s `<DCS>/MissionEditor/MissionEditor.lua` into the same VM. Globals persist across menu→ME→sim→ME→menu for the entire DCS process lifetime. The user's `Saved Games/DCS/Scripts/Hooks/*.lua` files (where `dcs-sms-hook.lua` lives) and the ME-mod (`<DCS>/MissionEditor/modules/dcs_sms_me/`) are in the **same Lua state**. Verified against ED's source files in agent1 report §1.
2. **`UpdateManager.add(fn)` is the per-frame primitive that ticks while at the main menu and in the ME.** It is the equivalent of `onSimulationFrame` for non-sim state. The dcs-sms ME-mod *already* uses it (`tools/me-mod/lua/dcs_sms_me/window.lua:49` requires it; `:1487-1491` registers a status-bar tick on it). Returning `false` from the registered function keeps it registered. There is **no** `onMenuFrame` / `onIdle` callback in `DCS.setUserCallbacks`.
3. **Nobody else has done this.** Every comparable tool (DCS-gRPC, dcs_code_injector, Quaggles' Lua Connector, Olympus, Witchcraft, DCSServerBot) is gated by `onSimulationFrame` and dies at the main menu. Quaggles' `luaEnv` request field is the closest precedent for env-routing semantics.

The single-VM finding is what makes the design simple. We do not need a second poller.

## Architecture

```
┌──────────┐  exec --target gui   ┌──────────────┐  write   ┌──────────────┐  poll       ┌────────────────────┐
│  Agent   │ ───────────────────> │  dcs-sms.exe │ ───────> │ Saved Games/ │ <────────── │ dcs-sms-hook.lua   │
│ (Claude) │                      │   (Go CLI)   │          │  DCS/dcs-sms │             │ (UpdateManager.add) │
│          │ <─────────────────── │              │ <─────── │  inbox/      │ ──────────> │                     │
└──────────┘    JSON              └──────────────┘  read    │  outbox/     │  write      └────┬────────┬──────┘
                                                            │  state/      │                  │        │
                                                            └──────────────┘                  │        │
                                                                                              │        │
                                                target=gui (run in shared VM)  ◄──────────────┘        │
                                                target=mission (dostring_in)   ◄───────────────────────┘
                                                                                              │        │
                                                                                              ▼        ▼
                                                                                 ┌─────────────┐  ┌─────────────────┐
                                                                                 │ ME-mod menu │  │ DCS mission env │
                                                                                 │ toggle      │  │ (sandboxed)     │
                                                                                 │ gates "gui" │  └─────────────────┘
                                                                                 └─────────────┘
```

Same pieces as the original bridge (CLI + file mailbox + hook), with three deltas:

1. The hook's tick source is `UpdateManager.add(poll_inbox)` instead of `onSimulationFrame`.
2. The request schema gets a `target` field: `"mission"` (default, current behavior) or `"gui"` (new path).
3. The ME-mod gets a menu item that flips a global the hook checks before honoring `target=gui` requests.

### Why the ME-mod doesn't grow a peer listener

Because the hook and the ME-mod share a Lua VM, a second poller in the ME-mod would be redundant — anything the hook does inside `UpdateManager.add` already executes in the ME's globals. Two pollers means two heartbeats, two install paths, and two protocols to keep in sync, with no functional benefit. Discussed in `_summary.md` Option B.

The ME-mod's only role in this design is the **menu toggle** (UX gate), not a separate execution surface.

## Request schema delta

### Existing (`inbox/<uuid>.req.json`, unchanged)

```json
{
  "id": "0193f9aa-...",
  "kind": "exec",
  "code": "return Unit.getByName('Tanker-1'):getCoalition()",
  "timeout_ms": 5000,
  "created_at": "2026-04-25T14:32:11.123Z"
}
```

When `target` is absent, behavior is unchanged: the hook routes to the mission env via `dostring_in('mission', wrapper)` exactly as today. Existing CLI users see no difference.

### New: `target` field

```json
{
  "id": "0193f9aa-...",
  "kind": "exec",
  "target": "gui",
  "code": "return mission.theatre",
  "timeout_ms": 5000,
  "created_at": "2026-05-08T14:32:11.123Z"
}
```

Allowed values:
- `"mission"` — execute in the sandboxed mission scripting env via `net.dostring_in('mission', wrapper)` plus `a_do_script(...)`. **Default when omitted.** Requires a mission to be running. Today's behavior.
- `"gui"` — execute directly in the shared GUI/ME Lua state via `loadstring(code)` + `pcall`. Requires the ME-mod toggle to be enabled. Reaches ME globals (the editable `mission` table, `Editor.*`, `DialogLoader`, etc.).

Other targets (e.g. `"hook"` as a synonym for `"gui"`) are not introduced — keep the surface small.

### Response schema (unchanged)

The response shape from `_summary.md` Option C — `{id, ok, return_value, output, error, frame_executed, duration_ms}` — is identical regardless of target. The `frame_executed` field, which today carries the sim frame number, will carry the `UpdateManager` tick counter for `target=gui` requests. Documented but not behaviorally significant.

### Heartbeat schema delta

```json
{
  "hook_version": "0.2.0",
  "state": "in_mission_editor",
  "mission_loaded": false,
  "mission_name": "",
  "gui_bridge_enabled": true,
  "tick_source": "update_manager",
  "last_tick": 184321,
  "last_tick_at": "2026-05-08T14:32:11.456Z"
}
```

New fields:
- `state` — one of `"starting" | "at_main_menu" | "in_mission_editor" | "loading_mission" | "in_mission" | "stopping"`. Set from `DCS.setUserCallbacks` events (`onShowMainInterface`, `onMissionLoadBegin/End`, `onSimulationStart/Stop`) plus a "ME open" probe (presence/visibility of the ME window). Source-of-truth for which targets the CLI can use right now.
- `gui_bridge_enabled` — mirrors the ME-mod toggle. Lets the CLI fail fast with a clear message instead of timing out.
- `tick_source` — `"update_manager" | "simulation_frame" | "simulation_frame_only"`. Reflects which handler is actively polling. The CLI can use this for diagnostics (`status` command) and to warn when `simulation_frame_only` means `target=gui` won't work outside a sim.
- Renamed `last_frame` → `last_tick` (and `last_frame_at` → `last_tick_at`) to match the new tick source. Old field names are kept as aliases for one release for backward compatibility.

### Bumping `hook_version`

`tools/lua/dcs-sms-hook.lua:8` (`version = "0.1.0"`) → `"0.2.0"`. CLI continues to warn-not-block on version mismatch.

## The hook (delta from today)

File: `tools/lua/dcs-sms-hook.lua` (modified). No new files at this layer.

### Lifecycle (new)

The hook registers **two** tick handlers — `UpdateManager.add(tick)` and `onSimulationFrame = tick` — but only one polls at any moment. A `DCS_SMS.tick_source` flag switches between them on sim start / stop. This trades a stable two-handlers-always-registered shape for an active/inactive flag, which avoids needing to figure out `UpdateManager`'s deregister semantics and removes any race between unregister and re-register.

**Why two sources at all:** `UpdateManager.add` ticks at GUI frame rate (~30-60 Hz foregrounded), but **throttles to ~2 Hz when DCS is minimized**. `onSimulationFrame` keeps ticking at sim rate during a running mission regardless of window state. Using `onSimulationFrame` while in sim means inbox polling stays responsive even when the user Alt-Tabs out of DCS during a long mission.

```
hook load
  └─ ensure_dirs (unchanged)
  └─ DCS_SMS.tick_source = "update_manager"        -- default at hook load
  └─ try require('UpdateManager')
       on success: UpdateManager.add(update_manager_tick)
       on failure (older DCS / unexpected env):
         DCS_SMS.tick_source = "simulation_frame_only"   -- degraded mode
         log.warn — partial functionality, heartbeat reflects this
  └─ register DCS.setUserCallbacks { onShowMainInterface, onMissionLoadBegin/End,
                                     onSimulationStart, onSimulationStop, onSimulationFrame }
  └─ write initial state/hook.json

update_manager_tick                 -- registered with UpdateManager.add
  └─ if DCS_SMS.tick_source ~= "update_manager" then return false end
       -- inactive: do nothing this tick, but stay registered for the next swap-back
  └─ DCS_SMS.tick = DCS_SMS.tick + 1
  └─ pcall(process_inbox)
  └─ pcall(write_heartbeat) if due
  └─ return false                    -- keep registered

handler.onSimulationFrame           -- registered via setUserCallbacks
  └─ if DCS_SMS.tick_source ~= "simulation_frame" then return end
       -- inactive in ME / main menu: do nothing
  └─ DCS_SMS.tick = DCS_SMS.tick + 1
  └─ pcall(process_inbox)
  └─ pcall(write_heartbeat) if due

handler.onShowMainInterface
  └─ DCS_SMS.state = "at_main_menu"
  └─ pcall(write_heartbeat)

handler.onMissionLoadBegin
  └─ DCS_SMS.state = "loading_mission"
  └─ pcall(write_heartbeat)

handler.onMissionLoadEnd
  └─ DCS_SMS.state = "in_mission" or "in_mission_editor" (probe — see Open Questions)
  └─ DCS_SMS.mission_loaded = true (only when in_mission, not in_mission_editor)
  └─ sweep stale (unchanged)
  └─ pcall(write_heartbeat)

handler.onSimulationStart           -- mission begins running
  └─ DCS_SMS.state = "in_mission"
  └─ DCS_SMS.tick_source = "simulation_frame"     -- swap to sim-rate polling
  └─ pcall(write_heartbeat)

handler.onSimulationStop            -- back out to ME or main menu
  └─ DCS_SMS.state = "in_mission_editor" or "at_main_menu"
  └─ DCS_SMS.mission_loaded = false
  └─ DCS_SMS.tick_source = "update_manager"       -- swap back to GUI tick
  └─ pcall(write_heartbeat)
```

`tick_source` values:
- `"update_manager"` — default. Active in main menu, ME, between missions.
- `"simulation_frame"` — active during a running mission. Set in `onSimulationStart`, cleared in `onSimulationStop`.
- `"simulation_frame_only"` — fallback if `require('UpdateManager')` fails on this DCS version. Polling only happens during a sim, exactly like today's behavior. Reported in heartbeat so the CLI can warn the user that `target=gui` won't work in the menu / ME on this install.

Both handlers are *always* registered after hook load; the flag decides which one does the work. There's no Lua race in switching: the flag is a single integer, both handlers run on the main thread (Lua single-threaded inside DCS), and the inactive handler simply early-returns without touching shared state.

### Distinguishing "in mission editor" from "at main menu"

Probe by checking for an ME-specific global. The ME-mod's existing menu probe (`me_menubar.menuBar`, used by `tools/me-mod/lua/dcs_sms_me/menu.lua`) is one option, but it's a side-effect of how the ME-mod injects into the menu and not a guaranteed-stable surface. A cheaper probe: when the ME's main module is loaded, `_G.Mission` (the live mission tree) is non-nil and has `theatre` set. Document this as the chosen probe with a fallback to "unknown" so we never lie in the heartbeat.

### Dispatch (new)

```lua
local function execute_request(filename)
  local req = parse(filename)            -- as today
  local target = req.target or "mission"

  if target == "mission" then
    -- existing path: build_wrapper -> net.dostring_in('mission', wrapper)
    return execute_mission(req)
  elseif target == "gui" then
    if not _G.DCS_SMS_GUI_BRIDGE_ENABLED then
      return write_response(req.id, { ok = false, error = {
        message = "gui bridge is disabled (toggle in DCS-SMS menu)",
        traceback = "",
      }})
    end
    return execute_gui(req)
  else
    return write_response(req.id, { ok = false, error = {
      message = "unknown target: " .. tostring(target),
      traceback = "",
    }})
  end
end
```

`execute_gui` runs the user code in the shared VM:

```lua
local function execute_gui(req)
  local out, orig_print = {}, print
  print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
    out[#out+1] = table.concat(parts, "\t")
  end

  local chunk, load_err = loadstring(req.code, "dcs-sms-gui:" .. req.id)
  if not chunk then
    print = orig_print
    return write_response(req.id, { ok = false, error = {
      message = "loadstring: " .. tostring(load_err),
      traceback = "",
    }})
  end

  local start = os.clock()
  local ok, ret = xpcall(chunk, debug.traceback)
  print = orig_print
  local dur = (os.clock() - start) * 1000

  write_response(req.id, {
    id = req.id,
    ok = ok,
    output = table.concat(out, "\n"),
    return_value = ok and ret or nil,
    error = (not ok) and { message = tostring(ret), traceback = "" } or nil,
    frame_executed = DCS_SMS.tick,
    duration_ms = dur,
  })
end
```

No `a_do_script(...)` wrapping — the hook *is* in the right state. JSON encoding is the same pure-Lua encoder already used in the mission wrapper, factored to a shared helper.

### Constraints on `target=gui` snippets

- **Locals don't persist; globals do.** Same caveat as `target=mission`. Each chunk is `loadstring`-ed fresh against the same `_G`. We document this; we do not introduce a "session" abstraction.
- **No preemption.** A `while true do end` snippet hangs the entire DCS GUI thread. CLI times out; user kills DCS. Same documented limitation as today.
- **Userdata can't be returned.** ME globals have far more userdata than the mission env (Qt-ish widgets, bound C objects). Returning a primitive — `mission.theatre`, `Mission.groups[1].name` — is the supported pattern. Documented.
- **Save side-effects are visible to the user.** Writing to `mission.groups`, calling `Mission.changesPending = true`, etc., affects the user's open mission. The toggle is the safety net for "I didn't mean to let the AI rewrite my mission while I went for coffee."

## ME-mod menu toggle

File: `tools/me-mod/lua/dcs_sms_me/menu.lua` (modified). One new menu item.

```lua
-- existing: DCS-SMS menu with "Prefab Manager", "About"
-- new: a third item, "External execution: <on|off>", that toggles _G.DCS_SMS_GUI_BRIDGE_ENABLED
```

Behavior:
- **Default off** at every DCS launch. (Session-only; see open question below.)
- Clicking the menu item flips the global and updates the menu label (`"External execution: ON"` vs `"External execution: OFF"`).
- Setting the global causes the hook's heartbeat to reflect `gui_bridge_enabled: true/false` on the next tick.
- The toggle is **runtime-instant**. No DCS restart required. (Restart is only required once after installing the new ME-mod / hook code.)

The ME-mod adds nothing else — no listener, no inbox watcher, no parallel state. Just the toggle. The hook is the entire execution path.

### Why default off

The `target=mission` path runs against a sandboxed env that exists only briefly during a sim. The `target=gui` path runs in the shared VM with full `io.*`, `lfs`, `os.execute`, and direct access to the editable mission table. That's a real blast-radius difference. Off-by-default is the conservative choice; a one-click flip to enable is the right friction level for "yes, Claude is driving for the next ten minutes."

## CLI delta (`tools/cmd/dcs-sms`)

### `dcs-sms exec` — new flag `--target`

```
dcs-sms exec [--file path.lua | --code "..."] [--target gui|mission|auto] [--timeout 5s] [--wait] [--json | --pretty]
```

- `--target mission` (default) — current behavior.
- `--target gui` — sets `target: "gui"` in the request file.
- `--target auto` — read the heartbeat's `state` field; route to `gui` if `state in {"in_mission_editor", "at_main_menu"}` and `gui_bridge_enabled`, route to `mission` if `state == "in_mission"`. Errors out with a clear message otherwise.

`auto` is the convenience knob for "Claude doesn't know which one is right." Implementation hint: it's just a one-liner over the existing `status` reader.

### `dcs-sms status`

Already prints heartbeat info. Just exposes the new `state` and `gui_bridge_enabled` fields. Exit codes unchanged.

### `dcs-sms exec` exit codes

Add one:
- `4` — `--target gui` requested but `gui_bridge_enabled` is false. Skip if `--wait` (poll until enabled).

Existing codes (`0` ok, `1` snippet error, `2` timeout, `3` hook not ready) keep their meanings.

### Path / install

- `dcs-sms install-hook` writes the new hook (still embedded via `//go:embed`).
- `dcs-sms install-me-mod` writes the updated ME-mod (now with the menu toggle).
- Both require a single DCS restart after install (existing behavior; documented in both READMEs).

## Lifecycle table (delta)

| Situation | Hook behavior | CLI sees |
|---|---|---|
| DCS not running | nothing | `status` reports stalled; `exec` exits 3 |
| DCS at main menu | `UpdateManager` ticks; heartbeat `state="at_main_menu"`, `mission_loaded=false`. `target=gui` works (toggle permitting); `target=mission` errors. | `exec --target gui` works; `--target mission` errors with helpful message |
| User opens ME, no mission | `state="in_mission_editor"` (no `Mission` global yet); `target=gui` works | `exec --target gui` works |
| User loads mission in ME | `state="in_mission_editor"`, `Mission` global populated; `target=gui` can read/write it | `exec --target gui` reads/mutates the editable mission |
| Mission starts | `onSimulationStart` flips `tick_source` to `"simulation_frame"`; `UpdateManager` tick goes inactive; sim-rate polling takes over | heartbeat shows `tick_source="simulation_frame"`; polling stays responsive even when DCS is minimized |
| Mission running | `state="in_mission"`, `mission_loaded=true`; both targets work; `target=gui` runs in shared VM (ME-mod globals still present) | both targets work |
| Mission stops (returns to ME or menu) | `onSimulationStop` flips `tick_source` back to `"update_manager"`; `onSimulationFrame` no longer fires anyway | heartbeat shows `tick_source="update_manager"` again on next tick |
| Toggle off, user requests `target=gui` | hook returns `ok=false` with explanatory message | exit code 1 (snippet error) with `error.message` containing "gui bridge is disabled" |
| `target=gui` snippet hangs | hook cannot preempt; UpdateManager stalls | CLI times out; user kills DCS |

## Repo layout (delta)

No new top-level dirs. Affected files only:

```
tools/
├── lua/
│   └── dcs-sms-hook.lua            # MODIFIED: UpdateManager poller + target dispatch
├── cmd/dcs-sms/
│   ├── exec.go                     # MODIFIED: --target flag, --auto routing
│   └── status.go                   # MODIFIED: render new state / gui_bridge_enabled fields
├── internal/
│   ├── proto/                      # MODIFIED: Request gets `target` field, Heartbeat gets `state` etc
│   └── hookstatus/                 # MODIFIED: parse new heartbeat fields, expose state probe
└── me-mod/lua/dcs_sms_me/
    └── menu.lua                    # MODIFIED: add "External execution: on/off" menu item

docs/
├── superpowers/specs/
│   └── 2026-05-08-me-execution-bridge-design.md   # NEW (this file)
├── interviews/me-bridge-2026-05-08/                # NEW: research artifacts (already exist)
└── api/                                            # UNCHANGED — no public sms.* surface added

research/
├── me-bridge-agent1-dcs-surfaces.md                # NEW (already exists)
├── me-bridge-agent2-existing-tools.md              # NEW (already exists)
└── me-bridge-agent3-ipc-patterns.md                # NEW (already exists)
```

No `framework/` changes. No new `sms.*` module. No `docs/api/` page.

## Versioning + AGENTS.md

- **Hook version:** `0.1.0` → `0.2.0` (in `tools/lua/dcs-sms-hook.lua`).
- **ME-mod version:** bumped according to AGENTS.md §11 for the menu toggle. Likely `0.5.0` (minor — additive feature). The ME-mod track is independent of the framework track.
- **Framework version:** unchanged (no `sms.*` change).
- **AGENTS.md §7:** **No edit needed.** This change does not touch the public framework surface (the `sms.*` modules); §7 is unaffected. The bridge / ME-mod are tools, not framework.
- **CHANGELOG.md:** new entry under both `[Unreleased]` ME-mod and tools sections in the same commit-set, per AGENTS.md §11.

## Testing strategy

L1 — Go unit tests, no DCS:
- New `proto.Request{Target}` round-trip through JSON.
- New heartbeat fields (`state`, `gui_bridge_enabled`) parse cleanly; old format (without those fields) parses with sensible defaults.
- `--target auto` routing logic with synthetic heartbeats: each combination of `(state, gui_bridge_enabled)` → expected route or error.
- Exit-code mapping for new code 4.

L2 — Fake-hook integration:
- Extend the existing fake hook to honor `target`. `target=gui` request → return synthetic response. `target=gui` with `gui_bridge_enabled=false` → error response.
- Test `--target auto` end-to-end against a fake hook that flips `state` between calls.

L3 — Real DCS smoke:
- Manual checklist additions (in `tools/lua/README.md` and `tools/me-mod/README.md`):
  1. Open DCS to main menu. `dcs-sms status` reports `state="at_main_menu"`, `gui_bridge_enabled=false`, `tick_source="update_manager"`.
  2. Open Mission Editor. `state` flips to `in_mission_editor`; `tick_source` stays `"update_manager"`.
  3. Click DCS-SMS menu → "External execution: OFF" → flips to ON. `gui_bridge_enabled=true` next tick.
  4. `dcs-sms exec --target gui --code 'return _VERSION'` → returns `"Lua 5.1"`.
  5. Open a .miz in the ME. `dcs-sms exec --target gui --code 'return mission.theatre'` → returns the theatre name.
  6. `dcs-sms exec --target gui --code 'mission.groups.blue[1].name = "Renamed"' ` then visually verify in the editor.
  7. Toggle off. `dcs-sms exec --target gui ...` returns "gui bridge is disabled" with exit code 1.
  8. Start a mission. `tick_source` flips to `"simulation_frame"`. Both `--target gui` and `--target mission` work.
  9. Minimize DCS during the running mission. `dcs-sms exec --target mission` round-trip stays sub-100 ms (sim ticks keep firing). Restore window — `tick_source` is still `"simulation_frame"`.
  10. Exit the mission back to the ME. `tick_source` flips back to `"update_manager"` on next tick. `state="in_mission_editor"`.

## Open implementation questions

These are deferred to the implementation plan, not this design:

- **Toggle persistence.** Default for this spec is **session-only** (off at every DCS launch). A "Remember" sub-item could persist via the ME-mod's existing config path (`<SavedGames>/DCS/dcs-sms/config.lua` or similar). Lower friction, slightly less safe. Recommend revisiting after a few weeks of use.
- **ME-window-open probe.** What's the cheapest reliable way to distinguish "DCS is in the ME" from "DCS is at the main menu"? Candidates: presence of `_G.Mission`, presence of `me_menubar.menuBar`, an explicit `setUserCallbacks` event the ME emits (none documented), or having the ME-mod set its own global on init. Pick during implementation.
- **`UpdateManager` failure mode on older DCS.** Decided: fall back to `tick_source = "simulation_frame_only"`, surfaced via the heartbeat. CLI prints a clear warning on `--target gui` requests when that flag is set. (Captured in the Lifecycle section above.)
- **CLI default routing.** Should `--target` default to `auto` instead of `mission`? Pros: smoother UX. Cons: changes default behavior for existing callers. Recommend keeping default = `mission` for one release, then revisit.

## Out of scope (deliberately)

- TCP / WebSocket listener (Phase 2 candidate, see `research/me-bridge-agent3-ipc-patterns.md`).
- A natural-language Claude wrapper / skill that drives `--target gui` from English. Lives in user's `.claude/`, not the framework.
- Capturing `env.info` / `log.write` from `target=gui` snippets (analog of the Phase-1 `print`-only constraint from the original spec).
- Multi-DCS-instance routing.
- Persistent toggle state across DCS restarts (deferred per Open Questions).
