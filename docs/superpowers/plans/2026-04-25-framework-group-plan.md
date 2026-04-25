# `sms.group` v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `sms.group` module — the first entity abstraction in the dcs-sms framework — establishing a handle-over-module pattern with a graceful failure model, verified end-to-end through the bridge.

**Architecture:** Single Lua file (`framework/group.lua`) with three layers: module functions (the underlying API), a `__call` metamethod on the module table for sugar construction (`sms.group("name")`), and lightweight handles (`{name=...}` tables with `__index = sms.group`). All three call shapes (`g:method()`, `sms.group.method(g)`, `sms.group.method("name")`) are equivalent. A separate self-spawning bash smoke test (`framework/test/smoke_group.sh`) drives the bridge to assert behavior end-to-end.

**Tech Stack:** Lua 5.1 (DCS mission environment), bash (mingw on Windows), the existing `dcs-sms.exe` execution bridge.

**Spec:** `docs/superpowers/specs/2026-04-25-framework-group-design.md`

---

## File Structure

| File | Purpose |
|---|---|
| `framework/group.lua` | The Group module + handle factory. New file. |
| `framework/test/smoke_group.sh` | Self-spawning, hermetic smoke test driving the bridge. New file. |

The existing `framework/test/smoke.sh` (logger + utils smoke test) is **unchanged**. Each module gets its own focused smoke test.

## Parallelism

This plan is sequential. Three tasks: failing test → implementation → green verification. Implementation is one Lua file (~70 lines); no value in further decomposition.

---

## Task 1: Failing smoke test (TDD red)

**Files:**
- Create: `framework/test/smoke_group.sh`

- [ ] **Step 1: Write the smoke test**

Create `framework/test/smoke_group.sh` with EXACTLY this content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.group v1.
# Self-contained: spawns its own test fixture via coalition.addGroup,
# exercises all 5 group methods, destroys the fixture.
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

echo "==> spawn test fixture _sms_test_group"
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
    name = "_sms_test_group",
    task = "Ground Nothing",
    units = {{
      name = "_sms_test_unit_1",
      type = "Soldier M4",
      x = fixture_x,
      y = fixture_y,
      heading = 0,
      skill = "Average",
    }},
  }
  coalition.addGroup(country.id.USA, Group.Category.GROUND, group_def)
  return Group.getByName("_sms_test_group") ~= nil
')
echo "${spawn_response}"
echo "${spawn_response}" | grep -q '"return_value":true' \
  || { echo "FAIL: could not spawn _sms_test_group"; exit 1; }

echo "==> is_alive should be true"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):is_alive()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: is_alive: ${result}"; exit 1; }

echo "==> get_name should be _sms_test_group"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_group"' \
  || { echo "FAIL: get_name: ${result}"; exit 1; }

echo "==> get_coalition should be blue"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):get_coalition()")
echo "${result}" | grep -q '"return_value":"blue"' \
  || { echo "FAIL: get_coalition: ${result}"; exit 1; }

echo "==> get_position should return a {x,y,z} table"
result=$("${DCSSMS}" exec --code '
  local p = sms.group("_sms_test_group"):get_position()
  return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_position: ${result}"; exit 1; }

echo "==> nonexistent group should return nil"
result=$("${DCSSMS}" exec --code "return sms.group(\"_definitely_does_not_exist\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: nonexistent: ${result}"; exit 1; }

echo "==> destroy on alive group should return true"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):destroy()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: destroy: ${result}"; exit 1; }

echo "==> after destroy, lookup should return nil"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: post-destroy: ${result}"; exit 1; }

echo "==> dcs.log should contain [sms.group] miss line"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.group\]' -n 200)
echo "${log_window}" | grep -q "couldn't find '_definitely_does_not_exist'" \
  || { echo "FAIL: missing log line for nonexistent group"; echo "${log_window}"; exit 1; }

echo "smoke ok"
```

- [ ] **Step 2: Make it executable and run it; expect failure**

Run:
```bash
chmod +x framework/test/smoke_group.sh
framework/test/smoke_group.sh
```

Expected: failure at the `==> load framework files` step on `exec --file group.lua` (file does not exist) — that's the correct TDD red. The first three steps (hook status, load sms.lua, load log.lua) should succeed.

If failure occurs at `==> hook status` because DCS isn't running, that is also valid red — note in the report and proceed; Task 3 will run the test for real.

If failure occurs anywhere unexpected (bash syntax error, dcs-sms.exe not found, etc.), STOP and report — that's not red-light TDD, that's a real problem.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_group.sh
git commit -m "test: add bridge-driven smoke test for sms.group v1"
```

