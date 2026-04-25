# Framework v1 — Logger + Utils Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first sub-project of the in-DCS Lua framework: a root namespace, a logger module with auto-tagged per-module loggers, and a utils module that exercises cross-module logging — all verified end-to-end through the existing execution bridge.

**Architecture:** Three small Lua files under `framework/` plus one bridge-driven smoke test. `sms.lua` (root) creates the global namespace; `log.lua` attaches a logger module with `info`, `error`, and a `module()` factory that returns per-module-tagged loggers using `debug.getinfo` to derive the tag from the caller's file path; `utils.lua` is a real example module with `add_numbers` that uses a bound logger. Loading is bridge-only in v1 (`dcs-sms.exe exec --file`).

**Tech Stack:** Lua 5.1 (DCS mission environment), bash (smoke test), the existing `dcs-sms.exe` execution bridge.

**Spec:** `docs/superpowers/specs/2026-04-25-framework-log-design.md`

---

## File Structure

| File | Purpose |
|---|---|
| `framework/sms.lua` | Root: creates `sms = sms or {}` and `sms.version = "0.1.0"`. |
| `framework/log.lua` | Logger module: `sms.log.info`, `sms.log.error`, `sms.log.module(name?)`. |
| `framework/utils.lua` | Example module: `sms.utils.add_numbers(a, b)` using a bound logger. |
| `framework/test/smoke.sh` | Bridge-driven end-to-end smoke test. |

All four are new files. No existing files modified.

## Parallelism

Tasks 2A, 2B, and 2C write independent files in `framework/`. They can be implemented by parallel subagents safely — no shared edits, no shared state. Task 1 (smoke test) must come first; Task 3 (verification) must come last. Tasks 2A/2B/2C are the parallel batch.

---

## Task 1: Failing smoke test

**Files:**
- Create: `framework/test/smoke.sh`

- [ ] **Step 1: Write the smoke test**

Create `framework/test/smoke.sh`:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for the dcs-sms framework v1 (logger + utils).
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework/sms.lua"
"${DCSSMS}" exec --file sms.lua >/dev/null

echo "==> load framework/log.lua"
"${DCSSMS}" exec --file log.lua >/dev/null

echo "==> load framework/utils.lua"
"${DCSSMS}" exec --file utils.lua >/dev/null

echo "==> sms.utils.add_numbers(2, 3) should return 5"
result=$("${DCSSMS}" exec --code "return sms.utils.add_numbers(2, 3)")
echo "${result}"
echo "${result}" | grep -q '"return_value":5' \
  || { echo "FAIL: expected return_value:5, got: ${result}"; exit 1; }

echo "==> sms.log.info('hello from smoke test')"
"${DCSSMS}" exec --code "sms.log.info('hello from smoke test')" >/dev/null

echo "==> sms.log.error('boom from smoke test')"
"${DCSSMS}" exec --code "sms.log.error('boom from smoke test')" >/dev/null

echo "==> verify dcs.log captured tagged lines"
log_window=$("${DCSSMS}" tail-log --grep '\[sms' -n 200)

