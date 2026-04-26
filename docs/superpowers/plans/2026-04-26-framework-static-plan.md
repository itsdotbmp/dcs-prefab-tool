# `sms.static` v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a static-object capability to the framework. Single new module file `framework/static.lua` exposes the entity wrapper `sms.static("name")` plus factory functions `sms.static.create(cfg)` and `sms.static.clone(template, overrides)`. `framework/area.lua` gains one new method `is_static_in(static_handle)` next to `is_unit_in`. A bridge-driven smoke test exercises the full surface.

**Architecture:** Stateless factories (mirror of `sms.group.create`/`clone`) producing handles backed by `coalition.addStaticObject` and `StaticObject.getByName`. Auto-suffix on name collision probes ONLY `StaticObject.getByName` (statics live in their own DCS name namespace, empirically verified). `pitch`/`bank` cfg fields are warned + dropped (DCS silently ignores them across all static types — verified empirically). `clone` walks `env.mission.coalition[*].country[*].static.group[]` for ME-defined templates.

**Tech Stack:** Lua 5.1 (DCS mission environment), bash (mingw on Windows), the existing `dcs-sms.exe` execution bridge, DCS APIs (`coalition.addStaticObject`, `StaticObject.getByName`, `country.id.*`, `env.mission.*`).

**Spec:** `docs/superpowers/specs/2026-04-26-framework-static-design.md`