---

## Task 2: Implement `framework/group.lua`

**Files:**
- Create: `framework/group.lua`

- [ ] **Step 1: Write the file**

Create `framework/group.lua` with EXACTLY this content:

```lua
-- dcs-sms framework: group module (sms.group).
--
-- sms.group("name") returns a lightweight handle, or nil + log if the
-- group doesn't exist in DCS. Handles are {name=name} tables with
-- __index = sms.group, so handle:method() dispatches to sms.group.method(handle).
--
-- All methods accept either a handle or a raw name string, normalized at
-- entry. Methods other than is_alive internally check is_alive first; if
-- the group is not alive, they log and return nil — they never throw.
--
-- See docs/superpowers/specs/2026-04-25-framework-group-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
local log = sms.log.module("sms.group")
sms.group = sms.group or {}

-- DCS coalition int -> normalized lowercase string.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}

-- Accept either a handle ({name=...}) or a raw name string; return the name.
local function _name_of(g)
  return type(g) == "string" and g or g.name
end

sms.group.is_alive = function(g)
  local name = _name_of(g)
  local obj = Group.getByName(name)
  return obj ~= nil and obj:isExist()
end

sms.group.get_name = function(g)
  return _name_of(g)
end

sms.group.get_coalition = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local c = Group.getByName(name):getCoalition()
  return _coalition_str[c]
end

sms.group.get_position = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_position: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local units = Group.getByName(name):getUnits()
  if not units or #units == 0 then
    log.error("get_position: '" .. tostring(name) .. "' has no units")
    return nil
  end
  local p = units[1]:getPoint()
  return {x = p.x, y = p.y, z = p.z}
end

sms.group.destroy = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  Group.getByName(name):destroy()
  return true
end

-- Sugar constructor: sms.group("name") -> handle | nil + log.
setmetatable(sms.group, {
  __call = function(_, name)
    if not Group.getByName(name) then
      log.error("couldn't find group '" .. tostring(name) .. "'")
      return nil
    end
    return setmetatable({name = name}, {__index = sms.group})
  end,
})
```

- [ ] **Step 2: Sanity-check the file loads via the bridge**

If DCS is running and a mission is loaded, run:
```bash
tools/dcs-sms.exe status
tools/dcs-sms.exe exec --file framework/sms.lua
tools/dcs-sms.exe exec --file framework/log.lua
tools/dcs-sms.exe exec --file framework/group.lua
```
Expected: each `exec --file` returns `"ok":true`. If `ok:false` with a Lua error, fix the syntax in `framework/group.lua` and rerun.

Then verify the module is callable:
```bash
tools/dcs-sms.exe exec --code "return type(sms.group)"
```
Expected: response includes `"return_value":"table"`.

If DCS is not running, defer full verification to Task 3.

- [ ] **Step 3: Commit**

```bash
git add framework/group.lua
git commit -m "feat(framework): add sms.group module with handle pattern and 5 methods"
```

---

## Task 3: Run smoke test, verify green

**Files:** none modified — verification only. May modify `framework/group.lua` or `framework/test/smoke_group.sh` if green-light reveals issues.

- [ ] **Step 1: Confirm DCS is running with mission loaded and fresh**

Run:
```bash
tools/dcs-sms.exe status
```
Expected: `mission loaded: true` and `fresh: true`.

If `fresh: false`, ask the user to bring DCS to the foreground / unpause the mission, then retry.
If `mission loaded: false`, ask the user to load a mission, then retry.
**Do NOT proceed without a fresh heartbeat.** The smoke test will fail with stale-heartbeat errors and produce confusing output.

- [ ] **Step 2: Run the smoke test**

Run:
```bash
framework/test/smoke_group.sh
```
Expected: terminates with `smoke ok` and exit 0. Every `==>` step prints with no `FAIL:` line.

- [ ] **Step 3: If green, run twice for idempotency**

Run:
```bash
framework/test/smoke_group.sh
framework/test/smoke_group.sh
```
Both runs should print `smoke ok` and exit 0. Globals carry over between bridge calls; `sms.group = sms.group or {}` keeps reloads idempotent. The fixture is destroyed at the end of each run, so each subsequent run spawns it fresh.

If both runs are green, skip to Step 5.

- [ ] **Step 4: If smoke fails, diagnose by category**

The most likely failure modes and how to address each:

