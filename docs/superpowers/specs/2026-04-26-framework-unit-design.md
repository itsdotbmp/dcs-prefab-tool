# dcs-sms Framework — `sms.unit` v1

**Date:** 2026-04-26
**Status:** Approved (brainstorm phase)
**Scope:** Second entity wrapper in the dcs-sms framework. Cargo-cults the pattern established by `sms.group`. Adds the cross-cutting pair `unit:get_group()` ↔ `group:get_units()`, completing the deferred `get_units()` story from the group spec.

## Goal

Build the smallest useful Unit abstraction that:

- Mirrors the entity-wrapper template established by `sms.group` (handle-over-module, never throw, log + nil on failure).
- Adds two unit-only getters (`get_type`, `get_group`) that justify a unit module beyond pure cargo-cult.
- Closes the deferred `sms.group:get_units()` story so the group/unit handle ecosystem feels complete.

## User value

After this iteration the user can write mission code like:

```lua
local u = sms.unit("PlayerJet-1")
if u and u:is_alive() then
  local g = u:get_group()
  sms.log.info(u:get_type() .. " in group " .. g:get_name())
end

-- And the round-trip:
for _, u in ipairs(sms.group("RedSAM-1"):get_units() or {}) do
  sms.log.info("unit: " .. u:get_name() .. " (" .. u:get_type() .. ")")
end
```

Same lightweight handles, same failure model, same call-shape variants as `sms.group`. The user can finally enumerate units of a group without dropping back to raw DCS APIs.

## Scope

### In scope (v1)

**New file: `framework/unit.lua`.** Public API:

- `sms.unit("name")` — callable module. Returns handle if `Unit.getByName(name) ~= nil`, else log `[sms.unit] couldn't find unit '<name>'` and return `nil`.
- `:is_alive()` — `bool`. Probe; never logs.
- `:get_name()` — `string`. Trivial; returns the stored name.
- `:get_coalition()` — `"red" | "blue" | "neutral"`. Normalized from DCS's 0/1/2.
- `:get_position()` — `{x, y, z}` (DCS-native vec3 from `getPoint()`). `nil` (with log) if dead.
- `:get_type()` — DCS type name string (e.g., `"M-1 Abrams"`, `"F/A-18C_hornet"`). `nil` (with log) if dead.
- `:get_group()` — `sms.group` handle. `nil` (with log) if dead, or if the wrapped group lookup itself fails.
- `:destroy()` — returns `true` if alive then destroyed; `nil` (with log) if already dead. Calls `unitObject:destroy()` (clean removal, no explosion).

**Edit: `framework/group.lua`.** Add one method:

- `g:get_units()` — array of `sms.unit` handles, in DCS order. `nil` (with log) if group is dead.

All methods callable as `u:method()` AND as `sms.unit.method(u_or_name, ...)`, same as group.

**New smoke test: `framework/test/smoke_unit.sh`.** Self-spawning fixture (single Soldier M4 unit named `_sms_test_unit` inside group `_sms_test_unit_group`). Exercises every unit method and the new `g:get_units()` round-trip. Cleans up after itself.

### Out of scope

