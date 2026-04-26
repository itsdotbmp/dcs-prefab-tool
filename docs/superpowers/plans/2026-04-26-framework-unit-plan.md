# `sms.unit` v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `sms.unit` module — second entity wrapper in the framework, cargo-culted from `sms.group` — and add the cross-cutting `sms.group:get_units()` method, completing the deferred `get_units()` story. Verified end-to-end via a self-spawning bridge smoke test.

**Architecture:** Single new Lua file (`framework/unit.lua`) with a callable module + handle metatable, following the exact three-layer shape established in `framework/group.lua`. One small edit to `framework/group.lua` to add `get_units()` (returns array of `sms.unit` handles). Bash smoke test (`framework/test/smoke_unit.sh`) spawns its own fixture, exercises every method including the unit↔group round-trip, cleans up after itself.

**Tech Stack:** Lua 5.1 (DCS mission environment), bash (mingw on Windows), the existing `dcs-sms.exe` execution bridge, DCS's native `Unit.getByName` / `Group.getByName` / `coalition.addGroup`.

**Spec:** `docs/superpowers/specs/2026-04-26-framework-unit-design.md`

---

## File Structure

| File | Purpose |
|---|---|
| `framework/unit.lua` | The `sms.unit` module + callable + handle factory. New file. |
| `framework/group.lua` | Add `sms.group.get_units` method. Edit. |
| `framework/test/smoke_unit.sh` | Bridge-driven smoke test that self-spawns a fixture. New file. |

Existing files (`framework/sms.lua`, `framework/log.lua`, `framework/utils.lua`, `framework/timer.lua`, `framework/test/smoke.sh`, `framework/test/smoke_group.sh`, `framework/test/smoke_timer.sh`) are unchanged.

## Parallelism

Sequential. Four tasks: failing smoke test → unit module → group `get_units` method → green-light verification.

---

## Task 1: Failing smoke test (TDD red)

**Files:**
- Create: `framework/test/smoke_unit.sh`

- [ ] **Step 1: Write the smoke test**

Create `framework/test/smoke_unit.sh` with EXACTLY this content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.unit v1.
# Self-contained: spawns its own test fixture via coalition.addGroup,
# exercises all 7 sms.unit methods plus the new sms.group:get_units(),
# verifies the unit<->group round-trip, then destroys the fixture.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null

echo "==> spawn test fixture _sms_test_unit_group with unit _sms_test_unit"
# Try to derive viable spawn coords from an existing mission unit;
# fall back to {0, 0} if no existing units found.
spawn_response=$("${DCSSMS}" exec --code '
  local fixture_x, fixture_y = 0, 0
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then
          local p = units[1]:getPoint()
          fixture_x = p.x
          fixture_y = p.z
          break
        end
      end
      if fixture_x ~= 0 or fixture_y ~= 0 then break end
    end
  end

  local group_def = {
    name = "_sms_test_unit_group",
    task = "Ground Nothing",
    units = {{
      name = "_sms_test_unit",
      type = "Soldier M4",
      x = fixture_x,
      y = fixture_y,
      heading = 0,
      skill = "Average",
    }},
  }
  coalition.addGroup(country.id.USA, Group.Category.GROUND, group_def)
  return Unit.getByName("_sms_test_unit") ~= nil
')
echo "${spawn_response}"
echo "${spawn_response}" | grep -q '"return_value":true' \
  || { echo "FAIL: could not spawn _sms_test_unit"; exit 1; }

echo "==> is_alive should be true"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):is_alive()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: is_alive: ${result}"; exit 1; }

echo "==> get_name should be _sms_test_unit"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_unit"' \
  || { echo "FAIL: get_name: ${result}"; exit 1; }

echo "==> get_coalition should be blue"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_coalition()")
echo "${result}" | grep -q '"return_value":"blue"' \
  || { echo "FAIL: get_coalition: ${result}"; exit 1; }

echo "==> get_position should return a {x,y,z} table"
result=$("${DCSSMS}" exec --code '
  local p = sms.unit("_sms_test_unit"):get_position()
  return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_position: ${result}"; exit 1; }

echo "==> get_type should be Soldier M4"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_type()")
echo "${result}" | grep -q '"return_value":"Soldier M4"' \
  || { echo "FAIL: get_type: ${result}"; exit 1; }

echo "==> get_group():get_name() should be _sms_test_unit_group (unit -> group round-trip)"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_group():get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_unit_group"' \
  || { echo "FAIL: get_group round-trip: ${result}"; exit 1; }

echo "==> group:get_units() should return one handle"
result=$("${DCSSMS}" exec --code "return #sms.group(\"_sms_test_unit_group\"):get_units()")
echo "${result}" | grep -q '"return_value":1' \
  || { echo "FAIL: get_units count: ${result}"; exit 1; }

echo "==> group:get_units()[1]:get_name() should be _sms_test_unit (group -> unit round-trip)"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_unit_group\"):get_units()[1]:get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_unit"' \
  || { echo "FAIL: get_units round-trip: ${result}"; exit 1; }

echo "==> nonexistent unit should return nil"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_definitely_not_a_unit\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: nonexistent unit: ${result}"; exit 1; }

echo "==> destroy on alive unit should return true"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):destroy()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: destroy: ${result}"; exit 1; }

