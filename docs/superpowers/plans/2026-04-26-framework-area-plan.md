# `sms.area` v1 + `_make_callable_handle` Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `sms.area` module — a unified "area on the map" abstraction supporting ME zones (circle and quad), ME drawings, runtime circles, and runtime polygons. Bundles a refactor that extracts the cargo-cult callable factory into `sms._make_callable_handle`, used by `sms.group` / `sms.unit` / future entity wrappers.

**Architecture:** Two-phase work. Phase 1 (refactor): expose `tag` field on the logger; add `_make_callable_handle` and `_is_handle_of` helpers to `framework/sms.lua`; refactor `framework/group.lua` and `framework/unit.lua` to use the new factory. Existing smoke tests (`smoke_group.sh`, `smoke_unit.sh`) prove the refactor is behavior-preserving. Phase 2 (new module): `framework/area.lua` with snapshot-data handles, four construction paths, ten methods, ray-casting polygon containment, rejection-sampling polygon random point. New smoke test exercises all paths with conditional drawing-test for `from_drawing`.

**Tech Stack:** Lua 5.1 (DCS mission environment), bash (mingw on Windows), the existing `dcs-sms.exe` execution bridge, DCS APIs (`trigger.misc.getZone`, `env.mission.drawings`, `coalition.addGroup`, `Unit.getByName`, `Group.getByName`).

**Spec:** `docs/superpowers/specs/2026-04-26-framework-area-design.md`

---

## File Structure

| File | Purpose | Change |
|---|---|---|
| `framework/log.lua` | Logger module | Edit: expose `tag` field on the table returned by `sms.log.module()` |
| `framework/sms.lua` | Framework root | Edit: add `_make_callable_handle` and `_is_handle_of` helpers |
| `framework/group.lua` | Group entity wrapper | Refactor: use `_make_callable_handle` for the trailing callable |
| `framework/unit.lua` | Unit entity wrapper | Refactor: same |
| `framework/area.lua` | Area abstraction | NEW: ~280 lines, the core deliverable |
| `framework/test/smoke_area.sh` | Area smoke test | NEW |

Existing smoke tests (`smoke.sh`, `smoke_group.sh`, `smoke_unit.sh`, `smoke_timer.sh`) are unchanged — they're the regression coverage for the refactor.

## Parallelism

Sequential. Seven tasks: refactor (4) → smoke test (1) → area implementation (1) → green-light verification (1).

---

## Task 1: Expose `tag` field on the logger

**Files:**
- Modify: `framework/log.lua`

- [ ] **Step 1: Edit the file**

Open `framework/log.lua`. Find the existing `return {...}` block inside `sms.log.module = function(name) ... end` (currently lines 36-39):

```lua
  return {
    info  = function(msg) env.info ("[" .. tag .. "] " .. tostring(msg)) end,
    error = function(msg) env.error("[" .. tag .. "] " .. tostring(msg)) end,
  }
```

Replace it with:

```lua
  return {
    tag   = tag,
    info  = function(msg) env.info ("[" .. tag .. "] " .. tostring(msg)) end,
    error = function(msg) env.error("[" .. tag .. "] " .. tostring(msg)) end,
  }
```

Single-line additive change. No other modifications.

- [ ] **Step 2: Sanity-check the file loads via the bridge**

If DCS is running:
```bash
tools/dcs-sms.exe status
tools/dcs-sms.exe exec --file framework/sms.lua
tools/dcs-sms.exe exec --file framework/log.lua
tools/dcs-sms.exe exec --code "local L = sms.log.module('sms.test'); return L.tag"
```

Expected: `"return_value":"sms.test"`.

- [ ] **Step 3: Run all existing smoke tests to confirm no regression**

```bash
framework/test/smoke.sh
framework/test/smoke_group.sh
framework/test/smoke_unit.sh
```

Each should end with `smoke ok`. (Skip `smoke_timer.sh` — it requires unpaused mission for ~25s.)

If DCS isn't running, skip Steps 2-3. The behavior change is purely additive; the implementation is so simple that bridge verification is sufficient when available.

- [ ] **Step 4: Commit**

```bash
git add framework/log.lua
git commit -m "refactor(framework): expose tag field on per-module logger"
```

---

## Task 2: Add `_make_callable_handle` and `_is_handle_of` to `framework/sms.lua`

**Files:**
- Modify: `framework/sms.lua`

- [ ] **Step 1: Read the current file**

The current `framework/sms.lua` is 6 lines:
```lua
-- dcs-sms framework root.
-- Creates the single global namespace and records the version.
-- Idempotent: safe to load multiple times.
sms = sms or {}
sms.version = "0.1.0"
```

- [ ] **Step 2: Replace the file with the extended version**

Write `framework/sms.lua` with EXACTLY this content:

```lua
-- dcs-sms framework root.
-- Creates the single global namespace and records the version.
-- Also exposes shared cross-cutting helpers used by entity-wrapper modules
-- (sms.group, sms.unit, sms.area, future sms.static, ...).
-- Idempotent: safe to load multiple times.
sms = sms or {}
sms.version = "0.1.0"

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
      return setmetatable({name = name}, {__index = module})
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

- [ ] **Step 3: Sanity-check via the bridge**

If DCS is running:
```bash
tools/dcs-sms.exe exec --file framework/sms.lua
tools/dcs-sms.exe exec --code "return type(sms._make_callable_handle)"
tools/dcs-sms.exe exec --code "return type(sms._is_handle_of)"
tools/dcs-sms.exe exec --code "return sms.version"
```

Expected: `"function"`, `"function"`, `"0.1.0"`.

If DCS isn't running, skip — Task 3 and 4 cover behavior validation.

- [ ] **Step 4: Commit**

```bash
git add framework/sms.lua
git commit -m "feat(framework): add _make_callable_handle and _is_handle_of helpers"
```

---

## Task 3: Refactor `framework/group.lua` to use `_make_callable_handle`

**Files:**
- Modify: `framework/group.lua`

- [ ] **Step 1: Locate and replace the trailing callable block**

Open `framework/group.lua`. At the bottom of the file there is a `setmetatable(sms.group, { __call = function(_, name) ... end })` block (currently the last 9 lines, starting around line 100).

The exact block to replace looks like this:

```lua
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

