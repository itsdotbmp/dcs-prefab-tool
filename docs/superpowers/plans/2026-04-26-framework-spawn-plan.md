# `sms.group.create` + `sms.group.clone` v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two stateless factory functions to `sms.group` (`create` and `clone`) for spawning new DCS groups, plus four unit-conversion helpers in `sms.utils`. Single new module file (`framework/spawn.lua`); no SPAWN class equivalent.

**Architecture:** A new `framework/spawn.lua` adds `sms.group.create` and `sms.group.clone` to the existing `sms.group` module at load time. All implementation, validation, name-collision suffixing, and DCS API translation lives in `spawn.lua` as file-local helpers. `framework/utils.lua` gets four pure conversion functions (deg/rad, ft/m). A bridge-driven smoke test exercises ground+air create paths, auto-suffix behavior, the clone path against an ME-discovered template, and all documented failure modes.

**Tech Stack:** Lua 5.1 (DCS mission environment), bash (mingw on Windows), the existing `dcs-sms.exe` execution bridge, DCS APIs (`coalition.addGroup`, `Group.getByName`, `Unit.getByName`, `country.id.*`, `Group.Category.*`, `env.mission.*`).

**Spec:** `docs/superpowers/specs/2026-04-26-framework-spawn-design.md`

---

## File Structure

| File | Purpose | Change |
|---|---|---|
| `framework/utils.lua` | Helpers/conversions | Edit: add 4 conversion functions (deg_to_rad, rad_to_deg, feet_to_meters, meters_to_feet) |
| `framework/spawn.lua` | Spawn implementation | NEW (~500 lines): all internal helpers + adds `sms.group.create` and `sms.group.clone` |
| `framework/test/smoke_spawn.sh` | Bridge smoke test | NEW (~400 lines): exercises both factories end-to-end |

Existing files (`sms.lua`, `log.lua`, `group.lua`, `unit.lua`, `area.lua`, `timer.lua`, the existing smoke tests) are unchanged.

## Parallelism

Tasks 1, 2, and 3 touch entirely different files and have NO edit-time dependencies on each other. They can be dispatched in parallel:

- **Task 1** edits `framework/utils.lua` (additive)
- **Task 2** creates `framework/test/smoke_spawn.sh` (new file)
- **Task 3** creates `framework/spawn.lua` (new file)

Task 4 (verification) is sequential and run by the controller after Tasks 1-3 complete.

---

## Task 1: Add 4 conversion functions to `framework/utils.lua`

**Files:**
- Modify: `framework/utils.lua`

- [ ] **Step 1: Read the current file**

The current `framework/utils.lua` exists and contains an `add_numbers` example function. Read it to understand the structure (header comment + `assert` + `local log = sms.log.module(...)` + `sms.utils = sms.utils or {}` + function definitions).

- [ ] **Step 2: Append the four conversion functions**

After the existing function definitions (and before any closing block — there shouldn't be one; Lua files don't need explicit endings), add EXACTLY these four functions:

```lua

-- Heading conversion: framework public input is degrees, DCS API is radians.
sms.utils.deg_to_rad = function(deg)
  if type(deg) ~= "number" then
    log.error("deg_to_rad: argument must be a number, got " .. type(deg))
    return nil
  end
  return deg * math.pi / 180
end

sms.utils.rad_to_deg = function(rad)
  if type(rad) ~= "number" then
    log.error("rad_to_deg: argument must be a number, got " .. type(rad))
    return nil
  end
  return rad * 180 / math.pi
end

-- Altitude conversion: framework I/O is meters (DCS-native), but pilots
-- think in feet — these helpers are for user code, not internal.
sms.utils.feet_to_meters = function(ft)
  if type(ft) ~= "number" then
    log.error("feet_to_meters: argument must be a number, got " .. type(ft))
    return nil
  end
  return ft * 0.3048
end

sms.utils.meters_to_feet = function(m)
  if type(m) ~= "number" then
    log.error("meters_to_feet: argument must be a number, got " .. type(m))
    return nil
  end
  return m / 0.3048
end
```

These functions:
- Validate input type (return `nil + log` on bad input — framework convention)
- Use the canonical conversion factor `0.3048` for feet/meters
- Have no side effects; pure math

- [ ] **Step 3: SKIP the live bridge sanity-check**

Multiple subagents may be running in parallel against the same DCS bridge. Task 4 (verification) will exercise these via the smoke test.

- [ ] **Step 4: Commit**

```bash
git add framework/utils.lua
git commit -m "feat(framework): add deg/rad and feet/meters conversion helpers to sms.utils"
```

---

## Task 2: Failing smoke test `framework/test/smoke_spawn.sh`

**Files:**
- Create: `framework/test/smoke_spawn.sh`

- [ ] **Step 1: Write the smoke test**

Create `framework/test/smoke_spawn.sh` with EXACTLY this content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.group.create + sms.group.clone v1.
# Exercises sms.utils conversions, ground/air create, multi-unit offsets,
# heading-degrees translation, auto-suffix, and clone against an ME template.
# Requires: DCS running with the dcs-sms hook installed and a mission with
# at least one ME-defined group (any kind).

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

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file utils.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null
"${DCSSMS}" exec --file area.lua >/dev/null
"${DCSSMS}" exec --file spawn.lua >/dev/null