echo "==> after destroy, lookup should return nil"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: post-destroy: ${result}"; exit 1; }

echo "==> dcs.log should contain [sms.unit] miss line"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.unit\]' -n 200)
echo "${log_window}" | grep -q "couldn't find unit '_definitely_not_a_unit'" \
  || { echo "FAIL: missing log line for nonexistent unit"; echo "${log_window}"; exit 1; }

echo "==> cleanup: destroy parent group (best-effort)"
"${DCSSMS}" exec --code "
  local g = sms.group('_sms_test_unit_group')
  if g then g:destroy() end
" >/dev/null

echo "smoke ok"
```

- [ ] **Step 2: Make it executable and run it; expect failure**

Run:
```bash
chmod +x framework/test/smoke_unit.sh
framework/test/smoke_unit.sh
```

Expected: failure at the `==> load framework files` step on `exec --file unit.lua` because `framework/unit.lua` does not exist yet — that's the correct TDD red. The earlier steps (status, sms.lua, log.lua, group.lua) should succeed.

If failure happens at `==> hook status` because DCS isn't running or has a stale heartbeat, that's also valid red — note in the report and proceed; Task 4 will run the test for real.

If failure occurs at any earlier step (bash syntax error, dcs-sms.exe not found), STOP and report — that's a real problem.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_unit.sh
git commit -m "test: add bridge-driven smoke test for sms.unit v1"
```

---

## Task 2: Implement `framework/unit.lua`

**Files:**
- Create: `framework/unit.lua`

- [ ] **Step 1: Write the file**

Create `framework/unit.lua` with EXACTLY this content:

```lua
-- dcs-sms framework: unit module (sms.unit).
--
-- Second entity wrapper in the framework. Cargo-culted from group.lua.
--
-- sms.unit("name") returns a lightweight handle, or nil + log if the
-- unit doesn't exist in DCS. Handles are {name=name} tables with
-- __index = sms.unit, so handle:method() dispatches to sms.unit.method(handle).
--
-- All methods accept either a handle or a raw name string, normalized at
-- entry. Methods that touch DCS state internally check is_alive first;
-- if the unit is not alive, they log and return nil — they never throw.
-- _name_of also accepts garbage input (nil, numbers, ...) and returns nil,
-- which then makes is_alive return false and the standard log+nil path
-- triggers.
--
-- Loading order: framework/sms.lua -> log.lua -> group.lua -> unit.lua.
-- get_group() returns an sms.group handle, so sms.group must already be
-- loaded by the time get_group is called.
--
-- See docs/superpowers/specs/2026-04-26-framework-unit-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
local log = sms.log.module("sms.unit")
sms.unit = sms.unit or {}

-- DCS coalition int -> normalized lowercase string.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}

-- Accept either a handle ({name=...}) or a raw name string; return the name.
-- Returns nil for any other input (nil, number, boolean, table-without-name).
-- Callers handle nil names as "not alive" rather than throwing.
local function _name_of(u)
  if type(u) == "string" then return u end
  if type(u) == "table" and type(u.name) == "string" then return u.name end
  return nil
end

sms.unit.is_alive = function(u)
  local name = _name_of(u)
  if not name then return false end
  local obj = Unit.getByName(name)
  return obj ~= nil and obj:isExist()
end

sms.unit.get_name = function(u)
  return _name_of(u)
end

sms.unit.get_coalition = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local c = Unit.getByName(name):getCoalition()
  local s = _coalition_str[c]
  if not s then
    log.error("get_coalition: '" .. tostring(name) .. "' returned unknown coalition " .. tostring(c))
    return nil
  end
  return s
end

sms.unit.get_position = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_position: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local p = Unit.getByName(name):getPoint()
  -- DCS world coords: x = east, y = altitude, z = north.
  return {x = p.x, y = p.y, z = p.z}
end

sms.unit.get_type = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_type: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  return Unit.getByName(name):getTypeName()
end

sms.unit.get_group = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("get_group: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local group_name = Unit.getByName(name):getGroup():getName()
  return sms.group(group_name)
end

sms.unit.destroy = function(u)
  local name = _name_of(u)
  if not sms.unit.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  Unit.getByName(name):destroy()
  return true
end

-- Sugar constructor: sms.unit("name") -> handle | nil + log.
setmetatable(sms.unit, {
  __call = function(_, name)
    if not Unit.getByName(name) then
      log.error("couldn't find unit '" .. tostring(name) .. "'")
      return nil
    end
    return setmetatable({name = name}, {__index = sms.unit})
  end,
})
```

