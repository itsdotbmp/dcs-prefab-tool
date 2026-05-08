# End-to-end smoke test for sms.options.
# Synthetic checks (no DCS dispatch) verify builder shape + flags + ROE marker.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

$fixtures = @('_smoke_opt_air', '_smoke_opt_ground')

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua'           | Out-Null
    Invoke-Smoke -File 'log.lua'           | Out-Null
    Invoke-Smoke -File 'utils.lua'         | Out-Null
    Invoke-Smoke -File 'constants.lua'     | Out-Null
    Invoke-Smoke -File 'group.lua'         | Out-Null
    Invoke-Smoke -File 'unit.lua'          | Out-Null
    Invoke-Smoke -File 'area.lua'          | Out-Null
    Invoke-Smoke -File 'timer.lua'         | Out-Null
    Invoke-Smoke -File 'group_spawn.lua'   | Out-Null
    Invoke-Smoke -File 'static.lua'        | Out-Null
    Invoke-Smoke -File 'events.lua'        | Out-Null
    Invoke-Smoke -File 'weapon.lua'        | Out-Null
    Invoke-Smoke -File 'task.lua'          | Out-Null
    Invoke-Smoke -File 'commands.lua'      | Out-Null
    Invoke-Smoke -File 'options.lua'       | Out-Null

    # ----------------------------------------------------------------
    # Synthetic builder shape checks
    # ----------------------------------------------------------------

    Write-Host "==> [build] ROE marker + value"
    Expect-True -Label 'roe via constant'     -Code 'local o = sms.options.roe(sms.K.roe.WEAPON_HOLD); return o._sms_roe == true and o.value == "weapon_hold"'
    Expect-True -Label 'roe via raw string'   -Code 'local o = sms.options.roe("weapon_free"); return o._sms_roe == true and o.value == "weapon_free"'
    Expect-True -Label 'roe verb'             -Code 'return sms.options.roe(sms.K.roe.WEAPON_HOLD)._sms_verb == "roe"'
    Expect-True -Label 'roe unknown rejected' -Code 'return sms.options.roe("kill_em_all") == nil'

    Write-Host "==> [build] enum builders (air-only)"
    Expect-True -Label 'reaction_on_threat'  -Code 'return sms.options.reaction_on_threat(sms.K.reaction_on_threat.EVADE_FIRE)._sms_air_only == true'
    Expect-True -Label 'radar_using'         -Code 'return sms.options.radar_using(sms.K.radar_using.NEVER).params == 0'
    Expect-True -Label 'flare_using bad arg' -Code 'return sms.options.flare_using("often") == nil'

    Write-Host "==> [build] formation"
    Expect-True -Label 'formation preset'      -Code 'return sms.options.formation(sms.K.formation.LINE_ABREAST).params == 65537'
    Expect-True -Label 'formation raw int'     -Code 'return sms.options.formation(393217).params == 393217'
    Expect-True -Label 'formation bad arg'     -Code 'return sms.options.formation("invalid_preset") == nil'
    Expect-True -Label 'formation_interval'    -Code 'return sms.options.formation_interval(50).params == 50'

    Write-Host "==> [build] bool builders"
    Expect-True -Label 'rtb_on_bingo true'      -Code 'return sms.options.rtb_on_bingo(true).params == true'
    Expect-True -Label 'rtb_on_bingo bad arg'   -Code 'return sms.options.rtb_on_bingo("yes") == nil'
    Expect-True -Label 'silence(true) air-only' -Code 'return sms.options.silence(true)._sms_air_only == true'
    Expect-True -Label 'jettison_empty_tanks'   -Code 'return sms.options.jettison_empty_tanks(true).params == true'
    Expect-True -Label 'landing_straight_in'    -Code 'return sms.options.landing_straight_in(true)._sms_air_only == true'

    Write-Host "==> [build] waypoint_pass_report (inverted)"
    Expect-True -Label 'wp report=true -> false' -Code 'return sms.options.waypoint_pass_report(true).params == false'
    Expect-True -Label 'wp report=false -> true' -Code 'return sms.options.waypoint_pass_report(false).params == true'

    Write-Host "==> [build] radio reporting (default + list)"
    Expect-True -Label 'radio_contact default'        -Code 'local o = sms.options.radio_contact(); return o.params[1] == "Air"'
    Expect-True -Label 'radio_engage list'            -Code 'local o = sms.options.radio_engage({"Ground Units","Air"}); return o.params[1] == "Ground Units"'
    Expect-True -Label 'radio_kill string -> table'   -Code 'local o = sms.options.radio_kill("Air"); return o.params[1] == "Air"'

    Write-Host "==> [build] ground-only builders"
    Expect-True -Label 'alarm_state'             -Code 'return sms.options.alarm_state(sms.K.alarm_state.RED).params == 2'
    Expect-True -Label 'alarm_state ground-only' -Code 'return sms.options.alarm_state(sms.K.alarm_state.GREEN)._sms_ground_only == true'
    Expect-True -Label 'disperse_on_attack'      -Code 'return sms.options.disperse_on_attack(30).params == 30'
    Expect-True -Label 'disperse_on_attack neg'  -Code 'return sms.options.disperse_on_attack(-5) == nil'

    # ----------------------------------------------------------------
    # Live-DCS apply checks
    # ----------------------------------------------------------------

    Write-Host "==> [apply] spawn fixtures"
    $spawnAir = @"