**Worktree path (use this for all file operations):** `D:\git\dcs-sms\.worktrees\sms-static\`

---

## File Structure

| File | Purpose | Change |
|---|---|---|
| `framework/static.lua` | Entity wrapper + factories for static objects | NEW (~270 lines) |
| `framework/area.lua` | Area abstraction; gains one new predicate | EDIT: add `is_static_in` (~15 lines) |
| `framework/test/smoke_static.sh` | Bridge smoke test | NEW (~400 lines) |

Existing files (`sms.lua`, `log.lua`, `utils.lua`, `group.lua`, `unit.lua`, `timer.lua`, `spawn.lua`, the existing smoke tests) are unchanged.

## Parallelism

Tasks 1, 2, and 3 touch entirely different files and have NO edit-time dependencies on each other. They can be dispatched in parallel:

- **Task 1** creates `framework/test/smoke_static.sh` (new file)
- **Task 2** creates `framework/static.lua` (new file)
- **Task 3** edits `framework/area.lua` (additive — appends one method)

Task 4 (verification) is sequential and run by the controller after Tasks 1-3 complete.

**All file paths in this plan are relative to the worktree root** `D:\git\dcs-sms\.worktrees\sms-static\`. Subagents executing tasks MUST use the absolute worktree path so files do not leak into the parent repo or other worktrees.

---

## Task 1: Failing smoke test `framework/test/smoke_static.sh`

**Files:**
- Create: `D:\git\dcs-sms\.worktrees\sms-static\framework\test\smoke_static.sh`

- [ ] **Step 1: Write the smoke test**

Create `framework/test/smoke_static.sh` with EXACTLY this content:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for sms.static v1.
# Exercises the entity wrapper, create happy + sad paths, auto-suffix,
# clone (skipped if no ME static found), pitch/bank warning,
# and sms.area:is_static_in.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

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
"${DCSSMS}" exec --file timer.lua >/dev/null
"${DCSSMS}" exec --file spawn.lua >/dev/null
"${DCSSMS}" exec --file static.lua >/dev/null

# ----------------------------------------------------------------
# Section 1: discover spawn coords from any existing unit
# (statics use the same world coords; we anchor relative to a
# known-livable ground spot in the mission.)
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
# Section 2: sms.static.create — happy path Hangar B
# ----------------------------------------------------------------
echo "==> [create] Hangar B happy path"
expect_eq_string "Hangar B type" "
  local s = sms.static.create({
    name     = '_smoke_static_hangar',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 50, y = 0, z = ${SPAWN_Z} + 50},
    country  = 'USA',
  })
  if not s then return 'NO_HANDLE' end
  if not s:is_alive() then return 'NOT_ALIVE' end
  return s:get_type()
" "Hangar B"

echo "==> [create] cleanup hangar"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_hangar')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 3: entity wrapper getters round-trip
# ----------------------------------------------------------------
echo "==> [entity] getters return sensible values"
expect_true "entity getters" "
  local s = sms.static.create({
    name     = '_smoke_static_entity',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 100, y = 0, z = ${SPAWN_Z} + 100},
    country  = 'USA',
  })
  if not s then return false end
  local name = s:get_name()
  local pos  = s:get_position()
  local coal = s:get_coalition()
  local cnty = s:get_country()
  local typ  = s:get_type()
  return type(name) == 'string'
    and type(pos) == 'table' and type(pos.x) == 'number' and type(pos.y) == 'number' and type(pos.z) == 'number'
    and (coal == 'red' or coal == 'blue' or coal == 'neutral')
    and cnty == 'USA'
    and typ == 'Hangar B'
"

echo "==> [entity] cleanup"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_entity')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 4: DCS-2D coordinate translation
# ----------------------------------------------------------------
echo "==> [create] DCS-2D translation: cfg.position.x -> def.x, cfg.position.z -> def.y"
expect_true "coord translation" "
  local s = sms.static.create({
    name     = '_smoke_static_coords',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 200, y = 0, z = ${SPAWN_Z} + 300},
    country  = 'USA',
  })
  if not s then return false end
  local p = s:get_position()
  return math.abs(p.x - (${SPAWN_X} + 200)) < 1
     and math.abs(p.z - (${SPAWN_Z} + 300)) < 1
"

echo "==> [create] cleanup coords"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_coords')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 5: heading degrees -> radians at spawn
# ----------------------------------------------------------------
echo "==> [create] heading 90 degrees -> ~pi/2 radians applied"
expect_true "heading translated" "
  local s = sms.static.create({
    name     = '_smoke_static_heading',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 400, y = 0, z = ${SPAWN_Z} + 400},
    country  = 'USA',
    heading  = 90,
  })
  if not s then return false end
  local obj = StaticObject.getByName('_smoke_static_heading')
  if not obj then return false end
  local pos = obj:getPosition()
  -- The static's x basis vector encodes its forward direction.
  -- For heading 0 (north), forward is +DCS-2D-y -> our +z; for heading 90 (east),
  -- forward is +DCS-2D-x -> our +x. atan2 derivation matches DCS conv.
  local yaw = math.atan2(pos.x.z, pos.x.x)
  return math.abs(yaw - math.pi/2) < 0.05 or math.abs(yaw + math.pi/2 - 2*math.pi) < 0.05
"

echo "==> [create] cleanup heading"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_heading')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 6: cargo with mass + canCargo
# ----------------------------------------------------------------
echo "==> [create] cargo iso_container with mass + canCargo"
expect_true "cargo spawned" "
  local s = sms.static.create({
    name     = '_smoke_static_cargo',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 500, y = 0, z = ${SPAWN_Z} + 500},
    country  = 'USA',
    category = 'Cargos',
    mass     = 1000,
    canCargo = true,
  })
  if not s then return false end
  return s:is_alive()
"

echo "==> [create] cleanup cargo"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_cargo')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 7: dead = true (wreckage)
# ----------------------------------------------------------------
echo "==> [create] dead=true spawns"
expect_true "dead static spawned" "
  local s = sms.static.create({
    name     = '_smoke_static_dead',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 600, y = 0, z = ${SPAWN_Z} + 600},
    country  = 'USA',
    dead     = true,
  })
  if not s then return false end
  return s:is_alive()
"

echo "==> [create] cleanup dead"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_dead')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 8: auto-suffix on name collision (within static namespace only)
# ----------------------------------------------------------------
echo "==> [auto-suffix] first 'crate' resolves to 'crate'"
expect_eq_string "crate first" "
  local s = sms.static.create({
    name     = 'crate',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 700, y = 0, z = ${SPAWN_Z} + 700},
    country  = 'USA',
    category = 'Cargos',
  })
  return s and s:get_name() or 'NIL'
" "crate"

echo "==> [auto-suffix] second 'crate' resolves to 'crate-1'"
expect_eq_string "crate second" "
  local s = sms.static.create({
    name     = 'crate',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 720, y = 0, z = ${SPAWN_Z} + 720},
    country  = 'USA',
    category = 'Cargos',
  })
  return s and s:get_name() or 'NIL'
" "crate-1"

echo "==> [auto-suffix] third 'crate' resolves to 'crate-2'"
expect_eq_string "crate third" "
  local s = sms.static.create({
    name     = 'crate',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 740, y = 0, z = ${SPAWN_Z} + 740},
    country  = 'USA',
    category = 'Cargos',
  })
  return s and s:get_name() or 'NIL'
" "crate-2"

echo "==> [auto-suffix] cleanup"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'crate', 'crate-1', 'crate-2'}) do
    local s = sms.static(name)
    if s then s:destroy() end
  end
" >/dev/null

# ----------------------------------------------------------------
# Section 9: namespace separation — static & group named the same coexist
# ----------------------------------------------------------------
echo "==> [namespace] static 'ns_test' and group 'ns_test' coexist (no over-probing)"
expect_true "namespace separation" "
  local s = sms.static.create({
    name     = 'ns_test',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 800, y = 0, z = ${SPAWN_Z} + 800},
    country  = 'USA',
  })
  if not s then return false end
  if s:get_name() ~= 'ns_test' then return false end
  -- Now spawn a group with the same name. It must succeed (separate namespace).
  local g = sms.group.create({
    name     = 'ns_test',
    position = {x = ${SPAWN_X} + 850, y = 0, z = ${SPAWN_Z} + 850},
    country  = 'USA',
    category = 'ground',
    units    = {{ type = 'AAV7' }},
  })
  if not g then return false end
  -- Both should be alive simultaneously.
  return s:is_alive() and g:is_alive()
"

echo "==> [namespace] cleanup"
"${DCSSMS}" exec --code "
  local s = sms.static('ns_test')
  if s then s:destroy() end
  local g = sms.group('ns_test')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 10: pitch/bank warn-and-drop
# ----------------------------------------------------------------
echo "==> [pitch/bank] spawn succeeds with pitch present (DCS ignores it)"
expect_true "pitch warned not failed" "
  local s = sms.static.create({
    name     = '_smoke_static_pitch',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 900, y = 0, z = ${SPAWN_Z} + 900},
    country  = 'USA',
    pitch    = 0.5,
    bank     = 0.5,
  })
  if not s then return false end
  return s:is_alive()
"

echo "==> [pitch/bank] cleanup"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_pitch')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 11: create — negative paths
# ----------------------------------------------------------------
echo "==> [create] no config -> nil"
expect_true "no config" 'return sms.static.create() == nil'

echo "==> [create] non-table config -> nil"
expect_true "string config" 'return sms.static.create("not a table") == nil'

echo "==> [create] missing name -> nil"
expect_true "no name" "
  return sms.static.create({
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] missing type -> nil"
expect_true "no type" "
  return sms.static.create({
    name = 'no_type',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] missing position -> nil"
expect_true "no position" "
  return sms.static.create({
    name = 'no_pos',
    type = 'Hangar B',
    country = 'USA',
  }) == nil
"

echo "==> [create] missing country -> nil"
expect_true "no country" "
  return sms.static.create({
    name = 'no_country',
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [create] bad country -> nil"
expect_true "bad country" "
  return sms.static.create({
    name = 'bad_country',
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
    country = 'WAKANDA',
  }) == nil
"

echo "==> [create] non-vec3 position -> nil"
expect_true "bad position" "
  return sms.static.create({
    name = 'bad_pos',
    type = 'Hangar B',
    position = 'not a vec3',
    country = 'USA',
  }) == nil
"

echo "==> [create] non-string type -> nil"
expect_true "non-string type" "
  return sms.static.create({
    name = 'numeric_type',
    type = 12345,
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] empty type string -> nil"
expect_true "empty type" "
  return sms.static.create({
    name = 'empty_type',
    type = '',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] non-number heading -> nil"
expect_true "non-num heading" "
  return sms.static.create({
    name = 'bad_heading',
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    heading = 'north',
  }) == nil
"

# ----------------------------------------------------------------
# Section 12: clone — discover ME-defined static template (skip if none)
# ----------------------------------------------------------------
echo "==> [clone] discover ME-defined static name (if any)"
TEMPLATE_NAME=$("${DCSSMS}" exec --code '
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country_entry in ipairs(side.country) do
        if country_entry.static and country_entry.static.group then
          for _, sg in ipairs(country_entry.static.group) do
            if sg.units and sg.units[1] then return sg.name end
          end
        end
      end
    end
  end
  return nil
' | grep -oE '"return_value":"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')

if [ -z "${TEMPLATE_NAME}" ]; then
  echo "==> [clone] no ME-defined static found in mission, skipping clone tests (Sections 12-13)"
else
  echo "==> [clone] using template: ${TEMPLATE_NAME}"

  echo "==> [clone] clone with new name + position"
  expect_true "clone alive" "
    local s = sms.static.clone('${TEMPLATE_NAME}', {
      name     = '_smoke_static_clone',
      position = {x = ${SPAWN_X} + 1000, y = 0, z = ${SPAWN_Z} + 1000},
    })
    if not s then return false end
    return s:is_alive()
  "

  echo "==> [clone] cleanup first clone"
  "${DCSSMS}" exec --code "
    local s = sms.static('_smoke_static_clone')
    if s then s:destroy() end
  " >/dev/null

  echo "==> [clone] auto-suffix: first 'dup_clone' resolves to 'dup_clone'"
  expect_eq_string "dup_clone first" "
    local s = sms.static.clone('${TEMPLATE_NAME}', {
      name     = 'dup_clone',
      position = {x = ${SPAWN_X} + 1100, y = 0, z = ${SPAWN_Z} + 1100},
    })
    return s and s:get_name() or 'NIL'
  " "dup_clone"

  echo "==> [clone] auto-suffix: second 'dup_clone' resolves to 'dup_clone-1'"
  expect_eq_string "dup_clone second" "
    local s = sms.static.clone('${TEMPLATE_NAME}', {
      name     = 'dup_clone',
      position = {x = ${SPAWN_X} + 1150, y = 0, z = ${SPAWN_Z} + 1150},
    })
    return s and s:get_name() or 'NIL'
  " "dup_clone-1"

  echo "==> [clone] cleanup duplicates"
  "${DCSSMS}" exec --code "
    for _, name in ipairs({'dup_clone', 'dup_clone-1'}) do
      local s = sms.static(name)
      if s then s:destroy() end
    end
  " >/dev/null
fi

# ----------------------------------------------------------------
# Section 13: clone — negative paths
# ----------------------------------------------------------------
echo "==> [clone] missing template -> nil"
expect_true "missing template" "
  return sms.static.clone('_definitely_not_a_template_xyz', {
    name = 'never',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] non-string template_name -> nil"
expect_true "non-string template" "
  return sms.static.clone(12345, {
    name = 'never',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] non-table overrides -> nil"
expect_true "non-table overrides" "
  return sms.static.clone('any', 'not a table') == nil
"

echo "==> [clone] missing name override -> nil"
expect_true "no override name" "
  return sms.static.clone('any', {
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] missing position override -> nil"
expect_true "no override position" "
  return sms.static.clone('any', {
    name = 'no_pos_override',
  }) == nil
"

# ----------------------------------------------------------------
# Section 14: sms.area:is_static_in
# ----------------------------------------------------------------
echo "==> [area] is_static_in true when static is inside circle"
expect_true "inside circle" "
  local center = {x = ${SPAWN_X} + 2000, y = 0, z = ${SPAWN_Z} + 2000}
  local area = sms.area.create_circular(center, 100)
  if not area then return false end
  local s = sms.static.create({
    name     = '_smoke_static_in',
    type     = 'Hangar B',
    position = {x = center.x, y = 0, z = center.z},
    country  = 'USA',
  })
  if not s then return false end
  return area:is_static_in(s)
"

echo "==> [area] is_static_in false when static is outside circle"
expect_false "outside circle" "
  local center = {x = ${SPAWN_X} + 3000, y = 0, z = ${SPAWN_Z} + 3000}
  local area = sms.area.create_circular(center, 50)
  if not area then return false end
  local s = sms.static.create({
    name     = '_smoke_static_out',
    type     = 'Hangar B',
    position = {x = center.x + 200, y = 0, z = center.z + 200},
    country  = 'USA',
  })
  if not s then return false end
  return area:is_static_in(s)
"

echo "==> [area] cleanup"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'_smoke_static_in', '_smoke_static_out'}) do
    local s = sms.static(name)
    if s then s:destroy() end
  end
" >/dev/null

echo "==> [area] is_static_in non-static handle -> false + log"
expect_false "non-static target" "
  local center = {x = 0, y = 0, z = 0}
  local area = sms.area.create_circular(center, 100)
  return area:is_static_in('not a handle')
"

echo "==> [area] is_static_in non-area handle -> false + log"
expect_false "non-area self" "
  local s = sms.static.create({
    name     = '_smoke_static_typecheck',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 4000, y = 0, z = ${SPAWN_Z} + 4000},
    country  = 'USA',
  })
  if not s then return true end -- if create failed, the typecheck below is moot; treat as 'no false positive'
  -- Pass a non-area first arg by calling sms.area.is_static_in directly.
  local result = sms.area.is_static_in('not an area', s)
  s:destroy()
  return result
"

# ----------------------------------------------------------------
# Section 15: handle methods on dead static -> nil + log
# ----------------------------------------------------------------
echo "==> [entity] get_position on destroyed static -> nil"
expect_true "destroyed get_position nil" "
  local s = sms.static.create({
    name     = '_smoke_static_dead_test',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 5000, y = 0, z = ${SPAWN_Z} + 5000},
    country  = 'USA',
  })
  if not s then return false end
  s:destroy()
  return s:get_position() == nil
"

# ----------------------------------------------------------------
# Section 16: tail-log assertion
# ----------------------------------------------------------------
echo "==> [log] dcs.log should contain [sms.static] line for unknown country"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.static\]' -n 200)
echo "${log_window}" | grep -q "unknown country" \
  || { echo "FAIL: missing log line for unknown country"; echo "${log_window}"; exit 1; }

echo "==> [log] dcs.log should contain [sms.static] pitch/bank warning"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.static\]' -n 200)
echo "${log_window}" | grep -q "pitch/bank" \
  || { echo "FAIL: missing log line for pitch/bank warning"; echo "${log_window}"; exit 1; }

echo "smoke ok"
```

