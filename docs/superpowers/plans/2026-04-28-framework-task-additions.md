# Framework task v1.1 additions — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `sms.task` to feature parity with DCS's "Tasks" + "Enroute Tasks" surface (skipping Mission, ControlledTask, WrappedAction). Adds 14 new builders, updates `attack_in_area` for `priority`, introduces `sms.targets` and `sms.designations` namespaces, and extends category enforcement to `_sms_ground_only`.

**Architecture:** Pure additions to existing modules plus two new constants files. New builders follow the established `_stamp` / `_validate_apply` patterns. `_stamp` gains an optional fourth arg for `_sms_ground_only`; `_validate_apply` in `group.lua` gets a parallel ground-only check; `combo` propagation aggregates both flags.

**Tech Stack:** Lua 5.1 (DCS mission environment), Bash smoke harness, the bridge (`tools/dcs-sms.exe`).

**Constraint — DCS is closed during implementation.** Smoke test entries are written into `framework/test/smoke_task.sh` but cannot be RUN per task. Per-task green signal is `luac -p` syntax-check on the touched Lua files. Smoke runs are deferred to the user post-implementation.

**Spec:** [`docs/superpowers/specs/2026-04-28-framework-task-additions-design.md`](../specs/2026-04-28-framework-task-additions-design.md).

---

## File Structure

**New files:**
- `framework/targets.lua` — `sms.targets` constants
- `framework/designations.lua` — `sms.designations` constants

**Modified files:**
- `framework/task.lua` — 14 new builders, `attack_in_area` update, `_stamp` extension, `combo` propagation
- `framework/group.lua` — `_sms_ground_only` enforcement in `_validate_apply`
- `framework/load_all.lua` — load order: targets, designations after utils
- `framework/test/smoke_task.sh` — new smoke entries (entries written, not executed)
- `AGENTS.md` — §6 load order, §7 sms.task new rows, §7 new sms.targets / sms.designations entries, §3 ground-only mention

---

## Task 1: Constants modules — `sms.targets` + `sms.designations`

**Files:**
- Create: `framework/targets.lua`
- Create: `framework/designations.lua`
- Modify: `framework/load_all.lua` (add to load list)
- Modify: `AGENTS.md` (§6 load chain + §2 file map)

- [ ] **Step 1: Create `framework/targets.lua`**

```lua
-- dcs-sms framework: targets module (sms.targets).
--
-- Named constants for DCS target attribute strings used by enroute
-- engagement tasks (sms.task.engage_en_route_*, sms.task.escort, etc.).
-- Constants resolve to plain strings; builders accept either the
-- constants (recommended) or raw strings (forward-compat for new DCS
-- attributes the framework hasn't catalogued yet).
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> targets.lua.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
sms.targets = sms.targets or {}

sms.targets.AIR             = "Air"
sms.targets.PLANES          = "Planes"
sms.targets.HELICOPTERS     = "Helicopters"
sms.targets.GROUND_UNITS    = "Ground Units"
sms.targets.GROUND_VEHICLES = "Ground vehicles"
sms.targets.SHIPS           = "Ships"
sms.targets.AIR_DEFENCE     = "Air Defence"
sms.targets.SAM             = "SAM"
sms.targets.AAA             = "AAA"
sms.targets.STATICS         = "Static"
sms.targets.BUILDINGS       = "Buildings"
sms.targets.ALL             = "All"
```

- [ ] **Step 2: Create `framework/designations.lua`**

```lua
-- dcs-sms framework: designations module (sms.designations).
--
-- Named constants for DCS FAC designation enum strings used by FAC
-- task builders (sms.task.fac_attack_group, sms.task.fac_engage_group).
-- Constants resolve to plain strings; builders accept either the
-- constants (recommended) or raw strings.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> designations.lua.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
sms.designations = sms.designations or {}

sms.designations.NO         = "No"
sms.designations.AUTO       = "Auto"
sms.designations.WP         = "WP"          -- white phosphorus marker
sms.designations.IR_POINTER = "IR-Pointer"
sms.designations.LASER      = "Laser"
```

- [ ] **Step 3: Update `framework/load_all.lua` to add the two modules**

Replace the `modules` table contents (around lines 25-39) with:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "targets.lua",
  "designations.lua",
  "group.lua",
  "unit.lua",
  "area.lua",
  "timer.lua",
  "group_spawn.lua",
  "static.lua",
  "events.lua",
  "weapon.lua",
  "task.lua",
}
```

- [ ] **Step 4: Update `AGENTS.md` §6 load chain**

Find the line containing `sms.lua → log.lua → utils.lua → group.lua → unit.lua → area.lua → timer.lua → group_spawn.lua → static.lua → events.lua → weapon.lua → task.lua` and replace with:

```
sms.lua → log.lua → utils.lua → targets.lua → designations.lua → group.lua → unit.lua → area.lua → timer.lua → group_spawn.lua → static.lua → events.lua → weapon.lua → task.lua
```

- [ ] **Step 5: Update `AGENTS.md` §2 file map**

Find the `framework/` block (under "Repo layout at a glance") and add two rows after `utils.lua`:

```
│   ├── targets.lua         sms.targets — DCS target attribute name constants.
│   ├── designations.lua    sms.designations — FAC designation enum constants.
```

- [ ] **Step 6: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output (all OK).

- [ ] **Step 7: Commit**

```bash
git add framework/targets.lua framework/designations.lua framework/load_all.lua AGENTS.md
git commit -m "feat(targets): add sms.targets and sms.designations constants

Two thin modules of named constants for DCS target attribute strings
(used by enroute engagement tasks) and FAC designation enum strings.
Builders consuming these will accept either the constants or raw
strings, so power users and forward-compat aren't blocked when DCS
adds new attributes.

Loaded after utils.lua in load_all.lua; AGENTS.md §2 and §6 updated.

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 2: Ground-only enforcement scaffolding

**Files:**
- Modify: `framework/group.lua` (`_validate_apply`)
- Modify: `framework/task.lua` (`_stamp`, `combo`)

- [ ] **Step 1: Extend `_stamp` in `framework/task.lua`**

Find the `_stamp` function (around line 77):

```lua
local function _stamp(t, verb, air_only)
  t._sms_verb = verb
  if air_only then t._sms_air_only = true end
  return t
end
```

Replace with:

```lua
local function _stamp(t, verb, air_only, ground_only)
  t._sms_verb = verb
  if air_only    then t._sms_air_only    = true end
  if ground_only then t._sms_ground_only = true end
  return t
end
```

- [ ] **Step 2: Extend `combo` propagation in `framework/task.lua`**

Find the `sms.task.combo = function(tasks)` body (around line 399) and replace its loop body + return:

```lua
  local any_air_only = false
  for i, t in ipairs(tasks) do
    if type(t) ~= "table" then
      log.warn("combo: tasks[" .. i .. "] must be a task table, got " .. type(t))
      return nil
    end
    if t._sms_air_only then any_air_only = true end
  end
  return _stamp({
    id     = "ComboTask",
    params = { tasks = tasks },
  }, "combo", any_air_only)
```

with:

```lua
  local any_air_only    = false
  local any_ground_only = false
  for i, t in ipairs(tasks) do
    if type(t) ~= "table" then
      log.warn("combo: tasks[" .. i .. "] must be a task table, got " .. type(t))
      return nil
    end
    if t._sms_air_only    then any_air_only    = true end
    if t._sms_ground_only then any_ground_only = true end
  end
  return _stamp({
    id     = "ComboTask",
    params = { tasks = tasks },
  }, "combo", any_air_only, any_ground_only)
```

- [ ] **Step 3: Add ground-only enforcement to `_validate_apply` in `framework/group.lua`**

Find the existing air-only block in `_validate_apply` (around lines 229-237):

```lua
  if task._sms_air_only then
    local cat = group_handle:get_category()
    if not _air_categories[cat] then
      local verb = task._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is air-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
```

Replace with:

```lua
  if task._sms_air_only then
    local cat = group_handle:get_category()
    if not _air_categories[cat] then
      local verb = task._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is air-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
  if task._sms_ground_only then
    local cat = group_handle:get_category()
    if cat ~= "ground" then
      local verb = task._sms_verb or "task"
      log.warn(method .. ": '" .. verb .. "' is ground-only; group '" .. tostring(group_handle.name) .. "' is " .. tostring(cat) .. " — not applied")
      return nil
    end
  end
```

- [ ] **Step 4: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output (all OK).

- [ ] **Step 5: Commit**

```bash
git add framework/task.lua framework/group.lua
git commit -m "feat(task): add _sms_ground_only flag and combo propagation

Extends _stamp() with an optional fourth arg for ground-only tasks
and updates combo() to aggregate both flags from sub-tasks.
group.lua's _validate_apply gains a parallel ground-only check
mirroring the existing air-only one — strictly category == 'ground'
(ships and trains are excluded; see spec for rationale).

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 3: `attack_in_area` priority opt

**Files:**
- Modify: `framework/task.lua` (`attack_in_area`)
- Modify: `framework/test/smoke_task.sh`

- [ ] **Step 1: Add priority opt to `attack_in_area` in `framework/task.lua`**

Find the existing `sms.task.attack_in_area` (around line 301) and locate this block:

```lua
  local params = {
    point       = {x = center.x, y = center.z},
    zoneRadius  = radius,
    targetTypes = {"All"},
    weaponType  = weapon_type,
  }
  if opts.altitude_min then params.minAlt = opts.altitude_min end
  if opts.altitude_max then params.maxAlt = opts.altitude_max end
```

Replace with:

```lua
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("attack_in_area: opts.priority must be a number, got " .. type(priority))
    return nil
  end

  local params = {
    point       = {x = center.x, y = center.z},
    zoneRadius  = radius,
    targetTypes = {"All"},
    weaponType  = weapon_type,
    priority    = priority,
  }
  if opts.altitude_min then params.minAlt = opts.altitude_min end
  if opts.altitude_max then params.maxAlt = opts.altitude_max end
```

- [ ] **Step 2: Add smoke test entries for `attack_in_area` priority**

Find the existing `attack_in_area` smoke section in `framework/test/smoke_task.sh` (search for "attack_in_area"). After the last existing `expect_*` for `attack_in_area`, add:

```bash
echo "==> [build] attack_in_area priority defaults to 1"
expect_true "attack_in_area default priority" "
  local a = sms.area.create_circular({x=0,y=0,z=0}, 5000)
  if not a then return false end
  return sms.task.attack_in_area(a).params.priority == 1
"

echo "==> [build] attack_in_area priority honored"
expect_true "attack_in_area set priority" "
  local a = sms.area.create_circular({x=0,y=0,z=0}, 5000)
  if not a then return false end
  return sms.task.attack_in_area(a, {priority=5}).params.priority == 5
"

echo "==> [build] attack_in_area bad priority -> nil"
expect_true "attack_in_area bad priority" "
  local a = sms.area.create_circular({x=0,y=0,z=0}, 5000)
  if not a then return false end
  return sms.task.attack_in_area(a, {priority='high'}) == nil
"
```

- [ ] **Step 3: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/task.lua framework/test/smoke_task.sh
git commit -m "feat(task): attack_in_area accepts priority opt (default 1)

EngageTargetsInZone is documented as an enroute task in the DCS FAQ;
all enroute tasks take a priority param (lower = higher priority).
Default 1 matches ME-generated tasks. Smoke entries added (DCS
closed during implementation; smokes deferred).

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 4: Trivial role-type builders — `no_task`, `refuel`, `awacs`, `tanker`, `ewr`

**Files:**
- Modify: `framework/task.lua`
- Modify: `framework/test/smoke_task.sh`

- [ ] **Step 1: Add the five builders to `framework/task.lua`**

Find the end of the existing builders (just before any final code; `combo` is the last builder, around line 421). Add a new "Role-type / no-target builders" section after `combo` (before any apply-related code, but task.lua ends at builders so add just before the file's final `end`):

Insert just before the final closing of the file (after `sms.task.combo = function(tasks) ... end`):

```lua

-- ============================================================
-- Role-type / no-target builders (Task v1.1 additions)
-- ============================================================

-- Empty noop. Air only per DCS FAQ. Useful for clearing the active
-- task without resetting the controller (resetTask clears the queue
-- entirely; setTask(no_task) just stops the current activity).
sms.task.no_task = function()
  return _stamp({id = "NoTask", params = {}}, "no_task", true)
end

-- Refuel from nearest tanker. Air only.
sms.task.refuel = function()
  return _stamp({id = "Refueling", params = {}}, "refuel", true)
end

