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

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort (set -e). Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
SMOKE_FIXTURES="birth dead smoke_destroy_target smoke_evt_sugar_grp smoke_evt_target smoke_grp_dead smoke_silent_destroy some_other_group"

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

echo "==> live DCS round-trip — DEAD event"
# Re-check heartbeat freshness — this section needs sim time to advance.
"${DCSSMS}" status | grep -q "fresh: *true" \
  || { echo "FAIL: live DCS section requires fresh heartbeat (mission unpaused). Skip or focus DCS."; exit 1; }

# Spawn a single-unit ground group, capture the resolved name (sms.spawn
# auto-suffixes on collision so concurrent agents don't break us).
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {dead_evt = nil, target_name = nil, group_name = nil}
  local g = sms.group.create({
    name = "smoke_evt_target",
    position = {x = -50000, y = 0, z = -50000},
    country = "USA",
    category = "ground",
    units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
  })
  if g then
    _G._sms_events_smoke.group_name = g:get_name()
    _G._sms_events_smoke.target_name = g:get_units()[1]:get_name()
  end
' >/dev/null
expect_true "spawned target unit captured" \
  'return type(_G._sms_events_smoke.target_name) == "string" and _G._sms_events_smoke.target_name ~= ""'

# Subscribe to DEAD, but only record the event if it matches OUR target
# (defensive — other agents may also be killing units in this DCS instance).
"${DCSSMS}" exec --code '
  sms.events.connect(sms.events.DEAD, function(evt)
    if evt.initiator and evt.initiator.name == _G._sms_events_smoke.target_name then
      _G._sms_events_smoke.dead_evt = evt
    end
  end)
' >/dev/null

# Kill the unit with an explosion (fires S_EVENT_DEAD). Unit:destroy() removes
# the unit silently without triggering death events; an explosion triggers the
# full hit → unit_lost → dead sequence.
"${DCSSMS}" exec --code '
  local u = Unit.getByName(_G._sms_events_smoke.target_name)
  if u then
    local pos = u:getPoint()
    trigger.action.explosion(pos, 5000)
  end
' >/dev/null

# Wait for sim time to deliver the event.
sleep 2

expect_true "DEAD event received" \
  'return _G._sms_events_smoke.dead_evt ~= nil'
expect_str "DEAD event has correct name" \
  'return _G._sms_events_smoke.dead_evt.name' 'dead'
expect_true "DEAD event initiator is an sms.unit handle" \
  'return type(_G._sms_events_smoke.dead_evt.initiator) == "table" and type(_G._sms_events_smoke.dead_evt.initiator.get_name) == "function"'
expect_true "DEAD event initiator name matches our target" \
  'return _G._sms_events_smoke.dead_evt.initiator.name == _G._sms_events_smoke.target_name'
expect_true "DEAD event initiator is no longer alive" \
  'return _G._sms_events_smoke.dead_evt.initiator:is_alive() == false'
expect_true "DEAD event time is a positive number" \
  'return type(_G._sms_events_smoke.dead_evt.time) == "number" and _G._sms_events_smoke.dead_evt.time > 0'

# Cleanup — best-effort. Group is already dead from the explosion; this
# attempts to remove the wreckage. DCS may leave wreckage regardless.
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_events_smoke.group_name)
  if g then pcall(g.destroy, g) end
' >/dev/null

echo "==> entity sugar — non-entity event rejected"
# Spawn a throwaway group just to get a real handle. Position is far from
# origin AND from the Task 4 round-trip spawn to avoid any collision with
# the concurrent sms.static agent.
"${DCSSMS}" exec --code '
  _G._sms_events_smoke = {sugar_group_name = nil}
  _G._sms_events_smoke.g = sms.group.create({
    name = "smoke_evt_sugar_grp",
    position = {x = -49000, y = 0, z = -49000},
    country = "USA",
    category = "ground",
    units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
  })
  if _G._sms_events_smoke.g then
    _G._sms_events_smoke.sugar_group_name = _G._sms_events_smoke.g:get_name()
  end
' >/dev/null
expect_true "g:connect on MISSION_START rejected (returns nil)" \
  'return _G._sms_events_smoke.g:connect(sms.events.MISSION_START, function() end) == nil'
expect_true "u:connect on MISSION_START rejected (returns nil)" \
  'local u = _G._sms_events_smoke.g:get_units()[1]; return u:connect(sms.events.MISSION_START, function() end) == nil'

echo "==> entity sugar — initiator filter (synthetic via emit)"
"${DCSSMS}" exec --code '
  _G._sms_events_smoke.matched = 0
  local target = _G._sms_events_smoke.g:get_units()[1]
  target:connect(sms.events.DEAD, function(evt) _G._sms_events_smoke.matched = _G._sms_events_smoke.matched + 1 end)
  -- Synthetic emit with matching initiator.
  sms.events.emit("dead", {
    name = "dead",
    initiator = sms._make_handle(sms.unit, target.name),
  })
  -- Synthetic emit with non-matching initiator.
  sms.events.emit("dead", {
    name = "dead",
    initiator = sms._make_handle(sms.unit, "definitely_not_our_unit_xyz"),
  })
' >/dev/null
expect_eq "u:connect fires only for matching initiator" \
  'return _G._sms_events_smoke.matched' 1

