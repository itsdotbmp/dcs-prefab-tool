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

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run abort.
# Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
$fixtures = @(
    'birth',
    'dead',
    'smoke_destroy_target',
    'smoke_evt_sugar_grp',
    'smoke_evt_target',
    'smoke_grp_dead',
    'smoke_silent_destroy',
    'some_other_group'
)

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua'          | Out-Null
    Invoke-Smoke -File 'log.lua'          | Out-Null
    Invoke-Smoke -File 'utils.lua'        | Out-Null
    Invoke-Smoke -File 'constants.lua'    | Out-Null
    Invoke-Smoke -File 'group.lua'        | Out-Null
    Invoke-Smoke -File 'unit.lua'         | Out-Null
    Invoke-Smoke -File 'area.lua'         | Out-Null
    Invoke-Smoke -File 'timer.lua'        | Out-Null
    Invoke-Smoke -File 'group_spawn.lua'  | Out-Null
    Invoke-Smoke -File 'events.lua'       | Out-Null

    Write-Host "==> constants exist"
    Expect-EqString -Label 'DEAD constant'          -Code 'return sms.events.DEAD'          -Expected 'dead'
    Expect-EqString -Label 'BIRTH constant'         -Code 'return sms.events.BIRTH'         -Expected 'birth'
    Expect-EqString -Label 'PILOT_DEAD constant'    -Code 'return sms.events.PILOT_DEAD'    -Expected 'pilot_dead'
    Expect-EqString -Label 'MISSION_START constant' -Code 'return sms.events.MISSION_START' -Expected 'mission_start'
    Expect-EqString -Label 'TAKEOFF constant'       -Code 'return sms.events.TAKEOFF'       -Expected 'takeoff'

    Write-Host "==> bad-arg validation"
    Expect-True -Label 'connect: nil name returns nil' `
        -Code 'return sms.events.connect(nil, function() end) == nil'
    Expect-True -Label 'connect: non-function fn returns nil' `
        -Code 'return sms.events.connect("foo", "not a function") == nil'
    Expect-True -Label 'disconnect: non-connection returns false' `
        -Code 'return sms.events.disconnect("garbage") == false'
    Expect-True -Label 'is_active: non-connection returns false silently' `
        -Code 'return sms.events.is_active("garbage") == false'

    Write-Host "==> basic synthetic dispatch"
    Invoke-Smoke -Code @'
_G._sms_events_smoke = {fired = 0, last = nil}
_G._sms_events_smoke.conn = sms.events.connect("test_signal", function(x)
  _G._sms_events_smoke.fired = _G._sms_events_smoke.fired + 1
  _G._sms_events_smoke.last = x
end)
'@ | Out-Null
    Expect-True -Label 'connect returns a Connection handle' `
        -Code 'return type(_G._sms_events_smoke.conn) == "table" and _G._sms_events_smoke.conn:is_active()'
    Invoke-Smoke -Code 'sms.events.emit("test_signal", "hello")' | Out-Null
    Expect-EqNumber -Label 'emit fires subscriber once' `
        -Code 'return _G._sms_events_smoke.fired' -Expected 1
    Expect-EqString -Label 'subscriber sees the emitted arg' `
        -Code 'return _G._sms_events_smoke.last' -Expected 'hello'

    Write-Host "==> multi-subscriber dispatch order"
    Invoke-Smoke -Code @'
_G._sms_events_smoke = {order = {}}
for i = 1, 3 do
  local n = i
  sms.events.connect("order_test", function() table.insert(_G._sms_events_smoke.order, n) end)
end
sms.events.emit("order_test")
'@ | Out-Null
    Expect-True -Label 'subscribers fire in connection order' `
        -Code 'local o = _G._sms_events_smoke.order; return #o == 3 and o[1] == 1 and o[2] == 2 and o[3] == 3'

    Write-Host "==> verbatim multi-arg pass-through"
    Invoke-Smoke -Code @'
_G._sms_events_smoke = {}
sms.events.connect("multi", function(a, b, c)
  _G._sms_events_smoke.a = a
  _G._sms_events_smoke.b = b
  _G._sms_events_smoke.c = c
end)
sms.events.emit("multi", 1, "two", true)
'@ | Out-Null
    Expect-EqNumber -Label 'multi-arg: first arg'  -Code 'return _G._sms_events_smoke.a' -Expected 1
    Expect-EqString -Label 'multi-arg: second arg' -Code 'return _G._sms_events_smoke.b' -Expected 'two'
    Expect-True     -Label 'multi-arg: third arg'  -Code 'return _G._sms_events_smoke.c == true'

    Write-Host "==> idempotent disconnect"
    Invoke-Smoke -Code @'
