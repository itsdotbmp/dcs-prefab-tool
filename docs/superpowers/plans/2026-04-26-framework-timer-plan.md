# `sms.timer` v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `sms.timer` module — the framework's first behavioral primitive — wrapping DCS's native `timer` API in a small, idiomatic surface for one-shot and repeating callbacks, verified end-to-end through the bridge with host-side sleeps.

**Architecture:** Single Lua file (`framework/timer.lua`) with a module-functions layer plus a handle metatable. Handles are created by `after`/`every` and have `:stop()`, `:is_active()`, `:get_remaining()` methods (also callable as `sms.timer.<method>(handle)`). User-supplied callbacks are wrapped in `pcall` so user errors never break the framework. A bash smoke test (`framework/test/smoke_timer.sh`) drives the bridge with sleeps to let DCS sim-time advance and verify timers fire as expected.

**Tech Stack:** Lua 5.1 (DCS mission environment), bash (mingw on Windows), the existing `dcs-sms.exe` execution bridge, DCS's native `timer.scheduleFunction` / `timer.removeFunction` / `timer.getTime`.

**Spec:** `docs/superpowers/specs/2026-04-26-framework-timer-design.md`

---

## File Structure

| File | Purpose |
|---|---|
| `framework/timer.lua` | The `sms.timer` module + handle metatable. New file. |
| `framework/test/smoke_timer.sh` | Bridge-driven smoke test with host-side sleeps. New file. |

Existing files (`framework/sms.lua`, `framework/log.lua`, `framework/utils.lua`, `framework/group.lua`, `framework/test/smoke.sh`, `framework/test/smoke_group.sh`) are unchanged.

## Parallelism

Sequential. Three tasks: failing smoke test → single-file implementation → green-light verification.

---

## Task 1: Failing smoke test (TDD red)

**Files:**
- Create: `framework/test/smoke_timer.sh`

- [ ] **Step 1: Write the smoke test**

Create `framework/test/smoke_timer.sh` with EXACTLY this content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.timer v1.
# Drives the bridge with host-side sleeps to let sim time advance and
# verify timer callbacks fire as expected.
# Requires DCS running, mission loaded, and unpaused (sim must tick).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

# Helpers: assert that a bridge exec returned a true / specific number.
# expect_true LABEL CODE                  -- expects "return_value":true
# expect_eq   LABEL CODE EXPECTED_NUMBER  -- expects "return_value":N, (with comma)
expect_true() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_eq() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":${expected}," \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
}

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file timer.lua >/dev/null

echo "==> bad-arg validation"
expect_true "after: negative seconds returns nil" 'return sms.timer.after(-1, function() end) == nil'
expect_true "after: non-function fn returns nil" 'return sms.timer.after(1, "not a function") == nil'
expect_true "every: zero seconds returns nil" 'return sms.timer.every(0, function() end) == nil'
expect_true "every: negative max returns nil" 'return sms.timer.every(1, function() end, -3) == nil'

echo "==> after fires once after delay"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.after(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)
' >/dev/null
expect_true "after: handle is active immediately" 'return _G._smoke.h:is_active()'
sleep 2
expect_eq "after: fired count" 'return _G._smoke.fired' 1
expect_true "after: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> every fires repeatedly until stopped"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)
' >/dev/null
sleep 4
expect_true "every: stop returns true when active" 'return _G._smoke.h:stop()'
expect_true "every: fired at least 3 times" 'return _G._smoke.fired >= 3'
expect_true "every: stop returns false on second call" 'return _G._smoke.h:stop() == false'
expect_true "every: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> every with max stops after N fires"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function() _G._smoke.fired = _G._smoke.fired + 1 end, 3)
' >/dev/null
sleep 5
expect_eq "every with max: fired exactly 3 times" 'return _G._smoke.fired' 3
expect_true "every with max: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> every self-cancels via fn returning false"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function()
    _G._smoke.fired = _G._smoke.fired + 1
    if _G._smoke.fired >= 2 then return false end
  end)
' >/dev/null
sleep 3
expect_eq "every self-cancel: fired exactly 2 times" 'return _G._smoke.fired' 2
expect_true "every self-cancel: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> get_remaining returns sensible values"
"${DCSSMS}" exec --code '
  _G._smoke = {h = sms.timer.after(5, function() end)}
' >/dev/null
expect_true "get_remaining initial (>4 and <=5)" '
  local r = _G._smoke.h:get_remaining()
  return type(r) == "number" and r > 4 and r <= 5.05
'
sleep 2
expect_true "get_remaining after sleep (>2 and <4)" '
  local r = _G._smoke.h:get_remaining()
  return type(r) == "number" and r > 2 and r < 4