echo "${log_window}" | grep -q '\[sms.utils\] add_numbers(2, 3)' \
  || { echo "FAIL: missing [sms.utils] add_numbers line in dcs.log"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q '\[sms\] hello from smoke test' \
  || { echo "FAIL: missing [sms] hello line in dcs.log"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q '\[sms\] boom from smoke test' \
  || { echo "FAIL: missing [sms] boom line in dcs.log"; echo "${log_window}"; exit 1; }

echo "smoke ok"
```

- [ ] **Step 2: Make it executable and run it; expect failure**

Run:
```bash
chmod +x framework/test/smoke.sh
framework/test/smoke.sh
```

Expected: failure at the first `exec --file sms.lua` step (file does not exist) or earlier at `status` if DCS is not running. Either way, the test runs and fails — that's correct for TDD red.

If `status` fails because DCS isn't running, that is also a valid "red" — the test is wired up correctly, the framework files just don't exist yet. Note in the implementation log if this happens and proceed.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke.sh
git commit -m "test: add bridge-driven smoke test for framework v1"
```

---

## Task 2A: Root file `framework/sms.lua`

**Files:**
- Create: `framework/sms.lua`

- [ ] **Step 1: Write the file**

Create `framework/sms.lua` with exactly this content:

```lua
-- dcs-sms framework root.
-- Creates the single global namespace and records the version.
-- Idempotent: safe to load multiple times.
sms = sms or {}
sms.version = "0.1.0"
```

- [ ] **Step 2: Sanity-check the file**

Run:
```bash
"${REPO_ROOT}/tools/dcs-sms.exe" exec --file framework/sms.lua
```
(Where `${REPO_ROOT}` is `D:/git/dcs-sms` — adjust for your shell.)

Expected: response with `"ok":true`. If DCS isn't running, this step is skipped and verified in Task 3.

Then verify the global is set:
```bash
"${REPO_ROOT}/tools/dcs-sms.exe" exec --code "return sms.version"
```
Expected: `"return_value":"0.1.0"`.

- [ ] **Step 3: Commit**

```bash
git add framework/sms.lua
git commit -m "feat(framework): add sms.lua root namespace"
```

---

## Task 2B: Logger module `framework/log.lua`

**Files:**
- Create: `framework/log.lua`

- [ ] **Step 1: Write the file**

Create `framework/log.lua` with exactly this content:

```lua
-- dcs-sms logger module. Attaches sms.log with info/error functions and
-- a per-module logger factory.
--
-- Top-level sms.log.info / sms.log.error are untagged callers (prefix [sms]).
-- sms.log.module(name?) returns a tagged logger whose calls prefix every
-- line with [<tag>]. When `name` is omitted the tag is auto-derived from
-- the caller's file path:
--   debug.getinfo(2, "S").source  ->  "@.../framework/utils.lua"
--   strip leading "@", take basename, strip ".lua"           ->  "utils"
--   prepend "sms."                                            ->  "sms.utils"
-- When `name` is provided it is used verbatim (no automatic "sms." prefix).
-- If auto-derivation fails (caller is a chunk loaded via the bridge,
-- source is "[string \"...\"]") the tag falls back to "sms.unknown".

assert(sms, "framework/sms.lua must be loaded first")
sms.log = sms.log or {}

sms.log.info  = function(msg) env.info ("[sms] " .. tostring(msg)) end
sms.log.error = function(msg) env.error("[sms] " .. tostring(msg)) end

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

- [ ] **Step 2: Sanity-check**

If DCS is running (Task 2A's load succeeded), verify:

```bash
"${REPO_ROOT}/tools/dcs-sms.exe" exec --file framework/log.lua
```
Expected: `"ok":true`.

```bash
"${REPO_ROOT}/tools/dcs-sms.exe" exec --code "sms.log.info('direct call test')"
```
Expected: `"ok":true`. Then `dcs-sms.exe tail-log --grep '\[sms\]' -n 5` should show `[sms] direct call test`.

If DCS isn't running, defer to Task 3.

- [ ] **Step 3: Commit**

```bash
git add framework/log.lua
git commit -m "feat(framework): add logger module with per-module tag factory"
```

---

## Task 2C: Utils module `framework/utils.lua`

**Files:**
- Create: `framework/utils.lua`

- [ ] **Step 1: Write the file**

Create `framework/utils.lua` with exactly this content:

```lua
-- dcs-sms utils module. Real module that doubles as the smoke-test
-- exerciser for cross-module logging in v1.

assert(sms, "framework/sms.lua must be loaded first")
local log = sms.log.module()       -- auto-tagged as "sms.utils"
sms.utils = sms.utils or {}

sms.utils.add_numbers = function(a, b)
  log.info("add_numbers(" .. tostring(a) .. ", " .. tostring(b) .. ")")
  return a + b
end
```

- [ ] **Step 2: Sanity-check**

If DCS is running:
```bash
"${REPO_ROOT}/tools/dcs-sms.exe" exec --file framework/utils.lua
"${REPO_ROOT}/tools/dcs-sms.exe" exec --code "return sms.utils.add_numbers(2, 3)"
```
Expected: second response has `"return_value":5`.

```bash
"${REPO_ROOT}/tools/dcs-sms.exe" tail-log --grep '\[sms.utils\]' -n 5
```
Expected: a line containing `[sms.utils] add_numbers(2, 3)`.

If DCS isn't running, defer to Task 3.

- [ ] **Step 3: Commit**

```bash
git add framework/utils.lua
git commit -m "feat(framework): add utils module with add_numbers example"
```

---

## Task 3: Run the smoke test (TDD green)

**Files:** none modified — verification only.

- [ ] **Step 1: Confirm DCS is running with mission loaded**

Run:
```bash
tools/dcs-sms.exe status
```
Expected: `mission loaded: true` and `fresh: true`. If not, the user must load a mission in DCS before proceeding. Pause and report rather than guessing.

- [ ] **Step 2: Run the smoke test**

Run:
```bash
framework/test/smoke.sh
```
Expected: terminates with `smoke ok` and exit code 0. Every intermediate `==> ...` line should appear with no `FAIL:` lines.

- [ ] **Step 3: If smoke fails, diagnose and fix**

If a step fails:

- **`exec --file` returns ok=false:** the relevant Lua file has a syntax or runtime error. Re-read the failing file against Task 2A/2B/2C and fix.
- **`return_value:5` missing:** the response shape may have changed, or `add_numbers` returned something else. Check by running `exec --code "return sms.utils.add_numbers(2, 3)" --pretty` and inspecting.
- **Missing `[sms.utils] add_numbers(2, 3)` in `dcs.log`:** the auto-tag derivation may not be matching `utils.lua`. Check `debug.getinfo(2, "S").source` from a fresh exec to see what string the runtime gives back; adjust the regex in `framework/log.lua` if needed (still `([^/\\]+)%.lua$` should be correct on Windows-style paths from DCS).
- **Missing `[sms]` lines:** check that `sms.log.info` / `sms.log.error` actually call `env.info` / `env.error` and not something else.

Fix the offending file, rerun the smoke test until green. Each fix is its own commit (`fix(framework): ...`).

- [ ] **Step 4: Final verification — re-run smoke from a cold state**

To prove idempotency, rerun the full smoke:
```bash
framework/test/smoke.sh
framework/test/smoke.sh
```
Both runs should succeed. Globals carry over between bridge calls; the `or {}` idempotent assignments make a re-load harmless.

- [ ] **Step 5: No commit required if green on first try**

If Task 3 only verifies and changes nothing, no commit. If diagnosis required edits to Task 2A/2B/2C files, those were committed in Step 3 of this task.

---

## Self-Review Checklist

Before declaring done:

- [ ] All four files exist: `framework/sms.lua`, `framework/log.lua`, `framework/utils.lua`, `framework/test/smoke.sh`.
- [ ] `framework/test/smoke.sh` is executable and ends with `smoke ok` on a fresh run.
- [ ] `git status` is clean. All work committed.
- [ ] `git log` shows the smoke-test commit, the three feat commits, and any fix commits, in a clear order.
- [ ] No edits made to anything under `tools/` (the bridge stays unchanged).
- [ ] The TODO comment about future log levels is present in `framework/log.lua` so the next iteration's intent isn't lost.

## Out of scope (do NOT do)

- Hook auto-injection of the framework on `onMissionLoadEnd` — tracked in #2.
- .miz bundling docs — falls out of #2.
- Versioning policy between mechanism C and A — tracked in #1.
- Lua-side Busted unit tests — explicitly skipped in v1.
- Adding `debug` or `warn` levels — TODO comment only.
- Touching `tools/` for any reason — the bridge is fixed and works.