Replace it with:

```lua
-- Sugar constructor: sms.group("name") -> handle | nil + log.
-- The factory lives in sms.lua; this call wires it up using Group.getByName
-- as the existence check.
sms._make_callable_handle(sms.group, Group.getByName, log)
```

- [ ] **Step 2: Run smoke_group.sh to verify no regression**

If DCS is running:
```bash
tools/dcs-sms.exe status
framework/test/smoke_group.sh
```

Expected: `smoke ok` and exit 0. The smoke test exercises the callable's success path AND its miss path (asserting that `sms.group("_definitely_does_not_exist") == nil` AND that the log line `couldn't find group '_definitely_does_not_exist'` appears in dcs.log). Both paths must continue to work.

If DCS isn't running, Task 7 will catch any regression; skip this step but flag it in the report.

- [ ] **Step 3: Commit**

```bash
git add framework/group.lua
git commit -m "refactor(framework): use _make_callable_handle in sms.group"
```

---

## Task 4: Refactor `framework/unit.lua` to use `_make_callable_handle`

**Files:**
- Modify: `framework/unit.lua`

- [ ] **Step 1: Locate and replace the trailing callable block**

Open `framework/unit.lua`. At the bottom of the file there is the equivalent block to group's:

```lua
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

Replace it with:

```lua
-- Sugar constructor: sms.unit("name") -> handle | nil + log.
-- The factory lives in sms.lua; this call wires it up using Unit.getByName
-- as the existence check.
sms._make_callable_handle(sms.unit, Unit.getByName, log)
```

- [ ] **Step 2: Run smoke_unit.sh to verify no regression**

If DCS is running:
```bash
framework/test/smoke_unit.sh
```

Expected: `smoke ok`. Same dual-path coverage as group's smoke (success construction AND missing-unit log).

If DCS isn't running, skip; Task 7 catches any regression.

- [ ] **Step 3: Commit**

```bash
git add framework/unit.lua
git commit -m "refactor(framework): use _make_callable_handle in sms.unit"
```

---

## Task 5: Failing smoke test for `sms.area` (TDD red)

**Files:**
- Create: `framework/test/smoke_area.sh`

- [ ] **Step 1: Write the smoke test**

Create `framework/test/smoke_area.sh` with EXACTLY this content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.area v1.
# Exercises all 4 construction paths (ME zone, runtime circle, runtime polygon, ME drawing)
# and all 10 methods. ME drawing path is conditional: if no drawing named
# `_sms_test_area_drawing` exists in the mission, those assertions are skipped
# with clear instructions on how to enable them.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded
# that contains at least one ME-defined trigger zone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

# Helpers
expect_true() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_false() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":false' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_eq_string() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
}

