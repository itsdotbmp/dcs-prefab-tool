# dcs-sms Execution Bridge — Design

**Date:** 2026-04-25
**Status:** Approved (brainstorm phase)
**Scope:** First sub-project of dcs-sms — a host-side tool and in-DCS hook that lets an agent (or human) execute Lua snippets in a running DCS mission and read back structured results.

## Goal

Replace the `dcs_code_injector` execution mechanism with one that:

1. Returns *actual results* (status, captured output, return value) — not just `MSG_OK` acks.
2. Does not require per-frame TCP teardown or client reconnect-loops.
3. Provides a clean agent-facing interface (CLI) so Claude can drive DCS efficiently during development.
4. Keeps the host-side tool small, single-binary, and stateless.

The deliverable is the bridge only. Building a human-facing REPL UI on top is explicitly out of scope for this iteration but is not blocked by anything in this design.

## Non-goals

- A general-purpose RPC framework. The bridge serves dcs-sms's own needs.
- Capturing every Lua/DCS output stream (`env.info`, `trigger.action.outText`, etc.) on day one. Just `print` is captured initially. More can be added later.
- Cross-platform. DCS is Windows-only; we are Windows-only.
- Multi-DCS-instance support. One DCS process, one bridge.
- Streaming output / sub-frame latency. Round-trip in 1–2 frames is the target.

## Architecture

```
┌──────────┐  exec        ┌──────────────┐  write   ┌──────────────┐  poll    ┌────────────────────┐
│  Agent   │ ───────────> │  dcs-sms.exe │ ───────> │ Saved Games/ │ <─────── │  DCS hook (Lua)    │
│ (Claude) │              │   (Go CLI)   │          │  DCS/dcs-sms │          │  Scripts/Hooks/    │
│          │ <─────────── │              │ <─────── │  inbox/      │ ───────> │  dcs-sms-hook.lua  │
└──────────┘    JSON      └──────────────┘  read    │  outbox/     │  write   └────────┬───────────┘
                                                    │  state/      │                   │
                                                    └──────────────┘                   │ net.dostring_in
                                                                                       v
                                                                                ┌──────────────┐
                                                                                │ DCS mission  │
                                                                                │  Lua env     │
                                                                                └──────────────┘
```

Three components, three boundaries, no daemons:

- **Agent / human** invokes the Go CLI.
- **Go CLI (`dcs-sms.exe`)** is the only host-side process. Stateless. Writes a request file, polls for a response, prints JSON, exits.
- **File mailbox** lives under `Saved Games/DCS*/dcs-sms/`. No sockets, no ports, no installer plumbing.
- **DCS hook** runs in the GUI/hook environment (full Lua, LuaSocket available, no sandbox). Each `onSimulationFrame` it scans the inbox, executes any pending requests via `net.dostring_in('mission', ...)`, captures output and return values, writes response files.
- **Mission env** is where snippets actually execute. The hook injects a small wrapper that captures `print` and the return value of the snippet.

### Why file-based, not TCP

The current `dcs_code_injector` accepts a TCP connection on every frame and tears it down at frame-end. The author tried but could not find a way to keep a persistent TCP server open inside DCS without blocking the simulation. File-based transport sidesteps this entirely:

- No socket lifecycle management inside DCS.
- No client-side reconnect loops.
- Crash-resistant: if DCS dies mid-snippet, the inbox just has a stale request — easy to recover.
- Trivially debuggable: just look at the files.
- Latency is acceptable. The agent use case is not real-time; 1–2 frames of round-trip (~30 ms at 60 fps) is invisible.

A persistent-TCP transport is preserved as a future option behind the same agent-facing CLI interface, if a use case ever justifies the complexity. The CLI surface does not change.

### Why Go for the CLI

- Single static binary distribution. The author previously hit AV false-positive issues with Nuitka-packaged Python; Go binaries avoid that whole class of problem.
- Fast cold-start (~5 ms vs. ~100 ms for Python). Matters when the agent calls the CLI dozens of times per session.
- Stdlib covers everything the tool needs (file IO, atomic rename, JSON, line-scanning a log file).
- Static typing and small surface area fit the dcs-sms philosophy of "small things that don't surprise you in a year."

## File mailbox protocol

### Directory layout

Under `Saved Games/DCS*/dcs-sms/`:

```
dcs-sms/
├── inbox/              # CLI writes <uuid>.req.json here
├── outbox/             # hook writes <uuid>.res.json here
├── state/
│   └── hook.json       # hook heartbeat (rewritten every ~30 frames)
└── log/
    └── hook.log        # hook's own diagnostic log (separate from dcs.log)
```

