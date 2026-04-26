# dcs-sms Framework — `sms.timer` v1

**Date:** 2026-04-26
**Status:** Approved (brainstorm phase)
**Scope:** Third module of the dcs-sms framework. First behavioral primitive (no entity wrapping). Wraps DCS's native `timer` API in a small, idiomatic surface for "run this in N seconds" and "run this every N seconds" patterns.

## Goal

Build a small timer module that covers the timing patterns DCS mission code reaches for daily:

- "Run this in 30 seconds." — one-shot delayed execution.
- "Run this every 4 seconds." — repeating, optionally bounded.
- "Stop running this." — cancellation.
- "Is this still running?" — probe.
- "How long until it fires?" — remaining time, mostly for UI/debug.

Built directly on DCS's `timer.scheduleFunction` / `timer.removeFunction` / `timer.getTime`. Operates on simulation time, not wall-clock — matching how missions actually work.

## User value

After this iteration:

```lua
-- One-shot
sms.timer.after(30, function()
  trigger.action.outText("30 seconds in", 10)
end)

-- Repeating, bounded
sms.timer.every(5, function()
  sms.log.info("patrol check")
end, 12)

-- Self-canceling repeat
local checks = 0
sms.timer.every(2, function()
  checks = checks + 1
  if checks >= 5 then return false end  -- stop
end)

-- Imperative cancel
local h = sms.timer.every(10, do_thing)
-- ... later ...
h:stop()

-- Probes
if h:is_active() then sms.log.info("still going") end
local s = h:get_remaining()
```

This is the foundation for almost every reactive or time-based behavior in subsequent modules (events, spawn waves, mission-flow control).

## Scope

### In scope (v1)

- One file: `framework/timer.lua`.
- One smoke test: `framework/test/smoke_timer.sh`.
- API surface (5 operations):
  - `sms.timer.after(seconds, fn)` — one-shot. Returns a handle, or `nil` + log on bad args.
  - `sms.timer.every(seconds, fn, max?)` — repeating. Returns a handle, or `nil` + log on bad args. If `fn` returns `false`, the timer self-cancels. If `max` is supplied, the timer stops after `max` iterations.
  - `h:stop()` — cancel. Returns `true` if was active and is now stopped; `false` if already stopped/expired. Idempotent.
  - `h:is_active()` — probe. Returns `bool` silently.
  - `h:get_remaining()` — returns seconds (number) until next fire, or `nil` + log if not active.