# ----------------------------------------------------------------
# Section 1: sms.utils conversion sanity
# ----------------------------------------------------------------
echo "==> [utils] deg_to_rad(180) approximately math.pi"
expect_true "deg_to_rad 180" '
  local r = sms.utils.deg_to_rad(180)
  return math.abs(r - math.pi) < 1e-9
'

echo "==> [utils] rad_to_deg(math.pi) approximately 180"
expect_true "rad_to_deg pi" '
  local d = sms.utils.rad_to_deg(math.pi)
  return math.abs(d - 180) < 1e-9
'

echo "==> [utils] feet_to_meters(1000) approximately 304.8"
expect_true "feet_to_meters 1000" '
  local m = sms.utils.feet_to_meters(1000)
  return math.abs(m - 304.8) < 1e-9
'

echo "==> [utils] meters_to_feet(304.8) approximately 1000"
expect_true "meters_to_feet 304.8" '
  local f = sms.utils.meters_to_feet(304.8)
  return math.abs(f - 1000) < 1e-9
'

echo "==> [utils] round-trip meters_to_feet(feet_to_meters(5000)) == 5000"
expect_true "round-trip" '
  return math.abs(sms.utils.meters_to_feet(sms.utils.feet_to_meters(5000)) - 5000) < 1e-6
'

echo "==> [utils] non-number input returns nil"
expect_true "deg_to_rad nil" 'return sms.utils.deg_to_rad("not a number") == nil'

