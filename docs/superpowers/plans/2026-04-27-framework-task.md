# `sms.task` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ergonomic task construction (`sms.task.<verb>(...)`) and runtime apply (`group:set_task` / `group:push_task`) so mission scripts can issue commands without hand-rolling DCS task tables.

**Architecture:** New `framework/task.lua` module with two layers — pure builders that return DCS task tables, and apply methods installed onto `sms.group`'s metatable. Builders stamp private `_sms_verb` and `_sms_air_only` fields; apply layer reads them for category checks. Companion change: `sms.group:get_category()` getter.

**Tech Stack:** Lua 5.1 (DCS scripting environment), bash (smoke harness), `dcs-sms.exe` execution bridge.

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `framework/group.lua` | modify | Add `sms.group.get_category(g)` |
| `framework/task.lua` | **new** | All builders + apply methods |
| `framework/test/smoke_task.sh` | **new** | Synthetic + live-DCS smoke coverage with EXIT-trap cleanup |
| `AGENTS.md` | modify | Add `sms.task` section + `:get_category()` row |
| `docs/superpowers/specs/2026-04-27-framework-task-design.md` | already committed | Spec |

Order: Task 1 first (companion change), then Task 2 (task.lua skeleton + builders), Task 3 (apply API in same file), Task 4 (smoke), Task 5 (AGENTS.md). Tasks share files only sequentially — no parallel-merge risk.

---

## Task 1: `sms.group:get_category()`

**Files:**
- Modify: `framework/group.lua` (insert after `get_coalition`)

- [ ] **Step 1: Insert the new method**

In `framework/group.lua`, after the `sms.group.get_coalition = function(g)` block (around line 50–63), add this `_category_str` lookup table and the new method. Place the lookup right after the existing comment about `coalition_int_to_str`:

```lua
-- DCS Group.Category int -> normalized lowercase string. Inline (not in
-- sms.utils) because no other module needs this mapping.
local _category_str = {
  [Group.Category.GROUND]     = "ground",
  [Group.Category.AIRPLANE]   = "airplane",
  [Group.Category.HELICOPTER] = "helicopter",
  [Group.Category.SHIP]       = "ship",
  [Group.Category.TRAIN]      = "train",
}

sms.group.get_category = function(g)
  local name = _name_of(g)
  if not sms.group.is_alive(name) then
    log.error("get_category: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local cat = Group.getByName(name):getCategory()
  local s = _category_str[cat]
  if not s then
    log.error("get_category: '" .. tostring(name) .. "' returned unknown category " .. tostring(cat))
    return nil
  end
  return s
end
```

- [ ] **Step 2: Sanity check**

Run: `luac -p framework/group.lua`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add framework/group.lua
git commit -m "feat(group): add :get_category() returning lowercase string"
```

---

## Task 2: `framework/task.lua` — module + helpers + builders

**Files:**
- Create: `framework/task.lua`

- [ ] **Step 1: Create the file with the full content below**

Create `framework/task.lua` with the following content:

```lua
-- dcs-sms framework: task module (sms.task).
--
-- Ergonomic builders for DCS task tables, plus runtime apply methods
-- (group:set_task, group:push_task) installed on sms.group's metatable.
--
-- The split between *build* and *apply* keeps tasks as first-class
-- values: a task can be stored, passed around, composed via combo,
-- or built once and applied to multiple groups.
--
-- Each builder returns a plain DCS task table with two private fields:
--   _sms_verb     -- string, used for log messages
--   _sms_air_only -- true for verbs DCS only honors on air groups
--
-- The fields are otherwise transparent to DCS. Manually-built task
-- tables (no _sms_* tags) skip the air-only check at apply time.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua ->
--                unit.lua -> area.lua -> timer.lua -> spawn.lua ->
--                static.lua -> events.lua -> weapon.lua -> task.lua.
--
-- See docs/superpowers/specs/2026-04-27-framework-task-design.md.

assert(type(sms) == "table",        "framework/sms.lua must be loaded first")
assert(type(sms.unit) == "table",   "framework/unit.lua must be loaded first")
assert(type(sms.group) == "table",  "framework/group.lua must be loaded first")
assert(type(sms.static) == "table", "framework/static.lua must be loaded first")
assert(type(sms.area) == "table",   "framework/area.lua must be loaded first")
assert(type(sms.utils) == "table",  "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.task")
sms.task = sms.task or {}