- [ ] **Step 2: Make it executable**

Run:
```bash
chmod +x "D:/git/dcs-sms/.worktrees/sms-static/framework/test/smoke_static.sh"
```

- [ ] **Step 3: Skip running the test now**

Multiple subagents may be running in parallel and `framework/static.lua` does not yet exist. Task 4 (verification) will run the smoke test after all parallel tasks complete.

- [ ] **Step 4: Commit**

Run from worktree root:
```bash
cd "D:/git/dcs-sms/.worktrees/sms-static" && git add framework/test/smoke_static.sh && git commit -m "test: add bridge-driven smoke test for sms.static"
```

---

## Task 2: Implement `framework/static.lua`

**Files:**
- Create: `D:\git\dcs-sms\.worktrees\sms-static\framework\static.lua`

- [ ] **Step 1: Write the file**

Create `framework/static.lua` with EXACTLY this content:

```lua
-- dcs-sms framework: static module (sms.static).
--
-- Entity wrapper + factories for DCS static objects (single-object scenery,
-- cargo, FARPs, hangars, wreckage). Sibling of sms.unit, with create/clone
-- factories on the same module (no separate sms.spawn_static).
--
-- sms.static("name") returns a lightweight handle, or nil + log if the
-- static doesn't exist in DCS. Handles are {name=name} tables with
-- __index = sms.static, so handle:method() dispatches to sms.static.method(handle).
--
-- sms.static.create(cfg) -> handle | nil + log. coalition.addStaticObject under the hood.
-- sms.static.clone(template_name, overrides) -> handle | nil + log. ME-template-derived.
--
-- All methods accept either a handle or a raw name string, normalized at entry.
-- Methods that touch DCS state internally check is_alive first; if the static is
-- not alive, they log and return nil — they never throw. _name_of also accepts
-- garbage input (nil, numbers, ...) and returns nil, which then makes is_alive
-- return false and the standard log+nil path triggers.
--
-- Auto-suffix probes ONLY StaticObject.getByName (statics live in their own
-- name namespace, separate from groups and units — verified empirically).
--
-- DCS silently ignores pitch/bank on coalition.addStaticObject; cfg.pitch and
-- cfg.bank (if present) are warned (via log.info with explicit "warning:" text,
-- since v1 logger has no warning level) and dropped — only heading is applied.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua -> unit.lua
--                -> area.lua -> timer.lua -> spawn.lua -> static.lua.
-- area.lua's is_static_in resolves sms.static lazily at call time.
--
-- See docs/superpowers/specs/2026-04-26-framework-static-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.static")
sms.static = sms.static or {}

-- DCS coalition int -> normalized lowercase string.
local _coalition_str = {[0] = "neutral", [1] = "red", [2] = "blue"}

-- base_name -> next-index hint for auto-suffix. Lost on reload (probe recovers).
local _name_counters = {}

-- int country id -> string country name. Built lazily.
local _country_reverse = nil

local function _build_country_reverse()
  if _country_reverse then return end
  _country_reverse = {}
  for k, v in pairs(country.id) do
    _country_reverse[v] = k
  end
end

-- ============================================================
-- Helpers (private)
-- ============================================================

-- Accept either a handle ({name=...}) or a raw name string; return the name.
-- Returns nil for any other input (nil, numbers, booleans, table-without-name).
-- Callers handle nil names as "not alive" rather than throwing.
local function _name_of(s)
  if type(s) == "string" then return s end
  if type(s) == "table" and type(s.name) == "string" then return s.name end
  return nil
end

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

local function _name_taken(name)
  return StaticObject.getByName(name) ~= nil
end

-- Resolve a unique name using base + numeric suffix. Probes ONLY
-- StaticObject.getByName — statics share name namespace with neither
-- groups nor units (verified empirically). Counter is a hint; probe is
-- the source of truth.
local function _resolve_unique_name(base)
  if not _name_taken(base) then return base end
  local n = _name_counters[base] or 1
  while _name_taken(base .. "-" .. n) do
    n = n + 1
  end
  _name_counters[base] = n + 1
  return base .. "-" .. n
end

local function _deep_copy(t)
  if type(t) ~= "table" then return t end
  local copy = {}
  for k, v in pairs(t) do
    copy[k] = _deep_copy(v)
  end
  return copy
end

-- ============================================================
-- Entity wrapper methods
-- ============================================================

sms.static.is_alive = function(s)
  local name = _name_of(s)
  if not name then return false end
  local obj = StaticObject.getByName(name)
  return obj ~= nil and obj:isExist()
end

sms.static.get_name = function(s)
  return _name_of(s)
end

sms.static.get_position = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_position: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local p = StaticObject.getByName(name):getPoint()
  -- DCS world coords: x = east, y = altitude, z = north.
  return {x = p.x, y = p.y, z = p.z}
end

sms.static.get_coalition = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local c = StaticObject.getByName(name):getCoalition()
  local s_str = _coalition_str[c]
  if not s_str then
    log.error("get_coalition: '" .. tostring(name) .. "' returned unknown coalition " .. tostring(c))
    return nil
  end
  return s_str
end

sms.static.get_country = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_country: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local int = StaticObject.getByName(name):getCountry()
  _build_country_reverse()
  local c_str = _country_reverse[int]
  if not c_str then
    log.error("get_country: '" .. tostring(name) .. "' returned unknown country " .. tostring(int))
    return nil
  end
  return c_str
end

sms.static.get_type = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_type: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  return StaticObject.getByName(name):getTypeName()
end

sms.static.destroy = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  StaticObject.getByName(name):destroy()
  return true
end

-- ============================================================
-- DCS def builder (factories)
-- ============================================================

local function _build_def(cfg, resolved_name)
  local heading_deg = cfg.heading or 0
  local heading_rad = sms.utils.deg_to_rad(heading_deg) or 0

  local def = {
    name    = resolved_name,
    type    = cfg.type,
    -- DCS-2D: x = vec3.x (east), y = vec3.z (north)
    x       = cfg.position.x,
    y       = cfg.position.z,
    heading = heading_rad,
  }

  -- Blessed optional fields
  if cfg.category   ~= nil then def.category   = cfg.category   end
  if cfg.dead       ~= nil then def.dead       = cfg.dead       end
  if cfg.mass       ~= nil then def.mass       = cfg.mass       end
  if cfg.canCargo   ~= nil then def.canCargo   = cfg.canCargo   end
  if cfg.shape_name ~= nil then def.shape_name = cfg.shape_name end
  if cfg.livery_id  ~= nil then def.livery_id  = cfg.livery_id  end

  -- Pitch/bank: warn-and-drop. DCS silently ignores these on
  -- coalition.addStaticObject (verified empirically across hangars, cargo,
  -- planes, and dead-state planes). v1 logger has no warning level; using
  -- log.info with explicit "warning:" text so it's both searchable and
  -- the call still succeeds.
  if cfg.pitch ~= nil or cfg.bank ~= nil then
    log.info("create: warning: pitch/bank are ignored by DCS on statics; dropping (only heading is applied)")
  end

  -- Pass-through unknown fields verbatim (forward-compat). pitch/bank are
  -- explicitly excluded since DCS silently drops them anyway.
  local known = {
    name = true, type = true, position = true, country = true, heading = true,
    category = true, dead = true, mass = true, canCargo = true,
    shape_name = true, livery_id = true,
    pitch = true, bank = true,  -- explicitly filtered (warned above)
  }
  for k, v in pairs(cfg) do
    if not known[k] and def[k] == nil then
      def[k] = v
    end
  end

  return def
end

local function _spawn(def, country_int, resolved_name)
  -- coalition.addStaticObject may error on bad input. Wrap in pcall.
  local ok, err = pcall(coalition.addStaticObject, country_int, def)
  if not ok then
    log.error("DCS rejected the spawn: " .. tostring(err))
    return nil
  end
  if not StaticObject.getByName(resolved_name) then
    log.error("DCS accepted addStaticObject but static '" .. resolved_name ..
              "' not found post-call (check type/category validity)")
    return nil
  end
  return sms.static(resolved_name)
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
  if type(cfg.type) ~= "string" or cfg.type == "" then
    log.error("create: type is required (non-empty string)")
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
  if cfg.heading ~= nil and type(cfg.heading) ~= "number" then
    log.error("create: heading must be a number (degrees) if provided")
    return false
  end
  if cfg.category ~= nil and type(cfg.category) ~= "string" then
    log.error("create: category must be a string if provided")
    return false
  end
  return true
end

sms.static.create = function(cfg)
  if not _validate_create_config(cfg) then return nil end

  local country_int = _resolve_country(cfg.country)
  if not country_int then
    log.error("create: unknown country '" .. tostring(cfg.country) .. "'")
    return nil
  end

  local resolved_name = _resolve_unique_name(cfg.name)
  local def = _build_def(cfg, resolved_name)
  return _spawn(def, country_int, resolved_name)
end

-- ============================================================
-- clone
-- ============================================================

-- Walk env.mission.coalition[red/blue/neutrals].country[*].static.group[]
-- for a "group" with matching name. In the ME mission descriptor each
-- static is wrapped in a single-unit "group" with units[1] holding the
-- actual static def.
local function _find_template_in_mission(template_name)
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country_entry in ipairs(side.country) do
        if country_entry.static and country_entry.static.group then
          for _, sg in ipairs(country_entry.static.group) do
            if sg.name == template_name and sg.units and sg.units[1] then
              return {
                def_unit    = sg.units[1],
                country_int = country_entry.id,
                group_name  = sg.name,
              }
            end
          end
        end
      end
    end
  end
  return nil
end

sms.static.clone = function(template_name, overrides)
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

  local def = _deep_copy(found.def_unit)

  -- Strip ME-assigned ids so DCS gets fresh ones for the clone.
  def.unitId = nil
  def.groupId = nil

  -- Re-anchor: replace x/y with new world position (DCS-2D translation).
  def.x = overrides.position.x
  def.y = overrides.position.z

  -- New unique name.
  local resolved_name = _resolve_unique_name(overrides.name)
  def.name = resolved_name

  return _spawn(def, found.country_int, resolved_name)
end

-- ============================================================
-- Sugar constructor
-- ============================================================

-- sms.static("name") -> handle | nil + log.
sms._make_callable_handle(sms.static, StaticObject.getByName, log)
```