### Atomic writes

Both sides write to a sibling `.tmp` file in the destination folder, then rename to the final name. On Windows NTFS, rename within a single folder is atomic enough that a reader never observes a half-written file. No file locking is needed.

### Request file (`inbox/<uuid>.req.json`)

```json
{
  "id": "0193f9aa-...",
  "kind": "exec",
  "code": "return Unit.getByName('Tanker-1'):getCoalition()",
  "timeout_ms": 5000,
  "created_at": "2026-04-25T14:32:11.123Z"
}
```

### Response file (`outbox/<uuid>.res.json`)

Success:
```json
{
  "id": "0193f9aa-...",
  "ok": true,
  "return_value": 2,
  "output": "spawned tanker at 1234,5678\n",
  "error": null,
  "frame_executed": 184321,
  "duration_ms": 1.2
}
```

Error:
```json
{
  "id": "0193f9aa-...",
  "ok": false,
  "return_value": null,
  "output": "",
  "error": {
    "message": "attempt to index a nil value (local 'unit')",
    "traceback": "stack traceback:\n\t[string \"...\"]:3: in function <...>\n\t..."
  },
  "frame_executed": 184321,
  "duration_ms": 0.4
}
```

### Heartbeat file (`state/hook.json`)

Rewritten by the hook every ~30 frames (~0.5 s at 60 fps):

```json
{
  "hook_version": "0.1.0",
  "mission_loaded": true,
  "mission_name": "Caucasus_QRA.miz",
  "last_frame": 184321,
  "last_frame_at": "2026-04-25T14:32:11.456Z"
}
```

Used by `dcs-sms status` and as a freshness gate by `dcs-sms exec` (see Lifecycle section).

### Concurrency

Multiple parallel `exec` calls each get a distinct UUID. The hook processes them in `os.time()` order, one per frame. No queue, no locking — the filesystem is the queue.

### Cleanup

- **Hook startup (`onMissionLoadEnd`):** delete any `*.req.json` and `*.res.json` older than 60 s. Recovers from the "DCS crashed mid-snippet" case.
- **CLI:** deletes its own `.res.json` after reading. Orphan `.res.json` files older than the request's timeout are also swept on next CLI run.

## Lua hook

Single file, `tools/lua/dcs-sms-hook.lua`, embedded into the Go binary via `//go:embed` and installed by `dcs-sms install-hook` into `Saved Games/DCS*/Scripts/Hooks/`.

### Hook lifecycle

```
hook load
  └─ register DCS userCallbacks {onMissionLoadEnd, onSimulationFrame, onSimulationStop}
  └─ ensure dcs-sms/ folder structure exists (lfs)
  └─ write initial state/hook.json

onMissionLoadEnd
  └─ mission_loaded = true
  └─ sweep stale request/response files (>60 s)
  └─ refresh state/hook.json

onSimulationFrame                   -- called every frame, GUI env
  └─ if not mission_loaded: write heartbeat if due, return
  └─ scan inbox/ for *.req.json (lfs.dir, oldest first)
  └─ for each: execute_request(req)
  └─ write heartbeat if due

onSimulationStop
  └─ mission_loaded = false
  └─ refresh state/hook.json
```

Empty-inbox scans complete in microseconds; the per-frame cost when there is no work is negligible. Real cost is only paid when there is actual work.

Every callback body runs inside `pcall` so a single bad request cannot break the hook for the rest of the session.

### `execute_request` flow

For each request file picked up:

1. Read and parse the `.req.json`.
2. Build a wrapper around the user's snippet that:
   - Rebinds `print` to capture into a buffer.
   - Runs the snippet inside `pcall(function() ... end)` so errors are catchable.
   - On error, captures the message and a traceback via `debug.traceback`.
   - Stashes the result into a global table `__DCS_SMS_RESULT`.
3. Call `net.dostring_in('mission', wrapper_code)` to execute in the mission env.
4. Call `net.dostring_in('mission', 'return net.lua2json(__DCS_SMS_RESULT)')` to serialize the result back out as a string.
5. Write the response to `outbox/<id>.res.json` (atomic rename).
6. Delete the request file.

Reference wrapper sketch (final form lives in `tools/lua/dcs-sms-hook.lua`):