# ----------------------------------------------------------------
# Section 2: discover spawn coords + reset name counters
# ----------------------------------------------------------------
echo "==> discover spawn coords from existing mission"
spawn_response=$("${DCSSMS}" exec --code '
  local x, z = 0, 0
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then
          local p = units[1]:getPoint()
          x = p.x
          z = p.z
          break
        end
      end
      if x ~= 0 or z ~= 0 then break end
    end
  end
  return {x = x, z = z}
')
echo "${spawn_response}"
echo "${spawn_response}" | grep -q '"return_value":{' \
  || { echo "FAIL: could not discover spawn coords"; exit 1; }

# Extract x/z via separate exec calls for portability (no jq dependency).
SPAWN_X=$("${DCSSMS}" exec --code '
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then return units[1]:getPoint().x end
      end
    end
  end
  return 0
' | grep -oE '"return_value":[-0-9.]+' | grep -oE '[-0-9.]+$')
SPAWN_Z=$("${DCSSMS}" exec --code '
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then return units[1]:getPoint().z end
      end
    end
  end
  return 0
' | grep -oE '"return_value":[-0-9.]+' | grep -oE '[-0-9.]+$')
echo "==> using anchor x=${SPAWN_X} z=${SPAWN_Z}"

# ----------------------------------------------------------------
# Section 3: sms.group.create — ground single unit
# ----------------------------------------------------------------
echo "==> [create] ground single AAV-7 alive"
expect_eq_string "single AAV-7 type" "
  local g = sms.group.create({
    name      = '_smoke_spawn_single',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  if not g then return 'NO_HANDLE' end
  return sms.unit('_smoke_spawn_single-1'):get_type()
" "AAV7"

echo "==> [create] cleanup single AAV-7"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_single')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 4: sms.group.create — multi-unit with offsets
# ----------------------------------------------------------------
echo "==> [create] multi-unit AAV-7 group with offsets"
expect_true "3 units spawned" "
  local g = sms.group.create({
    name      = '_smoke_spawn_multi',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {
      { type = 'AAV7', offset = {x = 0, y = 0, z = 0} },
      { type = 'AAV7', offset = {x = 0, y = 0, z = 20} },
      { type = 'AAV7', offset = {x = 0, y = 0, z = 40} },
    },
  })
  if not g then return false end
  return #g:get_units() == 3
"

echo "==> [create] verify offsets translated to world positions"
expect_true "offsets correct" "
  local units = sms.group('_smoke_spawn_multi'):get_units()
  if not units or #units ~= 3 then return false end
  -- Expected world positions: (x, _, z), (x, _, z+20), (x, _, z+40)
  -- Allow floating-point tolerance and terrain-snapped y differences.
  local p1 = units[1]:get_position()
  local p2 = units[2]:get_position()
  local p3 = units[3]:get_position()
  local ok1 = math.abs(p1.x - ${SPAWN_X}) < 1 and math.abs(p1.z - ${SPAWN_Z}) < 1
  local ok2 = math.abs(p2.x - ${SPAWN_X}) < 1 and math.abs(p2.z - (${SPAWN_Z} + 20)) < 1
  local ok3 = math.abs(p3.x - ${SPAWN_X}) < 1 and math.abs(p3.z - (${SPAWN_Z} + 40)) < 1
  return ok1 and ok2 and ok3
"

echo "==> [create] cleanup multi-unit"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_multi')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 5: heading degrees -> radians at spawn
# ----------------------------------------------------------------
echo "==> [create] heading 90 degrees -> ~pi/2 radians on the unit"
expect_true "heading translated" "
  local g = sms.group.create({
    name      = '_smoke_spawn_heading',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7', heading = 90 }},
  })
  if not g then return false end
  -- Read back unit orientation. unit:getPosition() returns a 4x4 matrix-ish table:
  -- {p = {x,y,z}, x = {x,y,z}, y = {x,y,z}, z = {x,y,z}}
  -- The unit's facing yaw (heading angle in radians, 0=N, pi/2=E in DCS conv)
  -- can be derived from the x-vector (forward-facing direction).
  local u = Unit.getByName('_smoke_spawn_heading-1')
  local pos = u:getPosition()
  -- pos.x.z and pos.x.x give us atan2 for yaw.
  local yaw = math.atan2(pos.x.z, pos.x.x)
  -- Expect yaw close to pi/2 (heading 90 = east = +z direction in our vec3 conv,
  -- which is +y in DCS-2D). With sms.utils.deg_to_rad(90) = pi/2, the unit's
  -- forward should be along +z. Tolerance 0.05 rad (~3 deg) for terrain effects.
  return math.abs(yaw - math.pi/2) < 0.05 or math.abs(yaw - math.pi/2 - 2*math.pi) < 0.05
"

echo "==> [create] cleanup heading"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_heading')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 6: sms.group.create — air with altitude
# ----------------------------------------------------------------
echo "==> [create] air F-16 at 5000m altitude"
expect_true "air spawned at altitude" "
  local g = sms.group.create({
    name      = '_smoke_spawn_air',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'airplane',
    units     = {
      {
        type = 'F-16C_50',
        alt = 5000,
        speed = 200,
      }
    },
  })
  if not g then return false end
  local u = Unit.getByName('_smoke_spawn_air-1')
  if not u then return false end
  local p = u:getPoint()
  -- Altitude (DCS world y) should be ~5000m, allow large tolerance for terrain reference.
  return p.y > 4000 and p.y < 6000
"

echo "==> [create] cleanup air"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_air')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 7: auto-suffix on name collision
# ----------------------------------------------------------------
echo "==> [auto-suffix] first 'tank' resolves to 'tank'"
expect_eq_string "tank first" "
  local g = sms.group.create({
    name      = 'tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "tank"

echo "==> [auto-suffix] second 'tank' resolves to 'tank-1'"
expect_eq_string "tank second" "
  local g = sms.group.create({
    name      = 'tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "tank-1"

echo "==> [auto-suffix] third 'tank' resolves to 'tank-2'"
expect_eq_string "tank third" "
  local g = sms.group.create({
    name      = 'tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "tank-2"

echo "==> [auto-suffix] cleanup"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'tank', 'tank-1', 'tank-2'}) do
    local g = sms.group(name)
    if g then g:destroy() end
  end
" >/dev/null

# ----------------------------------------------------------------
# Section 8: sms.group.create — negative paths
# ----------------------------------------------------------------
echo "==> [create] missing config -> nil"
expect_true "no config" 'return sms.group.create() == nil'

echo "==> [create] non-table config -> nil"
expect_true "string config" 'return sms.group.create("not a table") == nil'

echo "==> [create] missing name -> nil"
expect_true "no name" "
  return sms.group.create({
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] missing position -> nil"
expect_true "no position" "
  return sms.group.create({
    name = 'no_pos',
    country = 'USA',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] missing country -> nil"
expect_true "no country" "
  return sms.group.create({
    name = 'no_country',
    position = {x = 0, y = 0, z = 0},
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] bad country -> nil"
expect_true "bad country" "
  return sms.group.create({
    name = 'bad_country',
    position = {x = 0, y = 0, z = 0},
    country = 'WAKANDA',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] bad category -> nil"
expect_true "bad category" "
  return sms.group.create({
    name = 'bad_cat',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    category = 'submarine',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] missing units -> nil"
expect_true "no units" "
  return sms.group.create({
    name = 'no_units',
    position = {x = 0, y = 0, z = 0},
    country = 'USA'
  }) == nil
"

echo "==> [create] empty units -> nil"
expect_true "empty units" "
  return sms.group.create({
    name = 'empty_units',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    units = {}
  }) == nil
"

echo "==> [create] unit missing type -> nil"
expect_true "unit no type" "
  return sms.group.create({
    name = 'no_type',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    units = {{ heading = 0 }}
  }) == nil
"

echo "==> [create] air category with no alt -> nil"
expect_true "air no alt" "
  return sms.group.create({
    name = 'air_no_alt',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    category = 'airplane',
    units = {{ type = 'F-16C_50' }}
  }) == nil
"

# ----------------------------------------------------------------
# Section 9: sms.group.clone — discover ME template + clone
# ----------------------------------------------------------------
echo "==> [clone] discover an ME-defined group name"
TEMPLATE_NAME=$("${DCSSMS}" exec --code '
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  local cat_keys = {"plane", "helicopter", "vehicle", "ship"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country in ipairs(side.country) do
        for _, ck in ipairs(cat_keys) do
          local cat = country[ck]
          if cat and cat.group then
            for _, g in ipairs(cat.group) do
              return g.name
            end
          end
        end
      end
    end
  end
  return nil
' | grep -oE '"return_value":"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')

if [ -z "${TEMPLATE_NAME}" ]; then
  echo "FAIL: no ME-defined group found in mission. Add at least one group in the Mission Editor and reload."
  exit 1
fi
echo "==> [clone] using template: ${TEMPLATE_NAME}"

echo "==> [clone] clone with new name + position"
expect_true "clone exists" "
  local g = sms.group.clone('${TEMPLATE_NAME}', {
    name = '_smoke_spawn_clone',
    position = {x = ${SPAWN_X} + 1000, y = 0, z = ${SPAWN_Z}},
  })
  if not g then return false end
  return sms.group(g:get_name()):is_alive()
"

echo "==> [clone] cleanup"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_clone')
  if g then g:destroy() end
" >/dev/null

echo "==> [clone] auto-suffix on second clone with same name"
expect_eq_string "first clone resolved name" "
  local g = sms.group.clone('${TEMPLATE_NAME}', {
    name = '_smoke_spawn_clone_dup',
    position = {x = ${SPAWN_X} + 2000, y = 0, z = ${SPAWN_Z}},
  })
  return g and g:get_name() or 'NIL'
" "_smoke_spawn_clone_dup"

expect_eq_string "second clone resolved name with suffix" "
  local g = sms.group.clone('${TEMPLATE_NAME}', {
    name = '_smoke_spawn_clone_dup',
    position = {x = ${SPAWN_X} + 3000, y = 0, z = ${SPAWN_Z}},
  })
  return g and g:get_name() or 'NIL'
" "_smoke_spawn_clone_dup-1"

echo "==> [clone] cleanup duplicates"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'_smoke_spawn_clone_dup', '_smoke_spawn_clone_dup-1'}) do
    local g = sms.group(name)
    if g then g:destroy() end
  end
" >/dev/null

echo "==> [clone] missing template -> nil"
expect_true "missing template" "
  return sms.group.clone('_definitely_not_a_template_xyz', {
    name = 'never',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] missing name override -> nil"
expect_true "no override name" "
  return sms.group.clone('${TEMPLATE_NAME}', {
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] missing position override -> nil"
expect_true "no override position" "
  return sms.group.clone('${TEMPLATE_NAME}', {
    name = 'no_pos_override',
  }) == nil
"

# ----------------------------------------------------------------
# Section 10: log assertion
# ----------------------------------------------------------------
echo "==> [log] dcs.log should contain [sms.spawn] line for unknown country"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.spawn\]' -n 200)
echo "${log_window}" | grep -q "unknown country" \
  || { echo "FAIL: missing log line for unknown country"; echo "${log_window}"; exit 1; }

echo "smoke ok"
```

- [ ] **Step 2: Make it executable and run; expect failure**

```bash
chmod +x framework/test/smoke_spawn.sh
framework/test/smoke_spawn.sh
```

Expected: failure at `==> load framework files` step on `exec --file spawn.lua` because `framework/spawn.lua` doesn't exist yet — the correct TDD red.

Earlier failures (no DCS, no fresh heartbeat, missing ME group) are also valid red — note in the report.

If failure is at any step before framework loading (bash syntax error, dcs-sms.exe not found), STOP and report.

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_spawn.sh
git commit -m "test: add bridge-driven smoke test for sms.group.create + clone"
```

---

## Task 3: Implement `framework/spawn.lua`

**Files:**
- Create: `framework/spawn.lua`

- [ ] **Step 1: Write the file**

Create `framework/spawn.lua` with EXACTLY this content:

```lua
-- dcs-sms framework: spawn module.
--
-- Adds two factory functions to sms.group:
--   sms.group.create(config)             -> sms.group handle | nil + log
--   sms.group.clone(template, overrides) -> sms.group handle | nil + log
--
-- Stateless. Plain config tables. Auto-suffixes on name collision (so
-- create({name = "tank"}) called repeatedly yields tank, tank-1, tank-2,
-- ...). The returned handle's :get_name() is authoritative for the resolved
-- name — always use the handle, not the input string, for follow-up ops.
--
-- Public field names: position (group anchor, vec3), offset (per-unit
-- relative, vec3). Heading is in DEGREES; altitude is in METERS.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua -> unit.lua
-- -> area.lua -> spawn.lua. spawn.lua does not depend on area.lua but is
-- loaded after for consistency.
--
-- See docs/superpowers/specs/2026-04-26-framework-spawn-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.group) == "table", "framework/group.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.spawn")

-- ============================================================
-- Module-private state and lookup tables
-- ============================================================

-- base_name -> next-index hint for auto-suffix. Lost on reload (probe
-- recovers).
local _name_counters = {}

-- "ground" -> Group.Category.GROUND etc.
local _category_map = {
  ground     = Group.Category.GROUND,
  airplane   = Group.Category.AIRPLANE,
  helicopter = Group.Category.HELICOPTER,
  ship       = Group.Category.SHIP,
  train      = Group.Category.TRAIN,
}

-- Default group-level task per category.
local _default_task = {
  ground     = "Ground Nothing",
  airplane   = "Nothing",
  helicopter = "Nothing",
  ship       = "Nothing",
  train      = "Nothing",
}

-- Mission-descriptor category keys (env.mission.coalition.<side>.country[i].<cat>)
-- mapped to our category strings.
local _mission_cat_to_string = {
  plane      = "airplane",
  helicopter = "helicopter",
  vehicle    = "ground",
  ship       = "ship",
  train      = "train",
}

-- ============================================================
-- Validation helpers
-- ============================================================

local function _is_vec3(v)
  return type(v) == "table"
     and type(v.x) == "number"
     and type(v.y) == "number"
     and type(v.z) == "number"
end

local function _resolve_country(s)
  if type(s) ~= "string" then return nil end
  local key = s:upper():gsub(" ", "_")
  return country.id[key]
end

local function _resolve_category(s)
  if type(s) ~= "string" then return nil end
  return _category_map[s:lower()]
end

-- ============================================================
-- Auto-suffix name resolution
-- ============================================================

-- getter: function(name) -> non-nil if name is taken (Group.getByName or Unit.getByName)
local function _resolve_unique_name(base, getter)
  if not getter(base) then return base end
  local n = _name_counters[base] or 1
  while getter(base .. "-" .. n) do
    n = n + 1
  end
  _name_counters[base] = n + 1
  return base .. "-" .. n
end

-- ============================================================
-- DCS group_def builder
-- ============================================================

-- Build a single DCS unit table from a unit spec, anchor, and category.
-- Mutates u_spec is forbidden — we read fields and copy what we need.
local function _build_dcs_unit(u_spec, anchor, category, base_unit_name, idx)
  local offset = u_spec.offset or {x = 0, y = 0, z = 0}
  local heading_deg = u_spec.heading or 0
  local heading_rad = sms.utils.deg_to_rad(heading_deg) or 0

  -- Auto-suffix the unit name. If user provided one, suffix it. Otherwise
  -- auto-generate from the resolved group name + index.
  local desired_name
  if type(u_spec.name) == "string" then
    desired_name = u_spec.name
  else
    desired_name = base_unit_name .. "-" .. idx
  end
  local resolved_unit_name = _resolve_unique_name(desired_name, Unit.getByName)

  local dcs_unit = {
    name    = resolved_unit_name,
    type    = u_spec.type,
    -- DCS-2D: x = vec3.x (east), y = vec3.z (north)
    x       = anchor.x + offset.x,
    y       = anchor.z + offset.z,
    heading = heading_rad,
    psi     = -heading_rad,  -- DCS internal yaw, computed from heading
    skill   = u_spec.skill or "Average",
  }

  -- Optional universal fields
  if u_spec.livery_id   ~= nil then dcs_unit.livery_id   = u_spec.livery_id end
  if u_spec.onboard_num ~= nil then dcs_unit.onboard_num = u_spec.onboard_num end

  -- Air-specific fields
  if category == "airplane" or category == "helicopter" then
    if u_spec.alt        ~= nil then dcs_unit.alt        = u_spec.alt end
    if u_spec.alt_type   ~= nil then dcs_unit.alt_type   = u_spec.alt_type else dcs_unit.alt_type = "BARO" end
    if u_spec.speed      ~= nil then dcs_unit.speed      = u_spec.speed end
    if u_spec.payload    ~= nil then dcs_unit.payload    = u_spec.payload end
    if u_spec.callsign   ~= nil then dcs_unit.callsign   = u_spec.callsign end
    if u_spec.frequency  ~= nil then dcs_unit.frequency  = u_spec.frequency end
    if u_spec.modulation ~= nil then dcs_unit.modulation = u_spec.modulation end
    if u_spec.parking_id ~= nil then dcs_unit.parking_id = u_spec.parking_id end
  end

  -- Pass-through any unknown fields verbatim
  local known = {
    name = true, type = true, offset = true, heading = true, skill = true,
    livery_id = true, onboard_num = true, alt = true, alt_type = true,
    speed = true, payload = true, callsign = true, frequency = true,
    modulation = true, parking_id = true,
  }
  for k, v in pairs(u_spec) do
    if not known[k] and dcs_unit[k] == nil then
      dcs_unit[k] = v
    end
  end

  return dcs_unit
end

-- Default route for aircraft: single waypoint 50km north of anchor.
local function _default_route_for_aircraft(anchor, first_unit_alt)
  local alt = first_unit_alt or 5000
  return {
    points = {
      [1] = {
        type     = "Turning Point",
        action   = "Turning Point",
        x        = anchor.x,
        y        = anchor.z + 50000,  -- DCS-2D north
        alt      = alt,
        alt_type = "BARO",
        speed    = 200,
        task     = { id = "ComboTask", params = { tasks = {} } },
      },
    },
  }
end

-- Build the full DCS group_def from a validated cfg + resolved group name.
local function _build_dcs_group_def(cfg, resolved_group_name, category)
  local anchor = cfg.position
  local task = cfg.task or _default_task[category] or "Nothing"

  local dcs_units = {}
  for i, u_spec in ipairs(cfg.units) do
    dcs_units[i] = _build_dcs_unit(u_spec, anchor, category, resolved_group_name, i)
  end

  local def = {
    name  = resolved_group_name,
    task  = task,
    units = dcs_units,
  }

  -- Route handling
  if cfg.route ~= nil then
    def.route = cfg.route
  elseif category == "airplane" or category == "helicopter" then
    def.route = _default_route_for_aircraft(anchor, cfg.units[1].alt)
  end

  -- Pass-through unknown group-level fields
  local known = {
    name = true, position = true, country = true, category = true,
    task = true, route = true, units = true,
  }
  for k, v in pairs(cfg) do
    if not known[k] and def[k] == nil then
      def[k] = v
    end
  end

  return def
end

-- ============================================================
-- Spawn execution
-- ============================================================

local function _spawn(group_def, country_int, category_int, resolved_group_name)
  -- coalition.addGroup may error on bad input. Wrap in pcall.
  local ok, err = pcall(coalition.addGroup, country_int, category_int, group_def)
  if not ok then
    log.error("DCS rejected the spawn: " .. tostring(err))
    return nil
  end
  -- Verify by name
  if not Group.getByName(resolved_group_name) then
    log.error("DCS accepted addGroup but group '" .. resolved_group_name .. "' not found post-call (check type/payload validity)")
    return nil
  end
  return sms.group(resolved_group_name)
end

-- ============================================================
-- create
-- ============================================================

local function _validate_create_config(cfg)
  if type(cfg) ~= "table" then
    log.error("create: config must be a table")
    return false
  end
  if type(cfg.name) ~= "string" or cfg.name == "" then
    log.error("create: name is required (non-empty string)")
    return false
  end
  if not _is_vec3(cfg.position) then
    log.error("create: position is required (vec3 with x/y/z numbers)")
    return false
  end
  if type(cfg.country) ~= "string" then
    log.error("create: country is required (string)")
    return false
  end
  if type(cfg.units) ~= "table" or #cfg.units == 0 then
    log.error("create: units is required (non-empty table)")
    return false
  end
  for i, u in ipairs(cfg.units) do
    if type(u) ~= "table" then
      log.error("create: unit " .. i .. " must be a table")
      return false
    end
    if type(u.type) ~= "string" or u.type == "" then
      log.error("create: unit " .. i .. " missing type")
      return false
    end
    if u.offset ~= nil and not _is_vec3(u.offset) then
      log.error("create: unit " .. i .. " offset must be a vec3")
      return false
    end
    if u.heading ~= nil and type(u.heading) ~= "number" then
      log.error("create: unit " .. i .. " heading must be a number (degrees)")
      return false
    end
  end
  return true
end

sms.group.create = function(cfg)
  if not _validate_create_config(cfg) then return nil end

  local country_int = _resolve_country(cfg.country)
  if not country_int then
    log.error("create: unknown country '" .. tostring(cfg.country) .. "'")
    return nil
  end

  local category_str = cfg.category or "ground"
  local category_int = _resolve_category(category_str)
  if not category_int then
    log.error("create: unknown category '" .. tostring(cfg.category) .. "'")
    return nil
  end

  -- Air-specific validation: every unit must have alt
  if category_str == "airplane" or category_str == "helicopter" then
    for i, u in ipairs(cfg.units) do
      if type(u.alt) ~= "number" then
        log.error("create: air unit " .. i .. " missing alt (meters)")
        return nil
      end
    end
  end

  local resolved_group_name = _resolve_unique_name(cfg.name, Group.getByName)
  local group_def = _build_dcs_group_def(cfg, resolved_group_name, category_str)
  return _spawn(group_def, country_int, category_int, resolved_group_name)
end

-- ============================================================
-- clone
-- ============================================================

-- Walk env.mission.coalition[*].country[*].<category>.group[] for the named group.
-- Returns {def, country_int, category_string} or nil.
local function _find_template_in_mission(template_name)
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country_entry in ipairs(side.country) do
        for cat_key, cat_string in pairs(_mission_cat_to_string) do
          local cat = country_entry[cat_key]
          if cat and cat.group then
            for _, g in ipairs(cat.group) do
              if g.name == template_name then
                return {
                  def = g,
                  country_int = country_entry.id,
                  category_string = cat_string,
                }
              end
            end
          end
        end
      end
    end
  end
  return nil
end

-- Deep-copy a table (recursive, handles nested tables).
local function _deep_copy(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = _deep_copy(v)
  end
  return copy
end

sms.group.clone = function(template_name, overrides)
  if type(template_name) ~= "string" or template_name == "" then
    log.error("clone: template_name must be a non-empty string")
    return nil
  end
  if type(overrides) ~= "table" then
    log.error("clone: overrides must be a table")
    return nil
  end
  if type(overrides.name) ~= "string" or overrides.name == "" then
    log.error("clone: overrides.name is required (non-empty string)")
    return nil
  end
  if not _is_vec3(overrides.position) then
    log.error("clone: overrides.position is required (vec3)")
    return nil
  end

  local found = _find_template_in_mission(template_name)
  if not found then
    log.error("clone: template '" .. template_name .. "' not in mission")
    return nil
  end

  local cat_int = _resolve_category(found.category_string)
  if not cat_int then
    log.error("clone: internal error — unknown category '" .. tostring(found.category_string) .. "'")
    return nil
  end

  local def = _deep_copy(found.def)
  if not def.units or #def.units == 0 then
    log.error("clone: template '" .. template_name .. "' has no units")
    return nil
  end

  -- Compute original anchor (leader unit's DCS-2D position).
  local orig_x = def.units[1].x
  local orig_y = def.units[1].y  -- DCS-2D y == our z

  -- New anchor from overrides.
  local new_anchor = overrides.position

  -- Re-anchor every unit: original (x, y) -> new (anchor.x + dx, anchor.z + dy)
  for _, u in ipairs(def.units) do
    local dx = u.x - orig_x
    local dz = u.y - orig_y
    u.x = new_anchor.x + dx
    u.y = new_anchor.z + dz
  end

  -- Resolve unique group name from overrides.
  local resolved_group_name = _resolve_unique_name(overrides.name, Group.getByName)
  def.name = resolved_group_name

  -- Resolve unique unit names per unit.
  for i, u in ipairs(def.units) do
    local desired_unit_name = resolved_group_name .. "-" .. i
    u.name = _resolve_unique_name(desired_unit_name, Unit.getByName)
  end

  -- Update route waypoint 1 if present (keep relative shape; just shift first point to new anchor).
  -- For v1 we don't try to be clever with subsequent waypoints; users override route via create() for that.
  if def.route and def.route.points and def.route.points[1] then
    def.route.points[1].x = new_anchor.x
    def.route.points[1].y = new_anchor.z
  end

  return _spawn(def, found.country_int, cat_int, resolved_group_name)
end
```

Notes for the implementer:
- `category_str` defaults to `"ground"` in `create`; in `clone` it comes from the mission descriptor walk.
- The `_resolve_country` `s:upper():gsub(" ", "_")` translation handles common DCS country keys like `country.id.USA`, `country.id.UNITED_KINGDOM` (gsub returns `(string, count)` — only the first return value matters here; Lua's `:gsub` is fine).
- Pass-through fields are merged AFTER known fields are set, with `dcs_unit[k] == nil` guard so we never overwrite a known field.
- Air units with no `alt_type` get `"BARO"` as default (MSL).
- The `_default_route_for_aircraft` puts the waypoint 50km north of anchor at the first unit's altitude.

- [ ] **Step 2: SKIP the live bridge sanity-check**

Other tasks may be running in parallel. Task 4 (verification) will exercise this end-to-end via the smoke test.

- [ ] **Step 3: Commit**

```bash
git add framework/spawn.lua
git commit -m "feat(framework): add sms.group.create + sms.group.clone with auto-suffix and offsets"
```

---

## Task 4: Run smoke tests, verify green

**Files:** none modified — verification only. May modify `framework/spawn.lua` or `framework/test/smoke_spawn.sh` if green-light reveals issues.

- [ ] **Step 1: Confirm DCS is up and ready**

```bash
tools/dcs-sms.exe status
```

Expected: `mission loaded: true`, `fresh: true`. The mission must contain at least one ME-defined group (any kind) for the `clone` test.

- [ ] **Step 2: Run the existing smoke tests as a regression check**

```bash
framework/test/smoke.sh
framework/test/smoke_group.sh
framework/test/smoke_unit.sh
framework/test/smoke_area.sh
```

Each should print `smoke ok`. The new spawn module should not affect these — but verifies nothing leaked.

- [ ] **Step 3: Run smoke_spawn.sh**

```bash
framework/test/smoke_spawn.sh
```

Expected: terminates with `smoke ok`. ~10 seconds runtime.

- [ ] **Step 4: If green, run smoke_spawn.sh twice for idempotency**

```bash
framework/test/smoke_spawn.sh
framework/test/smoke_spawn.sh
```

Both runs end with `smoke ok`. The cleanup step destroys all spawned groups; the next run starts clean. Note: the auto-suffix counter survives across runs only within a single mission session — if you run twice, the second run's `tank-1` etc. names work because cleanup destroyed them, then probing finds them free again.

- [ ] **Step 5: If smoke fails, diagnose by category**

**A. `exec --file spawn.lua` returns ok:false.**
- Lua syntax/runtime error. Read the bridge response's `error` field. Fix in `framework/spawn.lua`. Commit `fix(framework): ...`.

**B. `[utils] deg_to_rad(180) approximately math.pi` fails.**
- Bug in `sms.utils.deg_to_rad`. Verify `deg * math.pi / 180`. Should be exact.

**C. ME group discovery returns empty `TEMPLATE_NAME`.**
- The mission has no ME-defined groups. Ask user to add one (any kind, any name). OR — the env.mission key walk uses keys that don't match this DCS version's mission descriptor. Inspect via:
  `tools/dcs-sms.exe exec --code "for sk, side in pairs(env.mission.coalition) do for k, v in pairs(side) do env.info('side='..sk..' field='..k) end end"` and adapt `_mission_cat_to_string` keys in `spawn.lua` accordingly.

**D. Spawn fails with "DCS rejected the spawn".**
- Type strings may be wrong for this DCS version. `AAV7` should work; `F-16C_50` is the standard F-16 type. Verify via:
  `tools/dcs-sms.exe exec --code "return Unit.getByName('<existing-unit-name>'):getTypeName()"` to see what an existing aircraft uses.
- Or country mismatch: `country.id.USA` should exist; `country.id.WAKANDA` should not.

**E. Multi-unit offset assertion fails (positions don't match `position + offset`).**
- The 2D-y → vec3-z translation may be wrong. Verify: in `_build_dcs_unit`, `dcs_unit.x = anchor.x + offset.x` and `dcs_unit.y = anchor.z + offset.z`.
- Tolerance issue: if positions are off by <1m, increase the `< 1` tolerance to `< 5` to accommodate terrain-snapping for ground units.

**F. Heading-degrees test fails.**
- Verify `_build_dcs_unit` calls `sms.utils.deg_to_rad(heading_deg)` not raw degrees.
- Verify the yaw extraction in the smoke test: `math.atan2(pos.x.z, pos.x.x)` for DCS's xz-plane forward vector.
- DCS may snap heading to nearest 5° for some unit types; widen tolerance to 0.1 rad if needed.

**G. Air spawn test (F-16 at 5000m) fails.**
- Aircraft need a route; check `_default_route_for_aircraft` is being called. If `cfg.route` is provided as `nil` explicitly (not absent), the `cfg.route ~= nil` check still treats it as absent — that's fine.
- Speed default: aircraft below stall speed will fail to spawn. Try increasing `speed = 200` in the test if needed.
- Type string: `F-16C_50` is the standard. If DCS rejects, try `F-16C` or check the mission's existing aircraft for the type string.

**H. Auto-suffix wrong sequence (e.g., second `tank` → `tank-2` instead of `tank-1`).**
- Verify `_name_counters[base] or 1` defaults to 1 (not 0).
- Verify the `_resolve_unique_name` while-loop probes correctly.

**I. Clone fails with "template not in mission" even though the user has groups.**
- The `_mission_cat_to_string` keys (`plane`, `vehicle`, etc.) don't match this DCS version. Probe and adapt.

After any fix, return to Step 3 and rerun.

- [ ] **Step 6: Final state check**

```bash
git status
git log --oneline -8
```

Expected: working tree clean; recent commits show (top is HEAD):
- `feat(framework): add sms.group.create + sms.group.clone with auto-suffix and offsets`
- `test: add bridge-driven smoke test for sms.group.create + clone`
- `feat(framework): add deg/rad and feet/meters conversion helpers to sms.utils`
- `docs: sms.group.create + sms.group.clone v1 design`
- (any fix commits from Step 5)

All five smoke tests run green.

No commit needed in this task unless Step 5 required fixes.

---

## Self-Review Checklist

Before declaring done:

- [ ] `framework/utils.lua` has `deg_to_rad`, `rad_to_deg`, `feet_to_meters`, `meters_to_feet` — all four functions, all type-checked
- [ ] `framework/spawn.lua` exists and loads cleanly
- [ ] `sms.group.create` and `sms.group.clone` are exposed on `sms.group` after spawn.lua loads
- [ ] All four existing smoke tests (`smoke.sh`, `smoke_group.sh`, `smoke_unit.sh`, `smoke_area.sh`) still green
- [ ] `smoke_spawn.sh` runs green idempotently (twice in a row)
- [ ] Auto-suffix verified: `tank` → `tank-1` → `tank-2`
- [ ] Multi-unit offset translation verified (3 units in a line, world positions = anchor + offset)
- [ ] Heading-degrees-to-radians verified (90° → ~π/2 rad on the unit's orientation matrix)
- [ ] Air spawn at altitude verified (`alt = 5000` lands ~5000m up)
- [ ] All negative-path tests pass (missing fields, bad country, bad category, etc.)
- [ ] Clone path works on an ME-discovered template
- [ ] Clone auto-suffix verified
- [ ] No `error()` calls anywhere in `spawn.lua`
- [ ] All work committed on branch `sms-spawn-v1`

## Out of scope (do NOT do)

- Static-object spawning (`coalition.addStaticObject`).
- Cargo.
- Per-unit overrides on `clone`.
- Live-API fallback for `clone`.
- `:activate()` / `:deactivate()` methods.
- Spawn limits / scheduled spawns.
- Event hooks.
- Group-level `heading` default.
- `strict_name = true` opt-out.
- Output-side feet/degrees conversion (getters stay DCS-native).
- Aircraft route DSL helpers.
- Triangulation-based offset placement.
- A `sms.spawn` namespace.
- Touching `framework/group.lua`, `framework/unit.lua`, `framework/area.lua`, `framework/timer.lua`, `framework/log.lua`, or any non-spawn smoke test.

## Self-review notes from plan author

**Spec coverage:**
- **`sms.utils.deg_to_rad/rad_to_deg/feet_to_meters/meters_to_feet`** → Task 1 implements all four with type validation; Task 2 smoke section 1 verifies them.
- **`sms.group.create` happy paths** (ground single, ground multi-unit with offsets, air with altitude, heading-degrees) → Task 3 implements; Task 2 sections 3-6 verify.
- **`sms.group.create` negative paths** (10+ failure cases) → Task 3 validation function; Task 2 section 8 verifies.
- **Auto-suffix on collision** → Task 3's `_resolve_unique_name` + `_name_counters`; Task 2 section 7 verifies sequence.
- **Pass-through unknown fields** → Task 3's known-key whitelist + iterate fallback; not directly tested in smoke (would require a contrived case) but covered by the implementation.
- **`sms.group.clone` discovery + re-anchor** → Task 3's `_find_template_in_mission` + offset-decompose-and-recompute; Task 2 section 9 verifies.
- **Clone auto-suffix** → Same `_resolve_unique_name` path; Task 2 section 9 verifies.
- **Air auto-default route** → Task 3's `_default_route_for_aircraft` invoked when `cfg.route` is absent; verified indirectly by air spawn assertion in Task 2 section 6 (would fail without the default route).
- **Failure model: log + nil, never throws** → Task 3 has zero `error()` calls; all paths go through `log.error + return nil`. `pcall` wraps `coalition.addGroup` to catch DCS-internal errors.
- **vec3 + offset → DCS-2D translation** → Task 3's `_build_dcs_unit`; Task 2 section 4 verifies positions.
- **Heading deg → rad** → Task 3 calls `sms.utils.deg_to_rad`; Task 2 section 5 verifies via orientation matrix.
- **Module organization** → Task 3 puts everything in `framework/spawn.lua`; load order documented at top of the file.

**Placeholder scan:** zero placeholders. All code blocks complete and compilable.

**Type consistency:**
- `cfg` always table; `cfg.position` always vec3 with x/y/z numbers; `cfg.units` always array of tables.
- `category` always lowercase string ("ground"/"airplane"/etc.); `category_int` always `Group.Category.*`.
- `country` always uppercased+gsubbed string; `country_int` always `country.id.*`.
- Handle return values consistent: `sms.group.create` and `sms.group.clone` both return `sms.group` handle | nil + log.
- `_resolve_unique_name` is used three times (group name in create, group name in clone, unit name in `_build_dcs_unit`) with consistent `(base, getter)` signature.
- Unit-table key whitelist matches between `_build_dcs_unit` (universal block, air block, pass-through block) and the spec's blessed-fields table.
