#!/usr/bin/env bash
# End-to-end smoke test for sms.rule v1.
# Drives the bridge with host-side sleeps to let sim time advance and verify
# the rule state machine. Requires DCS running, mission loaded, unpaused.

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
"${DCSSMS}" exec --file sms.lua   >/dev/null
"${DCSSMS}" exec --file log.lua   >/dev/null
"${DCSSMS}" exec --file timer.lua >/dev/null
"${DCSSMS}" exec --file rule.lua  >/dev/null

echo "==> bad-arg validation"
expect_true "rule: empty name returns nil" \
  'return sms.rule("", {type=sms.rule.TYPE.ONCE, condition=function()end, action=function()end}) == nil'
expect_true "rule: non-table opts returns nil" \
  'return sms.rule("x", "not a table") == nil'
expect_true "rule: unknown type returns nil" \
  'return sms.rule("x", {type="banana", condition=function()end, action=function()end}) == nil'
expect_true "rule: missing condition returns nil" \
  'return sms.rule("x", {type=sms.rule.TYPE.ONCE, action=function()end}) == nil'
expect_true "rule: missing action returns nil" \
  'return sms.rule("x", {type=sms.rule.TYPE.ONCE, condition=function()end}) == nil'
expect_true "rule: zero interval returns nil" \
  'return sms.rule("x", {type=sms.rule.TYPE.ONCE, interval=0, condition=function()end, action=function()end}) == nil'
expect_true "rule: negative cooldown returns nil" \
  'return sms.rule("x", {type=sms.rule.TYPE.CONTINUOUS, cooldown=-1, condition=function()end, action=function()end}) == nil'
expect_true "rule: cooldown on ONCE returns nil" \
  'return sms.rule("x", {type=sms.rule.TYPE.ONCE, cooldown=5, condition=function()end, action=function()end}) == nil'
expect_true "rule: negative sustain returns nil" \
  'return sms.rule("x", {type=sms.rule.TYPE.ONCE, sustain=-1, condition=function()end, action=function()end}) == nil'
expect_true "rule: non-function dev_condition returns nil" \
  'return sms.rule("x", {type=sms.rule.TYPE.ONCE, dev_condition=42, condition=function()end, action=function()end}) == nil'