-- ============================================================
-- Internal helpers
-- ============================================================

-- DCS weaponType bitmask. "Auto" lets DCS pick from anything available.
-- These are the canonical aggregate values from the DCS task framework.
local _weapon_type_str = {
  Auto     = 4194304,
  Guns     = 805306368,
  Rockets  = 30720,
  Missiles = 4161536,
  Bombs    = 2032,
}

local function _resolve_weapon_type(v, verb)
  if v == nil then return _weapon_type_str.Auto end
  if type(v) == "number" then return v end
  if type(v) == "string" then
    local n = _weapon_type_str[v]
    if n then return n end
    log.error(verb .. ": unknown weapon_type '" .. v .. "', falling back to Auto")
    return _weapon_type_str.Auto
  end
  log.error(verb .. ": weapon_type must be a number or string, got " .. type(v))
  return _weapon_type_str.Auto
end

-- Resolve a target argument to a vec3 position. Accepts vec3, sms.unit,
-- sms.group, sms.static, sms.area handles. Returns nil + log on bad input.
local function _position_of(target, verb)
  if sms.utils.is_vec3(target) then
    return {x = target.x, y = target.y, z = target.z}
  end
  if sms._is_handle_of(target, sms.unit)   then return target:get_position() end
  if sms._is_handle_of(target, sms.group)  then return target:get_position() end
  if sms._is_handle_of(target, sms.static) then return target:get_position() end
  if sms._is_handle_of(target, sms.area)   then return target:get_position() end
  log.error(verb .. ": target must be a vec3 or an sms.unit/group/static/area handle")
  return nil
end

-- Stamp the framework's private metadata on a task table. Returns t for
-- chaining.
local function _stamp(t, verb, air_only)
  t._sms_verb = verb
  if air_only then t._sms_air_only = true end
  return t
end

-- ============================================================
-- Builders
-- ============================================================

-- Mission task with one waypoint at the target's snapshotted position.
-- Works for all categories: DCS interprets "Off Road" + "Turning Point"
-- per group category. Snapshot is at build time — if target moves, the
-- task still drives to the original spot. Use sms.task.follow for live
-- tracking.
sms.task.move_to = function(target)
  local pos = _position_of(target, "move_to")
  if not pos then return nil end
  return _stamp({
    id = "Mission",
    params = {
      route = {
        points = {
          {
            x            = pos.x,
            y            = pos.z,  -- DCS 2D y maps to vec3 z
            alt          = pos.y,
            type         = "Turning Point",
            action       = "Off Road",
            speed        = 200,
            speed_locked = true,
            task         = { id = "ComboTask", params = { tasks = {} } },
          },
        },
      },
    },
  }, "move_to", false)
end

-- Stop and hold position. Air group loiters; ground group stops.
-- DCS interprets "Nothing" appropriately per category.
sms.task.hold = function()
  return _stamp({ id = "Nothing", params = {} }, "hold", false)
end