- [ ] **Step 2: Sanity-check the file loads via the bridge**

If DCS is running with a fresh heartbeat:
```bash
tools/dcs-sms.exe status
tools/dcs-sms.exe exec --file framework/sms.lua
tools/dcs-sms.exe exec --file framework/log.lua
tools/dcs-sms.exe exec --file framework/group.lua
tools/dcs-sms.exe exec --file framework/unit.lua
tools/dcs-sms.exe exec --code "return type(sms.unit)"
tools/dcs-sms.exe exec --code "return type(sms.unit.get_type)"
tools/dcs-sms.exe exec --code "return type(sms.unit.get_group)"
```

Expected: each `exec --file` returns `"ok":true`. The three type queries return `"return_value":"table"`, `"return_value":"function"`, `"return_value":"function"`.

If `exec --file framework/unit.lua` returns `ok:false`, read the response, fix the syntax in `framework/unit.lua`, and rerun until it loads cleanly.

If DCS is not running or heartbeat is stale, skip the sanity check. Task 4 will run the full smoke test.

- [ ] **Step 3: Commit**

```bash
git add framework/unit.lua
git commit -m "feat(framework): add sms.unit module (cargo-cult of sms.group + get_type/get_group)"
```

---

## Task 3: Add `get_units()` to `framework/group.lua`

**Files:**
- Modify: `framework/group.lua`

- [ ] **Step 1: Edit the file**

Open `framework/group.lua`. After the existing `sms.group.destroy = function(g) ... end` block (which currently ends at line 83 with `end`), and BEFORE the trailing `setmetatable(sms.group, { ... })` callable block, insert this new method.

The exact insertion: locate the line `end` that closes `sms.group.destroy`. Immediately after that line, add a blank line and then the following function definition. The result should be that `sms.group.get_units` is the last module function defined before the `setmetatable` callable.

Add EXACTLY this code:

```lua

sms.group.get_units = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_units: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local raw = Group.getByName(name):getUnits()
  local handles = {}
  for i, u in ipairs(raw or {}) do
    handles[i] = sms.unit(u:getName())
  end
  return handles
end
```

Also update the file header comment block (lines 1-15) to mention the cross-cutting requirement. Find this existing block:

```lua
-- All methods accept either a handle or a raw name string, normalized at
-- entry. Methods that touch DCS state internally check is_alive first;
-- if the group is not alive, they log and return nil — they never throw.
-- _name_of also accepts garbage input (nil, numbers, ...) and returns nil,
-- which then makes is_alive return false and the standard log+nil path
-- triggers. This protects the framework-wide "never throw" promise even
-- when callers pass bad values.
--
-- See docs/superpowers/specs/2026-04-25-framework-group-design.md.
```

Replace it with:

```lua
-- All methods accept either a handle or a raw name string, normalized at
-- entry. Methods that touch DCS state internally check is_alive first;
-- if the group is not alive, they log and return nil — they never throw.
-- _name_of also accepts garbage input (nil, numbers, ...) and returns nil,
-- which then makes is_alive return false and the standard log+nil path
-- triggers. This protects the framework-wide "never throw" promise even
-- when callers pass bad values.
--
-- get_units() returns sms.unit handles, so sms.unit must be loaded by
-- the time get_units is *called* (not at load time). Loading order:
-- framework/sms.lua -> log.lua -> group.lua -> unit.lua.
--
-- See docs/superpowers/specs/2026-04-25-framework-group-design.md.
-- See docs/superpowers/specs/2026-04-26-framework-unit-design.md (get_units).
```

- [ ] **Step 2: Sanity-check the file still loads via the bridge**

If DCS is running with a fresh heartbeat:
```bash
tools/dcs-sms.exe exec --file framework/sms.lua
tools/dcs-sms.exe exec --file framework/log.lua
tools/dcs-sms.exe exec --file framework/group.lua
tools/dcs-sms.exe exec --file framework/unit.lua
tools/dcs-sms.exe exec --code "return type(sms.group.get_units)"
```

