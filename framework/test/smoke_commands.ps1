# End-to-end smoke test for sms.commands.
# Synthetic checks (no DCS dispatch) verify builder shape + air-only flag.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

$fixtures = @('_smoke_cmd_air', '_smoke_cmd_ground')

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua'         | Out-Null
    Invoke-Smoke -File 'log.lua'         | Out-Null
    Invoke-Smoke -File 'utils.lua'       | Out-Null
    Invoke-Smoke -File 'constants.lua'   | Out-Null
    Invoke-Smoke -File 'group.lua'       | Out-Null
    Invoke-Smoke -File 'unit.lua'        | Out-Null
    Invoke-Smoke -File 'area.lua'        | Out-Null
    Invoke-Smoke -File 'timer.lua'       | Out-Null
    Invoke-Smoke -File 'group_spawn.lua' | Out-Null
    Invoke-Smoke -File 'static.lua'      | Out-Null
    Invoke-Smoke -File 'events.lua'      | Out-Null
    Invoke-Smoke -File 'weapon.lua'      | Out-Null
    Invoke-Smoke -File 'task.lua'        | Out-Null
    Invoke-Smoke -File 'commands.lua'    | Out-Null
    Invoke-Smoke -File 'options.lua'     | Out-Null

    # ----------------------------------------------------------------
    # Synthetic builder shape checks
    # ----------------------------------------------------------------

    Write-Host "==> [build] no_action shape"
    Expect-EqString -Label 'no_action verb' -Code 'return sms.commands.no_action()._sms_verb' -Expected 'no_action'
    Expect-EqString -Label 'no_action id'   -Code 'return sms.commands.no_action().id'       -Expected 'NoAction'

    Write-Host "==> [build] simple bool builders"
    Expect-True -Label 'set_invisible(true) verb'  -Code 'return sms.commands.set_invisible(true)._sms_verb == "set_invisible"'
    Expect-True -Label 'set_immortal(false) shape' -Code 'return sms.commands.set_immortal(false).params.value == false'
    Expect-True -Label 'stop_route(true) shape'    -Code 'return sms.commands.stop_route(true).params.value == true'
    Expect-True -Label 'set_invisible bad arg nil' -Code 'return sms.commands.set_invisible(nil) == nil'
    Expect-True -Label 'set_immortal bad arg nil'  -Code 'return sms.commands.set_immortal("yes") == nil'

    Write-Host "==> [build] frequency builders"
    Expect-True -Label 'set_frequency Hz/AM'    -Code 'local c = sms.commands.set_frequency(251000000); return c.params.frequency == 251000000 and c.params.modulation == 0'
    Expect-True -Label 'set_frequency FM'       -Code 'local c = sms.commands.set_frequency(40500000, sms.commands.MODULATION.FM); return c.params.modulation == 1'
    Expect-True -Label 'set_frequency bad hz'   -Code 'return sms.commands.set_frequency("foo") == nil'
    Expect-True -Label 'set_frequency_for_unit' -Code 'local c = sms.commands.set_frequency_for_unit(251000000, sms.commands.MODULATION.AM, nil, 42); return c.params.unitId == 42'

    Write-Host "==> [build] switch_waypoint"
    Expect-True -Label 'switch_waypoint shape'   -Code 'local c = sms.commands.switch_waypoint(0, 1); return c.params.fromWaypointIndex == 0 and c.params.goToWaypointIndex == 1'
    Expect-True -Label 'switch_waypoint bad arg' -Code 'return sms.commands.switch_waypoint(0, "x") == nil'

    Write-Host "==> [build] callsign (air-only)"
    Expect-True -Label 'set_callsign air-only flag' -Code 'return sms.commands.set_callsign(sms.commands.CALLSIGN.ENFIELD, 1)._sms_air_only == true'
    Expect-True -Label 'set_callsign bad arg'       -Code 'return sms.commands.set_callsign("foo") == nil'

    Write-Host "==> [build] beacon"
    Expect-True -Label 'activate_beacon air-only' -Code 'return sms.commands.activate_beacon({type=sms.commands.BEACON.TYPE.TACAN, system=sms.commands.BEACON.SYSTEM.TACAN_TANKER_X, frequency=1088000000})._sms_air_only == true'
    Expect-True -Label 'activate_beacon bad opts' -Code 'return sms.commands.activate_beacon({type="x"}) == nil'
    Expect-True -Label 'deactivate_beacon shape'  -Code 'return sms.commands.deactivate_beacon()._sms_verb == "deactivate_beacon"'

    Write-Host "==> [build] ACLS / ICLS / Link4"
    Expect-True -Label 'activate_acls'   -Code 'return sms.commands.activate_acls()._sms_air_only == true'
    Expect-True -Label 'deactivate_acls' -Code 'return sms.commands.deactivate_acls()._sms_verb == "deactivate_acls"'
    Expect-True -Label 'activate_icls'   -Code 'return sms.commands.activate_icls(11)._sms_air_only == true'
    Expect-True -Label 'activate_link4'  -Code 'return sms.commands.activate_link4(336000000)._sms_air_only == true'

    Write-Host "==> [build] eplrs"
    Expect-True -Label 'eplrs(true)'         -Code 'return sms.commands.eplrs(true).params.value == true'
    Expect-True -Label 'eplrs with group_id' -Code 'return sms.commands.eplrs(true, 100).params.groupId == 100'
    Expect-True -Label 'eplrs bad value'     -Code 'return sms.commands.eplrs("x") == nil'

    # ----------------------------------------------------------------
    # Live-DCS apply checks
    # ----------------------------------------------------------------

    Write-Host "==> [apply] spawn ground fixture"
    Expect-True -Label 'spawn ground' -Code @"
return sms.group.create({
  name='_smoke_cmd_ground', position={x=0,y=0,z=0}, country=sms.K.countries.USA,
  units={{type=sms.K.units.armor.tanks.M_1_Abrams}},
}) ~= nil
"@

    Write-Host "==> [apply] spawn air fixture"
    Expect-True -Label 'spawn air' -Code @"
return sms.group.create({
  name='_smoke_cmd_air', position={x=20000,y=0,z=20000}, country=sms.K.countries.USA,
  category=sms.K.category.AIRPLANE,
  units={{type=sms.K.units.planes.F_16C_50, alt=6000}},
}) ~= nil
"@

    # Wait one sim tick for controllers to wire up.
    Invoke-Smoke -Code 'sms.timer.after(0.5, function() end)' | Out-Null

    Write-Host "==> [apply] valid command on air"
    Expect-True -Label 'switch_waypoint on air' -Code "return sms.group('_smoke_cmd_air'):set_command(sms.commands.switch_waypoint(0, 1))"

    Write-Host "==> [apply] air-only rejected on ground"
    Expect-False -Label 'set_callsign on ground' -Code "return sms.group('_smoke_cmd_ground'):set_command(sms.commands.set_callsign(sms.commands.CALLSIGN.ENFIELD))"

    Write-Host "==> [apply] non-handle rejected"
    Expect-False -Label 'non-handle set_command' -Code "return sms.group.set_command('not-a-handle', sms.commands.no_action())"

    Write-Host "==> [apply] manually-built table rejected (missing _sms_verb)"
    Expect-False -Label 'raw table rejected' -Code "return sms.group('_smoke_cmd_air'):set_command({id='NoAction', params={}})"

    Write-Host ""
    Write-Host "ALL smoke_commands checks passed."
}
finally {
    Clear-SmokeFixtures -Names $fixtures
}
