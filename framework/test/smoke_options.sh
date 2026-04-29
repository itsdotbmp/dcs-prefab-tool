#!/usr/bin/env bash
# End-to-end smoke test for sms.options.
# Synthetic checks (no DCS dispatch) verify builder shape + flags + ROE marker.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

SMOKE_FIXTURES="_smoke_opt_air _smoke_opt_ground"

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

echo "==> load framework"
"${DCSSMS}" exec --file load_all.lua >/dev/null

# ----------------------------------------------------------------
# Synthetic builder shape checks
# ----------------------------------------------------------------

echo "==> [build] ROE marker + value"
expect_true "roe via constant"       'local o = sms.options.roe(sms.options.ROE.WEAPON_HOLD); return o._sms_roe == true and o.value == "weapon_hold"'
expect_true "roe via raw string"     'local o = sms.options.roe("weapon_free"); return o._sms_roe == true and o.value == "weapon_free"'
expect_true "roe verb"               'return sms.options.roe(sms.options.ROE.WEAPON_HOLD)._sms_verb == "roe"'
expect_true "roe unknown rejected"   'return sms.options.roe("kill_em_all") == nil'

echo "==> [build] enum builders (air-only)"
expect_true "reaction_on_threat"     'return sms.options.reaction_on_threat(sms.options.REACTION_ON_THREAT.EVADE_FIRE)._sms_air_only == true'
expect_true "radar_using"            'return sms.options.radar_using(sms.options.RADAR_USING.NEVER).params == 0'
expect_true "flare_using bad arg"    'return sms.options.flare_using("often") == nil'

echo "==> [build] formation"
expect_true "formation preset"       'return sms.options.formation(sms.options.FORMATION.LINE_ABREAST).params == 65537'
expect_true "formation raw int"      'return sms.options.formation(393217).params == 393217'
expect_true "formation bad arg"      'return sms.options.formation("invalid_preset") == nil'
expect_true "formation_interval"     'return sms.options.formation_interval(50).params == 50'

echo "==> [build] bool builders"
expect_true "rtb_on_bingo true"      'return sms.options.rtb_on_bingo(true).params == true'
expect_true "rtb_on_bingo bad arg"   'return sms.options.rtb_on_bingo("yes") == nil'
expect_true "silence(true) air-only" 'return sms.options.silence(true)._sms_air_only == true'
expect_true "jettison_empty_tanks"   'return sms.options.jettison_empty_tanks(true).params == true'
expect_true "landing_straight_in"    'return sms.options.landing_straight_in(true)._sms_air_only == true'

echo "==> [build] waypoint_pass_report (inverted)"
expect_true "wp report=true -> false" 'return sms.options.waypoint_pass_report(true).params == false'
expect_true "wp report=false -> true" 'return sms.options.waypoint_pass_report(false).params == true'

echo "==> [build] radio reporting (default + list)"
expect_true "radio_contact default"  'local o = sms.options.radio_contact(); return o.params[1] == "Air"'
expect_true "radio_engage list"      'local o = sms.options.radio_engage({"Ground Units","Air"}); return o.params[1] == "Ground Units"'
expect_true "radio_kill string -> table" 'local o = sms.options.radio_kill("Air"); return o.params[1] == "Air"'

echo "==> [build] ground-only builders"
expect_true "alarm_state"            'return sms.options.alarm_state(sms.options.ALARM_STATE.RED).params == 2'
expect_true "alarm_state ground-only" 'return sms.options.alarm_state(sms.options.ALARM_STATE.GREEN)._sms_ground_only == true'
expect_true "disperse_on_attack"     'return sms.options.disperse_on_attack(30).params == 30'
expect_true "disperse_on_attack neg" 'return sms.options.disperse_on_attack(-5) == nil'

# ----------------------------------------------------------------
# Live-DCS apply checks
# ----------------------------------------------------------------

echo "==> [apply] spawn fixtures"
expect_true "spawn air" "
  return sms.group.create({
    name='_smoke_opt_air', position={x=40000,y=0,z=40000}, country='USA',
    category='airplane',
    units={{type='F-16C_50', alt=6000}},
  }) ~= nil"

expect_true "spawn ground" "
  return sms.group.create({
    name='_smoke_opt_ground', position={x=10000,y=0,z=10000}, country='USA',
    units={{type='M-1 Abrams'}},
  }) ~= nil"

"${DCSSMS}" exec --code 'sms.timer.after(0.5, function() end)' >/dev/null

echo "==> [apply] ROE on each category"
expect_true "air ROE weapon_free"      "return sms.group('_smoke_opt_air'):set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))"
expect_true "air ROE weapon_hold"      "return sms.group('_smoke_opt_air'):set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))"
expect_true "ground ROE weapon_hold"   "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))"
expect_true "ground ROE return_fire"   "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.RETURN_FIRE))"

echo "==> [apply] ROE air-only value rejected on ground"
expect_false "ground ROE weapon_free" "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))"
expect_false "ground ROE open_fire_weapon_free" "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.options.ROE.OPEN_FIRE_WEAPON_FREE))"

echo "==> [apply] air-only option rejected on ground"
expect_false "rtb_on_bingo on ground" "return sms.group('_smoke_opt_ground'):set_option(sms.options.rtb_on_bingo(true))"

echo "==> [apply] ground-only option rejected on air"
expect_false "alarm_state on air" "return sms.group('_smoke_opt_air'):set_option(sms.options.alarm_state(sms.options.ALARM_STATE.RED))"

echo "==> [apply] valid air options"
expect_true "rtb_on_bingo on air"  "return sms.group('_smoke_opt_air'):set_option(sms.options.rtb_on_bingo(true))"
expect_true "radar_using on air"   "return sms.group('_smoke_opt_air'):set_option(sms.options.radar_using(sms.options.RADAR_USING.FOR_CONTINUOUS_SEARCH))"

echo "==> [apply] valid ground options"
expect_true "alarm_state on ground" "return sms.group('_smoke_opt_ground'):set_option(sms.options.alarm_state(sms.options.ALARM_STATE.RED))"
expect_true "disperse_on_attack ground" "return sms.group('_smoke_opt_ground'):set_option(sms.options.disperse_on_attack(15))"

echo "==> [apply] manually-built table rejected"
expect_false "raw option rejected" "return sms.group('_smoke_opt_air'):set_option({id=AI.Option.Air.id.ROE, params=4})"

echo "ALL SMOKE PASSED"