echo "==> ONCE: fires once and unregisters"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0, allow = false}
  _G._smoke.h = sms.rule("smoke_once", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    condition = function() return _G._smoke.allow end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
expect_true "ONCE: registered immediately" 'return sms.rule.get("smoke_once") ~= nil'
sleep 2
expect_eq "ONCE: did not fire while condition false" 'return _G._smoke.fires' 0
"${DCSSMS}" exec --code '_G._smoke.allow = true' >/dev/null
sleep 3
expect_eq "ONCE: fired exactly once" 'return _G._smoke.fires' 1
expect_true "ONCE: unregistered after fire" 'return sms.rule._rules["smoke_once"] == nil'

echo "==> CONTINUOUS: fires every tick condition is true"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_continuous", {
    type      = sms.rule.TYPE.CONTINUOUS,
    interval  = 1,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
sleep 4
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_continuous")' >/dev/null
expect_true "CONTINUOUS: fired at least 3 times" 'return _G._smoke.fires >= 3'

echo "==> TOGGLE: edge-triggered, refires after reset"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0, on = false}
  _G._smoke.h = sms.rule("smoke_toggle", {
    type      = sms.rule.TYPE.TOGGLE,
    interval  = 1,
    condition = function() return _G._smoke.on end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
"${DCSSMS}" exec --code '_G._smoke.on = true' >/dev/null
sleep 3
expect_eq "TOGGLE: fired exactly once on rising edge" 'return _G._smoke.fires' 1
expect_true "TOGGLE: handle reports active" 'return _G._smoke.h:is_active()'
"${DCSSMS}" exec --code '_G._smoke.on = false' >/dev/null
sleep 2
expect_true "TOGGLE: handle no longer active after falling edge" 'return _G._smoke.h:is_active() == false'
"${DCSSMS}" exec --code '_G._smoke.on = true' >/dev/null
sleep 2
expect_eq "TOGGLE: refired on second rising edge" 'return _G._smoke.fires' 2
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_toggle")' >/dev/null
expect_true "TOGGLE: is_active() returns false after :stop() on an active TOGGLE" \
  'return _G._smoke.h:is_active() == false'

echo "==> COOLDOWN gates fires"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_cooldown", {
    type      = sms.rule.TYPE.CONTINUOUS,
    interval  = 1,
    cooldown  = 3,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
sleep 4
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_cooldown")' >/dev/null
expect_true "COOLDOWN: fired between 1 and 2 times in 4s with cooldown=3" \
  'return _G._smoke.fires >= 1 and _G._smoke.fires <= 2'

echo "==> SUSTAIN delays first fire"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_sustain", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    sustain   = 3,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
sleep 2
expect_eq "SUSTAIN: did not fire before sustain elapsed" 'return _G._smoke.fires' 0
sleep 3
expect_eq "SUSTAIN: fired after sustain elapsed" 'return _G._smoke.fires' 1

echo "==> SUSTAIN resets when condition flickers false"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0, allow = true}
  _G._smoke.h = sms.rule("smoke_sustain_flicker", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    sustain   = 3,
    condition = function() return _G._smoke.allow end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
sleep 2
"${DCSSMS}" exec --code '_G._smoke.allow = false' >/dev/null
sleep 1
"${DCSSMS}" exec --code '_G._smoke.allow = true' >/dev/null
sleep 2
expect_eq "SUSTAIN flicker: did not fire (sustain restarted)" 'return _G._smoke.fires' 0
sleep 2
expect_eq "SUSTAIN flicker: fired after the sustained window" 'return _G._smoke.fires' 1

echo "==> dev_condition bypasses sustain and cooldown"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0, dev = false}
  _G._smoke.h = sms.rule("smoke_dev", {
    type          = sms.rule.TYPE.CONTINUOUS,
    interval      = 1,
    cooldown      = 999,
    sustain       = 999,
    condition     = function() return false end,
    dev_condition = function() return _G._smoke.dev end,
    action        = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
sleep 2
expect_eq "dev_condition off: no fires" 'return _G._smoke.fires' 0
"${DCSSMS}" exec --code '_G._smoke.dev = true' >/dev/null
sleep 3
"${DCSSMS}" exec --code '_G._smoke.dev = false' >/dev/null
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_dev")' >/dev/null
expect_true "dev_condition on: fired multiple times despite cooldown=999, sustain=999" \
  'return _G._smoke.fires >= 2'
expect_true "dev_condition: pure dev fires do NOT update last_fire_time" \
  'return _G._smoke.h.last_fire_time == nil'

echo "==> manual fire bypasses condition"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_manual", {
    type      = sms.rule.TYPE.CONTINUOUS,
    interval  = 5,
    condition = function() return false end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
expect_true "manual fire returns true on success" 'return _G._smoke.h:fire()'
expect_eq "manual fire ran the action" 'return _G._smoke.fires' 1
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_manual")' >/dev/null

echo "==> name collision replaces old rule"
"${DCSSMS}" exec --code '
  _G._smoke = {marker_a = 0, marker_b = 0}
  _G._smoke.a = sms.rule("smoke_collide", {
    type=sms.rule.TYPE.CONTINUOUS, interval=1,
    condition=function() return true end,
    action=function() _G._smoke.marker_a = _G._smoke.marker_a + 1 end,
  })
  _G._smoke.b = sms.rule("smoke_collide", {
    type=sms.rule.TYPE.CONTINUOUS, interval=1,
    condition=function() return true end,
    action=function() _G._smoke.marker_b = _G._smoke.marker_b + 1 end,
  })
' >/dev/null
sleep 2
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_collide")' >/dev/null
expect_eq "collide: replaced rule did not fire after being replaced" 'return _G._smoke.marker_a' 0
expect_true "collide: replacing rule fired" 'return _G._smoke.marker_b >= 1'

echo "==> registry: get / all / remove"
"${DCSSMS}" exec --code '
  sms.rule("reg_a", {type=sms.rule.TYPE.CONTINUOUS, interval=1, condition=function()end, action=function()end})
  sms.rule("reg_b", {type=sms.rule.TYPE.CONTINUOUS, interval=1, condition=function()end, action=function()end})
' >/dev/null
expect_true "registry: get returns the handle" 'return sms.rule.get("reg_a") ~= nil'
expect_true "registry: get on missing returns nil" 'return sms.rule.get("not_there") == nil'
expect_true "registry: all returns at least 2 handles" 'return #sms.rule.all() >= 2'
expect_true "registry: remove returns true on success" 'return sms.rule.remove("reg_a")'
expect_true "registry: remove returns false on missing" 'return sms.rule.remove("reg_a") == false'
"${DCSSMS}" exec --code 'sms.rule.remove("reg_b")' >/dev/null

echo "==> test_all does not change rule state"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0}
  _G._smoke.h = sms.rule("smoke_test_all", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 5,
    condition = function() return true end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
  sms.rule.test_all()
' >/dev/null
expect_eq "test_all: action ran (so fires == 1) but..." 'return _G._smoke.fires' 1
expect_true "test_all: ONCE rule was NOT unregistered" 'return sms.rule._rules["smoke_test_all"] ~= nil'
expect_true "test_all: last_fire_time was NOT set" \
  'return sms.rule._rules["smoke_test_all"].last_fire_time == nil'
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_test_all")' >/dev/null

echo "==> action throws are caught and don't unregister ONCE"
"${DCSSMS}" exec --code '
  _G._smoke = {attempts = 0}
  _G._smoke.h = sms.rule("smoke_throw", {
    type      = sms.rule.TYPE.ONCE,
    interval  = 1,
    condition = function() return true end,
    action    = function()
      _G._smoke.attempts = _G._smoke.attempts + 1
      error("boom from smoke_throw")
    end,
  })
' >/dev/null
sleep 3
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_throw")' >/dev/null
expect_true "throw: action retried (attempts >= 2)" 'return _G._smoke.attempts >= 2'

echo "==> :stop is idempotent"
"${DCSSMS}" exec --code '
  _G._smoke = {h = sms.rule("smoke_stop", {
    type=sms.rule.TYPE.CONTINUOUS, interval=1,
    condition=function() return false end,
    action=function() end,
  })}
' >/dev/null
expect_true "stop: returns true when active" 'return _G._smoke.h:stop()'
expect_true "stop: returns false when already stopped" 'return _G._smoke.h:stop() == false'

echo "==> :reset clears toggle active and cooldown bookkeeping"
"${DCSSMS}" exec --code '
  _G._smoke = {fires = 0, on = false}
  _G._smoke.h = sms.rule("smoke_reset", {
    type      = sms.rule.TYPE.TOGGLE,
    interval  = 1,
    cooldown  = 30,
    condition = function() return _G._smoke.on end,
    action    = function() _G._smoke.fires = _G._smoke.fires + 1 end,
  })
' >/dev/null
"${DCSSMS}" exec --code '_G._smoke.on = true' >/dev/null
sleep 2
expect_eq "reset: fired once" 'return _G._smoke.fires' 1
"${DCSSMS}" exec --code '_G._smoke.h:reset()' >/dev/null
sleep 2
expect_eq "reset: refired on next tick after reset (cooldown cleared)" 'return _G._smoke.fires' 2
"${DCSSMS}" exec --code 'sms.rule.remove("smoke_reset")' >/dev/null

echo "==> verify [sms.rule] log lines for bad args and user errors"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.rule\]' -n 200)
echo "${log_window}" | grep -q "type must be one of sms.rule.TYPE" \
  || { echo "FAIL: missing log line for unknown type"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "cooldown is meaningless on ONCE" \
  || { echo "FAIL: missing log line for cooldown on ONCE"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "boom from smoke_throw" \
  || { echo "FAIL: missing log line for action throw"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "manual fire" \
  || { echo "FAIL: missing log line for manual fire"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "replacing existing rule 'smoke_collide'" \
  || { echo "FAIL: missing log line for name collision"; echo "${log_window}"; exit 1; }

echo "smoke ok"