- [ ] **Step 2: Skip the live bridge sanity-check**

Multiple subagents may be running in parallel against the same DCS bridge. Task 4 (verification) will exercise this via the smoke test.

- [ ] **Step 3: Commit**

Run from worktree root:
```bash
cd "D:/git/dcs-sms/.worktrees/sms-static" && git add framework/static.lua && git commit -m "feat(framework): add sms.static (entity wrapper + create + clone)"
```

---

## Task 3: Add `is_static_in` to `framework/area.lua`

**Files:**
- Modify: `D:\git\dcs-sms\.worktrees\sms-static\framework\area.lua`

- [ ] **Step 1: Read the current file to find the insertion point**

Read `framework/area.lua`. Locate the existing `sms.area.is_unit_in` function definition. The new method `sms.area.is_static_in` will be added DIRECTLY after the closing `end` of `is_unit_in`, BEFORE `sms.area.is_any_of_group_in` begins.

The existing `is_unit_in` ends with:

```lua
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
```

The next function after it is `sms.area.is_any_of_group_in = function(a, g)`.

- [ ] **Step 2: Insert the new method**

Use the Edit tool to add the new method between `is_unit_in` and `is_any_of_group_in`. Old string to find:

```lua
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
```

Replace with:

```lua
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

sms.area.is_static_in = function(a, s)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_static_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(s, sms.static) then
    log.error("is_static_in: target must be an sms.static handle")
    return false
  end
  local p = sms.static.get_position(s)
  if not p then return false end
  if a.kind == "circle" then
    return _point_in_circle(a._data, p.x, p.z)
  end
  return _point_in_polygon(a._data.vertices, p.x, p.z)
end

sms.area.is_any_of_group_in = function(a, g)
```