_G._sms_events_smoke = {fired = 0}
_G._sms_events_smoke.conn = sms.events.connect("idem", function() _G._sms_events_smoke.fired = _G._sms_events_smoke.fired + 1 end)
'@ | Out-Null
    Expect-True -Label 'first disconnect returns true'  -Code 'return _G._sms_events_smoke.conn:disconnect() == true'
    Expect-True -Label 'second disconnect returns false' -Code 'return _G._sms_events_smoke.conn:disconnect() == false'
    Expect-True -Label 'disconnected conn is not active' -Code 'return _G._sms_events_smoke.conn:is_active() == false'
    Invoke-Smoke -Code 'sms.events.emit("idem")' | Out-Null
    Expect-EqNumber -Label 'disconnected subscriber does not fire' `
        -Code 'return _G._sms_events_smoke.fired' -Expected 0

    Write-Host "==> mid-dispatch disconnect is safe"
    Invoke-Smoke -Code @'
_G._sms_events_smoke = {a = 0, b = 0, conn_b = nil}
sms.events.connect("midcancel", function()
  _G._sms_events_smoke.a = _G._sms_events_smoke.a + 1
  _G._sms_events_smoke.conn_b:disconnect()
end)
_G._sms_events_smoke.conn_b = sms.events.connect("midcancel", function()
  _G._sms_events_smoke.b = _G._sms_events_smoke.b + 1
end)
sms.events.emit("midcancel")
'@ | Out-Null
    Expect-EqNumber -Label 'first sub fired (snapshot intact)' `
        -Code 'return _G._sms_events_smoke.a' -Expected 1
    Expect-EqNumber -Label 'second sub still fired this dispatch (snapshot)' `
        -Code 'return _G._sms_events_smoke.b' -Expected 1
    Invoke-Smoke -Code 'sms.events.emit("midcancel")' | Out-Null
    Expect-EqNumber -Label 'first sub fires again next dispatch' `
        -Code 'return _G._sms_events_smoke.a' -Expected 2
    Expect-EqNumber -Label 'second sub stays disconnected' `
        -Code 'return _G._sms_events_smoke.b' -Expected 1

    Write-Host "==> subscriber error does not break dispatch"
    Invoke-Smoke -Code @'
_G._sms_events_smoke = {good = 0}
sms.events.connect("err_test", function() error("boom") end)
sms.events.connect("err_test", function() _G._sms_events_smoke.good = _G._sms_events_smoke.good + 1 end)
sms.events.emit("err_test")
'@ | Out-Null
    Expect-EqNumber -Label 'good subscriber fires after bad one raised' `
        -Code 'return _G._sms_events_smoke.good' -Expected 1

    Write-Host "==> live DCS round-trip — DEAD event"
    # Note: bash version re-checks heartbeat freshness here. The PS helper
    # surfaces status text via Invoke-Status; we proceed and trust caller has
    # an unpaused mission. Failures will surface as missing DEAD events below.

    # Spawn a single-unit ground group, capture the resolved name (sms.spawn
    # auto-suffixes on collision so concurrent agents don't break us).
    Invoke-Smoke -Code @"
_G._sms_events_smoke = {dead_evt = nil, target_name = nil, group_name = nil}
local g = sms.group.create({
  name = "smoke_evt_target",
  position = {x = $SmokeAnchorX, y = 0, z = $SmokeAnchorZ},
  country = sms.K.countries.USA,
  category = sms.K.category.GROUND,
  units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
})
if g then
  _G._sms_events_smoke.group_name = g:get_name()
  _G._sms_events_smoke.target_name = g:get_units()[1]:get_name()
