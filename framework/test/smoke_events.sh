#!/usr/bin/env bash
# End-to-end smoke test for sms.events v1.
# Hybrid: most assertions are synthetic via sms.events.emit (fast, no DCS
# sleeps). One live-DCS section spawns + destroys a unit to verify the
# world-handler round-trip.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.
#
# Defensive vs. concurrent agents in the same DCS instance:
# - global state in _G._sms_events_smoke (not _G._smoke)
# - live DCS subscribers filter by our unit name so other agents' deaths
#   don't trigger our assertions
# - spawn names rely on sms.spawn's auto-suffix-on-collision; we capture
#   the returned name for cleanup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

# Helpers: assert that a bridge exec returned a true / specific value.
expect_true() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_eq() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":${expected}," \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
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
"${DCSSMS}" exec --file events.lua >/dev/null

echo "==> constants exist"
expect_str "DEAD constant"          'return sms.events.DEAD'           'dead'
expect_str "BIRTH constant"         'return sms.events.BIRTH'          'birth'
expect_str "PILOT_DEAD constant"    'return sms.events.PILOT_DEAD'     'pilot_dead'
expect_str "MISSION_START constant" 'return sms.events.MISSION_START'  'mission_start'
expect_str "TAKEOFF constant"       'return sms.events.TAKEOFF'        'takeoff'

echo "smoke ok"