- [ ] **Step 3: Update the area.lua header docstring to reference is_static_in**

The header has a "Methods" section listing each method. Use the Edit tool to add a line for `is_static_in`. Old string:

```lua
--   :is_unit_in(sms.unit handle)                -- bool, strict handle check
--   :is_any_of_group_in(sms.group handle)       -- bool
```

Replace with:

```lua
--   :is_unit_in(sms.unit handle)                -- bool, strict handle check
--   :is_static_in(sms.static handle)            -- bool, strict handle check
--   :is_any_of_group_in(sms.group handle)       -- bool
```

- [ ] **Step 4: Update the load-order comment in area.lua**

The header has a load-order line. Old string:

```lua
-- Loading order: sms.lua -> log.lua -> group.lua -> unit.lua -> area.lua.
-- is_unit_in / is_*_of_group_in require sms.unit/sms.group at call time.
```

Replace with:

```lua
-- Loading order: sms.lua -> log.lua -> group.lua -> unit.lua -> area.lua.
-- is_unit_in / is_static_in / is_*_of_group_in require sms.unit/sms.static/sms.group
-- at call time (loaded later in framework boot).
```

- [ ] **Step 5: Skip the live bridge sanity-check**

Task 4 (verification) will exercise this via the smoke test.

- [ ] **Step 6: Commit**