expect_eq_number() {
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
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null
"${DCSSMS}" exec --file area.lua >/dev/null

echo "==> discover an ME zone in the mission"
zone_info=$("${DCSSMS}" exec --code '
  local zones = env.mission and env.mission.triggers and env.mission.triggers.zones
  if not zones or #zones == 0 then return nil end
  for _, z in ipairs(zones) do
    if z.radius and z.radius > 0 then
      return {name = z.name, x = z.x, y = z.y, radius = z.radius}
    end
  end
  return nil
')
echo "${zone_info}"
echo "${zone_info}" | grep -q '"return_value":{' \
  || { echo "FAIL: no ME circle zone found in mission. Add at least one circle zone in the Mission Editor and reload."; exit 1; }

# Extract zone fields via a separate exec for each (jq not assumed to be installed).
ZONE_NAME=$("${DCSSMS}" exec --code '
  for _, z in ipairs(env.mission.triggers.zones) do
    if z.radius and z.radius > 0 then return z.name end
  end
' | grep -oP '"return_value":"\K[^"]+')
echo "==> using ME zone: ${ZONE_NAME}"

echo "==> spawn fixture groups (one inside zone, one outside)"
"${DCSSMS}" exec --code "
  local zone = trigger.misc.getZone('${ZONE_NAME}')
  local cx, cz = zone.point.x, zone.point.z
  local r = zone.radius

  -- inside group: at zone center
  coalition.addGroup(country.id.USA, Group.Category.GROUND, {
    name = '_sms_test_area_inside_group',
    task = 'Ground Nothing',
    units = {{name = '_sms_test_area_inside_unit', type = 'Soldier M4',
              x = cx, y = cz, heading = 0, skill = 'Average'}},
  })

  -- outside group: 2*radius east of center
  coalition.addGroup(country.id.USA, Group.Category.GROUND, {
    name = '_sms_test_area_outside_group',
    task = 'Ground Nothing',
    units = {{name = '_sms_test_area_outside_unit', type = 'Soldier M4',
              x = cx + 2 * r, y = cz, heading = 0, skill = 'Average'}},
  })
  return Unit.getByName('_sms_test_area_inside_unit') ~= nil
       and Unit.getByName('_sms_test_area_outside_unit') ~= nil
" >/dev/null
expect_true "fixtures alive" "
  return Unit.getByName('_sms_test_area_inside_unit') ~= nil
     and Unit.getByName('_sms_test_area_outside_unit') ~= nil
"

# ----------------------------------------------------------------
# Section 1: ME zone (circle) construction + method coverage
# ----------------------------------------------------------------
echo "==> [me-circle] get_kind = circle"
expect_eq_string "me-circle kind" "return sms.area('${ZONE_NAME}'):get_kind()" "circle"

echo "==> [me-circle] get_position returns vec3"
expect_true "me-circle position is vec3" "
  local p = sms.area('${ZONE_NAME}'):get_position()
  return p ~= nil and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number'
"

echo "==> [me-circle] get_radius is positive number"
expect_true "me-circle radius positive" "
  local r = sms.area('${ZONE_NAME}'):get_radius()
  return type(r) == 'number' and r > 0
"

echo "==> [me-circle] get_vertices on circle returns nil"
expect_true "me-circle get_vertices nil" "return sms.area('${ZONE_NAME}'):get_vertices() == nil"

echo "==> [me-circle] is_vec3_in zone center -> true"
expect_true "me-circle center inside" "
  local a = sms.area('${ZONE_NAME}')
  local p = a:get_position()
  return a:is_vec3_in(p)
"

echo "==> [me-circle] is_vec3_in 2*radius away -> false"
expect_false "me-circle far point outside" "
  local a = sms.area('${ZONE_NAME}')
  local p = a:get_position()
  local r = a:get_radius()
  return a:is_vec3_in({x = p.x + 2*r, y = 0, z = p.z + 2*r})
"

echo "==> [me-circle] is_vec3_in vec2 (missing z) -> false"
expect_false "me-circle vec2 input rejected" "
  return sms.area('${ZONE_NAME}'):is_vec3_in({x = 0, y = 0})
"

echo "==> [me-circle] is_unit_in inside_unit -> true"
expect_true "me-circle inside unit detected" "
  return sms.area('${ZONE_NAME}'):is_unit_in(sms.unit('_sms_test_area_inside_unit'))
"

echo "==> [me-circle] is_unit_in outside_unit -> false"
expect_false "me-circle outside unit excluded" "
  return sms.area('${ZONE_NAME}'):is_unit_in(sms.unit('_sms_test_area_outside_unit'))
"

echo "==> [me-circle] is_unit_in given group handle -> false (wrong type)"
expect_false "me-circle wrong handle type rejected" "
  return sms.area('${ZONE_NAME}'):is_unit_in(sms.group('_sms_test_area_inside_group'))
"

echo "==> [me-circle] is_any_of_group_in inside_group -> true"
expect_true "me-circle any-of inside" "
  return sms.area('${ZONE_NAME}'):is_any_of_group_in(sms.group('_sms_test_area_inside_group'))
"

echo "==> [me-circle] is_any_of_group_in outside_group -> false"
expect_false "me-circle any-of outside" "
  return sms.area('${ZONE_NAME}'):is_any_of_group_in(sms.group('_sms_test_area_outside_group'))
"

echo "==> [me-circle] is_all_of_group_in inside_group -> true"
expect_true "me-circle all-of inside" "
  return sms.area('${ZONE_NAME}'):is_all_of_group_in(sms.group('_sms_test_area_inside_group'))
"

echo "==> [me-circle] is_all_of_group_in outside_group -> false"
expect_false "me-circle all-of outside" "
  return sms.area('${ZONE_NAME}'):is_all_of_group_in(sms.group('_sms_test_area_outside_group'))
"

echo "==> [me-circle] get_random_point returns inside-vec3 (5 trials)"
expect_true "me-circle random points inside" "
  local a = sms.area('${ZONE_NAME}')
  for i = 1, 5 do
    local rp = a:get_random_point()
    if not rp or not a:is_vec3_in(rp) then return false end
  end
  return true
"

echo "==> [me-circle] missing zone returns nil"
expect_true "me-circle missing zone" "return sms.area('_definitely_not_a_zone') == nil"

# ----------------------------------------------------------------
# Section 2: Runtime circle
# ----------------------------------------------------------------
echo "==> [rt-circle] create_circular returns handle"
expect_eq_string "rt-circle kind" "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_kind()" "circle"

echo "==> [rt-circle] get_radius returns 500"
expect_eq_number "rt-circle radius" "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_radius()" "500"

echo "==> [rt-circle] get_name returns 'rt'"
expect_eq_string "rt-circle name" "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_name()" "rt"

echo "==> [rt-circle] anonymous (no name) -> get_name returns nil"
expect_true "rt-circle anon name nil" "
  return sms.area.create_circular({x=0,y=0,z=0}, 500):get_name() == nil
"

echo "==> [rt-circle] is_vec3_in inside point -> true"
expect_true "rt-circle inside" "
  return sms.area.create_circular({x=0,y=0,z=0}, 500):is_vec3_in({x=100,y=0,z=100})
"

echo "==> [rt-circle] is_vec3_in outside point -> false"
expect_false "rt-circle outside" "
  return sms.area.create_circular({x=0,y=0,z=0}, 500):is_vec3_in({x=1000,y=0,z=1000})
"

echo "==> [rt-circle] invalid center -> nil"
expect_true "rt-circle invalid center" "return sms.area.create_circular('not-a-vec3', 500) == nil"

echo "==> [rt-circle] negative radius -> nil"
expect_true "rt-circle negative radius" "return sms.area.create_circular({x=0,y=0,z=0}, -1) == nil"

echo "==> [rt-circle] zero radius -> nil"
expect_true "rt-circle zero radius" "return sms.area.create_circular({x=0,y=0,z=0}, 0) == nil"

# ----------------------------------------------------------------
# Section 3: Runtime polygon
# ----------------------------------------------------------------
echo "==> [rt-poly] create_polygon (1km square) returns polygon"
expect_eq_string "rt-poly kind" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }, 'sq'):get_kind()
" "polygon"

echo "==> [rt-poly] get_vertices returns 4-element list"
expect_eq_number "rt-poly vertex count" "
  return #sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }, 'sq'):get_vertices()
" "4"

