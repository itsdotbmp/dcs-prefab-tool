# dcs-sms Framework — `sms.group` v1

**Date:** 2026-04-25
**Status:** Approved (brainstorm phase)
**Scope:** First entity abstraction in the dcs-sms framework. Wraps DCS Group references in lightweight handles and establishes the cargo-cult pattern that future entity modules (`sms.unit`, `sms.zone`, `sms.static`, …) will follow.

## Goal

Build the smallest useful Group abstraction that:

- Establishes the **handle-over-module** pattern (lightweight tables sitting on top of plain module functions, no inheritance, no subclasses).
- Sets the **failure model** (graceful + log, never throw) for every entity module that comes after.
- Ships five methods that cover the most common Group queries plus `destroy`, all verifiable end-to-end through the bridge.

## User value

After this iteration the user can write mission code like:

```lua
local sam = sms.group("RedSAM-1")
if sam and sam:is_alive() then
  sms.log.info("SAM at " .. sam:get_position().x .. ", coalition " .. sam:get_coalition())
end
```

…and have it Just Work, without touching MOOSE, without paying for an inheritance chain, and without risking a single bad name aborting the mission script.

## Scope

### In scope (v1)

- One file: `framework/group.lua`.
- One smoke test: `framework/test/smoke_group.sh`.
- Construction: `sms.group(name)` (callable module form). Returns a handle if the group exists in DCS, otherwise logs `[sms.group] couldn't find '<name>'` and returns `nil`.
- Five methods, all callable as `g:method()` AND as `sms.group.method(g_or_name, ...)`:
  - `:is_alive()` — returns `bool`. Probe; never logs.
  - `:get_name()` — returns `string`. Trivial; just returns the stored name.
  - `:get_coalition()` — returns `"red" | "blue" | "neutral"`. Normalized from DCS's 0/1/2.
  - `:get_position()` — returns `{x, y, z}` (DCS-native vec3 from leader unit's `getPoint()`). `nil` (with log) if dead.
  - `:destroy()` — returns `true` if the group was alive and is now destroyed; `nil` (with log) if it was already dead or never existed. Calls `groupObject:destroy()` (clean removal, no explosion).
- Module logger via `local log = sms.log.module("sms.group")` (explicit tag — same v1 reason as `utils.lua`; will become auto-derived once mechanism C ships per #2).
- Self-spawning smoke test using `coalition.addGroup` (DCS API directly, not via the framework — spawning is a separate future sub-project). Hermetic: spawns its own fixture, asserts behavior, destroys fixture, leaves no litter.

### Out of scope

- **Spawning groups** — `sms.spawn` / `sms.group.spawn`. Future sub-project of the framework.
- **`sms.unit`** — the next entity to ship after Group. Follows the same pattern.
- **Other group methods** — `:smoke()`, `:set_ai()`, `:teleport()`, `:get_units()`, `:get_leader()`, etc. Each ships as a small follow-up once a real need shows up.
- **Vec3 math / geometry helpers** (`sms.geom`). Separate sub-project.
- **Group event subscriptions** (death, hit). Will live in the future events module and may add a `:on_event(...)` method to handles later.
- **Caching of DCS userdata.** Handles store only the name; methods re-resolve via `Group.getByName(name)` on every call. Robust against DCS destroying/respawning underlying objects between calls.
- **A generic `make_handle()` helper.** Duplicating the 3-line handle factory across modules is cheaper than the wrong abstraction. Revisit after 2–3 entity modules ship.

## Constraints

- Lua 5.1 (DCS mission environment). No `goto`, no `//` integer division, no Lua 5.2+ idioms.
- Must work under bridge-driven loading (mechanism D). When mechanism C lands, no changes required.
- Only public global is `sms.group` (and its sub-keys). No other globals leak.
- Failure model is fixed framework-wide (memory: `feedback_failure_mode.md`):
  - Construction miss: log + return `nil`. Never throws.
  - Method on dead group: log + return `nil` (or `false`-ish equivalent). Never throws.
  - Probe-style methods (`:is_alive()`) just return `bool` without logging.

## Architecture

`framework/group.lua` has three layers, all in one file:

```lua
-- 1. Module functions: the underlying API. Each accepts a handle OR a name string.
sms.group.is_alive       = function(g)            ... end
sms.group.get_name       = function(g)            ... end
sms.group.get_coalition  = function(g)            ... end
sms.group.get_position   = function(g)            ... end
sms.group.destroy        = function(g)            ... end

-- 2. Callable module: the sugar entry point.
--    sms.group("RedSAM") => handle or nil + log
setmetatable(sms.group, {
  __call = function(_, name)
    if not Group.getByName(name) then
      log.error("couldn't find group '" .. tostring(name) .. "'")
      return nil
    end
    return setmetatable({name = name}, {__index = sms.group})
  end,
})

-- 3. Handles: just {name=...} + dispatch via __index = sms.group.
--    g:is_alive() == sms.group.is_alive(g)
```

All three call shapes work, all equivalent:

```lua
local g = sms.group("RedSAM")            -- sugar; returns handle
g:is_alive()                              -- handle method
sms.group.is_alive(g)                     -- module function on handle
sms.group.is_alive("RedSAM")              -- module function on raw name
```

### Argument normalization

Every module function starts with the same one-liner:

```lua
local name = type(g) == "string" and g or g.name
```

…so `sms.group.is_alive("RedSAM")` and `sms.group.is_alive(handle)` resolve identically.

### Internal `is_alive` guard

Every method except `is_alive` itself first calls `is_alive`. If false, log and early-return:

```lua
sms.group.get_coalition = function(g)
  local name = type(g) == "string" and g or g.name
  if not sms.group.is_alive(name) then
    log.error("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  -- … real work …
end
```

`is_alive` itself does the existence check directly:

```lua
sms.group.is_alive = function(g)
  local name = type(g) == "string" and g or g.name
  local obj = Group.getByName(name)
  return obj ~= nil and obj:isExist()
end
```

### `destroy` semantics

```lua
sms.group.destroy = function(g)
  local name = type(g) == "string" and g or g.name
  if not sms.group.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  Group.getByName(name):destroy()
  return true
end
```

Calling destroy twice in a row: first call returns `true`, second call logs and returns `nil`. Safe to call without prior is_alive check.

### Coalition mapping

DCS uses `coalition.side.NEUTRAL = 0`, `coalition.side.RED = 1`, `coalition.side.BLUE = 2`. We map to strings: `0 -> "neutral"`, `1 -> "red"`, `2 -> "blue"`.

### Position semantics

A "group position" is not a native DCS concept — only Units have positions. v1 returns the **leader unit's** `getPoint()`, which is the conventional choice (also what MOOSE does by default). Document this. If `getUnits()` returns an empty list (shouldn't happen for a live group, but guard anyway), log and return `nil`.

### Handle field reservation

The handle table has one field, `name`. Future iterations may add `_cached_*` fields if a real need shows up; until then, anything other than `name` on the handle is reserved. A user-attached field could collide with future internal fields. Document; don't enforce in code.

## Decisions (made autonomously, recorded for revisit)

- **Single file `framework/group.lua`.** Layered (module → callable → handle factory) but in one place. Rationale: ~70 lines total; splitting now would be premature.
- **Smoke test is a new file (`framework/test/smoke_group.sh`), not an extension of `smoke.sh`.** Each module gets its own focused smoke test. The existing `smoke.sh` continues to test log + utils only. If a third module lands and we want a "run them all" runner, a `smoke_all.sh` aggregator is one-line shell — defer.
- **Test fixture: a single `Soldier M4` infantry unit, blue coalition, country USA, spawned via `coalition.addGroup` at coords queried from an existing mission unit if available, falling back to `{x = 0, y = 0}`.** Querying an existing unit's position keeps the spawn on whatever map the user is using; the {0,0} fallback is the contingency for a mission with no existing units. Test cleans up via `:destroy()` at the end.
- **`get_position()` returns the leader unit's vec3, not a centroid.** Matches MOOSE convention. Centroid is computable later as a separate helper if anyone wants it.
- **Coalition strings are lowercase** (`"red"`, `"blue"`, `"neutral"`). DCS's own constants are uppercase but lowercase reads better in mission code and matches a lot of existing tooling.
- **Module logger uses explicit tag `"sms.group"`, not auto-derive.** Mirrors `utils.lua` per the v1 limitation. Will become `sms.log.module()` (no arg) once mechanism C lands per issue #2.
- **No `must` / strict-construction variant.** The user explicitly rejected this in the brainstorm; the log line on a missed lookup IS the loud signal.
- **No chaining return.** Methods that "do something" (`destroy`) return a meaningful value (`true`), not the handle. Callers can chain by re-fetching: `if sms.group("X"):destroy() then ... end`.

## Smoke test outline

`framework/test/smoke_group.sh`:

1. `dcs-sms.exe status` — confirms hook alive + mission loaded + heartbeat fresh. Bail with a clear message otherwise.
2. Load framework files in order: `sms.lua`, `log.lua`, `group.lua`. Each must return `ok: true`.
3. Spawn fixture: a single-unit blue ground group named `_sms_test_group`. Use `coalition.addGroup` directly. Assert the spawn `ok: true` and that `Group.getByName("_sms_test_group") ~= nil`.
4. Run assertions, each as a separate `exec --code` so failures pinpoint:
   - `sms.group("_sms_test_group"):is_alive()` → `true`
   - `sms.group("_sms_test_group"):get_name()` → `"_sms_test_group"`
   - `sms.group("_sms_test_group"):get_coalition()` → `"blue"`
   - `local p = sms.group("_sms_test_group"):get_position(); return p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"` → `true`
   - `sms.group("_definitely_does_not_exist") == nil` → `true`
5. `sms.group("_sms_test_group"):destroy()` → `true`
6. `sms.group("_sms_test_group") == nil` → `true` (post-destroy lookup misses; also exercises construction-miss log path again, harmless).
7. Tail-log assertion: `dcs-sms.exe tail-log --grep '\[sms.group\]' -n 200` must contain a line including `couldn't find '_definitely_does_not_exist'`.
8. Final `echo "smoke ok"` and exit 0.

## Out-of-band fallbacks

- **If `Soldier M4` is not a valid unit type on the user's terrain mod / DCS version**, the spawn step will fail with a clear DCS error. Try a more universal type (`Tank M-1A1`, `MBT_T-72B`) — the implementer can iterate.
- **If `coalition.addGroup` fails because of map bounds at `{x=0,y=0}`**, the implementer queries an existing unit first and spawns near it. The smoke test should handle this gracefully — if it can't find any reference unit AND `{0,0}` fails, bail with a clear message asking the user to provide a coord hint.

## Related issues

- **#1** — framework versioning trade-off (when mechanism C lands).
- **#2** — hook auto-injection (mechanism C). When this ships, `sms.log.module()` no-arg form will start working and `framework/group.lua` can drop the explicit `"sms.group"` tag, same migration as `utils.lua`.
- **#3** — bridge auto-return-prepend ergonomics. Independent of this work.

This sub-project will likely produce one new follow-up issue: tracking when `sms.unit` should land. Filed as part of the implementation.
