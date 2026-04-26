# sms.events v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `sms.events` — a pub/sub bus where DCS world events are pre-registered emitters and user code can also emit custom signals — plus entity-scoped `:connect()` sugar on `sms.unit` and `sms.group`.

**Architecture:** Single-file module (`framework/events.lua`, ~200 lines) loaded last in the framework chain. One lazy-installed `world.addEventHandler` dispatches to subscriber lists. Connection handles use a metatable for `:disconnect()` / `:is_active()`. Entity sugar wraps `sms.events.connect` with an initiator-filter closure. Spec at `D:/git/dcs-sms/.worktrees/sms-events/docs/superpowers/specs/2026-04-26-framework-events-design.md`.

**Tech Stack:** Lua 5.1 (DCS mission environment), bash smoke tests driven via `tools/dcs-sms.exe exec`, runs against a live DCS instance.

**CRITICAL — worktree path discipline:** All file paths in this plan are absolute paths under the worktree at `D:/git/dcs-sms/.worktrees/sms-events/`. The implementer MUST stay inside the worktree at all times. Never edit files outside `D:/git/dcs-sms/.worktrees/sms-events/`. The bridge binary at `D:/git/dcs-sms/.worktrees/sms-events/tools/dcs-sms.exe` is the worktree-local build; use it (not the binary in the main checkout).

**CRITICAL — concurrent agents:** Another agent is working in `D:/git/dcs-sms/.worktrees/sms-static/` against the same DCS instance. Defensive measures are baked into this plan:
- Smoke test uses `_G._sms_events_smoke` (not `_G._smoke`) for global state, to avoid namespace collision.
- Live DCS subscriber filters by spawned unit name so the other agent's deaths don't trigger our assertions.
- Spawn calls rely on `sms.spawn`'s auto-suffix-on-collision behavior; capture the returned handle's resolved name and use that for cleanup.
- Never call `world.removeAllEventHandlers()` or any other global-state-clobbering operation.

---

## File Structure

| Path (absolute) | Purpose |
|---|---|
| `D:/git/dcs-sms/.worktrees/sms-events/framework/sms.lua` | **Modify** — add `sms._make_handle(module, name)` shared helper for unverified handle construction |
| `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua` | **Create** — the `sms.events` module: constants, connect/emit/disconnect/is_active, world handler, normalizer, entity sugar |
| `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh` | **Create** — end-to-end smoke test (synthetic bus + live DCS round-trip) |

No other files modified.

---

## Task 1: Add `sms._make_handle` helper to `framework/sms.lua`

**Goal:** Add a shared helper for unverified handle construction. Used in Task 4 by the events normalizer to wrap dead units into `sms.unit` handles. Also collapses one line of duplication out of `_make_callable_handle`.

**Files:**
- Modify: `D:/git/dcs-sms/.worktrees/sms-events/framework/sms.lua`

- [ ] **Step 1: Add `sms._make_handle` and refactor `_make_callable_handle` to use it**

Edit `D:/git/dcs-sms/.worktrees/sms-events/framework/sms.lua`. Replace the existing `sms._make_callable_handle` body so the inner `setmetatable(...)` line uses the new helper.

The new helper goes BEFORE `sms._make_callable_handle`. Resulting file content for the helpers section (everything after `sms.version = "0.1.0"`):

```lua
-- Build an entity handle for `name` without verifying the entity exists.
-- Used by sms._make_callable_handle (which adds the existence check) and by
-- sms.events (which needs to wrap units that have just died — Unit.getByName
-- returns nil for them, but a handle whose :is_alive() returns false and
-- whose :get_name() works from the cached name field is still useful for
-- post-mortem event reporting).
sms._make_handle = function(module, name)
  return setmetatable({name = name}, {__index = module})
end

-- Set up a callable handle factory on `module`. After this, calling
-- `module("name")` returns a {name=name} handle (or nil + log) based on
-- whether `dcs_getter(name)` returns non-nil.
--
-- The entity-type string for the log message is derived from the logger's
-- tag field by stripping the "sms." prefix (so the logger tag "sms.group"
-- yields "group" in messages like "couldn't find group 'X'").
--
-- Used by sms.group, sms.unit, and any future cargo-cult entity wrapper.
-- Modules with custom construction logic (multiple paths, snapshot data,
-- etc.) define their own callable instead — see sms.area.
sms._make_callable_handle = function(module, dcs_getter, module_log)
  local type_name = module_log.tag:match("^sms%.(.+)$") or module_log.tag
  setmetatable(module, {
    __call = function(_, name)
      if not dcs_getter(name) then
        module_log.error("couldn't find " .. type_name .. " '" .. tostring(name) .. "'")
        return nil
      end
      return sms._make_handle(module, name)
    end,
  })
end

-- Returns true iff `value` is a table whose metatable __index is `module`.
-- Used for strict handle-type validation in cross-module APIs (e.g. when
-- sms.area's is_unit_in needs to confirm the argument is a real sms.unit
-- handle, not a string or arbitrary {name=...} table).
sms._is_handle_of = function(value, module)
  if type(value) ~= "table" then return false end
  local mt = getmetatable(value)
  return (mt and mt.__index == module) or false
end
```