-- Continuously follow a unit or group at a fixed offset.
-- Accepts sms.unit (resolves to its parent group) or sms.group.
-- Air-only in v1 — DCS Follow task is for aircraft formations.
sms.task.follow = function(target, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("follow: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local offset = opts.offset or {x = -50, y = 0, z = -50}
  if not sms.utils.is_vec3(offset) then
    log.error("follow: opts.offset must be a vec3, got " .. type(offset))
    return nil
  end

  local group_id
  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.error("follow: group '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    group_id = raw:getID()
  elseif sms._is_handle_of(target, sms.unit) then
    local raw = Unit.getByName(target.name)
    if not raw then
      log.error("follow: unit '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    local g = raw:getGroup()
    if not g then
      log.error("follow: unit '" .. tostring(target.name) .. "' has no group")
      return nil
    end
    group_id = g:getID()
  else
    log.error("follow: target must be sms.unit or sms.group handle")
    return nil
  end

  return _stamp({
    id = "Follow",
    params = {
      groupId          = group_id,
      pos              = {x = offset.x, y = offset.y, z = offset.z},
      lastWptIndexFlag = false,
    },
  }, "follow", true)
end

-- Orbit a point. Pattern is "Circle" (default) or "RaceTrack". Air only.
sms.task.orbit = function(pos, opts)
  if not sms.utils.is_vec3(pos) then
    log.error("orbit: pos must be a vec3, got " .. type(pos))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("orbit: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local altitude = opts.altitude or 5000
  local speed    = opts.speed    or 200
  local pattern  = opts.pattern  or "Circle"
  if pattern ~= "Circle" and pattern ~= "RaceTrack" then
    log.error("orbit: pattern must be 'Circle' or 'RaceTrack', got '" .. tostring(pattern) .. "'")
    return nil
  end
  if type(altitude) ~= "number" then
    log.error("orbit: opts.altitude must be a number, got " .. type(altitude))
    return nil
  end
  if type(speed) ~= "number" then
    log.error("orbit: opts.speed must be a number, got " .. type(speed))
    return nil
  end

  return _stamp({
    id = "Orbit",
    params = {
      pattern  = pattern,
      point    = {x = pos.x, y = pos.z},  -- DCS 2D
      altitude = altitude,
      speed    = speed,
    },
  }, "orbit", true)
end

-- Attack a unit or group. Air only in v1. Statics are explicitly rejected
-- (use sms.task.bomb on the static's position instead).
sms.task.attack = function(target, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("attack: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack")
  local expend      = opts.expend or "Auto"

  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.error("attack: group '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    return _stamp({
      id = "AttackGroup",
      params = {
        groupId        = raw:getID(),
        weaponType     = weapon_type,
        expend         = expend,
        attackQty      = opts.attack_qty,
        attackQtyLimit = opts.attack_qty ~= nil,
      },
    }, "attack", true)
  end

  if sms._is_handle_of(target, sms.unit) then
    local raw = Unit.getByName(target.name)
    if not raw then
      log.error("attack: unit '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    return _stamp({
      id = "AttackUnit",
      params = {
        unitId         = raw:getID(),
        weaponType     = weapon_type,
        expend         = expend,
        attackQty      = opts.attack_qty,
        attackQtyLimit = opts.attack_qty ~= nil,
      },
    }, "attack", true)
  end

  if sms._is_handle_of(target, sms.static) then
    log.error("attack: static targets not supported in v1; use bomb(static:get_position()) instead")
    return nil
  end

  log.error("attack: target must be sms.group or sms.unit handle")
  return nil
end

-- Engage anything in a circular sms.area. Air only in v1; polygon areas
-- rejected with log + nil.
sms.task.attack_in_area = function(area, opts)
  if not sms._is_handle_of(area, sms.area) then
    log.error("attack_in_area: area must be an sms.area handle")
    return nil
  end
  if area:get_kind() ~= "circle" then
    log.error("attack_in_area: area '" .. tostring(area.name) .. "' is " .. tostring(area:get_kind()) .. "; only circular areas supported in v1")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("attack_in_area: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local center = area:get_position()
  local radius = area:get_radius()
  if not center or not radius then
    log.error("attack_in_area: failed to read center/radius from area '" .. tostring(area.name) .. "'")
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack_in_area")

  local params = {
    point       = {x = center.x, y = center.z},
    zoneRadius  = radius,
    targetTypes = {"All"},
    weaponType  = weapon_type,
  }
  if opts.altitude_min then params.minAlt = opts.altitude_min end
  if opts.altitude_max then params.maxAlt = opts.altitude_max end

  return _stamp({
    id     = "EngageTargetsInZone",
    params = params,
  }, "attack_in_area", true)
end

-- Bomb a position. Target may be a vec3 or a handle (snapshotted to vec3).
-- Air only.
sms.task.bomb = function(target, opts)
  local pos = _position_of(target, "bomb")
  if not pos then return nil end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("bomb: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "bomb")
  local altitude    = opts.altitude or 6000
  if type(altitude) ~= "number" then
    log.error("bomb: opts.altitude must be a number, got " .. type(altitude))
    return nil
  end

  return _stamp({
    id = "Bombing",
    params = {
      point             = {x = pos.x, y = pos.z},
      altitude          = altitude,
      altitudeEnabled   = true,
      expend            = opts.expend or "Auto",
      weaponType        = weapon_type,
      direction         = opts.direction,
      directionEnabled  = opts.direction ~= nil,
      groupAttack       = opts.group_attack and true or false,
    },
  }, "bomb", true)
end

-- Land at a position or a handle's position. duration in seconds (default 300).
-- Air only (helicopters mostly).
sms.task.land = function(target, opts)
  local pos = _position_of(target, "land")
  if not pos then return nil end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.error("land: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local duration = opts.duration or 300
  if type(duration) ~= "number" then
    log.error("land: opts.duration must be a number, got " .. type(duration))
    return nil
  end

  return _stamp({
    id = "Land",
    params = {
      point         = {x = pos.x, y = pos.z},
      durationFlag  = true,
      duration      = duration,
    },
  }, "land", true)
end

-- Run all listed tasks in parallel via DCS ComboTask. Propagates
-- _sms_air_only if any constituent has it. Rejects with log + nil if any
-- constituent is nil (caught a builder error upstream) or non-table.
sms.task.combo = function(tasks)
  if type(tasks) ~= "table" then
    log.error("combo: tasks must be an array of task tables, got " .. type(tasks))
    return nil
  end
  if #tasks == 0 then
    log.error("combo: tasks list is empty")
    return nil
  end
  local any_air_only = false
  for i, t in ipairs(tasks) do
    if type(t) ~= "table" then
      log.error("combo: tasks[" .. i .. "] must be a task table, got " .. type(t))
      return nil
    end
    if t._sms_air_only then any_air_only = true end
  end
  return _stamp({
    id     = "ComboTask",
    params = { tasks = tasks },
  }, "combo", any_air_only)
end
```

- [ ] **Step 2: Sanity check**

Run: `luac -p framework/task.lua`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add framework/task.lua
git commit -m "feat(task): module skeleton + 9 builder verbs"
```

---

## Task 3: Apply API on `sms.group` metatable

**Files:**
- Modify: `framework/task.lua` (append at end)

- [ ] **Step 1: Append the apply API to the bottom of `framework/task.lua`**

Append after the `sms.task.combo` function:

```lua

-- ============================================================
-- Apply API (installed on sms.group metatable)
-- ============================================================

-- Validate task table shape: must be a table with id and params fields.
-- Manually-built tables (no _sms_* tags) are accepted; only the basic DCS
-- shape is required.
local function _is_task_table(t)
  return type(t) == "table" and type(t.id) == "string" and type(t.params) == "table"
end

-- Categories DCS will honor an air-only task on.
local _air_categories = { airplane = true, helicopter = true }

-- Shared validation for set_task and push_task. Returns the live DCS group
-- object on success, or nil after logging.
local function _validate_apply(method, group_handle, task)
  if not sms._is_handle_of(group_handle, sms.group) then
    log.error(method .. ": first argument must be an sms.group handle")
    return nil
  end
  if not group_handle:is_alive() then
    log.error(method .. ": group '" .. tostring(group_handle.name) .. "' is not alive")
    return nil
  end
  if not _is_task_table(task) then
    log.error(method .. ": task must be a table with 'id' (string) and 'params' (table) fields")
    return nil
  end
  if task._sms_air_only then
    local cat = group_handle:get_category()
    if not _air_categories[cat] then
      local verb = task._sms_verb or "task"
      log.error(method .. ": '" .. verb .. "' is air-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  local raw = Group.getByName(group_handle.name)
  if not raw then
    log.error(method .. ": group '" .. tostring(group_handle.name) .. "' disappeared between is_alive and apply")
    return nil
  end
  return raw
end

-- Replace the group's current task. Wraps Controller:setTask.
sms.group.set_task = function(g, task)
  local raw = _validate_apply("set_task", g, task)
  if not raw then return false end
  local controller = raw:getController()
  if not controller then
    log.error("set_task: group '" .. tostring(g.name) .. "' has no controller")
    return false
  end
  local ok, err = pcall(controller.setTask, controller, task)
  if not ok then
    log.error("set_task: DCS rejected task for '" .. tostring(g.name) .. "': " .. tostring(err))
    return false
  end
  return true
end

-- Push a task onto the group's task stack. Wraps Controller:pushTask.
-- DCS pushTask is LIFO: the new task interrupts the current one and
-- runs to completion, then the previous task resumes.
sms.group.push_task = function(g, task)
  local raw = _validate_apply("push_task", g, task)
  if not raw then return false end
  local controller = raw:getController()
  if not controller then
    log.error("push_task: group '" .. tostring(g.name) .. "' has no controller")
    return false
  end
  local ok, err = pcall(controller.pushTask, controller, task)
  if not ok then
    log.error("push_task: DCS rejected task for '" .. tostring(g.name) .. "': " .. tostring(err))
    return false
  end
  return true
end
```

- [ ] **Step 2: Sanity check**

Run: `luac -p framework/task.lua`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add framework/task.lua
git commit -m "feat(task): add group:set_task / push_task with air-only check"
```

---

## Task 4: `framework/test/smoke_task.sh`

**Files:**
- Create: `framework/test/smoke_task.sh` (executable)

- [ ] **Step 1: Create the smoke file with the full content below**

Create `framework/test/smoke_task.sh` with this content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.task v1.
# Synthetic checks (no DCS dispatch) verify builder shape + air-only flag.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused,
# at least one ME-defined group (any kind).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort (set -e). Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
SMOKE_FIXTURES="_smoke_task_ground _smoke_task_air _smoke_task_target_grp"

cleanup_smoke_fixtures() {
  [ -z "${SMOKE_FIXTURES}" ] && return 0
  local lua_list=""
  for n in ${SMOKE_FIXTURES}; do lua_list="${lua_list}'${n}',"; done
  "${DCSSMS}" exec --code "
    for _, n in ipairs({${lua_list%,}}) do
      local g = Group.getByName(n); if g then g:destroy() end
      local s = StaticObject.getByName(n); if s then s:destroy() end
    end" >/dev/null 2>&1 || true
}
trap cleanup_smoke_fixtures EXIT

cd "${FRAMEWORK_DIR}"

expect_true() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
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
"${DCSSMS}" exec --file static.lua >/dev/null
"${DCSSMS}" exec --file events.lua >/dev/null
"${DCSSMS}" exec --file weapon.lua >/dev/null
"${DCSSMS}" exec --file task.lua >/dev/null

# ----------------------------------------------------------------
# Section 1: synthetic builder shape checks
# ----------------------------------------------------------------
echo "==> [build] move_to(vec3) returns Mission task with one waypoint"
expect_str "move_to id" 'return sms.task.move_to({x=100,y=0,z=200}).id' 'Mission'
expect_str "move_to verb tag" 'return sms.task.move_to({x=100,y=0,z=200})._sms_verb' 'move_to'
expect_true "move_to not air-only" 'return sms.task.move_to({x=100,y=0,z=200})._sms_air_only == nil'

echo "==> [build] hold() returns Nothing task"
expect_str "hold id" 'return sms.task.hold().id' 'Nothing'

echo "==> [build] orbit returns air-only Orbit task"
expect_str "orbit id" 'return sms.task.orbit({x=0,y=0,z=0}).id' 'Orbit'
expect_true "orbit air-only" 'return sms.task.orbit({x=0,y=0,z=0})._sms_air_only == true'
expect_str "orbit verb tag" 'return sms.task.orbit({x=0,y=0,z=0})._sms_verb' 'orbit'

echo "==> [build] orbit pattern defaults to Circle"
expect_str "orbit default pattern" 'return sms.task.orbit({x=0,y=0,z=0}).params.pattern' 'Circle'

echo "==> [build] orbit RaceTrack pattern accepted"
expect_str "orbit racetrack" 'return sms.task.orbit({x=0,y=0,z=0}, {pattern="RaceTrack"}).params.pattern' 'RaceTrack'

echo "==> [build] orbit invalid pattern -> nil"
expect_true "orbit bad pattern" 'return sms.task.orbit({x=0,y=0,z=0}, {pattern="Spiral"}) == nil'

echo "==> [build] orbit non-vec3 pos -> nil"
expect_true "orbit bad pos" 'return sms.task.orbit("nope") == nil'

echo "==> [build] bomb returns air-only Bombing task"
expect_str "bomb id" 'return sms.task.bomb({x=0,y=0,z=0}).id' 'Bombing'
expect_true "bomb air-only" 'return sms.task.bomb({x=0,y=0,z=0})._sms_air_only == true'

echo "==> [build] land returns air-only Land task"
expect_str "land id" 'return sms.task.land({x=0,y=0,z=0}).id' 'Land'
expect_true "land air-only" 'return sms.task.land({x=0,y=0,z=0})._sms_air_only == true'

echo "==> [build] combo returns ComboTask"
expect_str "combo id" 'return sms.task.combo({sms.task.hold()}).id' 'ComboTask'

echo "==> [build] combo propagates air-only when any constituent is air-only"
expect_true "combo air via orbit" 'return sms.task.combo({sms.task.move_to({x=0,y=0,z=0}), sms.task.orbit({x=0,y=0,z=0})})._sms_air_only == true'

echo "==> [build] combo not air-only when no constituent is"
expect_true "combo no air" 'return sms.task.combo({sms.task.move_to({x=0,y=0,z=0}), sms.task.hold()})._sms_air_only == nil'

echo "==> [build] combo with non-table constituent -> nil"
expect_true "combo bad constituent" 'return sms.task.combo({sms.task.hold(), "not a task"}) == nil'

echo "==> [build] combo with empty list -> nil"
expect_true "combo empty" 'return sms.task.combo({}) == nil'

echo "==> [build] move_to with non-handle -> nil"
expect_true "move_to bad target" 'return sms.task.move_to("nope") == nil'

# ----------------------------------------------------------------
# Section 2: discover spawn coords from existing mission
# ----------------------------------------------------------------
echo "==> discover spawn coords from existing mission"
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
# Section 3: live ground apply — move_to + air-only rejection
# ----------------------------------------------------------------
echo "==> [apply] spawn ground fixture _smoke_task_ground"
expect_true "ground spawned" "
  local g = sms.group.create({
    name      = '_smoke_task_ground',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g ~= nil
"

echo "==> [apply] sms.group:get_category returns 'ground'"
expect_str "category ground" "return sms.group('_smoke_task_ground'):get_category()" 'ground'

echo "==> [apply] ground:set_task(move_to) returns true"
expect_true "ground move_to ok" "
  local g = sms.group('_smoke_task_ground')
  local pos = {x = ${SPAWN_X} + 100, y = 0, z = ${SPAWN_Z} + 100}
  return g:set_task(sms.task.move_to(pos)) == true
"

echo "==> [apply] ground:set_task(orbit) rejected with log + false (air-only)"
expect_true "ground orbit rejected" "
  local g = sms.group('_smoke_task_ground')
  return g:set_task(sms.task.orbit({x = ${SPAWN_X}, y = 100, z = ${SPAWN_Z}})) == false
"

echo "==> [apply] verify air-only rejection log line"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.task\]' -n 50)
echo "${log_window}" | grep -q "set_task: 'orbit' is air-only" \
  || { echo "FAIL: missing air-only log line"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "_smoke_task_ground" \
  || { echo "FAIL: air-only log missing group name"; echo "${log_window}"; exit 1; }

echo "==> [apply] cleanup ground fixture"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_ground')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 4: live air apply — orbit + push + combo
# ----------------------------------------------------------------
echo "==> [apply] spawn air fixture _smoke_task_air"
expect_true "air spawned" "
  local g = sms.group.create({
    name      = '_smoke_task_air',
    position  = {x = ${SPAWN_X} + 5000, y = 5000, z = ${SPAWN_Z} + 5000},
    country   = 'USA',
    category  = 'airplane',
    altitude  = 5000,
    units     = {{ type = 'F-16C_50' }},
  })
  return g ~= nil
"

echo "==> [apply] air:get_category returns 'airplane'"
expect_str "category airplane" "return sms.group('_smoke_task_air'):get_category()" 'airplane'

echo "==> [apply] air:set_task(orbit) returns true"
expect_true "air orbit ok" "
  local g = sms.group('_smoke_task_air')
  return g:set_task(sms.task.orbit({x = ${SPAWN_X}, y = 5000, z = ${SPAWN_Z}}, {altitude=5000})) == true
"

echo "==> [apply] air:push_task(orbit) returns true"
expect_true "air push ok" "
  local g = sms.group('_smoke_task_air')
  return g:push_task(sms.task.orbit({x = ${SPAWN_X} + 1000, y = 5000, z = ${SPAWN_Z} + 1000})) == true
"

echo "==> [apply] air:set_task(combo of move_to + orbit) returns true"
expect_true "air combo ok" "
  local g = sms.group('_smoke_task_air')
  local task = sms.task.combo({
    sms.task.move_to({x = ${SPAWN_X} + 2000, y = 5000, z = ${SPAWN_Z} + 2000}),
    sms.task.orbit({x = ${SPAWN_X} + 2000, y = 5000, z = ${SPAWN_Z} + 2000}),
  })
  return g:set_task(task) == true
"

# ----------------------------------------------------------------
# Section 5: bad-arg matrix on apply
# ----------------------------------------------------------------
echo "==> [apply] set_task with non-handle -> false"
expect_true "set_task bad handle" 'return sms.group.set_task("not a handle", sms.task.hold()) == false'

echo "==> [apply] set_task with non-table task -> false"
expect_true "set_task bad task" "
  local g = sms.group('_smoke_task_air')
  return g:set_task(42) == false
"

echo "==> [apply] set_task with task missing id -> false"
expect_true "set_task no id" "
  local g = sms.group('_smoke_task_air')
  return g:set_task({params = {}}) == false
"

echo "==> [apply] cleanup air fixture"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_air')
  if g then g:destroy() end
" >/dev/null

echo "==> [apply] set_task on dead group -> false"
expect_true "set_task dead" "
  return sms.group.set_task(sms._make_handle(sms.group, '_smoke_task_air'), sms.task.hold()) == false
"

echo "smoke ok"
```

- [ ] **Step 2: Make executable and syntax-check**

Run: `chmod +x framework/test/smoke_task.sh && bash -n framework/test/smoke_task.sh`
Expected: no output (success).

- [ ] **Step 3: Commit**

```bash
git add framework/test/smoke_task.sh
git commit -m "test(task): smoke coverage with synthetic + live + EXIT trap"
```

---

## Task 5: `AGENTS.md` updates

**Files:**
- Modify: `AGENTS.md` (add `:get_category()` row to `sms.group` table; add new `sms.task` section)

- [ ] **Step 1: Add `:get_category()` row to the `sms.group` method table**

In `AGENTS.md`, find the `### \`sms.group\`` section (around line 194). Locate the method table that contains rows like `:get_coalition()` and `:get_position()`. Insert a new row immediately after `:get_coalition()`:

```markdown
| `:get_category()` | `"ground" \| "airplane" \| "helicopter" \| "ship" \| "train"`. |
```

- [ ] **Step 2: Append the new `sms.task` section near the end of the framework reference**

Append before the final `## Out-of-band notes` / similar trailing section (or simply at the end of the file if no such section exists). The exact section content:

```markdown
### `sms.task` — `framework/task.lua`

Ergonomic builders for DCS task tables, plus runtime apply methods (`group:set_task`, `group:push_task`) installed on `sms.group`'s metatable. The split between *build* and *apply* keeps tasks as first-class values: a task can be stored, passed around, composed via `combo`, or built once and applied to multiple groups.

Each builder returns a plain DCS task table with two private fields:

- `_sms_verb` — string, used in apply-layer log messages
- `_sms_air_only` — `true` for verbs DCS only honors on air groups; consumed by the apply-layer category check

The fields are otherwise transparent to DCS. Manually-built task tables (no `_sms_*` tags) skip the air-only check at apply time — user's responsibility.

**Builders:**

| Function | Targets | DCS task | Categories |
|---|---|---|---|
| `sms.task.move_to(target)` | vec3 / sms.unit / sms.group / sms.static / sms.area | `Mission` (single waypoint at snapshot pos) | all |
| `sms.task.hold()` | — | `Nothing` (DCS interprets per category: air loiters; ground stops) | all |
| `sms.task.follow(target, opts?)` | sms.unit / sms.group; opts: `{offset = {x,y,z}}` | `Follow` | air (v1) |
| `sms.task.orbit(pos, opts?)` | vec3; opts: `{altitude=5000, speed=200, pattern="Circle"\|"RaceTrack"}` | `Orbit` | air |
| `sms.task.attack(target, opts?)` | sms.group / sms.unit; opts: `{weapon_type="Auto", expend="Auto", attack_qty}` | `AttackGroup` (group) / `AttackUnit` (unit) | air (v1) |
| `sms.task.attack_in_area(area, opts?)` | circular sms.area; opts: `{altitude_min, altitude_max, weapon_type}` | `EngageTargetsInZone` | air (v1) |
| `sms.task.bomb(target, opts?)` | vec3 / sms.area / sms.unit / sms.static; opts: `{altitude, weapon_type, expend, group_attack, direction}` | `Bombing` | air |
| `sms.task.land(target, opts?)` | vec3 / sms.static / sms.unit / DCS Airbase; opts: `{duration=300}` | `Land` | air (incl. helo) |
| `sms.task.combo({t1, t2, ...})` | array of task tables | `ComboTask` (parallel; propagates `_sms_air_only` if any constituent has it) | inherits |

**Snapshot vs follow.** `move_to(unit)` reads `unit:get_position()` once at build time; if the unit moves before the task ends, the task still drives to the original location. For continuous tracking, use `follow(unit)`.

**Air-only enforcement.** Six builders set `_sms_air_only = true`: `follow`, `orbit`, `attack`, `attack_in_area`, `bomb`, `land`. At apply time, `set_task`/`push_task` reads the flag and rejects-with-log if the group's category is not `airplane` or `helicopter`:

```
[sms.task] set_task: 'orbit' is air-only; group 'tank-1' is ground — not applied
```

**Weapon type strings** (accepted by builders that take `opts.weapon_type`): `"Auto"` (default), `"Guns"`, `"Rockets"`, `"Missiles"`, `"Bombs"`. Numeric DCS bitmasks are also accepted.

**Apply API (on `sms.group`):**

| Method | Returns |
|---|---|
| `:set_task(task)` | `true` on dispatch; `false` + log on bad input or air-only mismatch. Wraps `Group:getController():setTask`. |
| `:push_task(task)` | `true` on dispatch; same failure modes. Wraps `Group:getController():pushTask`. LIFO — new task interrupts current; current resumes when new task ends. |

**Out of v1:** `sequence` verb (use `push_task` LIFO ordering or event-driven retasking), ground-specific engage verbs (DCS ground engagement is ROE-driven, separate design problem), polygon-area `attack_in_area`, `pop_task`, current-task introspection (DCS doesn't expose it cleanly), per-waypoint task mutation.
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): add sms.task section + sms.group:get_category row"
```

---

## Self-review — completed

**Spec coverage check:**

| Spec requirement | Plan task |
|---|---|
| `framework/task.lua` new file with builders | Task 2 |
| `framework/task.lua` apply methods (set_task / push_task) | Task 3 |
| `sms.group:get_category()` companion change | Task 1 |
| Air-only check at apply time | Task 3 |
| `_sms_verb` and `_sms_air_only` private tags on builders | Task 2 |
| All 9 verbs (move_to, hold, follow, orbit, attack, attack_in_area, bomb, land, combo) | Task 2 |
| Smoke test with synthetic + live sections | Task 4 |
| EXIT-trap fixture cleanup | Task 4 |
| AGENTS.md `sms.task` section | Task 5 |
| AGENTS.md `:get_category()` row | Task 5 |

All spec requirements covered. No gaps.

**Placeholder scan:** No "TBD", "TODO", "implement later", "similar to Task N", or vague-handling instructions. Every code step has full code. Every command has expected output.

**Type consistency check:** Method names `set_task`, `push_task`, `get_category`, builder names `move_to`, `hold`, `follow`, `orbit`, `attack`, `attack_in_area`, `bomb`, `land`, `combo` are consistent across all tasks. Private field names `_sms_verb`, `_sms_air_only` consistent. Helper names `_position_of`, `_stamp`, `_resolve_weapon_type`, `_is_task_table`, `_validate_apply` are defined and used coherently within their scope.