**A. `coalition.addGroup` fails (spawn step returns false or errors).**
- Try a different unit type. `Soldier M4` is universal but if the user has a stripped-down install, fall back to `Tank M-1A1`, `M-2 Bradley`, or `MBT_T-72B`.
- Try different spawn coords. The script already tries to derive coords from an existing mission unit; if the user's mission has *no* existing units, `{0, 0}` may be off-map.
  - Diagnostic: run `tools/dcs-sms.exe exec --code "local g = coalition.getGroups(coalition.side.BLUE); return g and #g or 0"` — if this returns 0 for all sides, the mission is empty and we need a hardcoded coord that's known-on-land for the user's terrain (Kola: try `x = -200000, y = 600000`).
- Edit `framework/test/smoke_group.sh` accordingly. Commit any fix as `fix(test): ...`.

**B. A method returns the wrong value.**
- For `get_coalition`: confirm the spawned group is really BLUE. `country.id.USA` should map to BLUE coalition; if the user has a custom coalition.json that puts USA elsewhere, edit either the test (assert against actual coalition) or use a different country (`country.id.RUSSIA` for RED).
- For `get_position`: print the raw return via `--pretty` and inspect. The test only checks `type(x) == "number"` so this should not fail unless the unit lookup is broken.
- For `is_alive` / `destroy` returning unexpected values: re-read `framework/group.lua` against Task 2's code block.

**C. `[sms.group] couldn't find '_definitely_does_not_exist'` line missing from `dcs.log`.**
- Confirm `framework/group.lua` actually calls `log.error(...)` in the `__call` metamethod's miss branch.
- Confirm `sms.log.module("sms.group")` produces a logger whose `error` method emits at ERROR level via `env.error`. Check `framework/log.lua` if needed (it should — v1 confirmed this).
- Run `tools/dcs-sms.exe tail-log -n 50` (no grep) to see what *did* get logged; the line may be there with a different format.

**D. Other.** Re-read the relevant file vs. the plan code block. Each fix is its own commit (`fix(framework): ...` for `group.lua`, `fix(test): ...` for the smoke test).

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

- [ ] `framework/group.lua` exists and loads cleanly via `exec --file` (returns `ok:true`).
- [ ] `framework/test/smoke_group.sh` exists, is shebang-executable, and ends with `smoke ok` on a fresh run.
- [ ] `framework/test/smoke.sh` (the v1 logger smoke test) is unchanged.
- [ ] All 5 methods are implemented: `is_alive`, `get_name`, `get_coalition`, `get_position`, `destroy`.
- [ ] Construction via `sms.group("name")` returns a handle on hit, `nil` on miss.
- [ ] Construction miss logs `[sms.group] couldn't find '<name>'` to `dcs.log`.
- [ ] `destroy` returns `true` on a live group, `nil` on a dead group (with log).
- [ ] No edits made to `tools/`, `framework/sms.lua`, `framework/log.lua`, `framework/utils.lua`, or `framework/test/smoke.sh`.
- [ ] All work committed on branch `feat/sms-group`.
- [ ] Smoke test runs green idempotently (twice in a row).

## Out of scope (do NOT do)

- `sms.unit`, `sms.zone`, or any other entity module — separate future iterations.
- `sms.spawn` / `sms.group.spawn` — separate future sub-project.
- Other group methods (`smoke`, `set_ai`, `teleport`, `get_units`, `get_leader`, etc.).
- Generalizing the handle pattern into a `sms.make_handle()` helper.
- Vec3 math helpers (`sms.geom`).
- Touching anything under `tools/` for any reason.
- Modifying `framework/test/smoke.sh` (the v1 logger smoke test).

## Self-review notes from plan author

Spec coverage check:
- **Goal** → Tasks 1–3 collectively.
- **Five methods** → Task 2's code block contains all 5; smoke test exercises all 5.
- **Failure model (log + nil, never throw)** → Task 2's code block routes every failure through `log.error(...)` + `return nil`. Verified by Task 1's nonexistent-group assertion.
- **Coalition string mapping** → `_coalition_str` table at top of `group.lua`.
- **Position is leader-unit's vec3** → Task 2's `get_position` uses `units[1]:getPoint()`.
- **Self-spawning hermetic smoke test** → Task 1's smoke script spawns and destroys its own fixture.
- **Module logger uses explicit "sms.group" tag** → Task 2 uses `sms.log.module("sms.group")`.
- **Handle is `{name=...}` + `__index = sms.group`** → Task 2's `__call` returns exactly this shape.
- **All three call shapes work** → Implicit in the `__index` + first-arg-normalization design; smoke test uses the handle method form throughout.

Placeholder scan: zero placeholders. All code blocks are complete.

Type consistency: every method's return type matches the spec table. `_coalition_str` keys are 0/1/2; `get_coalition` returns the string. `get_position` returns `{x, y, z}`; smoke test asserts all three are numbers.
