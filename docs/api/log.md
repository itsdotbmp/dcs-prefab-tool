# `sms.log` — structured logging with levels and tagged loggers

`sms.log` is the framework's logging surface. It exposes four severity levels — `debug` < `info` < `warn` < `error` — each routed to a DCS `env.*` sink, plus a per-module *tagged logger* factory so every framework module can log with a consistent `[sms.<module>]` prefix.

Every `sms.*` module uses this logger to honour the framework's [failure model: log + nil, never throw](../../AGENTS.md#3-failure-model-log--nil-never-throw). The logger itself is also designed to be cheap and lossy: calls below the runtime threshold are dropped before any string formatting touches `env.*`, so verbose `debug` logs in hot loops are effectively free in production.

**Sink mapping.** Severity levels map onto DCS sinks as follows:

| Level | Numeric weight | DCS sink | `dcs.log` line prefix |
|---|---|---|---|
| `debug` | 10 | `env.info` | `INFO ...` |
| `info` | 20 | `env.info` | `INFO ...` |
| `warn` | 30 | `env.warning` | `WARNING ...` |
| `error` | 40 | `env.error` | `ERROR ...` |

Note that `debug` and `info` share the same sink (`env.info`); the difference is purely which calls survive the threshold filter. DCS does not provide a separate "debug" log channel — the framework simulates one by gating on level.

**Default threshold** is `info`, so `debug` calls are silent until you opt in with `sms.log.set_level("debug")`. To mute caller-misuse warnings in a production mission, raise it with `sms.log.set_level("error")`.

## Loading

Requires `sms.lua`. Load order: `sms.lua → log.lua` (early — every other framework module depends on it). The simplest path is `framework/load_all.lua` — see the [API index](README.md).

## The warn-vs-error contract

