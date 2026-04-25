# dcs-sms Framework v1 — Logger + Utils

**Date:** 2026-04-25
**Status:** Approved (brainstorm phase)
**Scope:** First sub-project of the in-DCS framework. Establishes file layout, namespace, module pattern, and a logger module that proves the structure end-to-end. Verified live in DCS via the execution bridge.

## Goal

Prove the framework's code structure with the smallest possible surface area:

- A `framework/` directory in the repo, holding the in-DCS Lua code.
- A single root namespace, `sms`, that future modules attach to.
- A module pattern that scales: a new module is one file, attaches under `sms.<name>`, and uses a per-module logger.
- A logger that's good enough to be useful (`info` and `error` end up in `dcs.log`, tagged by calling module).
- An end-to-end smoke test that loads the framework through the bridge and verifies output in `dcs.log`.

The deliverable is the framework code, the smoke test, and updated docs. Everything else — hook auto-injection, .miz bundling, additional log levels — is explicitly out of scope and tracked as separate issues.

## Non-goals

- **Hook auto-injection (load mechanism C).** Tracked in #2. v1 is bridge-loaded only.
- **.miz bundling documentation (load mechanism A).** Falls out of C; documented when C lands.
- **Versioning strategy.** Tracked in #1. v1 has one user and one version.
- **Additional log levels (`debug`, `warn`) and runtime filtering.** A `TODO` comment in `log.lua` records the intended end state.
- **Custom call-site tags** (`sms.log.info("mytag", "msg")`). Not needed; the per-module logger covers it. Can be added later without breaking changes.
- **Lua-side unit tests with Busted.** Cost vs. value is not there for ~50 lines of Lua. Smoke testing through the bridge is sufficient.

## Architecture

Three Lua files under `framework/`. Each is independently loadable but they have a fixed dependency order: `sms.lua` → `log.lua` → everything else.

```
dcs-sms/
├── framework/
│   ├── sms.lua       # root: creates global `sms`, sets version
│   ├── log.lua       # logger module
│   ├── utils.lua     # example/test module exercising cross-module logging
│   └── test/
│       └── smoke.sh  # bridge-driven end-to-end smoke test
└── docs/superpowers/specs/
    └── 2026-04-25-framework-log-design.md
```

### Why this shape

- **Flat `framework/` directory.** No `framework/src/` or per-module subdirectories. With three files, structure is overhead. We revisit when there are enough files that the flat layout actually hurts.
- **Root file separate from logger.** Discussed during brainstorming: a self-bootstrapping single-file approach was on the table, but a dedicated root file scales better and is consistent with how future modules will look. Cost is one extra file; benefit is "every module starts with `assert(sms, ...)`" as a uniform pattern.
- **Smoke test next to the code it tests.** `framework/test/` is for tests *of the framework itself*. Tools-side Go tests stay under `tools/`.

### Module pattern

Every module file follows the same shape:

```lua
assert(sms, "framework/sms.lua must be loaded first")
local log = sms.log.module()         -- omit in log.lua itself
sms.<name> = sms.<name> or {}

sms.<name>.<func> = function(...) ... end
```

Three rules this encodes:

1. The root must be loaded first. Modules `assert` rather than create-on-the-fly so loading a module out of order is a loud failure, not silent corruption.
2. Each module binds its own logger once at load time (not on every call). The tag is auto-derived from the file name.
3. Modules attach to `sms` via `sms.<name> = sms.<name> or {}` — idempotent, so reloading a module replaces its functions without nuking sibling modules.

## File contents

### `framework/sms.lua`

```lua
-- dcs-sms framework root.
-- Creates the single global namespace and records the version.
sms = sms or {}
sms.version = "0.1.0"
```

That's it. The root file's only job is to make the global table exist and carry a version number. No utility functions live here in v1; if shared init logic emerges later (e.g., a once-per-load setup hook), it goes here.