echo "==> [rt-poly] get_radius on polygon -> nil"
expect_true "rt-poly radius nil" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):get_radius() == nil
"

echo "==> [rt-poly] get_position returns centroid"
expect_true "rt-poly centroid" "
  local c = sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):get_position()
  return c.x == 500 and c.z == 500
"

echo "==> [rt-poly] is_vec3_in center point -> true"
expect_true "rt-poly center inside" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):is_vec3_in({x=500,y=0,z=500})
"

echo "==> [rt-poly] is_vec3_in near corner inside -> true"
expect_true "rt-poly corner inside" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):is_vec3_in({x=999,y=0,z=999})
"

echo "==> [rt-poly] is_vec3_in outside -> false"
expect_false "rt-poly outside" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):is_vec3_in({x=1500,y=0,z=500})
"

echo "==> [rt-poly] get_random_point inside (5 trials)"
expect_true "rt-poly random inside" "
  local a = sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  })
  for i = 1, 5 do
    local rp = a:get_random_point()
    if not rp or not a:is_vec3_in(rp) then return false end
  end
  return true
"

echo "==> [rt-poly] empty vertices -> nil"
expect_true "rt-poly empty rejected" "return sms.area.create_polygon({}) == nil"

echo "==> [rt-poly] 2 vertices -> nil"
expect_true "rt-poly 2-vert rejected" "
  return sms.area.create_polygon({{x=0,y=0,z=0}, {x=1,y=0,z=0}}) == nil
"

echo "==> [rt-poly] non-vec3 vertex -> nil"
expect_true "rt-poly non-vec3 rejected" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1,y=0,z=0}, 'not a vec3'
  }) == nil
"

# ----------------------------------------------------------------
# Section 4: from_drawing (conditional)
# ----------------------------------------------------------------
echo "==> [drawing] check for _sms_test_area_drawing in mission"
drawing_present=$("${DCSSMS}" exec --code '
  local d = env.mission and env.mission.drawings
  if not d or not d.layers then return false end
  for _, layer in ipairs(d.layers) do
    if layer.objects then
      for _, obj in ipairs(layer.objects) do
        if obj.name == "_sms_test_area_drawing" then return true end
      end
    end
  end
  return false
')

if echo "${drawing_present}" | grep -q '"return_value":true'; then
  echo "==> [drawing] _sms_test_area_drawing found, exercising from_drawing"
  expect_eq_string "drawing kind" "
    return sms.area.from_drawing('_sms_test_area_drawing'):get_kind()
  " "polygon"
  expect_true "drawing has vertices" "
    local v = sms.area.from_drawing('_sms_test_area_drawing'):get_vertices()
    return v ~= nil and #v >= 3
  "
else
  echo "==> [drawing] skipping from_drawing assertions"
  echo "    (to enable, add a freeform polygon drawing named '_sms_test_area_drawing' to the mission)"
fi

echo "==> [drawing] missing drawing returns nil"
expect_true "drawing missing" "return sms.area.from_drawing('_no_such_drawing_xyz') == nil"

# ----------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------
echo "==> cleanup: destroy fixture groups"
"${DCSSMS}" exec --code "
  local g1 = sms.group('_sms_test_area_inside_group')
  if g1 then g1:destroy() end
  local g2 = sms.group('_sms_test_area_outside_group')
  if g2 then g2:destroy() end
" >/dev/null

echo "==> dcs.log should contain [sms.area] miss line"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.area\]' -n 200)
echo "${log_window}" | grep -q "couldn't find area '_definitely_not_a_zone'" \
  || { echo "FAIL: missing log line for nonexistent area"; echo "${log_window}"; exit 1; }

echo "smoke ok"
```

- [ ] **Step 2: Make it executable and run; expect failure**

```bash
chmod +x framework/test/smoke_area.sh
framework/test/smoke_area.sh
```

Expected: failure at the `==> load framework files` step on `exec --file area.lua` because `framework/area.lua` does not exist yet — that's the correct TDD red.

If failure happens at `==> hook status`, that's also valid red — note in the report. If the failure is "no ME circle zone found" — same: it's a real prerequisite, document and continue.

If failure happens at any earlier step (bash syntax error, dcs-sms.exe not found), STOP and report.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_area.sh
git commit -m "test: add bridge-driven smoke test for sms.area v1"
```

---

## Task 6: Implement `framework/area.lua`

**Files:**
- Create: `framework/area.lua`

- [ ] **Step 1: Write the file**

Create `framework/area.lua` with EXACTLY this content:

```lua
-- dcs-sms framework: area module (sms.area).
--
-- A unified "area on the map" abstraction — circles or polygons, sourced
-- from ME zones, ME drawings, or constructed at runtime. All sources share
-- the same handle shape and method surface.
--
-- Construction paths:
--   sms.area("ZoneName")                        -- ME zone (circle or quad)
--   sms.area.from_drawing("DrawingName")        -- ME freeform polygon drawing
--   sms.area.create_circular(vec3, radius, name?)
--   sms.area.create_polygon({vec3,...}, name?)  -- >= 3 vertices
--
-- Methods (all callable as a:method() AND as sms.area.method(handle, ...)):
--   :get_name()                                 -- string | nil (anonymous)
--   :get_kind()                                 -- "circle" | "polygon"
--   :get_position()                             -- vec3 (center / centroid)
--   :get_radius()                               -- number | nil + log on polygon
--   :get_vertices()                             -- list of vec3 | nil + log on circle
--   :is_vec3_in(vec3)                           -- bool
--   :is_unit_in(sms.unit handle)                -- bool, strict handle check
--   :is_any_of_group_in(sms.group handle)       -- bool
--   :is_all_of_group_in(sms.group handle)       -- bool
--   :get_random_point()                         -- vec3 inside the area
--
-- Failure model: log + return nil/false. Never throws.
--
-- Loading order: sms.lua -> log.lua -> group.lua -> unit.lua -> area.lua.
-- is_unit_in / is_*_of_group_in require sms.unit/sms.group at call time.
-- Polygon get_random_point uses rejection sampling within the bounding box;
-- triangulation-based replacement tracked in issue #4.
--
-- See docs/superpowers/specs/2026-04-26-framework-area-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
local log = sms.log.module("sms.area")
sms.area = sms.area or {}

-- ============================================================
-- Local helpers (private)
-- ============================================================

local function _validate_vec3(v)
  return type(v) == "table"
     and type(v.x) == "number"
     and type(v.y) == "number"
     and type(v.z) == "number"
end

local function _point_in_circle(data, x, z)
  local dx = x - data.center.x
  local dz = z - data.center.z
  return (dx * dx + dz * dz) <= (data.radius * data.radius)
end

-- Standard ray-casting point-in-polygon on the xz-plane. Handles concave
-- polygons. Edge-on-vertex cases are nondeterministic (acceptable for v1).
local function _point_in_polygon(verts, x, z)
  local inside = false
  local n = #verts
  local j = n
  for i = 1, n do
    local vi, vj = verts[i], verts[j]
    if ((vi.z > z) ~= (vj.z > z)) and
       (x < (vj.x - vi.x) * (z - vi.z) / (vj.z - vi.z) + vi.x) then
      inside = not inside
    end
    j = i
  end
  return inside
end

local function _bbox_of_polygon(verts)
  local min_x, max_x = verts[1].x, verts[1].x
  local min_z, max_z = verts[1].z, verts[1].z
  for i = 2, #verts do
    local v = verts[i]
    if v.x < min_x then min_x = v.x end
    if v.x > max_x then max_x = v.x end
    if v.z < min_z then min_z = v.z end
    if v.z > max_z then max_z = v.z end
  end
  return {min_x = min_x, max_x = max_x, min_z = min_z, max_z = max_z}
end

local function _centroid_of_polygon(verts)
  local sx, sy, sz = 0, 0, 0
  local n = #verts
  for _, v in ipairs(verts) do
    sx = sx + v.x
    sy = sy + v.y
    sz = sz + v.z
  end
  return {x = sx / n, y = sy / n, z = sz / n}
end

-- Uniform random point inside a circle. r = sqrt(random()) * radius gives
-- uniform distribution; naive r = random() * radius clusters near center.
local function _random_in_circle(data)
  local theta = math.random() * 2 * math.pi
  local r = math.sqrt(math.random()) * data.radius
  return {
    x = data.center.x + r * math.cos(theta),
    y = data.center.y,
    z = data.center.z + r * math.sin(theta),
  }
end

-- Rejection sampling within bounding box. Capped at 100 attempts; falls
-- back to centroid + log on degenerate input. See issue #4 for the
-- triangulation-based replacement plan.
local function _random_in_polygon(data, name)
  local bbox = data.bbox
  for attempt = 1, 100 do
    local x = bbox.min_x + math.random() * (bbox.max_x - bbox.min_x)
    local z = bbox.min_z + math.random() * (bbox.max_z - bbox.min_z)
    if _point_in_polygon(data.vertices, x, z) then
      return {x = x, y = data.centroid.y, z = z}
    end
  end
  log.error("get_random_point: 100 attempts failed for polygon '" .. tostring(name) .. "', returning centroid")
  return {x = data.centroid.x, y = data.centroid.y, z = data.centroid.z}
end

-- ============================================================
-- Internal handle factories
-- ============================================================

local function _make_circle_handle(name, center, radius)
  return setmetatable({
    name = name,
    kind = "circle",
    _data = {
      center = {x = center.x, y = center.y, z = center.z},
      radius = radius,
    },
  }, {__index = sms.area})
end

local function _make_polygon_handle(name, vertices)
  -- Copy vertices to prevent external mutation.
  local verts = {}
  for i, v in ipairs(vertices) do
    verts[i] = {x = v.x, y = v.y, z = v.z}
  end
  return setmetatable({
    name = name,
    kind = "polygon",
    _data = {
      vertices = verts,
      centroid = _centroid_of_polygon(verts),
      bbox = _bbox_of_polygon(verts),
    },
  }, {__index = sms.area})
end

-- ============================================================
-- Methods
-- ============================================================

sms.area.get_name = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_name: argument must be an sms.area handle")
    return nil
  end
  return a.name
end

sms.area.get_kind = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_kind: argument must be an sms.area handle")
    return nil
  end
  return a.kind
end

sms.area.get_position = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_position: argument must be an sms.area handle")
    return nil
  end
  if a.kind == "circle" then
    local c = a._data.center
    return {x = c.x, y = c.y, z = c.z}
  end
  local c = a._data.centroid
  return {x = c.x, y = c.y, z = c.z}
end

sms.area.get_radius = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_radius: argument must be an sms.area handle")
    return nil
  end
  if a.kind ~= "circle" then
    log.error("get_radius: area '" .. tostring(a.name) .. "' is a " .. a.kind .. ", no radius")
    return nil
  end
  return a._data.radius
end

sms.area.get_vertices = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_vertices: argument must be an sms.area handle")
    return nil
  end
  if a.kind ~= "polygon" then
    log.error("get_vertices: area '" .. tostring(a.name) .. "' is a " .. a.kind .. ", no vertices")
    return nil
  end
  -- Return a copy so the user can't mutate internal state.
  local copy = {}
  for i, v in ipairs(a._data.vertices) do
    copy[i] = {x = v.x, y = v.y, z = v.z}
  end
  return copy
end

sms.area.is_vec3_in = function(a, target)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_vec3_in: argument must be an sms.area handle")
    return false
  end
  if not _validate_vec3(target) then
    log.error("is_vec3_in: target must be a vec3 with x/y/z numbers")
    return false
  end
  if a.kind == "circle" then
    return _point_in_circle(a._data, target.x, target.z)
  end
  return _point_in_polygon(a._data.vertices, target.x, target.z)
end

sms.area.is_unit_in = function(a, u)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_unit_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(u, sms.unit) then
    log.error("is_unit_in: target must be an sms.unit handle")
    return false
  end
  local p = sms.unit.get_position(u)
  if not p then return false end
  if a.kind == "circle" then
    return _point_in_circle(a._data, p.x, p.z)
  end
  return _point_in_polygon(a._data.vertices, p.x, p.z)
end

sms.area.is_any_of_group_in = function(a, g)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_any_of_group_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(g, sms.group) then
    log.error("is_any_of_group_in: target must be an sms.group handle")
    return false
  end
  local units = sms.group.get_units(g)
  if not units then return false end
  for _, u in ipairs(units) do
    if u then
      local p = sms.unit.get_position(u)
      if p then
        local inside
        if a.kind == "circle" then
          inside = _point_in_circle(a._data, p.x, p.z)
        else
          inside = _point_in_polygon(a._data.vertices, p.x, p.z)
        end
        if inside then return true end
      end
    end
  end
  return false
end

sms.area.is_all_of_group_in = function(a, g)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_all_of_group_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(g, sms.group) then
    log.error("is_all_of_group_in: target must be an sms.group handle")
    return false
  end
  local units = sms.group.get_units(g)
  if not units or #units == 0 then return false end
  for _, u in ipairs(units) do
    if not u then return false end
    local p = sms.unit.get_position(u)
    if not p then return false end
    local inside
    if a.kind == "circle" then
      inside = _point_in_circle(a._data, p.x, p.z)
    else
      inside = _point_in_polygon(a._data.vertices, p.x, p.z)
    end
    if not inside then return false end
  end
  return true
end

sms.area.get_random_point = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_random_point: argument must be an sms.area handle")
    return nil
  end
  if a.kind == "circle" then
    return _random_in_circle(a._data)
  end
  return _random_in_polygon(a._data, a.name)
end

-- ============================================================
-- Constructors
-- ============================================================

sms.area.create_circular = function(center, radius, name)
  if not _validate_vec3(center) then
    log.error("create_circular: center must be a vec3 with x/y/z numbers")
    return nil
  end
  if type(radius) ~= "number" or radius <= 0 then
    log.error("create_circular: radius must be a positive number, got " .. tostring(radius))
    return nil
  end
  if name ~= nil and type(name) ~= "string" then
    log.error("create_circular: name must be a string or nil, got " .. type(name))
    return nil
  end
  return _make_circle_handle(name, center, radius)
end

sms.area.create_polygon = function(vertices, name)
  if type(vertices) ~= "table" then
    log.error("create_polygon: vertices must be a table (list) of vec3 entries")
    return nil
  end
  if #vertices < 3 then
    log.error("create_polygon: need at least 3 vertices, got " .. #vertices)
    return nil
  end
  for i, v in ipairs(vertices) do
    if not _validate_vec3(v) then
      log.error("create_polygon: vertex " .. i .. " is not a vec3 with x/y/z numbers")
      return nil
    end
  end
  if name ~= nil and type(name) ~= "string" then
    log.error("create_polygon: name must be a string or nil, got " .. type(name))
    return nil
  end
  return _make_polygon_handle(name, vertices)
end

sms.area.from_drawing = function(name)
  if type(name) ~= "string" then
    log.error("from_drawing: name must be a string")
    return nil
  end
  local drawings = env.mission and env.mission.drawings
  if not drawings or not drawings.layers then
    log.error("from_drawing: env.mission.drawings.layers not available")
    return nil
  end
  for _, layer in ipairs(drawings.layers) do
    if layer.objects then
      for _, obj in ipairs(layer.objects) do
        if obj.name == name then
          if obj.primitiveType ~= "Polygon" then
            log.error("from_drawing: '" .. name .. "' is not a polygon drawing (type: " .. tostring(obj.primitiveType) .. ")")
            return nil
          end
          local pts = obj.points
          if type(pts) ~= "table" or #pts < 3 then
            log.error("from_drawing: '" .. name .. "' has insufficient points")
            return nil
          end
          -- Drawing points are 2D {x, y} where DCS-y is north-south.
          -- Anchor at the drawing's mapX/mapY origin and convert to vec3
          -- with our z = DCS-y.
          local origin_x = obj.mapX or 0
          local origin_z = obj.mapY or 0
          local verts = {}
          for i, p in ipairs(pts) do
            verts[i] = {x = origin_x + p.x, y = 0, z = origin_z + p.y}
          end
          return _make_polygon_handle(name, verts)
        end
      end
    end
  end
  log.error("from_drawing: drawing '" .. name .. "' not found")
  return nil
end

-- Callable: sms.area("name") -> handle | nil + log.
-- Looks up via trigger.misc.getZone, dispatches to circle or polygon.
-- Quad zones use DCS's "verticies" key (note the spelling, that's how DCS
-- has it).
setmetatable(sms.area, {
  __call = function(_, name)
    local zone = trigger.misc.getZone(name)
    if not zone then
      log.error("couldn't find area '" .. tostring(name) .. "'")
      return nil
    end
    if zone.radius then
      return _make_circle_handle(name, zone.point, zone.radius)
    end
    if zone.verticies then
      -- Quad-zone vertices are {x, y} 2D (y = north-south). Convert to vec3.
      local verts = {}
      for i, v in ipairs(zone.verticies) do
        verts[i] = {x = v.x, y = 0, z = v.y}
      end
      return _make_polygon_handle(name, verts)
    end
    log.error("area '" .. tostring(name) .. "' has neither radius nor vertices")
    return nil
  end,
})
```

