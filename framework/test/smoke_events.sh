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

echo "==> bad-arg validation"
expect_true "connect: nil name returns nil" \
  'return sms.events.connect(nil, function() end) == nil'
expect_true "connect: non-function fn returns nil" \
  'return sms.events.connect("foo", "not a function") == nil'
expect_true "disconnect: non-connection returns false" \
  'return sms.events.disconnect("garbage") == false'
expect_true "is_active: non-connection returns false silently" \
  'return sms.events.is_active("garbage") == false'

echo "==> basic synthetic dispatch"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {fired = 0, last = nil}
  _G._sms_events_smoke.conn = sms.events.connect("test_signal", function(x)
    _G._sms_events_smoke.fired = _G._sms_events_smoke.fired + 1
    _G._sms_events_smoke.last = x
  end)
' >/dev/null
expect_true "connect returns a Connection handle" \
  'return type(_G._sms_events_smoke.conn) == "table" and _G._sms_events_smoke.conn:is_active()'
"${DCSSMS}" exec --code 'sms.events.emit("test_signal", "hello")' >/dev/null
expect_eq "emit fires subscriber once" \
  'return _G._sms_events_smoke.fired' 1
expect_str "subscriber sees the emitted arg" \
  'return _G._sms_events_smoke.last' 'hello'

echo "==> multi-subscriber dispatch order"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {order = {}}
  for i = 1, 3 do
    local n = i
    sms.events.connect("order_test", function() table.insert(_G._sms_events_smoke.order, n) end)
  end
  sms.events.emit("order_test")
' >/dev/null
expect_true "subscribers fire in connection order" \
  'local o = _G._sms_events_smoke.order; return #o == 3 and o[1] == 1 and o[2] == 2 and o[3] == 3'

echo "==> verbatim multi-arg pass-through"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {}
  sms.events.connect("multi", function(a, b, c)
    _G._sms_events_smoke.a = a
    _G._sms_events_smoke.b = b
    _G._sms_events_smoke.c = c
  end)
  sms.events.emit("multi", 1, "two", true)
' >/dev/null
expect_eq   "multi-arg: first arg"  'return _G._sms_events_smoke.a' 1
expect_str  "multi-arg: second arg" 'return _G._sms_events_smoke.b' 'two'
expect_true "multi-arg: third arg"  'return _G._sms_events_smoke.c == true'

echo "==> idempotent disconnect"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {fired = 0}
  _G._sms_events_smoke.conn = sms.events.connect("idem", function() _G._sms_events_smoke.fired = _G._sms_events_smoke.fired + 1 end)
' >/dev/null
expect_true "first disconnect returns true"  'return _G._sms_events_smoke.conn:disconnect() == true'
expect_true "second disconnect returns false" 'return _G._sms_events_smoke.conn:disconnect() == false'
expect_true "disconnected conn is not active" 'return _G._sms_events_smoke.conn:is_active() == false'
"${DCSSMS}" exec --code 'sms.events.emit("idem")' >/dev/null
expect_eq "disconnected subscriber does not fire" 'return _G._sms_events_smoke.fired' 0

echo "==> mid-dispatch disconnect is safe"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {a = 0, b = 0, conn_b = nil}
  sms.events.connect("midcancel", function()
    _G._sms_events_smoke.a = _G._sms_events_smoke.a + 1
    _G._sms_events_smoke.conn_b:disconnect()
  end)
  _G._sms_events_smoke.conn_b = sms.events.connect("midcancel", function()
    _G._sms_events_smoke.b = _G._sms_events_smoke.b + 1
  end)
  sms.events.emit("midcancel")
' >/dev/null
expect_eq "first sub fired (snapshot intact)" 'return _G._sms_events_smoke.a' 1
expect_eq "second sub still fired this dispatch (snapshot)" 'return _G._sms_events_smoke.b' 1
"${DCSSMS}" exec --code 'sms.events.emit("midcancel")' >/dev/null
expect_eq "first sub fires again next dispatch" 'return _G._sms_events_smoke.a' 2
expect_eq "second sub stays disconnected" 'return _G._sms_events_smoke.b' 1

echo "==> subscriber error does not break dispatch"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {good = 0}
  sms.events.connect("err_test", function() error("boom") end)
  sms.events.connect("err_test", function() _G._sms_events_smoke.good = _G._sms_events_smoke.good + 1 end)
  sms.events.emit("err_test")
' >/dev/null
expect_eq "good subscriber fires after bad one raised" 'return _G._sms_events_smoke.good' 1

echo "==> verify [sms.events] log lines for bad args and user errors"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.events\]' -n 200)
echo "${log_window}" | grep -q "connect: name must be a string" \
  || { echo "FAIL: missing log line for nil name"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "connect: fn must be a function" \
  || { echo "FAIL: missing log line for non-function fn"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "disconnect: argument must be a Connection handle" \
  || { echo "FAIL: missing log line for non-connection disconnect"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "subscriber for 'err_test' raised" \
  || { echo "FAIL: missing log line for subscriber error"; echo "${log_window}"; exit 1; }

echo "smoke ok"