- Module functions accept either a handle (preferred) or — for safety — log + nil if given non-handle. There is **no string-name lookup** for timers; they're created by `after`/`every`, not retrieved by name.
- Handles are `setmetatable({...state...}, _handle_mt)` where `_handle_mt.__index = sms.timer`. Same shape as `sms.group`.
- Module logger: `local log = sms.log.module("sms.timer")` (explicit tag — same v1 reason as the other modules; auto-derive is dead code per closed issue #2).
- User-supplied `fn` is wrapped in `pcall`; errors get logged and (for `after`) the timer ends; (for `every`) the timer continues with the next iteration. **Errors in user code never break the framework.**

### Out of scope

- **Pause/resume of individual timers.** Adds state-machine complexity (running/paused/stopped) without a clear use case in v1.
- **`run_at(sim_time, fn)`** — absolute-time scheduling. Computable as `after(sim_time - timer.getTime(), fn)`. Sugar later if it becomes common.
- **`next_frame(fn)`** — same-frame defer. Niche; `after(0, fn)` covers it (DCS schedules 0-delay calls for the next frame).
- **Naming/labeling timers** for debug. `sms.timer.every(4, fn, "patrol")`. Skip — adds a key system without clear value yet.
- **`sms.timer.list()`** — list all active timers. Useful debug aid but not v1.
- **`every_until(predicate, fn)`** — separate function. The `fn returns false` self-cancel covers this.
- **`repeat_n` as a separate function.** The `max` arg on `every` covers this with one function instead of two.
- **Wall-clock vs sim-time toggle.** Sim time only. If wall clock ever matters, it's a separate concern.

## Constraints

- Lua 5.1 (DCS mission environment). No `goto`, no `//`, no Lua 5.2+ idioms.
- Sim-time-based via `timer.getTime()`. When DCS pauses, sim time freezes; timers don't fire until sim resumes. This is desirable behavior (matches mission-author expectations).
- Failure model: log + return nil/false, never throw. Even when user code throws, the framework catches via `pcall` and continues.
- The module name `sms.timer` does NOT collide with DCS's global `timer` because we're under `sms.*`.

## Architecture

`framework/timer.lua`, single file, ~110 lines. Same three-layer shape as `sms.group` minus the `__call` constructor (timers aren't *looked up*, they're *created* by `after`/`every`):

```lua
-- 1. Module functions: the API.
sms.timer.after        = function(seconds, fn)        ... end
sms.timer.every        = function(seconds, fn, max)   ... end
sms.timer.stop         = function(h)                  ... end
sms.timer.is_active    = function(h)                  ... end
sms.timer.get_remaining = function(h)                 ... end

-- 2. Handle metatable. Identity-checked so callers can't slip arbitrary
--    tables into module functions and get unexpected behavior.
local _handle_mt = {__index = sms.timer}

-- 3. Handles created internally by after/every with state:
--    {kind="after"|"every", id=<DCS timer ID>, active=bool,
--     next_fire_time=number|nil, fn=fn, interval=seconds, iterations=N, max=N|nil}
```

### Handle state

A handle is created by `after` or `every` and carries:

| Field | Type | Meaning |
|---|---|---|
| `kind` | `"after"` or `"every"` | What kind of timer this is. |
| `id` | number | DCS timer ID returned by `timer.scheduleFunction`. Used by `:stop()` to call `timer.removeFunction`. |
| `active` | bool | Mutable. `true` while the timer is scheduled or about to fire; `false` once stopped/expired. |
| `next_fire_time` | number or `nil` | Sim time at which the timer next fires. `nil` once inactive. |
| `interval` | number | (every only) Seconds between fires. |
| `iterations` | number | (every only) How many times the timer has fired so far. |
| `max` | number or `nil` | (every only) If set, stop after this many iterations. |

### `after` flow

1. Validate `seconds` is a non-negative number; `fn` is a function. On bad args, log + return nil.
2. Create handle with `active = true`, `next_fire_time = timer.getTime() + seconds`.
3. Schedule a wrapper function via `timer.scheduleFunction` for `next_fire_time`. The wrapper:
   - Sets `handle.active = false` and `next_fire_time = nil` BEFORE calling user `fn` (so `is_active()` from inside user code reflects the right state).
   - Calls `fn()` inside `pcall`; logs any error.
   - Returns `nil` (don't reschedule).
4. Stash the DCS timer ID on the handle.
5. Return the handle.

### `every` flow

1. Validate `seconds` is a positive number (> 0; zero would mean every-frame, almost certainly a bug); `fn` is a function; `max` is `nil` or a positive number.
2. Create handle with `active = true`, `interval = seconds`, `iterations = 0`, `max = max`, `next_fire_time = timer.getTime() + seconds`.
3. Schedule a wrapper function via `timer.scheduleFunction` for `next_fire_time`. The wrapper:
   - Increments `iterations`.
   - Calls user `fn` inside `pcall`; logs errors and treats them as "continue" (don't crash).
   - If user's return value is exactly `false`, mark handle inactive and return `nil` (stop).
   - If `max` set and `iterations >= max`, mark handle inactive and return `nil` (stop).
   - Otherwise, compute `next_fire_time = t + interval`, store on handle, return it.
4. Stash the DCS timer ID on the handle.
5. Return the handle.

### `stop` semantics

- If handle is not a real handle (wrong metatable), log + return false.
- If handle is already inactive, return `false` (was not active to stop).
- Otherwise: set `active = false`, `next_fire_time = nil`, call `timer.removeFunction(handle.id)` inside `pcall` (DCS may complain if the timer just fired and was removed automatically; log but continue), return `true`.

### `is_active`

Silent probe. Returns `false` for non-handles (no log). Returns `handle.active == true` for real handles.

### `get_remaining`

- If handle is not a real handle: log + return nil.
- If handle is not active: log + return nil.
- Otherwise: return `handle.next_fire_time - timer.getTime()`. Can be negative if the timer is just about to fire and we're racing; that's fine. Document as "≈ seconds until next fire."

### Identity check for handles

Module functions like `stop`, `is_active`, `get_remaining` accept only real handles (created by `after`/`every`). The check is `getmetatable(h) == _handle_mt`. Plain tables shaped like a handle won't pass — this prevents accidental shape-collision bugs and is appropriate since timers are *created*, not constructed by name.

## Decisions (made autonomously, recorded for revisit)

- **No `__call` constructor on the module.** Timers are created by `after`/`every`, not retrieved by name. There's no `sms.timer("some_id")`.
- **Reject `seconds <= 0` for `every`, accept `seconds == 0` for `after`.** `every(0, fn)` is almost certainly a bug; `after(0, fn)` is "fire next frame," a real and useful pattern.
- **`max` arg on `every` covers the bounded-repeat case** instead of a separate `repeat_n`. One function name, two behaviors gated by `max`'s presence.
- **`fn` returning `false` self-cancels `every`.** Slightly magical (you have to know to do it) but avoids a separate `every_until` function. Documented in the file header.
- **User `fn` errors are caught via `pcall` and logged.** Prevents one bad timer from poisoning the rest of the mission. Errors in `after` end the timer; errors in `every` continue to the next iteration.
- **`stop` is idempotent.** First call stops + returns `true`; subsequent calls return `false`. No log on the second-call case (idempotent stop is a normal pattern; we don't want to spam the log).
- **`get_remaining` is logged on inactive timers** (unlike `is_active`). Rationale: probe vs. query. `is_active` is the explicit probe; `get_remaining` implies expectation of an active timer, so a nil return is informative.
- **Handle identity check via metatable.** `getmetatable(h) == _handle_mt`. Same protection that prevents `sms.group.is_alive({name="x"})` from accidentally matching a unit handle in the future.
- **No "list active timers" debug aid in v1.** Simple to add later if/when we feel the lack.
- **Single file `framework/timer.lua`, ~110 lines.** Same shape decision as `sms.group`.
- **Smoke test at `framework/test/smoke_timer.sh`, separate from `smoke.sh` and `smoke_group.sh`.** Per-module smoke tests, established convention.

## Smoke test outline

`framework/test/smoke_timer.sh` — host-side bash that drives the bridge.

The test must wait for sim time to advance for several assertions, so it sleeps host-side between scheduling and checking. This requires DCS to be **running and unpaused** during the test; status check at the top.

1. `dcs-sms.exe status` — `mission loaded: true, fresh: true` or bail.
2. Load `framework/sms.lua`, `framework/log.lua`, `framework/timer.lua`. Each `ok: true`.
3. **Bad-arg validation (instant, no sleep needed):**
   - `sms.timer.after(-1, function() end)` → `nil`. Verify log.
   - `sms.timer.after(1, "not a function")` → `nil`.
   - `sms.timer.every(0, function() end)` → `nil` (zero rejected).
   - `sms.timer.every(1, function() end, -3)` → `nil` (bad max).
   - Tail `dcs.log` for `[sms.timer]` lines from these calls.
4. **`after` fires once after delay:**
   - Set `_G._smoke = {fired = 0}`.
   - Schedule `after(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)`. Capture handle.
   - Verify handle `is_active() == true`.
   - Sleep host-side ~2 s.
   - Verify `_G._smoke.fired == 1`.
   - Verify handle `is_active() == false`.
5. **`every` fires repeatedly until stopped:**
   - Reset state.
   - Schedule `every(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)`. Capture handle.
   - Sleep host-side ~3.5 s.
   - Stop handle. Verify `:stop()` returned `true`.
   - Verify `_G._smoke.fired >= 3`.
   - Verify handle `is_active() == false`.
   - Verify `:stop()` called again returns `false`.
6. **`every` with `max` stops after N fires:**
   - Reset state.
   - Schedule `every(1, fn, 3)`.
   - Sleep host-side ~4 s (more than enough for 3 fires).
   - Verify `_G._smoke.fired == 3`.
   - Verify `is_active() == false`.
7. **`every` self-cancels via `fn returning false`:**
   - Reset state.
   - Schedule `every(1, function() _G._smoke.fired = _G._smoke.fired + 1; if _G._smoke.fired >= 2 then return false end end)`.
   - Sleep ~3 s.
   - Verify `_G._smoke.fired == 2`.
   - Verify `is_active() == false`.
8. **`get_remaining` returns sensible values:**
   - Schedule `after(5, fn)`. Capture handle.
   - Verify `get_remaining()` is between 4 and 5.
   - Sleep ~2 s.
   - Verify `get_remaining()` is between 2 and 3.
   - Stop handle (cleanup).
9. **User errors in `fn` are caught:**
   - Reset state.
   - Schedule `every(1, function() error("boom") end, 2)`.
   - Sleep ~3 s.
   - Verify `is_active() == false` (max reached, errors didn't crash framework).
   - Verify `dcs.log` contains a `[sms.timer]` error line about the user fn throwing.
10. Final: `echo "smoke ok"` and exit 0.

The total runtime is ~17 seconds of sleeps. Acceptable for a smoke test.

## Out-of-band fallbacks

- **If sim time advances faster/slower than expected** (e.g., the user has a time-acceleration mod), the assertions on `_G._smoke.fired` use `>=` where reasonable and bracket-checks elsewhere. They should be robust to small skew. If the user has aggressive time-acceleration that wildly distorts these, the smoke test will fail loudly with the actual count vs. expected — easy to diagnose.
- **If DCS is paused mid-test** (alt-tab, menu), heartbeat stops being fresh, sleeps don't advance sim time, assertions fail. The status check at the top sets the precondition; mid-test failure should be diagnosable from the partial output.

## Related issues

- **#3** — bridge auto-return-prepend ergonomics. Independent of this work.
- **#1** and **#2** — closed.

## Sets the cargo-cult template for…

This is the first **module-only** (no entity wrapping) module. `sms.events` will follow this style when it lands — function-based subscribe/dispatch with handle-style subscription tokens that have `:cancel()`. The pattern of "module-creates-handle, handle has `:probe()` and `:cancel()` methods" is now established and copyable.