Run from worktree root:
```bash
cd "D:/git/dcs-sms/.worktrees/sms-static" && git add framework/area.lua && git commit -m "feat(framework): add sms.area:is_static_in (mirrors is_unit_in for sms.static)"
```

---

## Task 4: Run smoke test + verify green (controller-only)

**Files:** none modified

This task is run by the controller agent AFTER tasks 1, 2, and 3 have all completed and committed.

- [ ] **Step 1: Verify hook is fresh**

Run:
```bash
cd "D:/git/dcs-sms" && tools/dcs-sms.exe status
```

Expected output includes `fresh: true`. If `fresh: false`, ask user to focus DCS or wait for a fresh frame, then re-run.

- [ ] **Step 2: Run regression smoke tests for previously-shipped framework modules**

This catches any accidental breakage of existing framework loading. Run each from the worktree:

```bash
cd "D:/git/dcs-sms/.worktrees/sms-static" && \
  framework/test/smoke.sh && \
  framework/test/smoke_group.sh && \
  framework/test/smoke_unit.sh && \
  framework/test/smoke_spawn.sh
```

Note: `smoke_area.sh` requires an ME circle zone in the current mission and will bail clearly if missing. `smoke_timer.sh` takes ~25s and requires an unpaused mission. Both are skippable for this verification (regression risk is low — Task 3 only adds one method to `area.lua`, no other behaviour changes).