Expected: each `exec --file` returns `"ok":true`. The type query returns `"return_value":"function"`.

If DCS is not running or heartbeat is stale, skip. Task 4 will run the full smoke test.

- [ ] **Step 3: Commit**

```bash
git add framework/group.lua
git commit -m "feat(framework): add sms.group:get_units() returning sms.unit handles"
```

---

## Task 4: Run smoke test, verify green

**Files:** none modified — verification only. May modify `framework/unit.lua`, `framework/group.lua`, or `framework/test/smoke_unit.sh` if green-light reveals issues.

- [ ] **Step 1: Confirm DCS is running and mission loaded**

Run:
```bash
tools/dcs-sms.exe status
```
Expected: `mission loaded: true` and `fresh: true`.

If `fresh: false`, ask the user to bring DCS to the foreground, then retry.
If `mission loaded: false`, ask the user to load a mission, then retry.

The smoke test does not depend on sim time advancing (no sleeps), so the mission can be paused — but the heartbeat must be fresh.

- [ ] **Step 2: Run the smoke test**

Run:
```bash
framework/test/smoke_unit.sh
```
Expected: terminates with `smoke ok` and exit 0. Every `==>` step prints with no `FAIL:` line.

Total runtime: <5 seconds wall-clock (no sleeps). All assertions are synchronous DCS calls.

- [ ] **Step 3: If green, run twice for idempotency**

Run:
```bash
framework/test/smoke_unit.sh
framework/test/smoke_unit.sh
```
Both runs should print `smoke ok` and exit 0. The cleanup step at the end of each run destroys the parent group; the next run respawns from scratch.

If both runs are green, skip to Step 5.

- [ ] **Step 4: If smoke fails, diagnose by category**

Most likely failure modes and how to address each:

**A. `exec --file unit.lua` returns ok:false.**
- The Lua file has a syntax or runtime error. Read the bridge response; the `error` field will have line info. Fix in `framework/unit.lua`. Commit fix as `fix(framework): ...`.

**B. Spawn fixture fails (`could not spawn _sms_test_unit`).**
- Most likely cause: `Soldier M4` is not a valid unit type on the user's DCS install / mod set. Try `Tank M-1A1` or `MBT_T-72B`.
- Second possibility: `coalition.addGroup` rejected `{x=0, y=0}` because it's outside the current map's bounds. The smoke script tries to derive coords from existing units first; if the mission has zero pre-existing units AND `{0,0}` is invalid, the spawn will fail. Ask the user to add at least one ME-placed unit anywhere on the map.

**C. `get_type` returns something other than `"Soldier M4"`.**
- DCS may use a slightly different display name. Run `tools/dcs-sms.exe exec --code "return Unit.getByName('_sms_test_unit'):getTypeName()"` directly to see what DCS returns. Update the assertion in `framework/test/smoke_unit.sh` to match.