### `framework/log.lua`

```lua
assert(sms, "framework/sms.lua must be loaded first")
sms.log = sms.log or {}

-- Top-level functions: untagged, callable directly. Used as the default
-- when a caller has not bound a module logger.
sms.log.info  = function(msg) env.info ("[sms] " .. tostring(msg)) end
sms.log.error = function(msg) env.error("[sms] " .. tostring(msg)) end

-- Per-module logger factory. Returns a small table with `info` and `error`
-- functions that prefix every line with the module's tag.
--
-- If `name` is omitted, the tag is derived from the caller's file path:
--   debug.getinfo(2, "S").source  ->  "@.../framework/utils.lua"
--   strip leading "@", take basename, strip ".lua"           ->  "utils"
--   prepend "sms."                                            ->  "sms.utils"
--
-- If `name` is provided explicitly, it is used as-is — no automatic
-- "sms." prefix. The caller is in full control. Use this from bridge
-- chunks or to override the file-derived tag.
--
-- If auto-derivation fails (caller is a chunk loaded via the bridge,
-- source is "[string \"...\"]") the tag falls back to "sms.unknown".
sms.log.module = function(name)
  local tag = name
  if not tag then
    local info = debug.getinfo(2, "S")
    local src = info and info.source or ""
    local base = src:match("([^/\\]+)%.lua$")
    tag = base and ("sms." .. base) or "sms.unknown"
  end
  return {
    info  = function(msg) env.info ("[" .. tag .. "] " .. tostring(msg)) end,
    error = function(msg) env.error("[" .. tag .. "] " .. tostring(msg)) end,
  }
end

-- TODO future: debug/warn levels + sms.log.set_level("info") for runtime
-- filtering. End-state is four levels (debug/info/warn/error) with a
-- threshold that mutes anything below it. Not in v1.
```

The implementation is small and there are deliberately no helpers, no formatting beyond `tostring`, no string interpolation. Keeping this file boring is the point — it's foundational.

### `framework/utils.lua`

```lua
assert(sms, "framework/sms.lua must be loaded first")
local log = sms.log.module()       -- auto-tagged as "sms.utils"
sms.utils = sms.utils or {}

sms.utils.add_numbers = function(a, b)
  log.info("add_numbers(" .. tostring(a) .. ", " .. tostring(b) .. ")")
  return a + b
end
```

`add_numbers` is the simplest function that exercises everything we care about: cross-module calls work, the logger's auto-tag picks up `sms.utils` from the file path, and the return value round-trips through the bridge as JSON.

`utils` is a real module, not throwaway test scaffolding. As more genuinely-shared helpers appear, they go here. If `utils.lua` ever becomes a grab bag of unrelated things, that is the signal to split it — but for v1, one example function is fine.

## Output format

Every log line in `dcs.log` looks like:

```
<DCS-prefix> SCRIPTING (Main): [<tag>] <message>
```

Where:

- `<DCS-prefix>` is whatever DCS prepends — timestamp, level, subsystem. We don't add or change anything there; `env.info`/`env.error` already produce it.
- `<tag>` is `sms` for direct calls to `sms.log.info` / `sms.log.error`, or the module-bound name (e.g., `sms.utils`) for calls through a logger created by `sms.log.module()`.
- `<message>` is `tostring(msg)`. We don't try to format tables or multi-arg messages in v1; if a caller wants a formatted string, they call `string.format` themselves.

Errors go through `env.error`, so DCS shows them at `ERROR` level. This matters because `dcs-sms.exe tail-log --grep ERROR` will pick up framework errors without further filtering.

## Loading (v1)

Bridge-driven only — load mechanism D from the brainstorm. Three sequential `exec --file` calls land all three files into the mission environment in order:

```bash
./dcs-sms.exe exec --file framework/sms.lua
./dcs-sms.exe exec --file framework/log.lua
./dcs-sms.exe exec --file framework/utils.lua
```