end
"@ | Out-Null
    Expect-True -Label 'spawned target unit captured' `
        -Code 'return type(_G._sms_events_smoke.target_name) == "string" and _G._sms_events_smoke.target_name ~= ""'

    # Subscribe to DEAD, but only record the event if it matches OUR target
    # (defensive — other agents may also be killing units in this DCS instance).
    Invoke-Smoke -Code @'
sms.events.connect(sms.events.DEAD, function(evt)
  if evt.initiator and evt.initiator.name == _G._sms_events_smoke.target_name then
    _G._sms_events_smoke.dead_evt = evt
  end
end)
'@ | Out-Null

    # Kill the unit with an explosion (fires S_EVENT_DEAD). Unit:destroy() removes
    # the unit silently without triggering death events; an explosion triggers the
    # full hit -> unit_lost -> dead sequence.
    Invoke-Smoke -Code @'
local u = Unit.getByName(_G._sms_events_smoke.target_name)
if u then
  local pos = u:getPoint()
  trigger.action.explosion(pos, 5000)
end
'@ | Out-Null

    # Poll for sim time to deliver the event. A fixed sleep is fragile —
    # DCS throttles the sim when the window is minimized / unfocused, so a
    # 2-second wall-clock wait can be far less than 2 seconds of sim time.
    # Poll up to 20 x 500ms = 10s.
    for ($i = 1; $i -le 20; $i++) {
        $r = Invoke-Smoke -Code 'return _G._sms_events_smoke.dead_evt ~= nil'
        if ($r.return_value -eq $true) { break }
        Start-Sleep -Milliseconds 500
    }

    Expect-True -Label 'DEAD event received' `
        -Code 'return _G._sms_events_smoke.dead_evt ~= nil'
    Expect-EqString -Label 'DEAD event has correct name' `
        -Code 'return _G._sms_events_smoke.dead_evt.name' -Expected 'dead'
    Expect-True -Label 'DEAD event initiator is an sms.unit handle' `
        -Code 'return type(_G._sms_events_smoke.dead_evt.initiator) == "table" and type(_G._sms_events_smoke.dead_evt.initiator.get_name) == "function"'
    Expect-True -Label 'DEAD event initiator name matches our target' `
        -Code 'return _G._sms_events_smoke.dead_evt.initiator.name == _G._sms_events_smoke.target_name'
    Expect-True -Label 'DEAD event initiator is no longer alive' `
        -Code 'return _G._sms_events_smoke.dead_evt.initiator:is_alive() == false'
    Expect-True -Label 'DEAD event time is a positive number' `
        -Code 'return type(_G._sms_events_smoke.dead_evt.time) == "number" and _G._sms_events_smoke.dead_evt.time > 0'

    # Cleanup — best-effort. Group is already dead from the explosion; this
    # attempts to remove the wreckage. DCS may leave wreckage regardless.
    Invoke-Smoke -Code @'
local g = Group.getByName(_G._sms_events_smoke.group_name)
if g then pcall(g.destroy, g) end
'@ | Out-Null

    Write-Host "==> entity sugar — non-entity event rejected"
    # Spawn a throwaway group just to get a real handle. Position is far from
    # origin AND from the Task 4 round-trip spawn to avoid any collision with
    # the concurrent sms.static agent.
    Invoke-Smoke -Code @"
_G._sms_events_smoke = {sugar_group_name = nil}
_G._sms_events_smoke.g = sms.group.create({
  name = "smoke_evt_sugar_grp",
  position = {x = $($SmokeAnchorX + 1000), y = 0, z = $($SmokeAnchorZ + 1000)},
  country = sms.K.countries.USA,
  category = sms.K.category.GROUND,
  units = {{ type = "M-1 Abrams", offset = {x = 0, y = 0, z = 0} }},
})
if _G._sms_events_smoke.g then
  _G._sms_events_smoke.sugar_group_name = _G._sms_events_smoke.g:get_name()
end
"@ | Out-Null
    Expect-True -Label 'g:connect on MISSION_START rejected (returns nil)' `
        -Code 'return _G._sms_events_smoke.g:connect(sms.events.MISSION_START, function() end) == nil'
    Expect-True -Label 'u:connect on MISSION_START rejected (returns nil)' `
        -Code 'local u = _G._sms_events_smoke.g:get_units()[1]; return u:connect(sms.events.MISSION_START, function() end) == nil'

    Write-Host "==> entity sugar — initiator filter (synthetic via emit)"
    Invoke-Smoke -Code @'
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
'@ | Out-Null
    Expect-EqNumber -Label 'u:connect fires only for matching initiator' `
        -Code 'return _G._sms_events_smoke.matched' -Expected 1

    Write-Host "==> entity sugar — group filter for non-DEAD event (per-unit, synthetic via emit)"
    # Non-DEAD entity events on g:connect fire per-unit. The filter checks
    # evt.initiator_group_name == target_name. We use BIRTH because it's
    # entity-scoped and easy to fake synthetically without DCS side effects.
    Invoke-Smoke -Code @'
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
'@ | Out-Null
    Expect-EqNumber -Label 'g:connect fires only for events in our group (not other groups)' `
        -Code 'return _G._sms_events_smoke.gmatched' -Expected 1

    # Cleanup — best-effort. Group is alive; this should succeed cleanly.
    Invoke-Smoke -Code @'
local g = Group.getByName(_G._sms_events_smoke.sugar_group_name)
if g then pcall(g.destroy, g) end
'@ | Out-Null

    Write-Host "==> sms.unit.destroy(u, {emit_event=true}) fires DEAD via the bus"
    Invoke-Smoke -Code @"
_G._sms_destroy_smoke = {fired = 0, target = nil, group_name = nil}
local g = sms.group.create({
  name = "smoke_destroy_target",
  position = {x = $($SmokeAnchorX + 1500), y = 0, z = $($SmokeAnchorZ + 1500)},
  country = sms.K.countries.USA,
  category = sms.K.category.GROUND,
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
"@ | Out-Null
    Expect-EqNumber -Label 'destroy(emit_event=true) fired DEAD subscriber once' `
        -Code 'return _G._sms_destroy_smoke.fired' -Expected 1
    Invoke-Smoke -Code @'