- [ ] **Step 2: Sanity-check the file loads via the bridge**

If DCS is running:
```bash
tools/dcs-sms.exe exec --file framework/sms.lua
tools/dcs-sms.exe exec --file framework/log.lua
tools/dcs-sms.exe exec --file framework/group.lua
tools/dcs-sms.exe exec --file framework/unit.lua
tools/dcs-sms.exe exec --file framework/area.lua
tools/dcs-sms.exe exec --code "return type(sms.area)"
tools/dcs-sms.exe exec --code "return type(sms.area.create_circular)"
tools/dcs-sms.exe exec --code "return type(sms.area.create_polygon)"
tools/dcs-sms.exe exec --code "return type(sms.area.from_drawing)"
tools/dcs-sms.exe exec --code "return type(sms.area.is_vec3_in)"
```

Expected: each `exec --file` returns `"ok":true`; type queries return `"table"` for `sms.area` and `"function"` for the methods.

If `exec --file framework/area.lua` returns `ok:false`, read the response, fix the syntax, and rerun.

If DCS isn't running, skip; Task 7 catches issues.

- [ ] **Step 3: Commit**

```bash
git add framework/area.lua
git commit -m "feat(framework): add sms.area module (circle + polygon, 4 constructors)"
```

---

## Task 7: Run smoke tests, verify all green

