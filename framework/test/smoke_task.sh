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
# Section 2b: spawn target group + synthetic shape for follow/attack/attack_in_area
# These three builders need a real DCS handle to inspect IDs at build time,
# so the synthetic shape tests live after target spawn.
# ----------------------------------------------------------------
echo "==> [build] spawn target fixture _smoke_task_target_grp"
expect_true "target spawned" "
  local g = sms.group.create({
    name      = '_smoke_task_target_grp',
    position  = {x = ${SPAWN_X} - 200, y = 0, z = ${SPAWN_Z} - 200},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g ~= nil
"

echo "==> [build] follow(group_handle) returns air-only Follow task"
expect_str "follow id" "return sms.task.follow(sms.group('_smoke_task_target_grp')).id" 'Follow'
expect_str "follow verb tag" "return sms.task.follow(sms.group('_smoke_task_target_grp'))._sms_verb" 'follow'
expect_true "follow air-only" "return sms.task.follow(sms.group('_smoke_task_target_grp'))._sms_air_only == true"

echo "==> [build] follow with non-handle target -> nil"
expect_true "follow bad target" 'return sms.task.follow("nope") == nil'

echo "==> [build] follow with bad opts.offset -> nil"
expect_true "follow bad offset" "return sms.task.follow(sms.group('_smoke_task_target_grp'), {offset='not vec3'}) == nil"

echo "==> [build] attack(group_handle) returns air-only AttackGroup task"
expect_str "attack id" "return sms.task.attack(sms.group('_smoke_task_target_grp')).id" 'AttackGroup'
expect_str "attack verb tag" "return sms.task.attack(sms.group('_smoke_task_target_grp'))._sms_verb" 'attack'
expect_true "attack air-only" "return sms.task.attack(sms.group('_smoke_task_target_grp'))._sms_air_only == true"

echo "==> [build] attack with non-handle target -> nil"
expect_true "attack bad target" 'return sms.task.attack("nope") == nil'

echo "==> [build] attack_in_area(circular area) returns air-only EngageTargetsInZone"
expect_str "attack_in_area id" "
  local a = sms.area.create_circular({x=${SPAWN_X}, y=0, z=${SPAWN_Z}}, 500, '_smoke_task_zone')
  return sms.task.attack_in_area(a).id
" 'EngageTargetsInZone'
expect_true "attack_in_area air-only" "
  local a = sms.area.create_circular({x=${SPAWN_X}, y=0, z=${SPAWN_Z}}, 500, '_smoke_task_zone')
  return sms.task.attack_in_area(a)._sms_air_only == true
"

echo "==> [build] attack_in_area with non-area target -> nil"
expect_true "attack_in_area bad target" 'return sms.task.attack_in_area("nope") == nil'

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