- `:get_life()` / `:get_life0()` — health/HP. Defer to v1.1; needs a small design call (absolute vs relative? both? threshold helpers?).
- `:get_player_name()` — player detection. Useful for MP, no current need.
- `:get_velocity()`, `:in_air()`, `:get_fuel()`, `:get_ammo()` — aircraft-specific. Defer until events/AI work or a real need shows up.
- `:has_attribute(attr)` — DCS attribute string queries. Defer.
- A `make_handle()` shared helper. Group spec already defers this until 3+ entity modules ship; unit is #2.
- `sms.zone`, `sms.static`, `sms.spawn` — separate sub-projects.
- Caching DCS userdata in handles. Re-resolve via `Unit.getByName(name)` on every call (matches group's design — robust against destroy/respawn between calls).

## Constraints

- Lua 5.1 (DCS mission environment). No `goto`, no `//` integer division, no Lua 5.2+ idioms.
- Must work under bridge-driven loading. No `require`. Globals only: `sms.unit` (and its sub-keys), plus the new `sms.group.get_units` key.
- Failure model is fixed framework-wide:
  - Construction miss: log + return `nil`. Never throws.
  - Method on dead unit: log + return `nil`. Never throws.
  - Probe `:is_alive()` returns `bool` without logging.
  - Garbage input (non-string, non-handle) flows through `_name_of` → `nil` → standard log+nil path.

## Architecture

`framework/unit.lua` has the same three-layer shape as `group.lua`:

```lua
-- 1. Module functions: each accepts a handle OR a name string.
sms.unit.is_alive       = function(u)            ... end
sms.unit.get_name       = function(u)            ... end
sms.unit.get_coalition  = function(u)            ... end
sms.unit.get_position   = function(u)            ... end
sms.unit.get_type       = function(u)            ... end
sms.unit.get_group      = function(u)            ... end
sms.unit.destroy        = function(u)            ... end

-- 2. Callable module: sugar entry point.
setmetatable(sms.unit, {
  __call = function(_, name)
    if not Unit.getByName(name) then
      log.error("couldn't find unit '" .. tostring(name) .. "'")
      return nil
    end
    return setmetatable({name = name}, {__index = sms.unit})
  end,
})

-- 3. Handles: just {name=...} + dispatch via __index = sms.unit.
```

Same `_name_of(u)` normalizer, same `_coalition_str = {[0]="neutral", [1]="red", [2]="blue"}` mapping, same is_alive guard at the top of every state-touching method.

### `get_group()` implementation

```lua
sms.unit.get_group = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_group: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local group_name = Unit.getByName(name):getGroup():getName()
  return sms.group(group_name)  -- delegates; logs + nil if group lookup somehow fails
end
```

Requires `sms.group` to be loaded. Documented in the file header.

### `get_units()` added to `group.lua`

```lua
sms.group.get_units = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_units: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local units = Group.getByName(name):getUnits()
  local handles = {}
  for i, u in ipairs(units or {}) do
    handles[i] = sms.unit(u:getName())
  end
  return handles
end
```

Requires `sms.unit` to be loaded at *call* time (not load time). If `unit.lua` hasn't been loaded when `g:get_units()` is called, the `sms.unit` callable doesn't exist and Lua will raise — we don't try to defend this; loading order is the user's responsibility, documented in the file header.

### Loading order

`sms.lua` → `log.lua` → `group.lua` → `unit.lua`. `group.lua` loads fine without `unit.lua` present (the `get_units` function references `sms.unit` lazily via runtime lookup, not at load time). Calling `g:get_units()` before `unit.lua` loads is a user error and surfaces as a normal Lua error — we don't try to be clever about it.

### Coalition mapping

Same as group: `0 -> "neutral"`, `1 -> "red"`, `2 -> "blue"`.

### Position semantics

Unit position is a native DCS concept (`unit:getPoint()` returns vec3 directly). No leader-unit indirection like group needed. Returns `{x, y, z}` table copy.

### Handle field reservation

Same as group: handle stores `name` only. Anything else is reserved for future internal use. Document; don't enforce.

## Failure mode summary

| Situation | Behavior |
|---|---|
| `sms.unit("nope")` — name doesn't exist | log `couldn't find unit 'nope'`, return `nil` |
| `:is_alive()` on dead/missing unit | return `false`, no log |
| `:get_name()` on any input | return name string (or `nil` for garbage input) |
| Any other method on dead unit | log `<method>: '<name>' no longer exists in mission`, return `nil` |
| `:get_group()` when unit alive but group lookup fails | inner `sms.group(name)` logs + returns `nil`; we propagate |
| `:destroy()` on already-dead unit | log + return `nil` |
| `:destroy()` called twice on same unit | first → `true`, second → log + `nil` |
| `g:get_units()` on dead group | log + return `nil` |
| Garbage input to any module function | flows through `_name_of` → `nil` → log+nil path. Never throws. |

## Smoke test outline

`framework/test/smoke_unit.sh`:

1. `dcs-sms.exe status` — confirms hook alive + mission loaded + heartbeat fresh. Bail with a clear message otherwise.
2. Load framework files in order: `sms.lua`, `log.lua`, `group.lua`, `unit.lua`. Each must return `ok: true`.
3. Spawn fixture: blue ground group `_sms_test_unit_group` with one unit `_sms_test_unit` (Soldier M4, country USA). Coordinate-discovery from existing mission units, fallback `{x=0, y=0}` (same trick as `smoke_group.sh`). Assert `Group.getByName("_sms_test_unit_group") ~= nil`.
4. Run assertions, each as a separate `exec --code` so failures pinpoint:
   - `sms.unit("_sms_test_unit"):is_alive()` → `true`
   - `sms.unit("_sms_test_unit"):get_name()` → `"_sms_test_unit"`
   - `sms.unit("_sms_test_unit"):get_coalition()` → `"blue"`
   - `local p = sms.unit("_sms_test_unit"):get_position(); return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"` → `true`
   - `sms.unit("_sms_test_unit"):get_type()` → `"Soldier M4"`
   - `sms.unit("_sms_test_unit"):get_group():get_name()` → `"_sms_test_unit_group"` *(round-trip through unit→group)*
   - `#sms.group("_sms_test_unit_group"):get_units()` → `1` *(the new group method)*
   - `sms.group("_sms_test_unit_group"):get_units()[1]:get_name()` → `"_sms_test_unit"` *(round-trip through group→unit)*
   - `sms.unit("_definitely_not_a_unit") == nil` → `true`
5. `sms.unit("_sms_test_unit"):destroy()` → `true`
6. `sms.unit("_sms_test_unit") == nil` → `true` (post-destroy lookup misses)
7. Tail-log assertion: `dcs-sms.exe tail-log --grep '\[sms.unit\]' -n 200` must contain a line including `couldn't find unit '_definitely_not_a_unit'`.
8. Cleanup: best-effort `sms.group("_sms_test_unit_group"):destroy()` to ensure no fixture residue. Accept either `true` (group hull still existed) or `nil` (already gone).
9. Final `echo "smoke ok"` and exit 0.

## Decisions (made autonomously, recorded for revisit)

- **Single file `framework/unit.lua`.** Same layered shape as group. ~80 lines projected.
- **`get_units()` lives in `group.lua`, not in `unit.lua` or a new `relations.lua`.** It's a method ON the group; the fact that it constructs unit handles is a dependency, not a placement signal.
- **`get_units()` returns `nil` on dead group, not `{}`.** Consistent with the framework's "log + nil on dead entity" convention. Caller writes the nil-check (`for _, u in ipairs(g:get_units() or {}) do ... end`).
- **Cross-module dependencies are documented, not enforced.** No `require`, no late-binding wrappers. Header comments in `unit.lua` and `group.lua` call out the loading order.
- **No shared handle factory.** Group spec already documented this rule; unit follows it. Revisit when the third entity module lands.
- **`get_type()` returns the raw DCS type name string.** No normalization, no enum, no localization. Matches MOOSE's `GetTypeName`.
- **Test fixture: one unit, single Soldier M4 in `_sms_test_unit_group`.** Same type as group's smoke for terrain compatibility. Multi-unit testing comes when there's a real reason (e.g., a `:get_unit_by_name()` method).
- **Smoke test loads `group.lua` before `unit.lua`** — required for the `unit:get_group()` round-trip and to match the documented loading order.
- **No callable wrapping check at handle-construction time** (e.g., "is this name actually a Unit, not a Group?"). DCS `Unit.getByName` returns `nil` for a group name; the existence check naturally rejects it. The error message "couldn't find unit 'X'" is good enough.
- **Module logger uses explicit tag `"sms.unit"`** — mirrors group/utils per the v1 limitation. Will become auto-derived once mechanism C lands per issue #2.

## Related issues

- **#2** — hook auto-injection (mechanism C). When this ships, `sms.log.module()` no-arg form will start working and `framework/unit.lua` can drop the explicit `"sms.unit"` tag.
- **#3** — bridge auto-return-prepend ergonomics. Independent of this work.

This sub-project will likely produce one new follow-up: a v1.1 issue tracking unit health/player-name additions when there's a real use case.