```lua
local __dcs_sms_out = {}
local __dcs_sms_print = print
print = function(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  __dcs_sms_out[#__dcs_sms_out+1] = table.concat(parts, '\t')
end

local __dcs_sms_ok, __dcs_sms_ret = pcall(function()
  -- USER CODE INJECTED HERE
end)

print = __dcs_sms_print

__DCS_SMS_RESULT = {
  ok = __dcs_sms_ok,
  output = table.concat(__dcs_sms_out, '\n'),
  return_value = __dcs_sms_ok and __dcs_sms_ret or nil,
  error = (not __dcs_sms_ok) and __dcs_sms_ret or nil,
}
```

### Constraints on user snippets

- **Return values must be JSON-serializable.** `net.lua2json` handles primitives, tables, and arrays. Userdata (DCS Unit/Group objects, MOOSE-wrapped vec3s) does not serialize. Snippets that want to return such things must convert to a primitive first (`return unit:getName()`, not `return unit`). This is a documented constraint, not an automatic conversion.
- **Locals don't persist; globals do.** This is just how Lua works. `my_var = 22` (no `local`) sticks around for the next snippet because `net.dostring_in` evaluates each call as its own chunk against the same `_G`. We document this; we do not introduce a "session" abstraction.
- **No preemption.** A snippet with `while true do end` will hang DCS. The CLI will time out and report the situation, but the user has to kill DCS. Documented limitation.

### Output capture scope

Phase 1 captures `print` only. `env.info` / `env.warning` / `env.error` and `trigger.action.outText` may be wrapped in a later iteration if needed. They go to `dcs.log`, which `tail-log` already reads, so this is mostly a UX nicety, not a missing capability.

## Go CLI

Binary name: `dcs-sms` (`dcs-sms.exe` on Windows). Three subcommands.

### `dcs-sms exec`

```
dcs-sms exec [--file path.lua | --code "..."] [--timeout 5s] [--wait] [--json | --pretty]
```

**Behavior:**
- Reads code from `--file`, `--code`, or stdin (in that priority order).
- Checks `state/hook.json` freshness:
  - If `last_frame_at` is more than 2 s old or file is missing, exit code 3 with a clear diagnostic — *unless* `--wait` is set, in which case poll until ready or `--timeout` expires.
- Generates a UUID, writes `inbox/<uuid>.req.json` (atomic rename).
- Polls `outbox/<uuid>.res.json` every 25 ms until the response appears or `--timeout` elapses.
- Reads the response, prints JSON to stdout, deletes the response file.
- Exits with status reflecting the outcome.

**Exit codes:**
- `0` — `ok: true`, snippet ran cleanly.
- `1` — `ok: false`, snippet raised a Lua error.
- `2` — timeout: no response within `--timeout`.
- `3` — hook not ready (stale heartbeat, missing file, mission not loaded). Skipped if `--wait`.

**Output:**
- Default: compact JSON (machine-friendly, what the agent wants).
- `--pretty`: indented JSON for human reading.

### `dcs-sms tail-log`

```
dcs-sms tail-log [--since <duration|cursor>] [--grep <regex>] [-n <N>]
```

**Behavior:**
- Reads `dcs.log` directly from the host filesystem (does *not* go through the hook). Works even when no mission is loaded — useful for debugging hook startup itself.
- `--since 30s` — emit lines from the last 30 s.
- `--since cursor` — emit lines after the position recorded in `state/log-cursor`. Updates the cursor on success. This is how the agent does incremental log polling without a `--follow` mode.
- `--grep <regex>` — filter server-side.
- `-n N` — emit only the last N matching lines.
- One JSON object per line on stdout (so it pipes cleanly into `jq`).

No `--follow` in v1. The agent polls; that is sufficient. A `--follow` mode for human terminal use can be added later without protocol changes.

### `dcs-sms status`

```
dcs-sms status [--json]
```

Reads `state/hook.json`. Prints a brief summary (hook loaded? mission loaded? mission name? heartbeat age?). Exit code `0` if everything is healthy, non-zero with a category code otherwise. Useful as a precondition check before `exec`.

### `dcs-sms install-hook`

```
dcs-sms install-hook [--dcs-saved-games <path>]
```

Writes the embedded hook source into `<saved-games>/Scripts/Hooks/dcs-sms-hook.lua`. Auto-discovers the Saved Games path the same way `dcs_code_injector` does (registry / known locations), with a flag override for unusual setups.

### Path discovery

First run: read DCS install / Saved Games paths from registry or known locations, cache to `~/.config/dcs-sms/config.toml`. Subsequent runs read the cache. `dcs-sms config` (a thin subcommand) lets the user inspect or override.

## Lifecycle, errors, and timeouts

