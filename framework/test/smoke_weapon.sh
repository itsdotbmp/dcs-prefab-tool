#!/usr/bin/env bash
# End-to-end smoke test for sms.weapon v1.
# Synthetic checks first (load + constants + bad-arg paths). Live DCS
# round-trip lives in later sections (added incrementally as tracking
# capabilities land per task).
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

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

echo "==> WEAPON_IMPACT constant exists"
expect_str "WEAPON_IMPACT" 'return sms.events.WEAPON_IMPACT' 'weapon_impact'

echo "==> wrap with bad input returns nil"
expect_true "wrap nil"     'return sms.weapon.wrap(nil) == nil'
expect_true "wrap number"  'return sms.weapon.wrap(42) == nil'
expect_true "wrap string"  'return sms.weapon.wrap("hi") == nil'

echo "==> module getters reject non-handles"
expect_true "get_name on string"    'return sms.weapon.get_name("nope") == nil'
expect_true "get_type on nil"       'return sms.weapon.get_type(nil) == nil'
expect_true "get_state on number"   'return sms.weapon.get_state(7) == nil'
expect_true "is_bomb on string"     'return sms.weapon.is_bomb("nope") == false'

echo "==> verify [sms.weapon] log lines for bad args"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.weapon\]' -n 100)
echo "${log_window}" | grep -q "wrap: argument must be a DCS weapon object" \
  || { echo "FAIL: missing log line for bad wrap arg"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "get_name: argument must be an sms.weapon handle" \
  || { echo "FAIL: missing log line for bad get_name arg"; echo "${log_window}"; exit 1; }

echo "smoke ok"