Expected: all four tests print `smoke ok` and exit 0.

- [ ] **Step 3: Run the new smoke test**

```bash
cd "D:/git/dcs-sms/.worktrees/sms-static" && framework/test/smoke_static.sh
```

Expected: prints `smoke ok` and exits 0.

If the user's `tempMission` has no ME-defined statics (most likely), Sections 12 + 13 of the smoke test will print:

```
==> [clone] no ME-defined static found in mission, skipping clone tests (Sections 12-13)
```

…and continue. The remaining clone-negative-path tests (Section 13) still run — they don't need an ME template. Sections 12 (clone happy/auto-suffix) skip cleanly.

- [ ] **Step 4: Verify the worktree is in the expected state**

Run from worktree root:
```bash
cd "D:/git/dcs-sms/.worktrees/sms-static" && git status && git log --oneline -10
```

Expected: working tree clean. `git log` shows (from most recent):
1. `feat(framework): add sms.area:is_static_in ...` (Task 3)
2. `feat(framework): add sms.static ...` (Task 2)
3. `test: add bridge-driven smoke test for sms.static` (Task 1)
4. `docs(static): clarify pitch/bank warn ...` (spec clarification)
5. `docs: sms.static v1 design` (spec)
6. `dd9a656 Merge sms.spawn v1` (parent — main branch)