**Files:** none modified — verification only. May modify `framework/area.lua` or `framework/test/smoke_area.sh` if green-light reveals issues.

- [ ] **Step 1: Confirm DCS is up and ready**

```bash
tools/dcs-sms.exe status
```
Expected: `mission loaded: true`, `fresh: true`. The mission must contain at least one ME circle zone (`smoke_area.sh` will bail with a clear message if not).

- [ ] **Step 2: Run all four framework smoke tests**

```bash
framework/test/smoke.sh
framework/test/smoke_group.sh
framework/test/smoke_unit.sh
framework/test/smoke_area.sh
```

Each should print `smoke ok` and exit 0.

`smoke.sh`, `smoke_group.sh`, and `smoke_unit.sh` going green proves the refactor (Tasks 1-4) is behavior-preserving.
`smoke_area.sh` going green proves the new module works.

`smoke_timer.sh` is not run here (requires unpaused mission for ~25s; manual verification).

- [ ] **Step 3: If green, run smoke_area.sh twice for idempotency**

```bash
framework/test/smoke_area.sh
framework/test/smoke_area.sh
```

Both runs end with `smoke ok`. The cleanup step destroys both fixture groups; the next run respawns from scratch.

If both runs are green AND all four smoke tests passed in Step 2, skip to Step 5.

- [ ] **Step 4: If smoke fails, diagnose by category**

Most likely failure modes and how to address each:

**A. `exec --file area.lua` returns ok:false.**
- The Lua file has a syntax error. Read the bridge response; the `error` field will have line info. Fix in `framework/area.lua`. Commit fix as `fix(framework): ...`.

**B. `smoke_group.sh` or `smoke_unit.sh` regressed (was green before refactor).**
- The `_make_callable_handle` extraction may have a subtle behavior difference. Check that:
  - The log message format is exactly `couldn't find <type> '<name>'` (note the type-name derivation strips `sms.` prefix from the logger tag).
  - The handle table shape is still `{name = name}` with `{__index = module}` metatable.
  - The miss-then-nil path returns nil (not false, not undefined).
- Compare a `git diff HEAD~4..HEAD~3 framework/group.lua` to see exactly what changed.

**C. Smoke fails on "no ME circle zone found in mission".**
- Real prerequisite. Ask the user to add at least one circle trigger zone to their mission and reload. Not a bug — the test correctly bails.

**D. Spawn fixture fails.**
- Same as group/unit smoke — `Soldier M4` may not exist on the user's terrain. Try `Tank M-1A1`. Or coords may be invalid (zone center could be at a weird location). Verify manually:
  `tools/dcs-sms.exe exec --code "return trigger.misc.getZone('<ZONE_NAME>')"` to confirm the zone returns a real point.

**E. `is_vec3_in(zone center)` returns false.**
- Floating-point edge case at the exact center? Unlikely (center is well inside, not on edge). More likely: the `_point_in_circle` math is wrong. Verify `(dx*dx + dz*dz) <= radius*radius`.

**F. `get_random_point()` returns a point outside the area (5-trial check fails).**
- For circles: check `_random_in_circle` — `r = math.sqrt(math.random()) * data.radius` is correct; naive `r = math.random() * radius` would still produce points inside, just non-uniformly distributed. So the `is_vec3_in` check should pass either way. If it fails, the bug is in `_point_in_circle` or in the math constants.
- For polygons: check `_point_in_polygon` ray-casting; off-by-one in vertex indexing is the classic bug.

**G. `from_drawing` assertions fail (when drawing is present).**
- DCS's mission descriptor schema for drawings may differ from what the implementation assumes. Run:
  `tools/dcs-sms.exe exec --code "for k,v in pairs(env.mission.drawings.layers[1].objects[1] or {}) do env.info(tostring(k)..'='..tostring(v)) end"` and inspect the dcs.log to see the actual field names. Adapt `from_drawing` accordingly. Fields most likely to vary: `primitiveType` (case, name), `points` (key name, structure), `mapX`/`mapY` (origin offsets).

**H. `is_unit_in(group_handle)` doesn't return false (or wrong log).**
- Verify `sms._is_handle_of` correctly compares `getmetatable(value).__index == module`. If it returns true for a group handle when checking against `sms.unit`, the check is broken.

After any fix, return to Step 2 and rerun.

- [ ] **Step 5: Final state check**

```bash
git status
git log --oneline -10
```

