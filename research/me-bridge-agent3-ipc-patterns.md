# IPC patterns for an out-of-mission DCS bridge (ME / main menu)

**Author:** research agent (2026-05-08)
**Scope:** how to drive a polling/listening loop in the ME / main-menu Lua state where there is no `onSimulationFrame` (or it ticks only inside a running mission). Companion research; the in-mission file-mailbox already works.

## Grounding facts (from this codebase + ED's published `MissionEditor.lua`)

- The ME-mod already uses **`UpdateManager`** as a per-frame tick. See `tools/me-mod/lua/dcs_sms_me/window.lua:49` (`require 'UpdateManager'`) and `:1487-1491` (`UpdateManager.add(tick_status_clear)`). `UpdateManager.add(fn)` registers a function called every Qt-ish frame (~30-60 Hz when the ME window is in the foreground; lower when minimised/Alt-Tabbed). Returning `false` keeps it registered. **This is the equivalent of `onSimulationFrame` for the ME state and it is the single most important finding.**
- ME state has full `io.*`, `lfs`, `os.rename`, and can `require('socket')` if LuaSocket DLLs are present in `bin/Lua/socket/` (DCS ships them; mods like Tacview / DCS-Hawk do this).
- The hook env (`Scripts/Hooks/`) is *also* a separate Lua state that runs in the main menu. It already has the file mailbox today (`tools/lua/dcs-sms-hook.lua`) but its `process_inbox` is gated on `mission_loaded` and driven by `onSimulationFrame`, which only fires inside a sim. The hook env *does* receive `onShowMainInterface`, `onMissionLoadEnd`, `onSimulationStart/Stop` callbacks but no per-frame tick at the main menu.
- Hook-env ↔ ME-env are **separate Lua states** in the same process. There is no `dostring_in('ME', …)` API. Cross-state communication has to go through disk, a socket, or a shared C-side global.

## Candidates

### 1. File mailbox + `UpdateManager` polling in the ME-mod

Reuse the hook's protocol verbatim (inbox/outbox JSON, atomic tmp+rename, heartbeat). Register one `UpdateManager.add(poll_inbox)` from `init.lua` (or lazily on first window open, like the status tick does at `window.lua:1489`).

- **Reliability:** very high. Survives mission load/unload (the ME state is loaded once at DCS startup and lives until DCS exits). Survives Alt-Tab — `UpdateManager` keeps firing, just slower. Re-opening the ME window doesn't re-init the state. The atomic-rename protocol is already battle-tested in the hook.
- **Latency:** one frame at 30-60 Hz = 16-33 ms when foregrounded; ~100-200 ms when DCS is minimised (Qt throttles). Fine for human-in-the-loop edit commands.
- **Complexity:** ~150 lines. ~80% of the hook's code copy-pastes; only the namespace / paths and the dispatcher (no `dostring_in` indirection — execute directly in ME state) change.
- **Failure mode:** external process dies → nothing happens, `.req.json` files just don't appear; stale-sweep handles half-written ones. ME freezes → polling stops, external client times out via heartbeat staleness.
- **Concurrency:** single-threaded request/response works fine. The poll loop drains 1-N requests per frame; mutating the mission table inside `UpdateManager` is safe — that's the Qt main thread. **Recommended.**

### 2. File mailbox in the always-on hook + handoff to ME

Keep the hook polling but add a tick source that works at main menu (e.g. piggy-back on `onShowMainInterface` + a `Window:scheduleCallback`-style timer). When a `target=me` request arrives, write a "shadow" file the ME-mod's own `UpdateManager` poller picks up.

- **Reliability:** high — same disk substrate. But you've now built **two** polling loops and a hand-off file. Fragile.
- **Latency:** worst-case = hook tick + ME tick = 50-100 ms, no real benefit.
- **Complexity:** much higher than (1). Two pollers, a routing rule, and you still need (1) anyway because `dostring_in('ME', …)` doesn't exist.
- **Verdict:** strict regression of (1). Only useful if you also want a **menu-only** path (no ME open) — and you can do that by polling from the hook on `onShowMainInterface`/timer, no handoff needed.

### 3. TCP socket server in the ME via LuaSocket

`require('socket')`; `local s = socket.bind('127.0.0.1', 7892); s:settimeout(0)`. Inside an `UpdateManager` callback: `local c = s:accept(); if c then c:settimeout(0); …`. Read framed JSON, dispatch, write response.

- **Reliability:** high while the ME state is alive. Bind survives mission load (different state). 127.0.0.1-only avoids firewall popup and untrusted-network risk. Single-threaded — accept happens on the main thread, so no GIL/lock issues.
- **Latency:** sub-millisecond on localhost. Best of any candidate.
- **Complexity:** ~200 lines of Lua (bind + non-blocking accept + length-prefixed framing + JSON via `net.lua2json` if exposed, else `dkjson` or hand-rolled). Cross-platform (LuaSocket works on Windows + Linux DCS).
- **Failure mode:** external client dies → orphan socket on next `accept`, just close it. ME freezes → TCP connect succeeds but read hangs; client uses timeouts. Port collision (7892 already taken) needs fallback. **Bind requires correct LuaSocket DLL location** — DCS ships it, but if a future patch moves it the mod silently loses sockets.
- **Concurrency:** single-threaded request/response in the same `UpdateManager` tick is the cleanest model. One in-flight request at a time keeps the mission table consistent.
- **Verdict:** **Strong second choice / future option.** Lower latency than file mailbox but gives up the "external tool can be plain shell + `cat` of a file" debuggability the mailbox protocol has. Recommended once a non-trivial command rate is needed.