echo "==> entity sugar — group filter for non-DEAD event (per-unit, synthetic via emit)"
# Non-DEAD entity events on g:connect fire per-unit. The filter checks
# evt.initiator_group_name == target_name. We use BIRTH because it's
# entity-scoped and easy to fake synthetically without DCS side effects.
"${DCSSMS}" exec --code '
  _G._sms_events_smoke.gmatched = 0
  _G._sms_events_smoke.g:connect(sms.events.BIRTH, function(evt) _G._sms_events_smoke.gmatched = _G._sms_events_smoke.gmatched + 1 end)
  local our_unit = _G._sms_events_smoke.g:get_units()[1]
  -- Synthetic dispatch with initiator_group_name matching our group.
  sms.events.emit("birth", {
    name = "birth",
    initiator = sms._make_handle(sms.unit, our_unit.name),
    initiator_group_name = _G._sms_events_smoke.sugar_group_name,
  })
  -- Synthetic dispatch with initiator_group_name from a different group.
  sms.events.emit("birth", {
    name = "birth",
    initiator = sms._make_handle(sms.unit, "any_other_unit"),
    initiator_group_name = "some_other_group",
  })
' >/dev/null
expect_eq "g:connect fires only for events in our group (not other groups)" \
  'return _G._sms_events_smoke.gmatched' 1

# Cleanup — best-effort. Group is alive; this should succeed cleanly.
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_events_smoke.sugar_group_name)
  if g then pcall(g.destroy, g) end
' >/dev/null

echo "==> sms.unit.destroy(u, {emit_event=true}) fires DEAD via the bus"
"${DCSSMS}" exec --code '
  _G._sms_destroy_smoke = {fired = 0, target = nil, group_name = nil}
  local g = sms.group.create({
    name = "smoke_destroy_target",
    position = {x = -48500, y = 0, z = -48500},
    country = "USA",
    category = "ground",
    units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
  })
  if g then
    _G._sms_destroy_smoke.target     = g:get_units()[1]:get_name()
    _G._sms_destroy_smoke.group_name = g:get_name()
  end
  sms.events.connect(sms.events.DEAD, function(evt)
    if evt.initiator and evt.initiator.name == _G._sms_destroy_smoke.target then
      _G._sms_destroy_smoke.fired = _G._sms_destroy_smoke.fired + 1
    end
  end)
  sms.unit.destroy(sms.unit(_G._sms_destroy_smoke.target), {emit_event = true})
' >/dev/null
expect_eq "destroy(emit_event=true) fired DEAD subscriber once" \
  'return _G._sms_destroy_smoke.fired' 1
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_destroy_smoke.group_name)
  if g then pcall(g.destroy, g) end
' >/dev/null

echo "==> sms.unit.destroy(u) without opts does NOT fire DEAD"
"${DCSSMS}" exec --code '
  _G._sms_destroy_silent = {fired = 0, target = nil, group_name = nil}
  local g = sms.group.create({
    name = "smoke_silent_destroy",
    position = {x = -47500, y = 0, z = -47500},
    country = "USA",
    category = "ground",
    units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
  })
  if g then
    _G._sms_destroy_silent.target     = g:get_units()[1]:get_name()
    _G._sms_destroy_silent.group_name = g:get_name()
  end
  sms.events.connect(sms.events.DEAD, function(evt)
    if evt.initiator and evt.initiator.name == _G._sms_destroy_silent.target then
      _G._sms_destroy_silent.fired = _G._sms_destroy_silent.fired + 1
    end
  end)
  sms.unit.destroy(sms.unit(_G._sms_destroy_silent.target))  -- no opts
' >/dev/null
expect_eq "destroy() without opts did NOT fire DEAD" \
  'return _G._sms_destroy_silent.fired' 0
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_destroy_silent.group_name)
  if g then pcall(g.destroy, g) end
' >/dev/null

echo "==> g:connect(DEAD) fires only when group is fully dead"
"${DCSSMS}" exec --code '
  _G._sms_grp_dead = {fired = 0, group_name = nil, units = {}}
  local g = sms.group.create({
    name = "smoke_grp_dead",
    position = {x = -46500, y = 0, z = -46500},
    country = "USA",
    category = "ground",
    units = {
      { type = "M-1 Abrams", offset = {x = 0, y = 0, z =  0} },
      { type = "M-1 Abrams", offset = {x = 0, y = 0, z = 20} },
    },
  })
  if g then
    _G._sms_grp_dead.group_name = g:get_name()
    for i, u in ipairs(g:get_units()) do
      _G._sms_grp_dead.units[i] = u:get_name()
    end
    g:connect(sms.events.DEAD, function(evt)
      _G._sms_grp_dead.fired = _G._sms_grp_dead.fired + 1
    end)
  end
  -- Kill the first unit. Group still has one alive — callback should NOT fire.
  sms.unit.destroy(sms.unit(_G._sms_grp_dead.units[1]), {emit_event = true})
' >/dev/null
# The fully-dead check is deferred one sim frame, so wait briefly for the
# timer to fire before asserting state.
sleep 1
expect_eq "g:connect(DEAD) does NOT fire while group has live units" \
  'return _G._sms_grp_dead.fired' 0
"${DCSSMS}" exec --code '
  -- Kill the second (last) unit. Group is now fully dead — callback should fire once.
  sms.unit.destroy(sms.unit(_G._sms_grp_dead.units[2]), {emit_event = true})
' >/dev/null
sleep 1
expect_eq "g:connect(DEAD) fires exactly once when last unit dies" \
  'return _G._sms_grp_dead.fired' 1
# Cleanup — group is fully dead; best-effort.
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_grp_dead.group_name)
  if g then pcall(g.destroy, g) end
' >/dev/null

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
