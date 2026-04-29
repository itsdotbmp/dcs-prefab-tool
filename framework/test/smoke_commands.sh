#!/usr/bin/env bash
# End-to-end smoke test for sms.commands.
# Synthetic checks (no DCS dispatch) verify builder shape + air-only flag.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

SMOKE_FIXTURES="_smoke_cmd_air _smoke_cmd_ground"

cleanup_smoke_fixtures() {
  [ -z "${SMOKE_FIXTURES}" ] && return 0
  local lua_list=""
  for n in ${SMOKE_FIXTURES}; do lua_list="${lua_list}'${n}',"; done
  "${DCSSMS}" exec --code "
    for _, n in ipairs({${lua_list%,}}) do
      local g = Group.getByName(n); if g then g:destroy() end
    end" >/dev/null 2>&1 || true
}
trap cleanup_smoke_fixtures EXIT

cd "${FRAMEWORK_DIR}"

expect_true() {
  local label="$1"; local code="$2"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_false() {
  local label="$1"; local code="$2"; local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":false' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_str() {
  local label="$1"; local code="$2"; local expected="$3"; local result
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
"${DCSSMS}" exec --file targets.lua >/dev/null
"${DCSSMS}" exec --file designations.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null
"${DCSSMS}" exec --file area.lua >/dev/null
"${DCSSMS}" exec --file timer.lua >/dev/null
"${DCSSMS}" exec --file group_spawn.lua >/dev/null
"${DCSSMS}" exec --file static.lua >/dev/null
"${DCSSMS}" exec --file events.lua >/dev/null
"${DCSSMS}" exec --file weapon.lua >/dev/null
"${DCSSMS}" exec --file task.lua >/dev/null
"${DCSSMS}" exec --file commands.lua >/dev/null
"${DCSSMS}" exec --file options.lua >/dev/null

# ----------------------------------------------------------------
# Synthetic builder shape checks
# ----------------------------------------------------------------

echo "==> [build] no_action shape"
expect_str "no_action verb"  'return sms.commands.no_action()._sms_verb' 'no_action'
expect_str "no_action id"    'return sms.commands.no_action().id' 'NoAction'

echo "==> [build] simple bool builders"
expect_true "set_invisible(true) verb"   'return sms.commands.set_invisible(true)._sms_verb == "set_invisible"'
expect_true "set_immortal(false) shape"  'return sms.commands.set_immortal(false).params.value == false'
expect_true "stop_route(true) shape"     'return sms.commands.stop_route(true).params.value == true'
expect_true "set_invisible bad arg nil"  'return sms.commands.set_invisible(nil) == nil'
expect_true "set_immortal bad arg nil"   'return sms.commands.set_immortal("yes") == nil'

echo "==> [build] frequency builders"
expect_true "set_frequency Hz/AM"      'local c = sms.commands.set_frequency(251000000); return c.params.frequency == 251000000 and c.params.modulation == 0'
expect_true "set_frequency FM"         'local c = sms.commands.set_frequency(40500000, sms.commands.MODULATION.FM); return c.params.modulation == 1'
expect_true "set_frequency bad hz"     'return sms.commands.set_frequency("foo") == nil'
expect_true "set_frequency_for_unit"   'local c = sms.commands.set_frequency_for_unit(251000000, sms.commands.MODULATION.AM, nil, 42); return c.params.unitId == 42'

echo "==> [build] switch_waypoint"
expect_true "switch_waypoint shape"    'local c = sms.commands.switch_waypoint(0, 1); return c.params.fromWaypointIndex == 0 and c.params.goToWaypointIndex == 1'
expect_true "switch_waypoint bad arg"  'return sms.commands.switch_waypoint(0, "x") == nil'

echo "==> [build] callsign (air-only)"
expect_true "set_callsign air-only flag" 'return sms.commands.set_callsign(sms.commands.CALLSIGN.ENFIELD, 1)._sms_air_only == true'
expect_true "set_callsign bad arg"       'return sms.commands.set_callsign("foo") == nil'

echo "==> [build] beacon"
expect_true "activate_beacon air-only" 'return sms.commands.activate_beacon({type=sms.commands.BEACON.TYPE.TACAN, system=sms.commands.BEACON.SYSTEM.TACAN_TANKER_X, frequency=1088000000})._sms_air_only == true'
expect_true "activate_beacon bad opts" 'return sms.commands.activate_beacon({type="x"}) == nil'
expect_true "deactivate_beacon shape"  'return sms.commands.deactivate_beacon()._sms_verb == "deactivate_beacon"'

echo "==> [build] ACLS / ICLS / Link4"
expect_true "activate_acls"   'return sms.commands.activate_acls()._sms_air_only == true'
expect_true "deactivate_acls" 'return sms.commands.deactivate_acls()._sms_verb == "deactivate_acls"'
expect_true "activate_icls"   'return sms.commands.activate_icls(11)._sms_air_only == true'
expect_true "activate_link4"  'return sms.commands.activate_link4(336000000)._sms_air_only == true'

echo "==> [build] eplrs"
expect_true "eplrs(true)"          'return sms.commands.eplrs(true).params.value == true'
expect_true "eplrs with group_id"  'return sms.commands.eplrs(true, 100).params.groupId == 100'
expect_true "eplrs bad value"      'return sms.commands.eplrs("x") == nil'

# ----------------------------------------------------------------
# Live-DCS apply checks
# ----------------------------------------------------------------

echo "==> [apply] spawn ground fixture"
expect_true "spawn ground" "
  return sms.group.create({
    name='_smoke_cmd_ground', position={x=0,y=0,z=0}, country='USA',
    units={{type='M-1 Abrams'}},
  }) ~= nil"

echo "==> [apply] spawn air fixture"
expect_true "spawn air" "
  return sms.group.create({
    name='_smoke_cmd_air', position={x=20000,y=0,z=20000}, country='USA',
    category='airplane',
    units={{type='F-16C_50', alt=6000}},
  }) ~= nil"

# Wait one sim tick for controllers to wire up.
"${DCSSMS}" exec --code 'sms.timer.after(0.5, function() end)' >/dev/null

echo "==> [apply] valid command on air"
expect_true "switch_waypoint on air" "
  return sms.group('_smoke_cmd_air'):set_command(sms.commands.switch_waypoint(0, 1))"

echo "==> [apply] air-only rejected on ground"
expect_false "set_callsign on ground" "
  return sms.group('_smoke_cmd_ground'):set_command(sms.commands.set_callsign(sms.commands.CALLSIGN.ENFIELD))"

echo "==> [apply] non-handle rejected"
expect_false "non-handle set_command" "return sms.group.set_command('not-a-handle', sms.commands.no_action())"

echo "==> [apply] manually-built table rejected (missing _sms_verb)"
expect_false "raw table rejected" "return sms.group('_smoke_cmd_air'):set_command({id='NoAction', params={}})"

echo "ALL SMOKE PASSED"