Picking the right level matters. Quoting [AGENTS.md §3](../../AGENTS.md#3-failure-model-log--nil-never-throw) verbatim:

> - **`log.warn`** — caller misuse. The API user passed garbage, named a non-existent entity, called an air-only verb on a ground group, requested an unknown enum, called against a destroyed handle, etc. The caller can fix it by changing what they pass or what state they call against. Most framework rejection paths are warns.
> - **`log.error`** — real failure that the caller couldn't have prevented. DCS rejected something the framework expected to succeed (`coalition.addGroup` raised, `addStaticObject` accepted but not findable post-call), DCS returned a value outside our known enum, an internal invariant was violated, or `pcall` caught a user callback raising during dispatch.
>
> When in doubt: if the message could plausibly cause the user to think *"oh, I called this wrong"*, it's a `warn`. If it points at framework or DCS misbehavior, it's an `error`.

In practice, this means smoke tests that exercise rejection paths produce `WARNING [sms.*]` lines on purpose — those lines are *evidence the test passed*. Only `ERROR [sms.*]` lines indicate something the framework or DCS is actually broken about.

A realistic example of each, side by side:

```lua
local log = sms.log.module("sms.foo")

-- warn: the caller named a non-existent group. They can fix it by
-- spelling the group name correctly or checking :is_alive() first.
local group = sms.group("typo-grup")  -- mistyped
if not group then
  log.warn("get_position: group 'typo-grup' not found")
  return nil
end

-- error: DCS accepted addGroup but the result is not findable.
-- The caller did everything right; this is DCS or framework
-- misbehaviour.
local ok, err = pcall(coalition.addGroup, country_id, cat, group_table)
if not ok then
  log.error("create: coalition.addGroup raised: " .. tostring(err))
  return nil
end
```

## Functions

### `sms.log.debug(msg)`

**Synopsis** — log `msg` at level `debug` with the untagged `[sms]` prefix. Routed to `env.info`. Filtered out unless the threshold is `debug`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `msg` | any | Logged via `tostring(msg)`. Typically a pre-formatted string. |

**Returns** — nothing.

**Example**

```lua
sms.log.set_level("debug")
sms.log.debug("dispatch loop tick @ " .. sms.timer.now())
-- dcs.log: INFO [sms] dispatch loop tick @ 12.345
```

### `sms.log.info(msg)`

**Synopsis** — log `msg` at level `info` with the untagged `[sms]` prefix. Routed to `env.info`. Visible at the default threshold.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `msg` | any | Logged via `tostring(msg)`. |

**Returns** — nothing.

**Example**

```lua
sms.log.info("mission script loaded")
-- dcs.log: INFO [sms] mission script loaded
```

### `sms.log.warn(msg)`

**Synopsis** — log `msg` at level `warn` with the untagged `[sms]` prefix. Routed to `env.warning`. Use for *caller misuse* (see the warn-vs-error contract above).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `msg` | any | Logged via `tostring(msg)`. |

**Returns** — nothing.

**Example**

```lua
sms.log.warn("group 'patrol-1' not found — skipping retask")
-- dcs.log: WARNING [sms] group 'patrol-1' not found — skipping retask
```

### `sms.log.error(msg)`

**Synopsis** — log `msg` at level `error` with the untagged `[sms]` prefix. Routed to `env.error`. Use for *real failures* the caller couldn't have prevented.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `msg` | any | Logged via `tostring(msg)`. |

**Returns** — nothing.

**Example**

```lua
sms.log.error("internal: dispatcher invariant violated")
-- dcs.log: ERROR [sms] internal: dispatcher invariant violated
```

### `sms.log.set_level(name) → nil`

**Synopsis** — set the runtime threshold. Calls below this level are dropped before reaching any `env.*` sink.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | One of `"debug"`, `"info"`, `"warn"`, `"error"`. **Case-insensitive** — `"DEBUG"`, `"Warn"`, `"ERROR"` all work. |

**Returns** — nothing. On bad input (non-string, or string not in the four-level set), logs a warning via `env.warning` and **leaves the threshold unchanged** — the logger's own failure mode is still log + no-op.

**Example**

```lua
-- Silence caller-misuse warns in production.
sms.log.set_level("error")

-- Bad input: logged and ignored, threshold stays at "error".
sms.log.set_level("verbose")
-- dcs.log: WARNING [sms] log.set_level: unknown level 'verbose' (use debug/info/warn/error)
```

### `sms.log.get_level() → string`

**Synopsis** — read the current threshold.

**Arguments** — none.

**Returns** — the current threshold's lowercase string name (`"debug"`, `"info"`, `"warn"`, or `"error"`). Never `nil`.

**Example**

```lua
sms.log.set_level("WARN")
sms.log.get_level()   --> "warn"
```

### `sms.log.module(name?) → tagged logger`

**Synopsis** — build a per-module logger whose lines are prefixed with `[<tag>]` instead of `[sms]`. This is the canonical way to log from inside a framework module.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` (optional) | The tag to use verbatim — no automatic `sms.` prefix is added; the caller is in full control. When omitted, the tag is auto-derived from the caller's file basename: `framework/utils.lua` → `sms.utils`. Falls back to `"sms.unknown"` if no `.lua` basename is recoverable. |

**Returns** — a small table:

| Key | Type | Description |
|---|---|---|
| `tag` | `string` | The resolved tag, useful for assertions and tests. |
| `debug` | `function(msg)` | Tagged debug log. |
| `info` | `function(msg)` | Tagged info log. |
| `warn` | `function(msg)` | Tagged warn log. |
| `error` | `function(msg)` | Tagged error log. |

**Important caveat — auto-derivation only works for `dofile`-loaded modules.** The framework auto-derives the tag by reading the caller's chunk source via `debug.getinfo(2, "S").source` and pulling the `.lua` basename. This works when a module is loaded via `dofile()` / `loadfile()` / `framework/load_all.lua`, because Lua records the file path as the chunk source.

It does **not** work for modules loaded through the host-side bridge (`tools/dcs-sms exec --file ...`). The bridge ships code into DCS via `net.dostring_in`, which does not set a chunkname, so `info.source` is the wrapper source string itself and the `.lua$` pattern does not match. Auto-derivation falls back to `"sms.unknown"`. **Bridge-loaded modules must pass an explicit tag**:

```lua
-- BAD inside a bridge-loaded module: tag becomes "sms.unknown"
local log = sms.log.module()

-- GOOD: explicit tag works in either environment
local log = sms.log.module("sms.foo")
```

**Example — typical framework module header**

```lua
-- framework/foo.lua
assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

local log = sms.log.module("sms.foo")

sms.foo = sms.foo or {}

sms.foo.do_thing = function(name)
  if type(name) ~= "string" then
    log.warn("do_thing: expected string name, got " .. type(name))
    return nil
  end
  log.info("do_thing(" .. name .. ")")
  -- ...
end
```

Output in `dcs.log`:

```
WARNING [sms.foo] do_thing: expected string name, got nil
INFO    [sms.foo] do_thing(alpha)
```

**Example — inspecting a logger's tag**

```lua
local log = sms.log.module("sms.test_harness")
log.tag         --> "sms.test_harness"
log.warn("smoke ok")
-- dcs.log: WARNING [sms.test_harness] smoke ok
```

## Notes

- **Threshold is process-wide.** There is one `_level` shared by every untagged call and every tagged logger. `sms.log.set_level` changes filtering for everyone at once; there is no per-module threshold.
- **No string formatting helper.** `sms.log.<level>` takes a single message argument. Use Lua concatenation (`..`) or `string.format` at the call site.
- **The logger never throws.** Bad input to `set_level` warns and no-ops; bad message values to the level functions are coerced via `tostring`.
