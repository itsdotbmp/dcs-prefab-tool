#!/usr/bin/env bash
# End-to-end smoke test for sms.timer v1.
# Drives the bridge with host-side sleeps to let sim time advance and
# verify timer callbacks fire as expected.
# Requires DCS running, mission loaded, and unpaused (sim must tick).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

# Helpers: assert that a bridge exec returned a true / specific number.
# expect_true LABEL CODE                  -- expects "return_value":true
# expect_eq   LABEL CODE EXPECTED_NUMBER  -- expects "return_value":N, (with comma)
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

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file timer.lua >/dev/null

echo "==> bad-arg validation"
expect_true "after: negative seconds returns nil" 'return sms.timer.after(-1, function() end) == nil'
expect_true "after: non-function fn returns nil" 'return sms.timer.after(1, "not a function") == nil'
expect_true "every: zero seconds returns nil" 'return sms.timer.every(0, function() end) == nil'
expect_true "every: negative max returns nil" 'return sms.timer.every(1, function() end, -3) == nil'

echo "==> after fires once after delay"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.after(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)
' >/dev/null
expect_true "after: handle is active immediately" 'return _G._smoke.h:is_active()'
sleep 2
expect_eq "after: fired count" 'return _G._smoke.fired' 1
expect_true "after: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> every fires repeatedly until stopped"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function() _G._smoke.fired = _G._smoke.fired + 1 end)
' >/dev/null
sleep 4
expect_true "every: stop returns true when active" 'return _G._smoke.h:stop()'
expect_true "every: fired at least 3 times" 'return _G._smoke.fired >= 3'
expect_true "every: stop returns false on second call" 'return _G._smoke.h:stop() == false'
expect_true "every: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> every with max stops after N fires"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function() _G._smoke.fired = _G._smoke.fired + 1 end, 3)
' >/dev/null
sleep 5
expect_eq "every with max: fired exactly 3 times" 'return _G._smoke.fired' 3
expect_true "every with max: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> every self-cancels via fn returning false"
"${DCSSMS}" exec --code '
  _G._smoke = {fired = 0}
  _G._smoke.h = sms.timer.every(1, function()
    _G._smoke.fired = _G._smoke.fired + 1
    if _G._smoke.fired >= 2 then return false end
  end)
' >/dev/null
sleep 3
expect_eq "every self-cancel: fired exactly 2 times" 'return _G._smoke.fired' 2
expect_true "every self-cancel: handle is no longer active" 'return _G._smoke.h:is_active() == false'

echo "==> get_remaining returns sensible values"
"${DCSSMS}" exec --code '
  _G._smoke = {h = sms.timer.after(5, function() end)}
' >/dev/null
expect_true "get_remaining initial (>4 and <=5)" '
  local r = _G._smoke.h:get_remaining()
  return type(r) == "number" and r > 4 and r <= 5.05
'
sleep 2
expect_true "get_remaining after sleep (>2 and <4)" '
  local r = _G._smoke.h:get_remaining()
  return type(r) == "number" and r > 2 and r < 4
'
"${DCSSMS}" exec --code '_G._smoke.h:stop()' >/dev/null

echo "==> user errors in fn are caught"
"${DCSSMS}" exec --code '
  _G._smoke = {h = sms.timer.every(1, function() error("boom from smoke test") end, 2)}
' >/dev/null
sleep 3
expect_true "errors caught: handle ran to max iterations" 'return _G._smoke.h:is_active() == false'

echo "==> verify [sms.timer] log lines for bad args and user errors"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.timer\]' -n 200)
echo "${log_window}" | grep -q "after: seconds must be a non-negative" \
  || { echo "FAIL: missing log line for negative seconds"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "boom from smoke test" \
  || { echo "FAIL: missing log line for user error"; echo "${log_window}"; exit 1; }

echo "smoke ok"
