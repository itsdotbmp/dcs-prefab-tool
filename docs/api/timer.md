# `sms.timer` — sim-time scheduling

`sms.timer` wraps DCS's native `timer.scheduleFunction` / `timer.removeFunction` / `timer.getTime` in an idiomatic surface for "run this in N seconds" (`after`) and "run this every N seconds" (`every`) patterns, plus a thin `now()` accessor.

All scheduling is **sim-time-based**: the clock ticks with the DCS simulation and **pauses with DCS** (pausing the sim pauses your timers; time-compression speeds them up). This is the right behavior for mission scripting — a 30-second timer means 30 sim-seconds, not 30 wall-clock seconds.

`after` / `every` return a small **handle** (private metatable, identity-checked). Method-style (`h:stop()`) and module-style (`sms.timer.stop(h)`) calls both work. User errors raised inside the scheduled `fn` are caught via `pcall` and logged at `error` level — bad user code never breaks the framework.

All functions follow the framework's [failure model: log + nil, never throw](../../AGENTS.md#3-failure-model-log--nil-never-throw). "Returns X" implicitly means "returns X | nil + log on bad input".

## Loading

Requires `sms.lua` and `log.lua`. The simplest path is `framework/load_all.lua` — see the [API index](README.md).

## Functions

### `sms.timer.after(seconds, fn) → handle`

**Synopsis** — schedule `fn` to run once after `seconds` of sim time has elapsed.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `seconds` | `number` | Delay in sim-seconds. Must be `>= 0`. `0` is accepted and effectively defers `fn` to the next scheduler tick. |
| `fn` | `function` | Zero-arg callback. Its return value is ignored. Errors are caught and logged. |

**Returns** — timer handle. The handle deactivates **before** `fn` is called (the post-fire state is final), so `h:is_active()` observed from inside `fn` returns `false`.

**Example**

```lua
-- Tell a CAS flight to push 30 seconds after they spawn.
local cas = sms.group("red-cas-1")
sms.timer.after(30, function()
  sms.task.attack_group(cas, "blue-convoy-1")
end)
```

### `sms.timer.every(seconds, fn, max?) → handle`

**Synopsis** — schedule `fn` to run repeatedly every `seconds` of sim time.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `seconds` | `number` | Interval in sim-seconds. Must be `> 0` (zero is rejected — use `after(0, ...)` for next-tick deferral). |
| `fn` | `function` | Zero-arg callback. Returning `false` self-cancels the timer. Any other return (including `nil`) keeps it running. Errors are caught and logged; iteration continues. |
| `max` | `number` (optional) | Cap on total iterations. Must be `> 0` if provided. After `max` fires, the handle deactivates. Omit (or pass `nil`) for unbounded repeats. |

**Self-cancellation:** `fn` returning the literal `false` deactivates the handle and unschedules it. This is the idiomatic "poll until done" pattern.

**Iteration cap:** when both `max` and self-cancel are in play, whichever happens first wins. Errors raised in `fn` do **not** count as a self-cancel — the timer keeps iterating.

**Drift:** the next fire time is rebased from the actual fire time supplied by DCS, not from the previously-scheduled fire time, so a single late dispatch does not compound into runaway drift.

**Returns** — timer handle. While `fn` is executing, `h:is_active()` returns `true` (the handle deactivates **after** `fn` returns `false` or `max` is reached). This differs from `after`, which deactivates before calling `fn`.

**Example**

```lua
-- Poll a strike package every 10 seconds; stop watching once they're dead.
local strike = sms.group("red-strike-1")
sms.timer.every(10, function()
  if not strike:is_alive() then
    sms.log.info("red-strike-1 is down — stopping watch")
    return false      -- self-cancel
  end
  local left = strike:get_size()
  sms.log.info("red-strike-1: " .. left .. " alive")
end)
```

### `sms.timer.now() → number`

**Synopsis** — current simulation time in seconds since mission start. Thin wrapper over DCS's `timer.getTime` so mission code that timestamps events stays inside the `sms.*` idiom.

**Arguments** — none.

**Returns** — `number` (sim-seconds, monotonic while the mission is running, frozen while DCS is paused).

**Example**

```lua
local t0 = sms.timer.now()
sms.events.on("kill", function(ev)
  sms.log.info(string.format("kill at T+%.1fs", sms.timer.now() - t0))
end)
```

## Handle methods

The handle returned by `after` / `every` exposes three methods. Method-style and module-style calls are equivalent: `h:stop()` is the same as `sms.timer.stop(h)`.

### `h:stop() → bool`

**Synopsis** — cancel the timer. Idempotent.

**Returns** — `true` if this call newly stopped an active timer, `false` if the timer was already inactive (already fired, already self-cancelled, hit `max`, or stopped earlier). Logs and returns `false` if `h` is not a real timer handle.

**Example**

```lua
local h = sms.timer.every(1, function() sms.log.info("tick") end)
sms.timer.after(5, function()
  if h:stop() then
    sms.log.info("stopped the ticker")
  end
end)
```

### `h:is_active() → bool`

**Synopsis** — silent probe: is this timer still scheduled to fire?

**Returns** — `bool`. Silent on failure: returns `false` for non-handles, dead handles, or anything else — never logs. Inside an `every` callback this returns `true` (the handle stays active for the duration of `fn`); inside an `after` callback this returns `false`.

**Example**

```lua
local h = sms.timer.after(60, function() end)
-- ...later...
if h:is_active() then
  sms.log.info("timer still pending: " .. h:get_remaining() .. "s left")
end
```

### `h:get_remaining() → number`

**Synopsis** — seconds of sim time until the timer's next scheduled fire.

**Returns** — `number` (sim-seconds, can be slightly negative if DCS is late dispatching). Logs and returns `nil` if the handle is inactive (already fired / stopped / cancelled) or not a real handle.

**Example**

```lua
local h = sms.timer.after(120, function() sms.log.info("two minutes up") end)
sms.log.info("remaining: " .. h:get_remaining() .. "s")  -- ~120
```

**See also** — [`sms.events`](events.md) for event-driven scheduling (fire on `kill` / `land` / custom signals), [`sms.group`](group.md) for entity-scoped polling targets.