local g = Group.getByName(_G._sms_destroy_smoke.group_name)
if g then pcall(g.destroy, g) end
'@ | Out-Null

    Write-Host "==> sms.unit.destroy(u) without opts does NOT fire DEAD"
    Invoke-Smoke -Code @"
_G._sms_destroy_silent = {fired = 0, target = nil, group_name = nil}
local g = sms.group.create({
  name = "smoke_silent_destroy",
  position = {x = $($SmokeAnchorX + 2500), y = 0, z = $($SmokeAnchorZ + 2500)},
  country = sms.K.countries.USA,
  category = sms.K.category.GROUND,
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
"@ | Out-Null
    Expect-EqNumber -Label 'destroy() without opts did NOT fire DEAD' `
        -Code 'return _G._sms_destroy_silent.fired' -Expected 0
    Invoke-Smoke -Code @'
local g = Group.getByName(_G._sms_destroy_silent.group_name)
if g then pcall(g.destroy, g) end
'@ | Out-Null

    Write-Host "==> g:connect(DEAD) fires only when group is fully dead"
    Invoke-Smoke -Code @"
_G._sms_grp_dead = {fired = 0, group_name = nil, units = {}}
local g = sms.group.create({
  name = "smoke_grp_dead",
  position = {x = $($SmokeAnchorX + 3500), y = 0, z = $($SmokeAnchorZ + 3500)},
  country = sms.K.countries.USA,
  category = sms.K.category.GROUND,
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
"@ | Out-Null
    # The fully-dead check is deferred one sim frame, so wait briefly for the
    # timer to fire before asserting state.
    Start-Sleep -Seconds 1
    Expect-EqNumber -Label 'g:connect(DEAD) does NOT fire while group has live units' `
        -Code 'return _G._sms_grp_dead.fired' -Expected 0
    Invoke-Smoke -Code @'
-- Kill the second (last) unit. Group is now fully dead — callback should fire once.
sms.unit.destroy(sms.unit(_G._sms_grp_dead.units[2]), {emit_event = true})
'@ | Out-Null
    Start-Sleep -Seconds 1
    Expect-EqNumber -Label 'g:connect(DEAD) fires exactly once when last unit dies' `
        -Code 'return _G._sms_grp_dead.fired' -Expected 1
    # Cleanup — group is fully dead; best-effort.
    Invoke-Smoke -Code @'
local g = Group.getByName(_G._sms_grp_dead.group_name)
if g then pcall(g.destroy, g) end
'@ | Out-Null

    Write-Host "==> verify [sms.events] log lines for bad args and user errors"
    Expect-LogContains -Label 'log: connect nil name'         -Pattern 'connect: name must be a string'                 -Grep '\[sms.events\]'
    Expect-LogContains -Label 'log: connect non-fn'           -Pattern 'connect: fn must be a function'                 -Grep '\[sms.events\]'
    Expect-LogContains -Label 'log: disconnect non-handle'    -Pattern 'disconnect: argument must be a Connection handle' -Grep '\[sms.events\]'
    Expect-LogContains -Label 'log: subscriber raised'        -Pattern "subscriber for 'err_test' raised"               -Grep '\[sms.events\]'

    Write-SmokeSummary
} finally {
    Clear-SmokeFixtures -Names $fixtures
}