- [ ] **Step 2: Verify the helper works via inline exec**

From `D:/git/dcs-sms/.worktrees/sms-events/`:

```bash
./tools/dcs-sms.exe exec --file framework/sms.lua >/dev/null
./tools/dcs-sms.exe exec --code 'local h = sms._make_handle({foo = function(self) return "bar" end}, "x"); return h.name == "x" and h:foo() == "bar"'
```

Expected: the second command outputs `"return_value":true`.

- [ ] **Step 3: Verify `sms.unit` still works (regression check on `_make_callable_handle` refactor)**

```bash
./tools/dcs-sms.exe exec --file framework/sms.lua >/dev/null
./tools/dcs-sms.exe exec --file framework/log.lua >/dev/null
./tools/dcs-sms.exe exec --file framework/group.lua >/dev/null
./tools/dcs-sms.exe exec --file framework/unit.lua >/dev/null
./tools/dcs-sms.exe exec --code 'local u = sms.unit("nonexistent_unit_xyz"); return u == nil'
```

Expected: `"return_value":true` (unit lookup returns nil for missing names, log line in dcs.log).

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
git add framework/sms.lua
git commit -m "$(cat <<'EOF'
feat(framework): add sms._make_handle helper for unverified construction

Used by sms.events to wrap units that have just died (Unit.getByName
returns nil for them but a handle with cached name is still useful for
post-mortem event reporting). _make_callable_handle delegates to it.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: clean commit, working tree clean.

---

## Task 2: Create `framework/events.lua` skeleton with constants + smoke test skeleton

**Goal:** Bootstrap both files together. `events.lua` exposes constants only at this stage (no functions yet). `smoke_events.sh` loads the full framework chain and spot-checks constants. Establishes the file scaffolding everything else builds on.

**Files:**
- Create: `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua`
- Create: `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh`

- [ ] **Step 1: Write `framework/events.lua` skeleton (constants only)**

Create `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua` with this exact content:

```lua
-- dcs-sms framework: events module (sms.events).
--
-- Pub/sub bus where DCS world events are pre-registered emitters and user
-- mission code can also emit custom signals. Wraps DCS's single-handler
-- world.addEventHandler API so multiple subscribers can listen to specific
-- event types independently.
--
-- API:
--   sms.events.<NAME>                          -> string constant for every world.event.S_EVENT_<NAME>
--   sms.events.connect(name, fn)               -> Connection handle | nil + log
--   sms.events.emit(name, ...)                 -> nil (verbatim args to subscribers)
--   sms.events.disconnect(conn)                -> bool (idempotent)
--   sms.events.is_active(conn)                 -> bool (silent probe)
--
-- Entity sugar on existing modules:
--   u:connect(name, fn)                        -> Connection | nil + log
--   g:connect(name, fn)                        -> Connection | nil + log
--
-- DCS event payload is normalized into {name, id, time, initiator, target,
-- weapon_type, place_name}. initiator/target are sms.unit handles (returned
-- even for dead units; :is_alive() returns false). User-emitted signals
-- pass args verbatim.
--
-- Loading order: framework/sms.lua -> log.lua -> utils.lua -> group.lua ->
-- unit.lua -> area.lua -> timer.lua -> spawn.lua -> events.lua. Entity
-- sugar requires sms.unit and sms.group to already exist.
--
-- See docs/superpowers/specs/2026-04-26-framework-events-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.unit) == "table", "framework/unit.lua must be loaded first")
assert(type(sms.group) == "table", "framework/group.lua must be loaded first")
local log = sms.log.module("sms.events")
sms.events = sms.events or {}

-- Module-level state (file-local).
local _subscribers = {}                 -- _subscribers[name] = { conn, conn, ... }
local _world_handler_installed = false  -- one-shot guard
local _id_to_name = {}                  -- numeric DCS id -> friendly string

-- Build constants from world.event. For each S_EVENT_FOO with value N,
-- defines sms.events.FOO = "foo" and _id_to_name[N] = "foo". Auto-derives
-- new events when DCS patches add them (they default to non-entity-scoped,
-- which the entity sugar in this module rejects safely).
for k, v in pairs(world.event) do
  if type(k) == "string" and k:match("^S_EVENT_") then
    local short = k:gsub("^S_EVENT_", "")
    local lname = short:lower()
    sms.events[short] = lname
    _id_to_name[v] = lname
  end
end
```