### 4. Named pipes (Windows `\\.\pipe\name`)

Lua 5.1 + LuaSocket has **no** named-pipe support out of the box (LuaSocket is BSD-sockets-only). Would need a C extension (`luaposix`, `lua-winapi`) or use `io.open('\\.\\pipe\\name')` which works for *client* mode against an already-created pipe but **cannot create a server pipe** (no `CreateNamedPipe` Lua binding).

- **Verdict:** not viable without shipping a C DLL. Skip.

### 5. Shared memory / mmap

Same problem as (4) — needs a native binding (`lua-mmap`). Adds Linux/Windows binary churn for sub-ms latency we don't need.

- **Verdict:** overkill for human-in-the-loop edit commands. Skip.

### 6. LSP-style stdio child process

Spawn a child from DCS that owns a TCP/WebSocket and forwards via stdin/stdout. **DCS Lua has no `io.popen` for long-lived bidirectional pipes** — `os.execute` blocks the GUI thread until the child returns. Even if it didn't, you've added a process for no benefit (the ME can listen directly per (3)).

- **Verdict:** not viable in DCS Lua. Skip.

### 7. WebSocket via pure-Lua over LuaSocket

Same socket plumbing as (3) plus the WS handshake (~150 extra lines, well-trodden — `lua-websockets` or `lua-resty-websocket` strip down well). Useful only if a browser UI is in scope.

- **Reliability / latency:** identical to (3).
- **Complexity:** strict superset of (3).
- **Verdict:** revisit only if a browser-based frontend is decided. For Claude-CLI driving, (3) is leaner.

## How other Lua-scripted editors / runtimes solve it

- **ZeroBrane Studio + LÖVE / Defold:** TCP debugger. ZBS's `MobDebug` opens a listener on the IDE side; the script connects out via LuaSocket. Pattern survived ~15 years and works for any Lua host that exposes LuaSocket. **Closest analogue to candidate (3).**
- **Defold editor:** the editor is JVM, but exposes a TCP HTTP server (`/post`) for hot-reload commands; build tools push code over HTTP. Same TCP-on-localhost pattern.
- **WoW addons:** **no** outbound IPC — the Blizzard sandbox forbids `io.*` and sockets entirely. WowMatrix-style external launchers work *outside* the game (touch SavedVariables files when WoW is closed). The DCS analogue is "edit `.miz` while DCS isn't running" — strictly weaker than what we're after.
- **KSP / kOS:** Telnet listener inside the C# plugin (kOS exposes Lua-ish kRPC). TCP is the dominant choice.
- **FlightGear:** built-in Telnet `props` protocol on a TCP port — query/set the property tree. Survived 20 years.
- **X-Plane plugins:** UDP/TCP listeners are the standard pattern (ExtPlane, X-Plane Connect). File mailboxes are rare because X-Plane has a stable per-frame callback (`XPLMRegisterFlightLoopCallback`).

**Pattern that survived everywhere it was tried:** TCP-on-localhost driven from the host's per-frame callback. **Pattern that was abandoned:** named pipes (Windows-only, fragile across Lua versions) and shared memory (binary-deps churn). File mailboxes survive in environments without sockets (sandboxed addon hosts) and as a debug-friendly fallback.

## Recommendation

**Phase 1 (now):** candidate **(1)** — file mailbox driven by `UpdateManager.add` in the ME-mod. Reuses 80% of the hook's mailbox code, zero new dependencies, debuggable with `cat`/`type`, latency is fine for editor commands. Add the `target=me` field to the protocol so the CLI can route.

**Phase 2 (later, only if needed):** candidate **(3)** — add a localhost TCP listener alongside the mailbox for sub-ms latency once command rate / streaming use cases appear. Keep the mailbox as a fallback / debug surface.

Skip (2), (4), (5), (6), (7) for now.

## Comparison table

| Candidate | Latency | Reliability | Complexity | Risk | Verdict |
|---|---|---|---|---|---|
| 1. Mailbox + UpdateManager | 16-200 ms | Very high | Low (~150 LOC, reuse) | Very low | **Recommended (Phase 1)** |
| 2. Mailbox + hook handoff | 50-100 ms | Medium | High (two pollers) | Medium | Skip — strict regression of (1) |
| 3. TCP localhost server | <1 ms | High | Medium (~200 LOC) | Low (LuaSocket dep) | **Phase 2 upgrade** |
| 4. Windows named pipe | <1 ms | Medium | High (needs C ext) | High (binary churn) | Skip |
| 5. Shared memory / mmap | <1 ms | Medium | High (needs C ext) | High | Skip — overkill |
| 6. LSP-style stdio child | n/a | n/a | n/a | n/a | Not viable in DCS Lua |
| 7. WebSocket over LuaSocket | <1 ms | High | Medium-high | Low | Defer — only if browser UI |