-- Generic priority validator + extractor for enroute role tasks.
local function _validate_priority(verb, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn(verb .. ": opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn(verb .. ": opts.priority must be a number, got " .. type(priority))
    return nil
  end
  return priority
end

-- Act as AWACS for friendly units. Enroute, air only.
sms.task.awacs = function(opts)
  local priority = _validate_priority("awacs", opts)
  if priority == nil then return nil end
  return _stamp({
    id     = "AWACS",
    params = {priority = priority},
  }, "awacs", true)
end

-- Act as tanker for friendly units. Enroute, air only.
sms.task.tanker = function(opts)
  local priority = _validate_priority("tanker", opts)
  if priority == nil then return nil end
  return _stamp({
    id     = "Tanker",
    params = {priority = priority},
  }, "tanker", true)
end

-- Act as EW radar for friendly units. Enroute, ground only.
sms.task.ewr = function(opts)
  local priority = _validate_priority("ewr", opts)
  if priority == nil then return nil end
  return _stamp({
    id     = "EWR",
    params = {priority = priority},
  }, "ewr", false, true)
end
```

- [ ] **Step 2: Add smoke entries to `framework/test/smoke_task.sh`**

Find the section near the end of the build-coverage smoke tests (look for the last `expect_*` block before the apply / live sections). Add a new section:

```bash
# ----------------------------------------------------------------
# Section: v1.1 role-type builders (no_task, refuel, awacs, tanker, ewr)
# ----------------------------------------------------------------

echo "==> [build] no_task returns NoTask, air-only"
expect_str  "no_task id"          'return sms.task.no_task().id' 'NoTask'
expect_true "no_task air-only"    'return sms.task.no_task()._sms_air_only == true'
expect_str  "no_task verb"        'return sms.task.no_task()._sms_verb' 'no_task'

echo "==> [build] refuel returns Refueling, air-only"
expect_str  "refuel id"           'return sms.task.refuel().id' 'Refueling'
expect_true "refuel air-only"     'return sms.task.refuel()._sms_air_only == true'

echo "==> [build] awacs returns AWACS with priority default 1, air-only"
expect_str  "awacs id"            'return sms.task.awacs().id' 'AWACS'
expect_true "awacs default prio"  'return sms.task.awacs().params.priority == 1'
expect_true "awacs air-only"      'return sms.task.awacs()._sms_air_only == true'
expect_true "awacs prio set"      'return sms.task.awacs({priority=3}).params.priority == 3'
expect_true "awacs bad prio"      'return sms.task.awacs({priority="high"}) == nil'

echo "==> [build] tanker returns Tanker with priority default 1, air-only"
expect_str  "tanker id"           'return sms.task.tanker().id' 'Tanker'
expect_true "tanker air-only"     'return sms.task.tanker()._sms_air_only == true'

echo "==> [build] ewr returns EWR with priority default 1, ground-only"
expect_str  "ewr id"              'return sms.task.ewr().id' 'EWR'
expect_true "ewr default prio"    'return sms.task.ewr().params.priority == 1'
expect_true "ewr ground-only"     'return sms.task.ewr()._sms_ground_only == true'
expect_true "ewr not air-only"    'return sms.task.ewr()._sms_air_only == nil'
expect_true "ewr bad opts"        'return sms.task.ewr("nope") == nil'
```

- [ ] **Step 3: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/task.lua framework/test/smoke_task.sh
git commit -m "feat(task): add no_task / refuel / awacs / tanker / ewr builders

Five role-type / no-target task builders. AWACS, Tanker, EWR are
enroute tasks taking opts.priority (default 1). EWR is ground-only
(first user of _sms_ground_only flag); the others are air-only.
no_task is a controller-state noop, useful for clearing the active
task without nuking the queue. Smoke entries added (DCS closed).

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 5: Point-target builders — `fire_at_point`, `attack_map_object`, `bomb_runway`

**Files:**
- Modify: `framework/task.lua`
- Modify: `framework/test/smoke_task.sh`

- [ ] **Step 1: Add the three builders to `framework/task.lua`**

Append to `framework/task.lua` after the role-type builders added in Task 4:

```lua

-- ============================================================
-- Point/runway-target builders (Task v1.1 additions)
-- ============================================================

-- Fire at a point on the ground. Optional radius spreads fire over a
-- circle; without radius DCS targets the exact point. Ground only.
sms.task.fire_at_point = function(point, opts)
  if not sms.utils.is_vec3(point) then
    log.warn("fire_at_point: point must be a vec3, got " .. type(point))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fire_at_point: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.radius ~= nil and type(opts.radius) ~= "number" then
    log.warn("fire_at_point: opts.radius must be a number, got " .. type(opts.radius))
    return nil
  end
  return _stamp({
    id = "FireAtPoint",
    params = {
      point  = {x = point.x, y = point.z},  -- DCS 2D
      radius = opts.radius,
    },
  }, "fire_at_point", false, true)
end

-- Attack a map object (building / structure / etc.) at the given vec3.
-- DCS doesn't take a map-object id from scripts; the point must be
-- within ~2km of the structure for the AI to find it. Air only.
sms.task.attack_map_object = function(point, opts)
  if not sms.utils.is_vec3(point) then
    log.warn("attack_map_object: point must be a vec3, got " .. type(point))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("attack_map_object: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.attack_qty ~= nil and type(opts.attack_qty) ~= "number" then
    log.warn("attack_map_object: opts.attack_qty must be a number, got " .. type(opts.attack_qty))
    return nil
  end
  if opts.direction ~= nil and type(opts.direction) ~= "number" then
    log.warn("attack_map_object: opts.direction must be a number (degrees), got " .. type(opts.direction))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "attack_map_object")
  return _stamp({
    id = "AttackMapObject",
    params = {
      point       = {x = point.x, y = point.z},
      weaponType  = weapon_type,
      expend      = opts.expend or "Auto",
      attackQty   = opts.attack_qty,
      direction   = opts.direction and sms.utils.deg_to_rad(opts.direction) or nil,
      groupAttack = opts.group_attack and true or false,
    },
  }, "attack_map_object", true)
end

-- Bomb a runway by integer DCS airdrome ID. See issue #23 for the
-- planned sms.airdrome handle integration. Air only.
sms.task.bomb_runway = function(airdrome_id, opts)
  if type(airdrome_id) ~= "number" then
    log.warn("bomb_runway: airdrome_id must be a number (DCS airdrome ID), got " .. type(airdrome_id))
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("bomb_runway: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.attack_qty ~= nil and type(opts.attack_qty) ~= "number" then
    log.warn("bomb_runway: opts.attack_qty must be a number, got " .. type(opts.attack_qty))
    return nil
  end
  if opts.direction ~= nil and type(opts.direction) ~= "number" then
    log.warn("bomb_runway: opts.direction must be a number (degrees), got " .. type(opts.direction))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "bomb_runway")
  return _stamp({
    id = "BombingRunway",
    params = {
      runwayId    = airdrome_id,
      weaponType  = weapon_type,
      expend      = opts.expend or "Auto",
      attackQty   = opts.attack_qty,
      direction   = opts.direction and sms.utils.deg_to_rad(opts.direction) or nil,
      groupAttack = opts.group_attack and true or false,
    },
  }, "bomb_runway", true)
end
```

- [ ] **Step 2: Add smoke entries to `framework/test/smoke_task.sh`**

Append after the role-type smoke section from Task 4:

```bash
# ----------------------------------------------------------------
# Section: v1.1 point/runway builders
# ----------------------------------------------------------------

echo "==> [build] fire_at_point returns FireAtPoint, ground-only"
expect_str  "fire_at_point id"        'return sms.task.fire_at_point({x=0,y=0,z=0}).id' 'FireAtPoint'
expect_true "fire_at_point ground"    'return sms.task.fire_at_point({x=0,y=0,z=0})._sms_ground_only == true'
expect_true "fire_at_point not air"   'return sms.task.fire_at_point({x=0,y=0,z=0})._sms_air_only == nil'
expect_true "fire_at_point radius"    'return sms.task.fire_at_point({x=0,y=0,z=0}, {radius=200}).params.radius == 200'
expect_true "fire_at_point bad point" 'return sms.task.fire_at_point("nope") == nil'
expect_true "fire_at_point bad rad"   'return sms.task.fire_at_point({x=0,y=0,z=0}, {radius="big"}) == nil'

echo "==> [build] attack_map_object returns AttackMapObject, air-only"
expect_str  "amo id"            'return sms.task.attack_map_object({x=0,y=0,z=0}).id' 'AttackMapObject'
expect_true "amo air-only"      'return sms.task.attack_map_object({x=0,y=0,z=0})._sms_air_only == true'
expect_true "amo bad point"     'return sms.task.attack_map_object("nope") == nil'
expect_true "amo direction rad" "
  local t = sms.task.attack_map_object({x=0,y=0,z=0}, {direction=90})
  return math.abs(t.params.direction - math.pi/2) < 1e-6
"

echo "==> [build] bomb_runway returns BombingRunway, air-only"
expect_str  "bomb_runway id"      'return sms.task.bomb_runway(7).id' 'BombingRunway'
expect_true "bomb_runway air"     'return sms.task.bomb_runway(7)._sms_air_only == true'
expect_true "bomb_runway runway"  'return sms.task.bomb_runway(7).params.runwayId == 7'
expect_true "bomb_runway bad id"  'return sms.task.bomb_runway("seven") == nil'
```

- [ ] **Step 3: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/task.lua framework/test/smoke_task.sh
git commit -m "feat(task): add fire_at_point / attack_map_object / bomb_runway

Three point-targeted task builders. fire_at_point is ground-only
(second user of _sms_ground_only); attack_map_object and bomb_runway
are air-only. Direction opts are public-degrees, internal-radians per
the framework convention. bomb_runway takes an integer airdrome ID
for v1.1 (handle/name acceptance tracked in #23).

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 6: `escort` builder

**Files:**
- Modify: `framework/task.lua`
- Modify: `framework/test/smoke_task.sh`

- [ ] **Step 1: Add the `escort` builder to `framework/task.lua`**

Append to `framework/task.lua` after the point-target builders:

```lua

-- ============================================================
-- Coordination builders (Task v1.1 additions)
-- ============================================================

-- Escort another airborne group: follow at offset, engage threats
-- matching opts.target_types. Air only. Mirrors sms.task.follow's
-- target/offset shape.
--
-- opts:
--   offset                 vec3?    relative to target leader, default {-50, 0, -50}
--   engagement_dist_max    number?  meters, default 5000
--   target_types           table?   array of attribute strings (sms.targets.* recommended)
--   last_waypoint_index    number?  detach when target reaches this waypoint
sms.task.escort = function(target, opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("escort: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local offset = opts.offset or {x = -50, y = 0, z = -50}
  if not sms.utils.is_vec3(offset) then
    log.warn("escort: opts.offset must be a vec3, got " .. type(offset))
    return nil
  end

  local group_id
  if sms._is_handle_of(target, sms.group) then
    local raw = Group.getByName(target.name)
    if not raw then
      log.warn("escort: group '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    group_id = raw:getID()
  elseif sms._is_handle_of(target, sms.unit) then
    local raw = Unit.getByName(target.name)
    if not raw then
      log.warn("escort: unit '" .. tostring(target.name) .. "' not in mission")
      return nil
    end
    local g = raw:getGroup()
    if not g then
      log.error("escort: unit '" .. tostring(target.name) .. "' has no group")
      return nil
    end
    group_id = g:getID()
  else
    log.warn("escort: target must be sms.unit or sms.group handle")
    return nil
  end

  local engagement_dist_max = opts.engagement_dist_max or 5000
  if type(engagement_dist_max) ~= "number" then
    log.warn("escort: opts.engagement_dist_max must be a number, got " .. type(engagement_dist_max))
    return nil
  end
  if opts.target_types ~= nil and type(opts.target_types) ~= "table" then
    log.warn("escort: opts.target_types must be a table, got " .. type(opts.target_types))
    return nil
  end
  if opts.last_waypoint_index ~= nil and type(opts.last_waypoint_index) ~= "number" then
    log.warn("escort: opts.last_waypoint_index must be a number, got " .. type(opts.last_waypoint_index))
    return nil
  end

  return _stamp({
    id = "Escort",
    params = {
      groupId           = group_id,
      pos               = {x = offset.x, y = offset.y, z = offset.z},
      lastWptIndexFlag  = opts.last_waypoint_index ~= nil,
      lastWptIndex      = opts.last_waypoint_index,
      engagementDistMax = engagement_dist_max,
      targetTypes       = opts.target_types,
    },
  }, "escort", true)
end
```

- [ ] **Step 2: Add smoke entries to `framework/test/smoke_task.sh`**

Append after the point-target smoke section:

```bash
# ----------------------------------------------------------------
# Section: v1.1 escort
# ----------------------------------------------------------------

# escort tests need a group in env.mission to resolve groupId; reuse
# the discovered ME template name from the spawn smoke if available,
# otherwise spawn one.
echo "==> [build] escort needs a sms.unit/group handle"
expect_true "escort bad target" 'return sms.task.escort("nope") == nil'

echo "==> [build] escort spawns group fixture and returns Escort task"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_escort_target')
  if not g then
    sms.group.create({
      name='_smoke_task_escort_target',
      position={x=0,y=0,z=0},
      country='USA', category='airplane',
      units={{type='F-15C', alt=5000}},
    })
  end
" >/dev/null

expect_str "escort id" "
  local g = sms.group('_smoke_task_escort_target')
  if not g then return 'NIL' end
  local t = sms.task.escort(g, {target_types={sms.targets.PLANES}})
  return t and t.id or 'NIL'
" 'Escort'

expect_true "escort air-only" "
  local g = sms.group('_smoke_task_escort_target')
  if not g then return false end
  return sms.task.escort(g)._sms_air_only == true
"

expect_true "escort default offset" "
  local g = sms.group('_smoke_task_escort_target')
  if not g then return false end
  local t = sms.task.escort(g)
  return t.params.pos.x == -50 and t.params.pos.y == 0 and t.params.pos.z == -50
"

expect_true "escort last_waypoint flag" "
  local g = sms.group('_smoke_task_escort_target')
  if not g then return false end
  local t = sms.task.escort(g, {last_waypoint_index=4})
  return t.params.lastWptIndexFlag == true and t.params.lastWptIndex == 4
"

echo "==> [build] escort cleanup fixture"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_escort_target')
  if g then g:destroy() end
" >/dev/null
```

Also add `_smoke_task_escort_target` to the `SMOKE_FIXTURES` cleanup list at the top of `smoke_task.sh`. Search the file for `SMOKE_FIXTURES=` and append the new fixture name.

- [ ] **Step 3: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/task.lua framework/test/smoke_task.sh
git commit -m "feat(task): add escort builder

Air-only Escort task. Mirrors follow's target/offset shape (accepts
sms.unit or sms.group, default offset {-50, 0, -50}). Adds
engagement_dist_max (default 5000m), target_types (array of
sms.targets.* constants or raw strings), and optional
last_waypoint_index for auto-detach.

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 7: FAC family — `fac_attack_group`, `fac`, `fac_engage_group`

**Files:**
- Modify: `framework/task.lua`
- Modify: `framework/test/smoke_task.sh`

- [ ] **Step 1: Add the three FAC builders to `framework/task.lua`**

Append to `framework/task.lua` after `escort`:

```lua

-- ============================================================
-- FAC builders (Task v1.1 additions)
-- ============================================================

-- Validate a designation string. Accepts sms.designations.* values or
-- the raw string equivalents. Returns the resolved string or nil + warn.
local function _validate_designation(verb, raw)
  if raw == nil then return "Auto" end
  if type(raw) ~= "string" then
    log.warn(verb .. ": opts.designation must be a string, got " .. type(raw))
    return nil
  end
  return raw  -- pass-through; DCS validates
end

-- FAC for a specific target group (immediate). Air or ground.
sms.task.fac_attack_group = function(target, opts)
  if not sms._is_handle_of(target, sms.group) then
    log.warn("fac_attack_group: target must be an sms.group handle")
    return nil
  end
  local raw = Group.getByName(target.name)
  if not raw then
    log.warn("fac_attack_group: group '" .. tostring(target.name) .. "' not in mission")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fac_attack_group: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local designation = _validate_designation("fac_attack_group", opts.designation)
  if designation == nil then return nil end
  if opts.datalink ~= nil and type(opts.datalink) ~= "boolean" then
    log.warn("fac_attack_group: opts.datalink must be a boolean, got " .. type(opts.datalink))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "fac_attack_group")
  return _stamp({
    id = "FAC_AttackGroup",
    params = {
      groupId     = raw:getID(),
      weaponType  = weapon_type,
      designation = designation,
      datalink    = opts.datalink ~= false,  -- default true
    },
  }, "fac_attack_group", false, false)  -- air or ground
end

-- Area FAC (enroute). Air or ground.
sms.task.fac = function(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fac: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if type(opts.radius) ~= "number" then
    log.warn("fac: opts.radius is required (number, meters)")
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("fac: opts.priority must be a number, got " .. type(priority))
    return nil
  end
  return _stamp({
    id = "FAC",
    params = {
      radius   = opts.radius,
      priority = priority,
    },
  }, "fac", false, false)
end

-- Enroute FAC for a specific target group. Air or ground.
sms.task.fac_engage_group = function(target, opts)
  if not sms._is_handle_of(target, sms.group) then
    log.warn("fac_engage_group: target must be an sms.group handle")
    return nil
  end
  local raw = Group.getByName(target.name)
  if not raw then
    log.warn("fac_engage_group: group '" .. tostring(target.name) .. "' not in mission")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("fac_engage_group: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  local designation = _validate_designation("fac_engage_group", opts.designation)
  if designation == nil then return nil end
  if opts.datalink ~= nil and type(opts.datalink) ~= "boolean" then
    log.warn("fac_engage_group: opts.datalink must be a boolean, got " .. type(opts.datalink))
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("fac_engage_group: opts.priority must be a number, got " .. type(priority))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "fac_engage_group")
  return _stamp({
    id = "FAC_EngageGroup",
    params = {
      groupId     = raw:getID(),
      weaponType  = weapon_type,
      designation = designation,
      datalink    = opts.datalink ~= false,
      priority    = priority,
    },
  }, "fac_engage_group", false, false)
end
```

- [ ] **Step 2: Add smoke entries to `framework/test/smoke_task.sh`**

Append after the escort smoke section:

```bash
# ----------------------------------------------------------------
# Section: v1.1 FAC builders
# ----------------------------------------------------------------

# Reuse the escort fixture if still alive, else spawn fresh
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_fac_target')
  if not g then
    sms.group.create({
      name='_smoke_task_fac_target',
      position={x=0,y=0,z=0},
      country='RUSSIA', category='ground',
      units={{type='Tank Maus'}},
    })
  end
" >/dev/null

echo "==> [build] fac_attack_group returns FAC_AttackGroup, any-category"
expect_str "fac_attack_group id" "
  local g = sms.group('_smoke_task_fac_target')
  if not g then return 'NIL' end
  local t = sms.task.fac_attack_group(g)
  return t and t.id or 'NIL'
" 'FAC_AttackGroup'
expect_true "fac_attack_group not air-only" "
  local g = sms.group('_smoke_task_fac_target')
  if not g then return false end
  return sms.task.fac_attack_group(g)._sms_air_only == nil
"
expect_true "fac_attack_group not ground-only" "
  local g = sms.group('_smoke_task_fac_target')
  if not g then return false end
  return sms.task.fac_attack_group(g)._sms_ground_only == nil
"
expect_true "fac_attack_group default designation" "
  local g = sms.group('_smoke_task_fac_target')
  if not g then return false end
  return sms.task.fac_attack_group(g).params.designation == 'Auto'
"
expect_true "fac_attack_group designation constant" "
  local g = sms.group('_smoke_task_fac_target')
  if not g then return false end
  local t = sms.task.fac_attack_group(g, {designation=sms.designations.LASER})
  return t.params.designation == 'Laser'
"

echo "==> [build] fac returns FAC, any-category"
expect_str  "fac id"               'return sms.task.fac({radius=10000}).id' 'FAC'
expect_true "fac default priority" 'return sms.task.fac({radius=10000}).params.priority == 1'
expect_true "fac requires radius"  'return sms.task.fac({}) == nil'
expect_true "fac not air-only"     'return sms.task.fac({radius=10000})._sms_air_only == nil'

echo "==> [build] fac_engage_group returns FAC_EngageGroup with priority"
expect_str "fac_engage_group id" "
  local g = sms.group('_smoke_task_fac_target')
  if not g then return 'NIL' end
  return sms.task.fac_engage_group(g).id
" 'FAC_EngageGroup'
expect_true "fac_engage_group default priority" "
  local g = sms.group('_smoke_task_fac_target')
  if not g then return false end
  return sms.task.fac_engage_group(g).params.priority == 1
"

echo "==> [build] FAC fixture cleanup"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_fac_target')
  if g then g:destroy() end
" >/dev/null
```

Add `_smoke_task_fac_target` to `SMOKE_FIXTURES` at top of `smoke_task.sh`.

- [ ] **Step 3: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/task.lua framework/test/smoke_task.sh
git commit -m "feat(task): add fac / fac_attack_group / fac_engage_group

Three FAC builders: immediate FAC for a specific target group, area
FAC (enroute), and enroute variant for a specific group. All are
'any category' (air or ground can be FAC). Designation accepts
sms.designations.* constants or raw strings; default 'Auto'.
Datalink defaults to true.

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 8: Engage en route builders — `engage_en_route_targets`, `engage_en_route_group`, `engage_en_route_unit`

**Files:**
- Modify: `framework/task.lua`
- Modify: `framework/test/smoke_task.sh`

- [ ] **Step 1: Add the three engage builders to `framework/task.lua`**

Append to `framework/task.lua` after the FAC builders:

```lua

-- ============================================================
-- Engage en route builders (Task v1.1 additions)
-- ============================================================
--
-- Distinct from the immediate-attack family (sms.task.attack and
-- sms.task.attack_in_area). Enroute = "permission to engage", with a
-- priority field that determines order against other enroute tasks.

-- Engage anything matching target_types. Air only.
sms.task.engage_en_route_targets = function(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("engage_en_route_targets: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if type(opts.target_types) ~= "table" then
    log.warn("engage_en_route_targets: opts.target_types is required (table of attribute strings)")
    return nil
  end
  if opts.max_dist ~= nil and type(opts.max_dist) ~= "number" then
    log.warn("engage_en_route_targets: opts.max_dist must be a number, got " .. type(opts.max_dist))
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("engage_en_route_targets: opts.priority must be a number, got " .. type(priority))
    return nil
  end
  return _stamp({
    id = "EngageTargets",
    params = {
      targetTypes = opts.target_types,
      maxDist     = opts.max_dist,
      priority    = priority,
    },
  }, "engage_en_route_targets", true)
end

-- Permission to engage a specific group (enroute). Air only.
sms.task.engage_en_route_group = function(target, opts)
  if not sms._is_handle_of(target, sms.group) then
    log.warn("engage_en_route_group: target must be an sms.group handle")
    return nil
  end
  local raw = Group.getByName(target.name)
  if not raw then
    log.warn("engage_en_route_group: group '" .. tostring(target.name) .. "' not in mission")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("engage_en_route_group: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.attack_qty ~= nil and type(opts.attack_qty) ~= "number" then
    log.warn("engage_en_route_group: opts.attack_qty must be a number, got " .. type(opts.attack_qty))
    return nil
  end
  if opts.direction ~= nil and type(opts.direction) ~= "number" then
    log.warn("engage_en_route_group: opts.direction must be a number (degrees), got " .. type(opts.direction))
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("engage_en_route_group: opts.priority must be a number, got " .. type(priority))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "engage_en_route_group")
  return _stamp({
    id = "EngageGroup",
    params = {
      groupId        = raw:getID(),
      weaponType     = weapon_type,
      expend         = opts.expend or "Auto",
      attackQty      = opts.attack_qty,
      attackQtyLimit = opts.attack_qty ~= nil,
      direction      = opts.direction and sms.utils.deg_to_rad(opts.direction) or nil,
      priority       = priority,
    },
  }, "engage_en_route_group", true)
end

-- Permission to engage a specific unit (enroute). Air only.
sms.task.engage_en_route_unit = function(target, opts)
  if not sms._is_handle_of(target, sms.unit) then
    log.warn("engage_en_route_unit: target must be an sms.unit handle")
    return nil
  end
  local raw = Unit.getByName(target.name)
  if not raw then
    log.warn("engage_en_route_unit: unit '" .. tostring(target.name) .. "' not in mission")
    return nil
  end
  opts = opts or {}
  if type(opts) ~= "table" then
    log.warn("engage_en_route_unit: opts must be a table or nil, got " .. type(opts))
    return nil
  end
  if opts.attack_qty ~= nil and type(opts.attack_qty) ~= "number" then
    log.warn("engage_en_route_unit: opts.attack_qty must be a number, got " .. type(opts.attack_qty))
    return nil
  end
  if opts.direction ~= nil and type(opts.direction) ~= "number" then
    log.warn("engage_en_route_unit: opts.direction must be a number (degrees), got " .. type(opts.direction))
    return nil
  end
  local priority = opts.priority or 1
  if type(priority) ~= "number" then
    log.warn("engage_en_route_unit: opts.priority must be a number, got " .. type(priority))
    return nil
  end
  local weapon_type = _resolve_weapon_type(opts.weapon_type, "engage_en_route_unit")
  return _stamp({
    id = "EngageUnit",
    params = {
      unitId         = raw:getID(),
      weaponType     = weapon_type,
      expend         = opts.expend or "Auto",
      attackQty      = opts.attack_qty,
      attackQtyLimit = opts.attack_qty ~= nil,
      direction      = opts.direction and sms.utils.deg_to_rad(opts.direction) or nil,
      groupAttack    = opts.group_attack and true or false,
      priority       = priority,
    },
  }, "engage_en_route_unit", true)
end
```

- [ ] **Step 2: Add smoke entries to `framework/test/smoke_task.sh`**

Append after the FAC smoke section:

```bash
# ----------------------------------------------------------------
# Section: v1.1 engage_en_route builders
# ----------------------------------------------------------------

echo "==> [build] engage_en_route_targets returns EngageTargets, air-only"
expect_str  "eert id" "
  return sms.task.engage_en_route_targets({target_types={sms.targets.PLANES}}).id
" 'EngageTargets'
expect_true "eert air-only" "
  return sms.task.engage_en_route_targets({target_types={sms.targets.PLANES}})._sms_air_only == true
"
expect_true "eert default priority" "
  return sms.task.engage_en_route_targets({target_types={sms.targets.PLANES}}).params.priority == 1
"
expect_true "eert priority set" "
  return sms.task.engage_en_route_targets({target_types={sms.targets.PLANES}, priority=3}).params.priority == 3
"
expect_true "eert requires target_types" 'return sms.task.engage_en_route_targets({}) == nil'
expect_true "eert bad max_dist" "
  return sms.task.engage_en_route_targets({target_types={sms.targets.AIR}, max_dist='close'}) == nil
"

# Group/unit engage tests piggyback on the FAC fixture if alive
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_engage_target')
  if not g then
    sms.group.create({
      name='_smoke_task_engage_target',
      position={x=0,y=0,z=0},
      country='RUSSIA', category='airplane',
      units={{type='Su-27', alt=5000}},
    })
  end
" >/dev/null

echo "==> [build] engage_en_route_group returns EngageGroup, air-only, priority"
expect_str "eerg id" "
  local g = sms.group('_smoke_task_engage_target')
  if not g then return 'NIL' end
  return sms.task.engage_en_route_group(g).id
" 'EngageGroup'
expect_true "eerg priority" "
  local g = sms.group('_smoke_task_engage_target')
  if not g then return false end
  return sms.task.engage_en_route_group(g, {priority=2}).params.priority == 2
"
expect_true "eerg air-only" "
  local g = sms.group('_smoke_task_engage_target')
  if not g then return false end
  return sms.task.engage_en_route_group(g)._sms_air_only == true
"
expect_true "eerg bad target" 'return sms.task.engage_en_route_group("nope") == nil'

echo "==> [build] engage_en_route_unit returns EngageUnit"
expect_true "eeru id" "
  local g = sms.group('_smoke_task_engage_target')
  if not g then return false end
  local us = g:get_units()
  if not us or #us == 0 then return false end
  local t = sms.task.engage_en_route_unit(us[1])
  return t and t.id == 'EngageUnit'
"

echo "==> [build] engage cleanup fixture"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_task_engage_target')
  if g then g:destroy() end
" >/dev/null
```

Add `_smoke_task_engage_target` to `SMOKE_FIXTURES` at top of `smoke_task.sh`.

- [ ] **Step 3: Run syntax check**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add framework/task.lua framework/test/smoke_task.sh
git commit -m "feat(task): add engage_en_route_{targets,group,unit}

Three air-only enroute permission-to-engage builders, distinct from
the immediate-attack family. All take opts.priority (default 1).
engage_en_route_targets requires opts.target_types (no default —
caller must say what to engage). engage_en_route_group / _unit
target sms.group / sms.unit handles respectively.

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Task 9: AGENTS.md surface updates

**Files:**
- Modify: `AGENTS.md` (§3 ground-only mention, §7 sms.task new rows, §7 new sms.targets / sms.designations entries)

- [ ] **Step 1: Update AGENTS.md §3 — failure model**

Find §3 ("Failure model: log + nil, never throw") and locate the "Log levels" sub-section (`### Log levels: warn for caller misuse, error for real failures`). Just after that block, add a new sub-section:

```markdown
### Category enforcement: air-only and ground-only

Two private flags on a task table mark category restrictions:

- `_sms_air_only = true` — only `airplane` / `helicopter` groups accept this task. Set by `attack`, `attack_in_area`, `bomb`, `land`, `follow`, `orbit`, `no_task`, `refuel`, `escort`, `attack_map_object`, `bomb_runway`, `awacs`, `tanker`, and the `engage_en_route_*` family.
- `_sms_ground_only = true` — only `ground` groups accept (ships and trains are excluded). Set by `fire_at_point` and `ewr`.

`set_task` / `push_task` reject mismatches at apply time with `log.warn + return false`. `combo` aggregates: a combo containing any air-only sub-task inherits `_sms_air_only`; same for ground. A combo with both flags is built without a build-time warning — DCS will reject it at apply time.
```

- [ ] **Step 2: Update AGENTS.md §7 — sms.task table rows**

Find the existing `sms.task` row block in §7 (search for `sms.task.move_to`). Locate the `attack_in_area` row and update it (replace `priority` mention is appropriate). Then APPEND the 14 new rows after the last existing row (`combo`):

For `attack_in_area`, find this row:

```
| `sms.task.attack_in_area(area, opts?)` | sms.area handle (must be circular in v1); opts: `{weapon_type="Auto", altitude_min, altitude_max}` | `EngageTargetsInZone` | air |
```

Replace with:

```
| `sms.task.attack_in_area(area, opts?)` | sms.area handle (must be circular in v1); opts: `{weapon_type="Auto", altitude_min, altitude_max, priority=1}` | `EngageTargetsInZone` | air enroute |
```

After the `combo` row, append:

```
| `sms.task.no_task()` | — | `NoTask` | air |
| `sms.task.refuel()` | — | `Refueling` | air |
| `sms.task.attack_map_object(point, opts?)` | vec3 (within 2km of structure); opts: `{weapon_type="Auto", expend="Auto", attack_qty?, direction? (deg), group_attack=false}` | `AttackMapObject` | air |
| `sms.task.bomb_runway(airdrome_id, opts?)` | integer DCS airdrome ID; opts same as `attack_map_object`. Handle/name acceptance tracked in [#23](https://github.com/nielsvaes/dcs-sms/issues/23). | `BombingRunway` | air |
| `sms.task.fire_at_point(point, opts?)` | vec3; opts: `{radius?}` | `FireAtPoint` | ground |
| `sms.task.escort(target, opts?)` | sms.unit \| sms.group; opts: `{offset={-50,0,-50}, engagement_dist_max=5000, target_types?, last_waypoint_index?}` | `Escort` | air |
| `sms.task.fac_attack_group(target, opts?)` | sms.group; opts: `{weapon_type="Auto", designation="Auto", datalink=true}` | `FAC_AttackGroup` | any |
| `sms.task.fac(opts)` | opts: `{radius (required), priority=1}` | `FAC` | any enroute |
| `sms.task.fac_engage_group(target, opts?)` | sms.group; opts same as `fac_attack_group` plus `priority=1` | `FAC_EngageGroup` | any enroute |
| `sms.task.engage_en_route_targets(opts)` | opts: `{target_types (required), max_dist?, priority=1}` | `EngageTargets` | air enroute |
| `sms.task.engage_en_route_group(target, opts?)` | sms.group; opts: `{weapon_type="Auto", expend="Auto", attack_qty?, direction?, priority=1}` | `EngageGroup` | air enroute |
| `sms.task.engage_en_route_unit(target, opts?)` | sms.unit; opts same as `engage_en_route_group` plus `group_attack=false` | `EngageUnit` | air enroute |
| `sms.task.awacs(opts?)` | opts: `{priority=1}` | `AWACS` | air enroute |
| `sms.task.tanker(opts?)` | opts: `{priority=1}` | `Tanker` | air enroute |
| `sms.task.ewr(opts?)` | opts: `{priority=1}` | `EWR` | ground enroute |
```

- [ ] **Step 3: Add `sms.targets` and `sms.designations` sections to AGENTS.md §7**

Find §7's `sms.task` heading. After the entire `sms.task` table block, add two new sub-sections (before the next `### sms.<...>` heading or before §8):

```markdown
### `sms.targets` — `framework/targets.lua`

Named constants for DCS target attribute strings, used by enroute engagement task builders. Builders accept either these constants or raw strings (forward-compat for new attributes the framework hasn't catalogued).

| Constant | Resolves to |
|---|---|
| `sms.targets.AIR` | `"Air"` |
| `sms.targets.PLANES` | `"Planes"` |
| `sms.targets.HELICOPTERS` | `"Helicopters"` |
| `sms.targets.GROUND_UNITS` | `"Ground Units"` |
| `sms.targets.GROUND_VEHICLES` | `"Ground vehicles"` |
| `sms.targets.SHIPS` | `"Ships"` |
| `sms.targets.AIR_DEFENCE` | `"Air Defence"` |
| `sms.targets.SAM` | `"SAM"` |
| `sms.targets.AAA` | `"AAA"` |
| `sms.targets.STATICS` | `"Static"` |
| `sms.targets.BUILDINGS` | `"Buildings"` |
| `sms.targets.ALL` | `"All"` |

### `sms.designations` — `framework/designations.lua`

Named constants for DCS FAC designation enum strings. Used by `sms.task.fac_attack_group` / `sms.task.fac_engage_group` opts.

| Constant | Resolves to |
|---|---|
| `sms.designations.NO` | `"No"` |
| `sms.designations.AUTO` | `"Auto"` |
| `sms.designations.WP` | `"WP"` (white phosphorus marker) |
| `sms.designations.IR_POINTER` | `"IR-Pointer"` |
| `sms.designations.LASER` | `"Laser"` |
```

- [ ] **Step 4: Run syntax check + AGENTS link sanity**

Run: `find framework -maxdepth 1 -name "*.lua" -exec luac -p {} \;`
Expected: no output.

Run: `grep -c "^| \`sms\.task\." AGENTS.md`
Expected: 23 (existing 9 builders + 14 new = 23 rows).

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): document v1.1 task additions, ground-only flag, sms.targets/designations

§3 gains a Category enforcement sub-section covering _sms_air_only
and _sms_ground_only flags + combo propagation. §7 sms.task table
gets 14 new rows plus an updated attack_in_area row (now lists
priority and tags as enroute). §7 also gets two new entries for
sms.targets and sms.designations namespaces.

Refs spec docs/superpowers/specs/2026-04-28-framework-task-additions-design.md."
```

---

## Self-Review

**Spec coverage check:**

- ✅ 14 new builders → Tasks 4–8
- ✅ `attack_in_area` priority update → Task 3
- ✅ `sms.targets` namespace → Task 1
- ✅ `sms.designations` namespace → Task 1
- ✅ `_sms_ground_only` flag + `_validate_apply` extension + combo propagation → Task 2
- ✅ AGENTS.md §3 / §7 updates → Task 9
- ✅ Smoke entries per builder → integrated into each builder task
- ✅ Load order update → Task 1
- ✅ AGENTS.md §6 load chain update → Task 1

**Placeholder scan:** No TBDs, TODOs, or "implement appropriately" instructions. Every step has full code. Cross-references between tasks are by content (not "see Task 4") so each task is independently readable.

**Type / signature consistency:**

- `_stamp` extended uniformly: 4 args, optional `ground_only` bool. Tasks that don't need ground_only just omit. ✅
- `_validate_priority` helper introduced in Task 4 and reused conceptually in Tasks 7 & 8 (each task validates priority inline via the same pattern; helper is task-local). ✅
- `_validate_designation` introduced in Task 7 and used by both FAC builders that take designation. ✅
- `_resolve_weapon_type` reuses the existing helper in `task.lua` — no signature change. ✅
- All builders use `_stamp(table, "verb", air_only, ground_only?)`. ✅
- `_sms_ground_only` strictly means category == "ground" (excludes ship/train) — stated in Task 2 step 3 and AGENTS §3 update. Consistent. ✅

No issues found. Plan is ready for execution.