- [ ] **Step 2: Write `framework/test/smoke_events.sh` skeleton**

Create `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh` with this exact content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.events v1.
# Hybrid: most assertions are synthetic via sms.events.emit (fast, no DCS
# sleeps). One live-DCS section spawns + destroys a unit to verify the
# world-handler round-trip.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.
#
# Defensive vs. concurrent agents in the same DCS instance:
# - global state in _G._sms_events_smoke (not _G._smoke)
# - live DCS subscribers filter by our unit name so other agents' deaths
#   don't trigger our assertions
# - spawn names rely on sms.spawn's auto-suffix-on-collision; we capture
#   the returned name for cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

# Helpers: assert that a bridge exec returned a true / specific value.
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

expect_str() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected '${expected}'): ${result}"; exit 1; }
}

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file utils.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null
"${DCSSMS}" exec --file area.lua >/dev/null
"${DCSSMS}" exec --file timer.lua >/dev/null
"${DCSSMS}" exec --file spawn.lua >/dev/null
"${DCSSMS}" exec --file events.lua >/dev/null

echo "==> constants exist"
expect_str "DEAD constant"          'return sms.events.DEAD'           'dead'
expect_str "BIRTH constant"         'return sms.events.BIRTH'          'birth'
expect_str "PILOT_DEAD constant"    'return sms.events.PILOT_DEAD'     'pilot_dead'
expect_str "MISSION_START constant" 'return sms.events.MISSION_START'  'mission_start'
expect_str "TAKEOFF constant"       'return sms.events.TAKEOFF'        'takeoff'

echo "smoke ok"
```

- [ ] **Step 3: Make smoke executable and run it**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
chmod +x framework/test/smoke_events.sh
framework/test/smoke_events.sh
```

Expected: ends with `smoke ok` and exits 0. If `dcs-sms.exe status` reports `fresh: false` or `mission loaded: false`, the test will fail at that line — pause and ask the user to focus DCS or unpause.

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
git add framework/events.lua framework/test/smoke_events.sh
git commit -m "$(cat <<'EOF'
feat(framework): scaffold sms.events with auto-derived constants

events.lua exposes sms.events.<NAME> for every world.event.S_EVENT_<NAME>
(DEAD, BIRTH, PILOT_DEAD, etc.), derived at module load from world.event.
No subscribe/emit functions yet — those land in the next commit.
smoke_events.sh covers status check, framework load, constants spot-check.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Implement `connect`, `emit`, `disconnect`, `is_active` (synthetic bus)

**Goal:** Add the four core module functions and the Connection handle metatable. Dispatch is `pcall`-wrapped and snapshot-protected against mid-iteration disconnects from the start. World handler install is deferred to Task 4 (DCS-side path) — `connect()` does NOT yet install the world handler. Smoke covers all synthetic bus behavior.

**Files:**
- Modify: `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua`
- Modify: `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh`

- [ ] **Step 1: Extend `framework/events.lua` with the four functions and Connection metatable**

Append to `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua` (after the constants block from Task 2):

```lua
-- Connection handle metatable. __index points at sms.events so
-- conn:disconnect() dispatches to sms.events.disconnect(conn). Identity-
-- checked in disconnect/is_active so callers can't slip arbitrary tables in.
local _conn_mt = {__index = sms.events}

local function _is_connection(c)
  return type(c) == "table" and getmetatable(c) == _conn_mt
end

-- Lazy world-handler install. Stub for Task 3 (synthetic-only); real
-- world.addEventHandler call lands in Task 4.
local function _ensure_world_handler()
  -- Implementation in Task 4. For now this is a no-op so connect() works
  -- for the synthetic emit() path without needing live DCS.
end

sms.events.connect = function(name, fn)
  if type(name) ~= "string" then
    log.error("connect: name must be a string, got " .. type(name))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("connect: fn must be a function, got " .. type(fn))
    return nil
  end
  _ensure_world_handler()
  local conn = setmetatable({name = name, fn = fn, active = true}, _conn_mt)
  _subscribers[name] = _subscribers[name] or {}
  table.insert(_subscribers[name], conn)
  return conn
end

sms.events.emit = function(name, ...)
  if type(name) ~= "string" then
    log.error("emit: name must be a string, got " .. type(name))
    return
  end
  local subs = _subscribers[name]
  if not subs then return end
  -- Snapshot so a subscriber that disconnects mid-dispatch doesn't mutate
  -- the iteration. Subscribers added during dispatch are NOT seen by the
  -- in-flight emit (Godot semantics: connect-during-emit takes effect on
  -- the next emit).
  local snapshot = {}
  for i, c in ipairs(subs) do snapshot[i] = c end
  for _, conn in ipairs(snapshot) do
    if conn.active then
      local ok, err = pcall(conn.fn, ...)
      if not ok then
        log.error("subscriber for '" .. name .. "' raised: " .. tostring(err))
      end
    end
  end
end

sms.events.disconnect = function(conn)
  if not _is_connection(conn) then
    log.error("disconnect: argument must be a Connection handle")
    return false
  end
  if not conn.active then return false end
  conn.active = false
  local subs = _subscribers[conn.name]
  if subs then
    for i, c in ipairs(subs) do
      if c == conn then
        table.remove(subs, i)
        break
      end
    end
  end
  return true
end

sms.events.is_active = function(conn)
  if not _is_connection(conn) then return false end
  return conn.active == true
end
```