**D. `get_group():get_name()` round-trip fails with nil.**
- Verify `framework/unit.lua`'s `get_group` calls `sms.group(group_name)` (the callable, not e.g. `sms.group.get_name`). The callable returns a handle; without it, you'd be calling methods on the module table itself, not on a handle.
- Also verify that `framework/group.lua` is being loaded BEFORE `framework/unit.lua` in the smoke test (the smoke test does this correctly; if you've reordered something, restore the original order).

**E. `group:get_units()` returns nil or empty array on a live group.**
- Verify `Group.getByName(name):getUnits()` returns a non-empty list directly: `tools/dcs-sms.exe exec --code "return #Group.getByName('_sms_test_unit_group'):getUnits()"`.
- If that returns 1, the bug is in `framework/group.lua`'s `get_units` — likely a typo or a stale `is_alive` check.

**F. `[sms.unit]` log line missing for the nonexistent-unit case.**
- The grep pattern is `couldn't find unit '_definitely_not_a_unit'`. The `unit.lua` module's callable should log `[sms.unit] couldn't find unit '<name>'`. Check the module logger setup at the top of `framework/unit.lua` uses `sms.log.module("sms.unit")` — exactly that string, not `"unit"` or `"sms_unit"`.
- `tools/dcs-sms.exe tail-log -n 50` (no grep) shows what *did* get logged. The error message format may differ slightly from the grep pattern.

After any fix, return to Step 2 and rerun.

- [ ] **Step 5: Final state check**

Run:
```bash
git status
git log --oneline -6
```

Expected: working tree clean; recent commits show (top is HEAD):
- one feat commit for `sms.group.get_units`
- one feat commit for `sms.unit`
- one test commit for the smoke test
- the design spec commit
- (any fix commits from Step 4 if needed)

Smoke test runs green twice in a row.

No commit needed in this task unless Step 4 required fixes.

---

## Self-Review Checklist

Before declaring done:

- [ ] `framework/unit.lua` exists and loads cleanly via `exec --file` (returns `ok:true`).
- [ ] `framework/group.lua` has `sms.group.get_units` defined and still loads cleanly.
- [ ] `framework/test/smoke_unit.sh` exists, is executable, and ends with `smoke ok` on a fresh run.
- [ ] All other framework files are unchanged (`sms.lua`, `log.lua`, `utils.lua`, `timer.lua`).
- [ ] All other smoke tests are unchanged (`smoke.sh`, `smoke_group.sh`, `smoke_timer.sh`).
- [ ] All 7 unit operations work: callable construction, `is_alive`, `get_name`, `get_coalition`, `get_position`, `get_type`, `get_group`, `destroy`.
- [ ] `sms.group.get_units` works on a live group with units, returns nil with log on a dead group.
- [ ] Round-trip in both directions: `unit:get_group():get_name()` and `group:get_units()[1]:get_name()`.
- [ ] Construction miss logs `[sms.unit] couldn't find unit '<name>'` and returns nil.
- [ ] No `error()` calls anywhere in `unit.lua` or in the new `get_units` block — every failure goes through `log.error + return nil`.
- [ ] No edits to `tools/`.
- [ ] All work committed on branch `sms-unit-v1`.
- [ ] Smoke test runs green idempotently (two runs in a row, both end with `smoke ok`).

## Out of scope (do NOT do)

- `:get_life()`, `:get_life0()`, `:get_player_name()`, `:get_velocity()`, `:in_air()`, `:get_fuel()`, `:get_ammo()`, `:has_attribute()` — defer to v1.1 or later.
- A shared `make_handle()` helper. Spec defers this until 3+ entity modules ship.
- `sms.zone`, `sms.static`, `sms.spawn`, `sms.events` — separate future iterations.
- Caching DCS userdata in handles.
- Touching `tools/`, `framework/sms.lua`, `framework/log.lua`, `framework/utils.lua`, `framework/timer.lua`, or any other smoke test.
- Creating a `make_unit()` factory exposed in some module — the callable `sms.unit(name)` is the only construction path.
- A `sms.group.find_by_unit(unit_name)` helper — unit:get_group() covers it.

## Self-review notes from plan author

**Spec coverage:**
- **`sms.unit` callable + 7 methods** (is_alive, get_name, get_coalition, get_position, get_type, get_group, destroy) → Task 2 implements all 7; Task 1 smoke test exercises each.
- **`sms.group.get_units`** returning array of unit handles → Task 3 implements; Task 1 smoke test exercises both `#get_units() == 1` and `get_units()[1]:get_name() == "_sms_test_unit"`.
- **Cross-cutting round-trip** (unit→group, group→unit) → Both directions covered by smoke test assertions in Task 1.
- **Failure model: log + nil on dead, never throw** → Every state-touching method in Task 2 calls `is_alive` first and goes through `log.error + return nil`. No `error()` calls.
- **Callable rejects missing names** → Task 2's `setmetatable(sms.unit, {__call = ...})` checks `Unit.getByName(name)` and logs + returns nil if absent. Task 1 asserts this.
- **`get_units` returns nil (not `{}`) on dead group** → Task 3's implementation logs + returns nil for dead groups. Smoke test does not exercise the dead-group case explicitly (would require destroying the group first), but the code path is straight cargo-cult of `is_alive`-guarded methods that are tested elsewhere.
- **Garbage input handled via `_name_of` returning nil** → Task 2's `_name_of` returns nil for non-string, non-handle-table inputs; downstream `is_alive` returns false; standard log+nil path triggers.
- **Module logger explicit tag `"sms.unit"`** → Task 2 uses `sms.log.module("sms.unit")`. Smoke test asserts `[sms.unit]` appears in logs.
- **Loading order documented** → Task 2's file header explicitly calls out the order. Task 3 updates `framework/group.lua`'s header to mention the unit dependency at call-time.

**Placeholder scan:** zero placeholders. All code blocks complete.

**Type consistency:**
- Handle representation: `{name = name}` with `setmetatable(..., {__index = sms.unit})` — same shape across construction (callable) and `get_units` (Task 3).
- `_name_of` signature consistent with group: handles either string or `{name=...}` table.
- `_coalition_str` shape identical to group's: `{[0]="neutral", [1]="red", [2]="blue"}`.
- All log messages use the `<method>: '<name>' no longer exists in mission` template, matching group's existing message format.