Expected: working tree clean; recent commits show (top is HEAD):
- one feat commit for `sms.area`
- one test commit for `smoke_area.sh`
- two refactor commits (group.lua, unit.lua)
- one feat commit for the helpers in `sms.lua`
- one refactor commit for `log.lua` (tag exposure)
- one docs commit for the design spec
- one docs commit for this plan

All four primary smoke tests (group, unit, area, plus the basic `smoke.sh`) green twice in a row.

No commit needed in this task unless Step 4 required fixes.

---

## Self-Review Checklist

Before declaring done:

- [ ] `framework/log.lua` exposes `tag` field; existing logger callers are unaffected.
- [ ] `framework/sms.lua` has `_make_callable_handle` and `_is_handle_of` helpers.
- [ ] `framework/group.lua` uses `_make_callable_handle`; `smoke_group.sh` green.
- [ ] `framework/unit.lua` uses `_make_callable_handle`; `smoke_unit.sh` green.
- [ ] `framework/area.lua` exists, loads cleanly, all 10 methods + 4 constructors implemented.
- [ ] `framework/test/smoke_area.sh` exists, executable, ends with `smoke ok`.
- [ ] All other smoke tests (`smoke.sh`, `smoke_group.sh`, `smoke_unit.sh`) unchanged and green.
- [ ] `is_unit_in` / `is_*_of_group_in` use strict handle-type checking via `sms._is_handle_of`.
- [ ] No `error()` calls anywhere in the new code — every failure goes through `log.error + return nil/false`.
- [ ] Polygon `get_random_point` uses rejection sampling with 100-attempt cap and centroid fallback.
- [ ] Circle `get_random_point` uses sqrt-corrected uniform distribution.
- [ ] `create_circular` rejects bad center (non-vec3) and bad radius (≤0).
- [ ] `create_polygon` rejects fewer than 3 vertices and any non-vec3 vertex.
- [ ] Anonymous areas (no `name` arg) → `:get_name()` returns `nil`.
- [ ] `sms.area("typo")` logs `couldn't find area 'typo'` (using shared helper format) and returns nil.
- [ ] All work committed on branch `sms-area-v1`.
- [ ] `smoke_area.sh` runs green idempotently.

## Out of scope (do NOT do)

- Triangulation-based polygon `get_random_point` — tracked in #4.
- Self-intersecting polygon detection.
- Polygons with holes.
- 3D volumes.
- Boolean operations on areas.
- F10 map drawing / smoke / flare.
- `is_static_in` (no `sms.static` exists).
- Snapshot invalidation / `:refresh()` method.
- Auto-detection of non-polygon ME drawings (lines, text, icons).
- Touching `tools/`, `framework/utils.lua`, `framework/timer.lua`, or any non-area smoke test (other than verifying they still pass).
- Adding a `sms.zone` alias — name is locked as `sms.area`.

## Self-review notes from plan author

**Spec coverage:**
- **Refactor (helpers + log + group + unit)** → Tasks 1-4 cover each piece independently with intermediate smoke verification.
- **`sms.area("ZoneName")` callable for circle and quad** → Task 6's setmetatable(sms.area, {__call = ...}) dispatches on `radius` vs `verticies`.
- **`sms.area.from_drawing`** → Task 6 implementation; Task 5 smoke test treats it as conditional per spec.
- **`sms.area.create_circular`** → Task 6 implementation; Task 5 covers happy path + 3 invalid-input cases.
- **`sms.area.create_polygon`** → Task 6 implementation; Task 5 covers happy path + 3 invalid-input cases.
- **All 10 methods** → Task 6 implementation; Task 5 covers each method on at least one shape (circle for ME-discovered; polygon for runtime square).
- **Strict handle typing on is_unit_in / is_*_of_group_in** → Task 6 uses `sms._is_handle_of`; Task 5 explicitly tests `is_unit_in(group_handle)` returning false.
- **Failure model: log + nil/false, never throw** → Every error path in Task 6 calls `log.error(...)` then returns nil/false. No `error()` calls.
- **Polygon containment via ray-casting** → Task 6's `_point_in_polygon` uses the standard horizontal-ray algorithm.
- **Polygon get_random_point: rejection sampling + centroid fallback** → Task 6's `_random_in_polygon` caps at 100 attempts, logs and returns centroid on miss.
- **Circle uniform random distribution** → Task 6's `_random_in_circle` uses `math.sqrt(math.random())`.
- **Anonymous areas** → Task 6's `_make_circle_handle` / `_make_polygon_handle` accept nil `name`; `:get_name()` returns whatever was passed.
- **Vertices stored as copies (immutable from user POV)** → Task 6's `_make_polygon_handle` and `get_vertices` both deep-copy.
- **`is_all_of_group_in(empty/dead)` returns false** → Task 6 explicitly returns false for `not units or #units == 0`.

**Placeholder scan:** Zero placeholders. All code blocks complete and compilable.

**Type consistency:**
- Handle table shape across all four constructors: `{name=, kind=, _data=}` with `{__index = sms.area}` metatable.
- `_data` shape varies by kind, consistently:
  - circle: `{center = vec3, radius = number}`
  - polygon: `{vertices = list, centroid = vec3, bbox = {min_x, max_x, min_z, max_z}}`
- All log messages start with `<method>:` for in-method failures, or are bare for callable misses.
- All vec3-validating helpers use the same `_validate_vec3` predicate.

**Cross-task consistency:**
- Task 1's logger change (adding `tag` field) is consumed by Task 2's `_make_callable_handle` (`module_log.tag:match...`). Verified the field name matches.
- Task 2's `_is_handle_of` is consumed by Task 6's `sms.area` methods. Verified the function name and signature match.
- Task 6's area module references `sms.unit.get_position` and `sms.group.get_units`, which exist on `main` (not modified by this branch). Verified.