After that, any subsequent `exec` call can use `sms.*` directly. Globals persist across `net.dostring_in` calls (documented in the bridge spec), so reloading is just running these three again — idempotent because every file starts with `<global> = <global> or {}`.

Mechanisms C (hook auto-injection, #2) and A (.miz bundling) are not implemented in v1 and are not required to validate the design. They build on top of this same file structure unchanged.

## Testing

### Smoke test

`framework/test/smoke.sh` is a small shell script that drives the bridge and asserts on the responses. Pseudocode:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DCSSMS=../tools/dcs-sms.exe

# 1. Hook is alive and a mission is loaded.
$DCSSMS status

# 2. Load framework files in order. Each must return ok=true.
$DCSSMS exec --file sms.lua
$DCSSMS exec --file log.lua
$DCSSMS exec --file utils.lua

# 3. Call into utils. Verify return value round-trips.
result=$($DCSSMS exec --code "return sms.utils.add_numbers(2, 3)")
echo "$result" | grep -q '"return_value":5'

# 4. Direct top-level log call.
$DCSSMS exec --code "sms.log.info('hello from smoke test')"
$DCSSMS exec --code "sms.log.error('boom from smoke test')"

# 5. Verify dcs.log saw the right tagged lines.
$DCSSMS tail-log --grep '\[sms' -n 50 | grep -q '\[sms.utils\] add_numbers(2, 3)'
$DCSSMS tail-log --grep '\[sms\]'  -n 50 | grep -q '\[sms\] hello from smoke test'
$DCSSMS tail-log --grep '\[sms\]'  -n 50 | grep -q '\[sms\] boom from smoke test'

echo "smoke ok"
```

The exact form (shell vs. Go test program vs. checklist in markdown) is an implementation-plan decision. The substance — load all three, exercise cross-module logging, exercise direct logging, grep `dcs.log` for the expected tags — is the contract.

### What's not tested

- Auto-tag fallback to `sms.unknown` for bridge chunks. Easy to verify manually if we ever want; not part of the smoke run.
- Behavior when `framework/sms.lua` is not loaded first. The `assert` will trip; that's the test.
- Concurrent calls. The bridge already serializes execs; nothing to check here.

## Lifecycle, errors, edge cases

| Situation | Behavior |
|---|---|
| `log.lua` loaded before `sms.lua` | `assert` fails loudly; bridge response has `ok=false` and a clear error. Same for any non-root module loaded before the root. |
| `sms.log.module()` called from a bridge chunk (not a real file) | Tag falls back to `sms.unknown`. Logger still works. |
| `sms.log.module("explicit")` called explicitly | Tag is `explicit` (no automatic `sms.` prefix when name is given — caller is in control). |
| Same module file reloaded | `sms.<name> = sms.<name> or {}` keeps the table identity stable; functions get replaced. Existing references to function values in other modules become stale (Lua semantics) — acceptable for v1's reload-via-bridge dev flow. |
| Caller passes non-string (table, nil) | `tostring(msg)` handles it. Tables print as `table: 0x...` — fine for v1; better formatting can come with the levels rework. |

## Open implementation questions

Deferred to the implementation plan:

- Exact form of `framework/test/smoke.sh` — bash, Go test, or a markdown checklist. Probably bash for simplicity, but it has to run on the user's Windows + mingw bash setup.
- Whether `sms.log.module()` should cache the derived tag per file path. Not needed for correctness; might matter for performance once we're logging at 60 Hz. Unlikely to bite v1.
- Whether to expose `sms.log.set_level` as a no-op stub now (so calls don't break when levels land later) or wait until real filtering exists. Lean: wait.

## Related issues

- **#1** — Framework versioning trade-off between mechanisms C and A. Becomes load-bearing once C is implemented.
- **#2** — Hook auto-injection (mechanism C). Builds on this spec's file structure with no changes required.