return sms.group.create({
  name='_smoke_opt_air', position={x=40000,y=0,z=40000}, country=sms.K.countries.USA,
  category=sms.K.category.AIRPLANE,
  units={{type=sms.K.units.planes.F_16C_50, alt=6000}},
}) ~= nil
"@
    Expect-True -Label 'spawn air' -Code $spawnAir

    $spawnGround = @"
return sms.group.create({
  name='_smoke_opt_ground', position={x=10000,y=0,z=10000}, country=sms.K.countries.USA,
  units={{type=sms.K.units.armor.tanks.M_1_Abrams}},
}) ~= nil
"@
    Expect-True -Label 'spawn ground' -Code $spawnGround

    Invoke-Smoke -Code 'sms.timer.after(0.5, function() end)' | Out-Null

    Write-Host "==> [apply] ROE on each category"
    Expect-True -Label 'air ROE weapon_free'    -Code "return sms.group('_smoke_opt_air'):set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))"
    Expect-True -Label 'air ROE weapon_hold'    -Code "return sms.group('_smoke_opt_air'):set_option(sms.options.roe(sms.K.roe.WEAPON_HOLD))"
    Expect-True -Label 'ground ROE weapon_hold' -Code "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.K.roe.WEAPON_HOLD))"
    Expect-True -Label 'ground ROE return_fire' -Code "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.K.roe.RETURN_FIRE))"

    Write-Host "==> [apply] ROE air-only value rejected on ground"
    Expect-False -Label 'ground ROE weapon_free'           -Code "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))"
    Expect-False -Label 'ground ROE open_fire_weapon_free' -Code "return sms.group('_smoke_opt_ground'):set_option(sms.options.roe(sms.K.roe.OPEN_FIRE_WEAPON_FREE))"

    Write-Host "==> [apply] air-only option rejected on ground"
    Expect-False -Label 'rtb_on_bingo on ground' -Code "return sms.group('_smoke_opt_ground'):set_option(sms.options.rtb_on_bingo(true))"

    Write-Host "==> [apply] ground-only option rejected on air"
    Expect-False -Label 'alarm_state on air' -Code "return sms.group('_smoke_opt_air'):set_option(sms.options.alarm_state(sms.K.alarm_state.RED))"

    Write-Host "==> [apply] valid air options"
    Expect-True -Label 'rtb_on_bingo on air' -Code "return sms.group('_smoke_opt_air'):set_option(sms.options.rtb_on_bingo(true))"
    Expect-True -Label 'radar_using on air'  -Code "return sms.group('_smoke_opt_air'):set_option(sms.options.radar_using(sms.K.radar_using.FOR_CONTINUOUS_SEARCH))"

    Write-Host "==> [apply] valid ground options"
    Expect-True -Label 'alarm_state on ground'     -Code "return sms.group('_smoke_opt_ground'):set_option(sms.options.alarm_state(sms.K.alarm_state.RED))"
    Expect-True -Label 'disperse_on_attack ground' -Code "return sms.group('_smoke_opt_ground'):set_option(sms.options.disperse_on_attack(15))"

    Write-Host "==> [apply] manually-built table rejected"
    Expect-False -Label 'raw option rejected' -Code "return sms.group('_smoke_opt_air'):set_option({id=AI.Option.Air.id.ROE, params=4})"

    Write-SmokeSummary
}
finally {
    Clear-SmokeFixtures -Names $fixtures
}