| Situation | Hook behavior | CLI sees |
|---|---|---|
| DCS not running | nothing | `status` reports stalled; `exec` exits code 3 immediately (or polls if `--wait`) |
| DCS at main menu | hook running, `mission_loaded=false`, fresh heartbeat | `status` reports mission not loaded; `exec` exits code 3 (or polls if `--wait`) |
| Mission loaded, normal | normal frame loop | `exec` round-trips in 1–2 frames |
| Mission paused | frames don't fire → no heartbeat | `exec` times out at `--timeout`; CLI exits code 2 with "DCS appears paused or hung" |
| Hook crashes mid-frame | each callback is `pcall`-wrapped; bad request logged + skipped, response written with `ok=false` | next request still works |
| Snippet hangs DCS | hook cannot preempt | CLI times out; user has to kill DCS. Documented. |

### Versioning

`state/hook.json.hook_version` is checked by the CLI on every `exec`. On mismatch, the CLI emits a warning but proceeds. If we ever need a breaking protocol change, this is the lever to refuse incompatible pairs cleanly.

## Repo layout

```
dcs-sms/
├── MISSION.md
├── README.md
├── tools/                              # everything host-side (Go)
│   ├── go.mod
│   ├── cmd/
│   │   └── dcs-sms/
│   │       └── main.go                 # CLI entry point
│   ├── internal/
│   │   ├── mailbox/                    # request/response file IO, atomic writes
│   │   ├── hookstatus/                 # state/hook.json reader, freshness checks
│   │   ├── logtail/                    # dcs.log reader with cursor
│   │   ├── dcspath/                    # DCS install / Saved Games discovery
│   │   └── proto/                      # request/response Go structs (single source of truth)
│   ├── lua/
│   │   ├── dcs-sms-hook.lua            # the hook, embedded into the Go binary via //go:embed
│   │   └── README.md                   # install instructions and manual smoke checklist
│   └── testdata/
│       ├── fixtures/
│       └── golden/
├── framework/                          # the in-DCS Lua framework (MOOSE-rework, future work)
│   └── (empty for now; out of scope for this design)
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-04-25-execution-bridge-design.md
```

Reasons for the shape:

- **One repo, two top-level halves.** `tools/` and `framework/` are different worlds (Go vs. Lua, host vs. in-DCS, GUI hook env vs. mission env), and both will evolve. Keeping them in one repo lets versioning stay coherent and lets the agent grep across both halves at once. Splitting into separate repos repeats a MOOSE pain point and is not justified.
- **Hook lives under `tools/lua/`, not `framework/`.** The hook runs in the GUI/hook environment (full Lua, no sandbox), while the framework runs in the mission environment (sandboxed). They are as different as Go and JavaScript despite sharing syntax. The hook is also intrinsically coupled to the Go CLI (embedded, versioned, shipped together), so it lives next to its owner.
- **No `pkg/`.** Everything is `internal/` until there is a real external Go consumer.
- **Hook is one file, intentionally.** No premature modularization. If it grows to need splitting, that is a real signal — and we revisit then.

## Testing strategy

Three layers, in order of importance:

- **L1 — Go unit tests, no DCS.** Mailbox round-trips, atomic write semantics, JSON marshal/unmarshal, log-tail cursor logic, status freshness checks, exit-code mapping. Target ~80 % of the Go code. Fast, runs in CI, no external deps.
- **L2 — Fake-hook integration tests.** A small Go test harness plays the role of the hook: watches the inbox, writes synthetic responses (success, error, timeout, malformed). Lets us drive the CLI end-to-end through every error path without launching DCS. This is where most timing bugs would surface.
- **L3 — Real DCS smoke tests.** A short manual checklist run before each release: load a mission, `exec` a simple snippet, confirm response, run `tail-log`, exercise the timeout case (`while true do end`), exercise the error case (`error('boom')`). Documented in `tools/lua/README.md`.

A Lua-side mock of `net.dostring_in` plus Busted is conceivable but not justified for one Lua file. Manual smoke covers it.

## Open implementation questions

These are deferred to the implementation plan, not to this design:

- Exact mechanism for atomic rename on Windows (`os.rename` semantics from LuaFileSystem vs. `MoveFileExW`).
- Polling strategy on the CLI side for very high-volume call patterns (likely won't matter for the agent use case, but worth instrumenting once we see real numbers).
- Whether `dcs-sms install-hook` should also offer to comment out the `sanitizeModule` lines in `MissionScripting.lua`, or just print instructions. The original injector requires the user to do this manually.