- [ ] **Step 2: Extend `framework/test/smoke_events.sh` with synthetic test sections**

Insert these sections in `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh` BEFORE the final `echo "smoke ok"` line:

```bash
echo "==> bad-arg validation"
expect_true "connect: nil name returns nil" \
  'return sms.events.connect(nil, function() end) == nil'
expect_true "connect: non-function fn returns nil" \
  'return sms.events.connect("foo", "not a function") == nil'
expect_true "disconnect: non-connection returns false" \
  'return sms.events.disconnect("garbage") == false'
expect_true "is_active: non-connection returns false silently" \
  'return sms.events.is_active("garbage") == false'

echo "==> basic synthetic dispatch"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {fired = 0, last = nil}
  _G._sms_events_smoke.conn = sms.events.connect("test_signal", function(x)
    _G._sms_events_smoke.fired = _G._sms_events_smoke.fired + 1
    _G._sms_events_smoke.last = x
  end)
' >/dev/null
expect_true "connect returns a Connection handle" \
  'return type(_G._sms_events_smoke.conn) == "table" and _G._sms_events_smoke.conn:is_active()'
"${DCSSMS}" exec --code 'sms.events.emit("test_signal", "hello")' >/dev/null
expect_eq "emit fires subscriber once" \
  'return _G._sms_events_smoke.fired' 1
expect_str "subscriber sees the emitted arg" \
  'return _G._sms_events_smoke.last' 'hello'

echo "==> multi-subscriber dispatch order"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {order = {}}
  for i = 1, 3 do
    local n = i
    sms.events.connect("order_test", function() table.insert(_G._sms_events_smoke.order, n) end)
  end
  sms.events.emit("order_test")
' >/dev/null
expect_true "subscribers fire in connection order" \
  'local o = _G._sms_events_smoke.order; return #o == 3 and o[1] == 1 and o[2] == 2 and o[3] == 3'

echo "==> verbatim multi-arg pass-through"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {}
  sms.events.connect("multi", function(a, b, c)
    _G._sms_events_smoke.a = a
    _G._sms_events_smoke.b = b
    _G._sms_events_smoke.c = c
  end)
  sms.events.emit("multi", 1, "two", true)
' >/dev/null
expect_eq   "multi-arg: first arg"  'return _G._sms_events_smoke.a' 1
expect_str  "multi-arg: second arg" 'return _G._sms_events_smoke.b' 'two'
expect_true "multi-arg: third arg"  'return _G._sms_events_smoke.c == true'

echo "==> idempotent disconnect"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {fired = 0}
  _G._sms_events_smoke.conn = sms.events.connect("idem", function() _G._sms_events_smoke.fired = _G._sms_events_smoke.fired + 1 end)
' >/dev/null
expect_true "first disconnect returns true"  'return _G._sms_events_smoke.conn:disconnect() == true'
expect_true "second disconnect returns false" 'return _G._sms_events_smoke.conn:disconnect() == false'
expect_true "disconnected conn is not active" 'return _G._sms_events_smoke.conn:is_active() == false'
"${DCSSMS}" exec --code 'sms.events.emit("idem")' >/dev/null
expect_eq "disconnected subscriber does not fire" 'return _G._sms_events_smoke.fired' 0

echo "==> mid-dispatch disconnect is safe"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {a = 0, b = 0, conn_b = nil}
  sms.events.connect("midcancel", function()
    _G._sms_events_smoke.a = _G._sms_events_smoke.a + 1
    _G._sms_events_smoke.conn_b:disconnect()
  end)
  _G._sms_events_smoke.conn_b = sms.events.connect("midcancel", function()
    _G._sms_events_smoke.b = _G._sms_events_smoke.b + 1
  end)
  sms.events.emit("midcancel")
' >/dev/null
expect_eq "first sub fired (snapshot intact)" 'return _G._sms_events_smoke.a' 1
expect_eq "second sub still fired this dispatch (snapshot)" 'return _G._sms_events_smoke.b' 1
"${DCSSMS}" exec --code 'sms.events.emit("midcancel")' >/dev/null
expect_eq "first sub fires again next dispatch" 'return _G._sms_events_smoke.a' 2
expect_eq "second sub stays disconnected" 'return _G._sms_events_smoke.b' 1

echo "==> subscriber error does not break dispatch"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {good = 0}
  sms.events.connect("err_test", function() error("boom") end)
  sms.events.connect("err_test", function() _G._sms_events_smoke.good = _G._sms_events_smoke.good + 1 end)
  sms.events.emit("err_test")
' >/dev/null
expect_eq "good subscriber fires after bad one raised" 'return _G._sms_events_smoke.good' 1
```