'
"${DCSSMS}" exec --code '_G._smoke.h:stop()' >/dev/null

echo "==> user errors in fn are caught"
"${DCSSMS}" exec --code '
  _G._smoke = {h = sms.timer.every(1, function() error("boom from smoke test") end, 2)}
' >/dev/null
sleep 3
expect_true "errors caught: handle ran to max iterations" 'return _G._smoke.h:is_active() == false'

echo "==> verify [sms.timer] log lines for bad args and user errors"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.timer\]' -n 200)
echo "${log_window}" | grep -q "after: seconds must be a non-negative" \
  || { echo "FAIL: missing log line for negative seconds"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "boom from smoke test" \
  || { echo "FAIL: missing log line for user error"; echo "${log_window}"; exit 1; }

echo "smoke ok"
```

- [ ] **Step 2: Make it executable and run it; expect failure**

Run:
```bash
chmod +x framework/test/smoke_timer.sh
framework/test/smoke_timer.sh
```

Expected: failure at the `==> load framework files` step on `exec --file timer.lua` because `framework/timer.lua` does not exist yet — that's the correct TDD red. The earlier steps (status, sms.lua, log.lua) should succeed.

If failure happens at `==> hook status` because DCS isn't running or has a stale heartbeat, that's also valid red — note in the report and proceed; Task 3 will run the test for real.

If failure occurs at any earlier step (bash syntax error, dcs-sms.exe not found), STOP and report — that's a real problem.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_timer.sh
git commit -m "test: add bridge-driven smoke test for sms.timer v1"
```

---

## Task 2: Implement `framework/timer.lua`

**Files:**
- Create: `framework/timer.lua`

- [ ] **Step 1: Write the file**

Create `framework/timer.lua` with EXACTLY this content:

```lua
-- dcs-sms framework: timer module (sms.timer).
--
-- First behavioral primitive in the framework. Wraps DCS's native
-- timer.scheduleFunction / timer.removeFunction / timer.getTime in
-- an idiomatic surface for "run this in N seconds" and "run this every
-- N seconds" patterns.
--
-- API:
--   sms.timer.after(seconds, fn)              -> handle | nil + log
--   sms.timer.every(seconds, fn, max?)        -> handle | nil + log
--   h:stop()                                  -> bool
--   h:is_active()                             -> bool (silent probe)
--   h:get_remaining()                         -> number | nil + log
--
-- For repeating timers, fn returning false self-cancels. The optional
-- max arg on every() also caps the total iterations. User errors in fn
-- are caught via pcall and logged — bad user code never breaks the
-- framework.
--
-- Sim-time-based via timer.getTime(); pauses with DCS.
--
-- See docs/superpowers/specs/2026-04-26-framework-timer-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
local log = sms.log.module("sms.timer")
sms.timer = sms.timer or {}

-- Handle metatable. Identity-checked so callers can't slip arbitrary
-- tables into module functions and get unexpected behavior.
local _handle_mt = {__index = sms.timer}

-- Returns true if h is a real timer handle (created by after/every).
local function _is_handle(h)
  return type(h) == "table" and getmetatable(h) == _handle_mt
end

sms.timer.after = function(seconds, fn)
  if type(seconds) ~= "number" or seconds < 0 then
    log.error("after: seconds must be a non-negative number, got " .. tostring(seconds))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("after: fn must be a function, got " .. type(fn))
    return nil
  end

  local now = timer.getTime()
  local handle = setmetatable({
    kind = "after",
    active = true,
    next_fire_time = now + seconds,
  }, _handle_mt)

  handle.id = timer.scheduleFunction(function(_, t)
    handle.active = false
    handle.next_fire_time = nil
    local ok, err = pcall(fn)
    if not ok then
      log.error("after: user fn raised: " .. tostring(err))
    end
    return nil
  end, nil, handle.next_fire_time)

  return handle
end

sms.timer.every = function(seconds, fn, max)
  if type(seconds) ~= "number" or seconds <= 0 then
    log.error("every: seconds must be a positive number, got " .. tostring(seconds))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("every: fn must be a function, got " .. type(fn))
    return nil
  end
  if max ~= nil and (type(max) ~= "number" or max <= 0) then
    log.error("every: max must be a positive number or nil, got " .. tostring(max))
    return nil
  end

  local now = timer.getTime()
  local handle = setmetatable({
    kind = "every",
    active = true,
    interval = seconds,
    iterations = 0,
    max = max,
    next_fire_time = now + seconds,
  }, _handle_mt)

  handle.id = timer.scheduleFunction(function(_, t)
    handle.iterations = handle.iterations + 1
    local ok, result = pcall(fn)
    if not ok then
      log.error("every: user fn raised: " .. tostring(result))
      result = nil
    end
    if result == false then
      handle.active = false
      handle.next_fire_time = nil
      return nil
    end
    if handle.max and handle.iterations >= handle.max then
      handle.active = false
      handle.next_fire_time = nil
      return nil
    end
    handle.next_fire_time = t + handle.interval
    return handle.next_fire_time
  end, nil, handle.next_fire_time)

  return handle
end

sms.timer.stop = function(h)
  if not _is_handle(h) then
    log.error("stop: argument must be a timer handle")
    return false
  end
  if not h.active then return false end
  h.active = false
  h.next_fire_time = nil
  pcall(timer.removeFunction, h.id)
  return true
end

sms.timer.is_active = function(h)
  if not _is_handle(h) then return false end
  return h.active == true
end

sms.timer.get_remaining = function(h)
  if not _is_handle(h) then
    log.error("get_remaining: argument must be a timer handle")
    return nil
  end
  if not h.active or not h.next_fire_time then
    log.error("get_remaining: timer is not active")
    return nil
  end
  return h.next_fire_time - timer.getTime()
end
```

- [ ] **Step 2: Sanity-check the file loads via the bridge**

If DCS is running with a fresh heartbeat:
```bash
tools/dcs-sms.exe status
tools/dcs-sms.exe exec --file framework/sms.lua
tools/dcs-sms.exe exec --file framework/log.lua
tools/dcs-sms.exe exec --file framework/timer.lua
tools/dcs-sms.exe exec --code "return type(sms.timer)"
tools/dcs-sms.exe exec --code "return type(sms.timer.after)"
```

Expected: each `exec --file` returns `"ok":true`. The two type queries return `"return_value":"table"` and `"return_value":"function"`.

If `exec --file framework/timer.lua` returns `ok:false`, read the response, fix the syntax in `framework/timer.lua`, and rerun until it loads cleanly.

If DCS is not running or heartbeat is stale, skip the sanity check. Task 3 will run the full smoke test.

- [ ] **Step 3: Commit**

```bash
git add framework/timer.lua
git commit -m "feat(framework): add sms.timer module with after/every/stop"
```

---

## Task 3: Run smoke test, verify green

**Files:** none modified — verification only. May modify `framework/timer.lua` or `framework/test/smoke_timer.sh` if green-light reveals issues.

- [ ] **Step 1: Confirm DCS is running, mission loaded, and unpaused**

Run:
```bash
tools/dcs-sms.exe status
```
Expected: `mission loaded: true` and `fresh: true`.

If `fresh: false`, ask the user to bring DCS to the foreground / unpause the mission, then retry.
If `mission loaded: false`, ask the user to load a mission, then retry.

The smoke test relies on sim time advancing during host-side `sleep` calls. **The mission MUST be unpaused for the duration of the test (~25 seconds).**

- [ ] **Step 2: Run the smoke test**

Run:
```bash
framework/test/smoke_timer.sh
```
Expected: terminates with `smoke ok` and exit 0. Every `==>` step prints with no `FAIL:` line.

Total runtime: approximately 19 seconds of sleeps plus exec overhead — budget ~25-30 seconds wall time. Don't alt-tab DCS during the run.

- [ ] **Step 3: If green, run twice for idempotency**

Run:
```bash
framework/test/smoke_timer.sh
framework/test/smoke_timer.sh
```
Both runs should print `smoke ok` and exit 0. Each run sets a fresh `_G._smoke = {...}` in the mission environment, so prior state doesn't carry over.

If both runs are green, skip to Step 5.

- [ ] **Step 4: If smoke fails, diagnose by category**

Most likely failure modes and how to address each:

**A. Timing-sensitive assertion fails (`fired == N` is off).**
- The most common cause: DCS time scaling is not 1x, or the sim ticked while paused (e.g., user has time-acceleration mod).
- Diagnostic: check raw sim-time advance with `tools/dcs-sms.exe exec --code "return timer.getTime()"` before and after a 2-second host sleep; compute the delta. Should be ~2.0. If it's drastically different, sim is scaling.
- Fix: if scaling is the cause, the smoke test isn't really wrong — adjust assertions OR ask the user to set DCS to 1x time. Edit assertions in `framework/test/smoke_timer.sh` only as a last resort, and document.

**B. `exec --file timer.lua` returns ok:false.**
- The Lua file has a syntax or runtime error. Read the response; the `error` field will have line info. Fix in `framework/timer.lua`. Commit fix as `fix(framework): ...`.

**C. `[sms.timer]` log line missing for the user-error case.**
- Check that `framework/timer.lua`'s `every` wrapper actually calls `log.error("every: user fn raised: ...")` when `pcall` returns false.
- `tools/dcs-sms.exe tail-log -n 50` (no grep) shows what *did* get logged. The error message format may differ slightly from the grep pattern.

**D. `get_remaining` returns out-of-bracket values.**
- If the initial check is failing because `r` is e.g. `4.95` and the bracket is `r > 4` — that should pass. If `r` is `5.1`, the bracket allows up to `5.05` so that fails. Adjust the upper bound to `5.1` if needed (DCS frame timing can shift the actual schedule slightly past the requested time).
- If the post-sleep check (`> 2 and < 4`) fails because `r` is `1.95`, sim advanced more than expected — adjust to `> 1.5`.

**E. `every` fires more or fewer times than expected.**
- Check the wrapper logic in `every` — particularly the `handle.iterations >= handle.max` comparison. Fence-post errors here cause off-by-one.
- Use `tools/dcs-sms.exe exec --code "return _G._smoke.fired"` mid-test to inspect the actual count.

After any fix, return to Step 2 and rerun.

- [ ] **Step 5: Final state check**

Run:
```bash
git status
git log --oneline -5
```

Expected: working tree clean; recent commits show the test commit, the feat commit, and any fix commits. Smoke test runs green twice in a row.

No commit needed in this task unless Step 4 required fixes.

---

## Self-Review Checklist

Before declaring done:

- [ ] `framework/timer.lua` exists and loads cleanly via `exec --file` (returns `ok:true`).
- [ ] `framework/test/smoke_timer.sh` exists and ends with `smoke ok` on a fresh run.
- [ ] All other framework files are unchanged (`sms.lua`, `log.lua`, `utils.lua`, `group.lua`).
- [ ] All other smoke tests are unchanged (`smoke.sh`, `smoke_group.sh`).
- [ ] All 5 API operations work: `after`, `every`, `stop`, `is_active`, `get_remaining`.
- [ ] User error in `fn` is caught and logged, doesn't break the timer (every) or break the framework (after).
- [ ] `every` self-cancels on `fn` returning false.
- [ ] `every` with `max` stops after exactly `max` iterations.
- [ ] `stop()` is idempotent: returns true once, false thereafter.
- [ ] `is_active()` is silent on non-handles (no log).
- [ ] No edits to `tools/`.
- [ ] All work committed on branch `feat/sms-timer`.
- [ ] Smoke test runs green idempotently.

## Out of scope (do NOT do)

- `sms.unit`, `sms.zone`, `sms.events`, `sms.spawn` — separate future iterations.
- Pause/resume of timers.
- Absolute-time scheduling (`run_at`).
- Same-frame defer (`next_frame`) — `after(0, fn)` covers it.
- Naming/labeling timers.
- `sms.timer.list()` debug aid.
- A separate `every_until` or `repeat_n` function — `every` covers both via fn-returns-false and `max`.
- Touching anything outside `framework/timer.lua` and `framework/test/smoke_timer.sh`.

## Self-review notes from plan author

Spec coverage:
- **5 operations** (`after`, `every`, `stop`, `is_active`, `get_remaining`) → Task 2's code block contains all five; smoke test exercises each.
- **`every` with `max` arg** → Task 2's `every` flow explicitly checks `handle.iterations >= handle.max`; smoke test verifies "fired exactly 3 times" with `max=3`.
- **`fn` returning false self-cancels** → Task 2's `every` wrapper handles `result == false`; smoke test covers it.
- **User error catching via `pcall`** → Both `after` and `every` wrap user `fn` in `pcall`; smoke test asserts the timer continues to run (every) and that the error is logged.
- **`stop` idempotency** → Task 2 returns `false` if already inactive; smoke test calls stop twice and asserts true-then-false.
- **Bad-arg validation** → Task 2 validates `seconds`, `fn`, `max` types; smoke test exercises all four bad-arg cases.
- **Sim-time-based** → Uses `timer.getTime()` throughout, not wall clock.
- **Failure model (log + nil/false, never throw)** → Every error path in Task 2's code goes through `log.error(...) + return nil/false`. No `error()` calls.
- **Module logger explicit tag `sms.timer`** → Task 2 uses `sms.log.module("sms.timer")`.
- **Handle identity check via metatable** → Task 2's `_is_handle` checks `getmetatable(h) == _handle_mt`; module functions use it.

Placeholder scan: zero placeholders. All code blocks complete.

Type consistency: `seconds` is always a number; `fn` is always a function; `max` is number or nil; handle has consistent fields (`kind`, `active`, `next_fire_time`, `id`, plus `interval`/`iterations`/`max` for every).