(Order of tasks 1, 2, 3 may vary based on subagent commit order — that's fine.)

- [ ] **Step 5: No commit needed**

This task verifies green; it does not modify files.

---

## Self-Review Notes

- **Spec coverage:**
  - Entity wrapper methods (`is_alive`, `get_name`, `get_position`, `get_coalition`, `get_country`, `get_type`, `destroy`) → Task 2
  - `sms.static.create` blessed fields (name, type, position, country, heading, category, dead, mass, canCargo, shape_name, livery_id) → Task 2 + smoke Task 1 (Sections 2, 6, 7, 11)
  - Pass-through behaviour for unknown fields → Task 2 (filter table) + Task 1 doesn't directly assert this beyond happy paths (acceptable: same level of coverage as spawn smoke)
  - Pitch/bank warn-and-drop → Task 2 (`_build_def` warning) + Task 1 (Section 10 + log assertion in Section 16)
  - Auto-suffix probing only `StaticObject.getByName` → Task 2 (`_name_taken`) + Task 1 (Sections 8 + 9 namespace-separation)
  - `sms.static.clone` ME-walk + name+position re-anchor → Task 2 (`_find_template_in_mission`) + Task 1 (Section 12, conditional)
  - `sms.area:is_static_in` → Task 3 + Task 1 (Section 14)
  - Failure modes summary → Task 2 (validation + `_spawn` post-verify) + Task 1 (Section 11 + 13)
  - Loading order comment → Task 3 (Step 4 updates `area.lua` header)
- **Placeholder scan:** complete code in every step, no TODO/TBD/FIXME. ✓
- **Type consistency:** `sms.static` referenced consistently; method names match across spec and plan; smoke test uses `:get_name()` / `:get_type()` / etc. matching the implemented methods. `_build_def` field names match the spec table. `_find_template_in_mission` returns `def_unit` / `country_int` / `group_name` consistently. ✓

## Notes for the executing agent(s)

- **Use the absolute worktree path** for all file operations: `D:\git\dcs-sms\.worktrees\sms-static\`. The shared git directory is fine; the working tree must stay isolated to the worktree.
- **The `dcs-sms.exe` binary lives in the parent repo** (`D:/git/dcs-sms/tools/dcs-sms.exe`), not the worktree's `tools/` (which only has Go source). The smoke test resolves this correctly via the relative path traversal `${SCRIPT_DIR}/../..`. From inside the worktree, `framework/test/smoke_static.sh` will end up calling the parent-repo binary — that is intentional and correct.
- **Do not amend commits.** If a commit is wrong, fix forward with another commit.
- **Do not push to remote.** The user will decide that during `/bring-it-home`.