**Note on the mid-dispatch test (`midcancel`):** Per Godot snapshot semantics, the second subscriber DOES fire during the dispatch in which it was disconnected (because the snapshot was taken before the first subscriber's disconnect ran). It only stops firing on subsequent dispatches. This is asserted explicitly above.

- [ ] **Step 3: Run smoke**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
framework/test/smoke_events.sh
```

Expected: ends with `smoke ok` and exits 0. Tail `dcs.log` for `[sms.events]` lines if anything fails.

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
git add framework/events.lua framework/test/smoke_events.sh
git commit -m "$(cat <<'EOF'
feat(framework): sms.events synthetic bus (connect/emit/disconnect)

Four core module functions plus Connection metatable. Dispatch is
pcall-wrapped (subscriber errors don't break the loop) and snapshot-
protected (mid-dispatch disconnects don't mutate iteration). Mirrors
sms.timer's idempotent-stop pattern. World-handler install is a stub
for now — the live DCS path lands in the next commit.

Smoke covers: bad-arg validation, basic dispatch, multi-sub order,
verbatim multi-arg, idempotent disconnect, mid-dispatch safety,
subscriber error containment.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: World handler install + `_normalize_event` + live DCS round-trip

**Goal:** Wire DCS world events into the bus. Lazy install on first `connect()`. `_normalize_event` builds the `evt` payload with `pcall`-wrapped DCS calls. Add a live smoke section that spawns a unit, subscribes to DEAD, destroys the unit, and asserts the event flowed through.

**Files:**
- Modify: `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua`
- Modify: `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh`

- [ ] **Step 1: Add `_normalize_event` and replace `_ensure_world_handler` stub in `events.lua`**

In `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua`, replace the stub `_ensure_world_handler` (defined in Task 3) with a real implementation, and add `_normalize_event` immediately above it. The stub to remove:

```lua
local function _ensure_world_handler()
  -- Implementation in Task 4. For now this is a no-op so connect() works
  -- for the synthetic emit() path without needing live DCS.
end
```

Replace with:

```lua
-- Build the user-facing evt payload from a raw DCS world event. Every
-- DCS-side method call is pcall-wrapped because half-deconstructed
-- unit/weapon/place objects are a real failure mode in DCS during
-- destruction events. A field that fails to extract just stays nil; the
-- rest of the event still dispatches.
local function _normalize_event(raw)
  local evt = {
    id   = raw.id,
    name = _id_to_name[raw.id] or ("unknown_" .. tostring(raw.id)),
    time = raw.time,
  }
  if raw.initiator then
    local ok, n = pcall(raw.initiator.getName, raw.initiator)
    if ok and n then evt.initiator = sms._make_handle(sms.unit, n) end
  end
  if raw.target then
    local ok, n = pcall(raw.target.getName, raw.target)
    if ok and n then evt.target = sms._make_handle(sms.unit, n) end
  end
  if raw.weapon then
    local ok, t = pcall(raw.weapon.getTypeName, raw.weapon)
    if ok and t then evt.weapon_type = t end
  end
  if raw.place then
    local ok, p = pcall(raw.place.getName, raw.place)
    if ok and p then evt.place_name = p end
  end
  return evt
end

-- Lazy world-handler install. Called from connect(). One install for the
-- lifetime of the mission load; no teardown API.
local function _ensure_world_handler()
  if _world_handler_installed then return end
  _world_handler_installed = true
  world.addEventHandler({
    onEvent = function(self, raw)
      local evt = _normalize_event(raw)
      local subs = _subscribers[evt.name]
      if not subs then return end
      local snapshot = {}
      for i, c in ipairs(subs) do snapshot[i] = c end
      for _, conn in ipairs(snapshot) do
        if conn.active then
          local ok, err = pcall(conn.fn, evt)
          if not ok then
            log.error("dispatch '" .. evt.name .. "': " .. tostring(err))
          end
        end
      end
    end,
  })
end
```

- [ ] **Step 2: Add live DCS round-trip section to smoke**

Insert this section in `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh` BEFORE the final `echo "smoke ok"` line:

```bash
echo "==> live DCS round-trip — DEAD event"
# Re-check heartbeat freshness — this section needs sim time to advance.
"${DCSSMS}" status | grep -q "fresh: *true" \
  || { echo "FAIL: live DCS section requires fresh heartbeat (mission unpaused). Skip or focus DCS."; exit 1; }

# Spawn a single-unit ground group, capture the resolved name (sms.spawn
# auto-suffixes on collision so concurrent agents don't break us).
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {dead_evt = nil, target_name = nil}
  local g = sms.group.create({
    name = "smoke_evt_target",
    position = {x = 0, y = 0, z = 0},
    country = "USA",
    category = "ground",
    units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
  })
  if g then
    _G._sms_events_smoke.target_name = g:get_units()[1]:get_name()
  end
' >/dev/null
expect_true "spawned target unit captured" \
  'return type(_G._sms_events_smoke.target_name) == "string" and _G._sms_events_smoke.target_name ~= ""'

# Subscribe to DEAD, but only record the event if it matches OUR target
# (defensive — other agents may also be killing units in this DCS instance).
"${DCSSMS}" exec --code '
  sms.events.connect(sms.events.DEAD, function(evt)
    if evt.initiator and evt.initiator.name == _G._sms_events_smoke.target_name then
      _G._sms_events_smoke.dead_evt = evt
    end
  end)
' >/dev/null

# Destroy the unit (this fires S_EVENT_DEAD).
"${DCSSMS}" exec --code '
  local u = Unit.getByName(_G._sms_events_smoke.target_name)
  if u then u:destroy() end
' >/dev/null

# Wait for sim time to deliver the event.
sleep 2

expect_true "DEAD event received" \
  'return _G._sms_events_smoke.dead_evt ~= nil'
expect_str "DEAD event has correct name" \
  'return _G._sms_events_smoke.dead_evt.name' 'dead'
expect_true "DEAD event initiator is an sms.unit handle" \
  'return type(_G._sms_events_smoke.dead_evt.initiator) == "table" and type(_G._sms_events_smoke.dead_evt.initiator.get_name) == "function"'
expect_true "DEAD event initiator name matches our target" \
  'return _G._sms_events_smoke.dead_evt.initiator.name == _G._sms_events_smoke.target_name'
expect_true "DEAD event initiator is no longer alive" \
  'return _G._sms_events_smoke.dead_evt.initiator:is_alive() == false'
expect_true "DEAD event time is a positive number" \
  'return type(_G._sms_events_smoke.dead_evt.time) == "number" and _G._sms_events_smoke.dead_evt.time > 0'
```

- [ ] **Step 3: Run smoke**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
framework/test/smoke_events.sh
```

Expected: ends with `smoke ok` and exits 0. The live section needs DCS unpaused — if it fails at the heartbeat re-check, ask the user to focus DCS.

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
git add framework/events.lua framework/test/smoke_events.sh
git commit -m "$(cat <<'EOF'
feat(framework): sms.events DCS world handler + payload normalization

connect() now lazy-installs world.addEventHandler on first call. DCS raw
events are normalized into {id, name, time, initiator, target,
weapon_type, place_name}; initiator/target wrapped as sms.unit handles
even for dead units (cached name, is_alive() returns false). Every DCS-
side method call is pcall-wrapped against half-deconstructed objects.

Smoke gains a live DCS round-trip: spawn a tank, subscribe to DEAD,
destroy it, assert the normalized payload. Subscriber filters by our
unit name to ignore concurrent agents' deaths in the same DCS instance.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Entity sugar — `sms.unit.connect` + `sms.group.connect`

**Goal:** Add `:connect(name, fn)` to `sms.unit` and `sms.group`. Both filter on initiator (unit-level: name match; group-level: initiator's group matches). Both reject events that have no entity scope (e.g., `MISSION_START`) at connect time.

**Files:**
- Modify: `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua`
- Modify: `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh`

- [ ] **Step 1: Add `_entity_scoped` whitelist and entity sugar to `events.lua`**

Append to `D:/git/dcs-sms/.worktrees/sms-events/framework/events.lua` (after the existing module functions):

```lua
-- Whitelist of event names with a meaningful .initiator field. Entity
-- sugar (u:connect / g:connect) rejects everything else at connect time
-- so users get a clear error instead of silent never-fires. Hand-
-- maintained — new DCS events default to non-entity-scoped (safe).
local _entity_scoped = {
  birth              = true,
  dead               = true,
  hit                = true,
  kill               = true,
  takeoff            = true,
  land               = true,
  crash              = true,
  ejection           = true,
  pilot_dead         = true,
  shot               = true,
  engine_startup     = true,
  engine_shutdown    = true,
  refueling          = true,
  refueling_stop     = true,
  player_enter_unit  = true,
  player_leave_unit  = true,
  human_failure      = true,
  unit_lost          = true,
  shooting_start     = true,
  shooting_end       = true,
  landing_quality_mark = true,
  landing_after_ejection = true,
  emergency_landing  = true,
}

-- u:connect(name, fn) — fires only when evt.initiator.name == self.name.
-- Returns the wrapped Connection (so :disconnect() works as expected).
sms.unit.connect = function(self, name, fn)
  if type(self) ~= "table" or type(self.name) ~= "string" then
    log.error("unit:connect: self must be an sms.unit handle")
    return nil
  end
  if type(name) ~= "string" then
    log.error("unit:connect: event name must be a string, got " .. type(name))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("unit:connect: fn must be a function, got " .. type(fn))
    return nil
  end
  if not _entity_scoped[name] then
    log.error("unit:connect: event '" .. name .. "' has no entity scope")
    return nil
  end
  local target_name = self.name
  return sms.events.connect(name, function(evt)
    if evt.initiator and evt.initiator.name == target_name then
      fn(evt)
    end
  end)
end

-- g:connect(name, fn) — fires per-unit-death (etc.) for any unit whose
-- group is this group. A 4-vehicle group losing all units fires the
-- callback 4 times. Users compose "fully dead" via
-- evt.initiator:get_group():is_alive() inside the callback.
sms.group.connect = function(self, name, fn)
  if type(self) ~= "table" or type(self.name) ~= "string" then
    log.error("group:connect: self must be an sms.group handle")
    return nil
  end
  if type(name) ~= "string" then
    log.error("group:connect: event name must be a string, got " .. type(name))
    return nil
  end
  if type(fn) ~= "function" then
    log.error("group:connect: fn must be a function, got " .. type(fn))
    return nil
  end
  if not _entity_scoped[name] then
    log.error("group:connect: event '" .. name .. "' has no entity scope")
    return nil
  end
  local target_name = self.name
  return sms.events.connect(name, function(evt)
    if evt.initiator then
      local g = evt.initiator:get_group()
      if g and g.name == target_name then
        fn(evt)
      end
    end
  end)
end
```

- [ ] **Step 2: Add entity sugar smoke sections**

Insert this section in `D:/git/dcs-sms/.worktrees/sms-events/framework/test/smoke_events.sh` BEFORE the final `echo "smoke ok"` line:

```bash
echo "==> entity sugar — non-entity event rejected"
# Spawn a throwaway group just to get a real handle.
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {}
  _G._sms_events_smoke.g = sms.group.create({
    name = "smoke_evt_sugar_grp",
    position = {x = 1000, y = 0, z = 0},
    country = "USA",
    category = "ground",
    units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
  })
' >/dev/null
expect_true "g:connect on MISSION_START rejected (returns nil)" \
  'return _G._sms_events_smoke.g:connect(sms.events.MISSION_START, function() end) == nil'
expect_true "u:connect on MISSION_START rejected (returns nil)" \
  'local u = _G._sms_events_smoke.g:get_units()[1]; return u:connect(sms.events.MISSION_START, function() end) == nil'

echo "==> entity sugar — initiator filter (synthetic via emit)"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke.matched = 0
  _G._sms_events_smoke.unmatched = 0
  local target = _G._sms_events_smoke.g:get_units()[1]
  target:connect(sms.events.DEAD, function(evt) _G._sms_events_smoke.matched = _G._sms_events_smoke.matched + 1 end)
  -- Synthetic emit with matching initiator.
  sms.events.emit("dead", {
    name = "dead",
    initiator = sms._make_handle(sms.unit, target.name),
  })
  -- Synthetic emit with non-matching initiator.
  sms.events.emit("dead", {
    name = "dead",
    initiator = sms._make_handle(sms.unit, "definitely_not_our_unit_xyz"),
  })
' >/dev/null
expect_eq "u:connect fires only for matching initiator" \
  'return _G._sms_events_smoke.matched' 1

echo "==> entity sugar — group filter (synthetic via emit, requires get_group)"
# Note: this test exercises g:connect's filter via real DCS .get_group()
# call, which requires the unit to still be alive. We use the live group
# spawned above (still alive — only the previous round-trip target was
# destroyed).
"${DCSSMS}" exec --code '
  _G._sms_events_smoke.gmatched = 0
  _G._sms_events_smoke.g:connect(sms.events.DEAD, function(evt) _G._sms_events_smoke.gmatched = _G._sms_events_smoke.gmatched + 1 end)
  local our_unit = _G._sms_events_smoke.g:get_units()[1]
  -- Synthetic dispatch with a real (alive) initiator from our group.
  sms.events.emit("dead", {
    name = "dead",
    initiator = sms._make_handle(sms.unit, our_unit.name),
  })
' >/dev/null
expect_eq "g:connect fires for unit in our group" \
  'return _G._sms_events_smoke.gmatched' 1
```

- [ ] **Step 3: Run smoke**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
framework/test/smoke_events.sh
```

Expected: ends with `smoke ok` and exits 0.

- [ ] **Step 4: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/sms-events
git add framework/events.lua framework/test/smoke_events.sh
git commit -m "$(cat <<'EOF'
feat(framework): sms.events entity sugar (u:connect, g:connect)

Adds :connect(name, fn) to sms.unit and sms.group. Filter is initiator-
based: u:connect fires when evt.initiator.name == self.name; g:connect
fires per-unit-death within the group (4-unit group losing all 4 fires
4 times). Both reject (log + nil) at connect time for events that have
no entity scope (MISSION_START, BASE_CAPTURED, etc.) — fail loud rather
than silently never fire.

Hand-maintained _entity_scoped whitelist; new DCS events default to
non-entity-scoped (safe). Smoke covers rejection path and both filters.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Checklist (run after writing the plan)

**1. Spec coverage:**
- ✅ `sms.events.connect/emit/disconnect/is_active` — Task 3
- ✅ ALL_CAPS constants auto-derived from `world.event` — Task 2
- ✅ Connection metatable + identity check — Task 3
- ✅ Snapshot-on-dispatch (mid-dispatch disconnect safety) — Task 3
- ✅ pcall around subscriber calls (error containment) — Task 3
- ✅ Verbatim multi-arg dispatch for user emits — Task 3
- ✅ Idempotent `disconnect` (true once / false thereafter) — Task 3
- ✅ Lazy world handler install — Task 4
- ✅ `_normalize_event` with pcall around DCS calls — Task 4
- ✅ `evt.initiator` / `evt.target` as `sms.unit` handles even when dead — Task 4 (uses `sms._make_handle` from Task 1)
- ✅ `evt.weapon_type` / `evt.place_name` stringification — Task 4 (in `_normalize_event`)
- ✅ Entity sugar `u:connect` (initiator name match) — Task 5
- ✅ Entity sugar `g:connect` (initiator's group match) — Task 5
- ✅ `_entity_scoped` whitelist + rejection at connect time — Task 5
- ✅ `sms._make_handle` shared helper — Task 1
- ✅ Smoke test file `smoke_events.sh` covering all behaviors — Task 2 + extensions in Tasks 3, 4, 5

**2. Placeholder scan:** No "TBD", "TODO", "fill in details", "similar to", or "implement appropriate X" in any task. Every code block contains complete, runnable code.

**3. Type consistency:**
- `_subscribers[name]` is always an array of Connection tables.
- Connection shape `{name=string, fn=function, active=bool}` is consistent across `connect`, `emit`, `disconnect`, `is_active`, and dispatch.
- `_id_to_name[number]` → string.
- `_entity_scoped[string]` → bool.
- `evt` payload shape stable across normalize and entity sugar (`evt.name`, `evt.initiator.name` are accessed in both).
- `sms._make_handle(module, name)` signature matches usage in `_normalize_event` and the entity sugar synthetic test.

**4. Concurrent-agent defensiveness:**
- Global state in `_G._sms_events_smoke` (not `_G._smoke`).
- Live DCS subscriber filters by `target_name` so other agents' deaths are ignored.
- Spawn relies on `sms.spawn` auto-suffix; resolved name captured via `g:get_units()[1]:get_name()`.

**5. Worktree path discipline:** Every Edit/Write/Read in the plan uses `D:/git/dcs-sms/.worktrees/sms-events/` absolute prefix. Bash steps `cd` into the worktree before running.

No issues found.
