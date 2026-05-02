# End-to-end smoke test for the dcs-sms framework v1 (logger + utils + constants).
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

Write-Host "==> hook status"
Invoke-Status

Write-Host "==> load framework/sms.lua"
Invoke-Smoke -File 'sms.lua' | Out-Null

Write-Host "==> load framework/log.lua"
Invoke-Smoke -File 'log.lua' | Out-Null

Write-Host "==> load framework/utils.lua"
Invoke-Smoke -File 'utils.lua' | Out-Null

Write-Host "==> sms.version should be `"0.1.0`""
Expect-EqString -Label 'sms.version' -Code 'return sms.version' -Expected '0.1.0'

Write-Host "==> sms.utils.add_numbers(2, 3) should return 5"
Expect-EqNumber -Label 'add_numbers(2,3)' -Code 'return sms.utils.add_numbers(2, 3)' -Expected 5

Write-Host "==> sms.utils.is_vec3 happy path -> true"
Expect-True -Label 'is_vec3 happy' -Code 'return sms.utils.is_vec3({x=1, y=2, z=3})'

Write-Host "==> sms.utils.is_vec3 missing z -> false"
# tostring() works around a bridge serialization bug where Lua false
# returns get serialized to JSON null. The function returns false
# correctly; the bridge just can't transport it.
Expect-EqString -Label 'is_vec3 missing z' -Code "return tostring(sms.utils.is_vec3({x=1, y=2}))" -Expected 'false'

Write-Host "==> sms.utils.vec3_length({x=3, y=4, z=0}) should return 5"
Expect-EqNumber -Label 'vec3_length 3,4,0' -Code 'return sms.utils.vec3_length({x=3, y=4, z=0})' -Expected 5

Write-Host "==> sms.utils.vec3_length(bad arg) should log and return nil"
Expect-Nil -Label 'vec3_length bad arg' -Code "return sms.utils.vec3_length('not a vec3')"

Write-Host "==> sms.utils.vec3_distance origin to {x=3, y=4, z=0} should return 5"
Expect-EqNumber -Label 'vec3_distance' -Code 'return sms.utils.vec3_distance({x=0,y=0,z=0}, {x=3,y=4,z=0})' -Expected 5

Write-Host "==> sms.utils.vec3_distance(nil, vec3) should log and return nil"
Expect-Nil -Label 'vec3_distance nil arg' -Code 'return sms.utils.vec3_distance(nil, {x=0,y=0,z=0})'

Write-Host "==> sms.utils.resolve_country('USA') returns an int"
Expect-EqString -Label 'resolve_country USA type' -Code "return type(sms.utils.resolve_country('USA'))" -Expected 'number'

Write-Host "==> sms.utils.resolve_country('united kingdom') case-insensitive + space->underscore"
Expect-True -Label 'resolve_country UK case' -Code "return sms.utils.resolve_country('united kingdom') == sms.utils.resolve_country('UNITED_KINGDOM')"

Write-Host "==> load framework/constants.lua"
Invoke-Smoke -File 'constants.lua' | Out-Null

Write-Host "==> sms.K is sms.constants alias"
Expect-True -Label 'sms.K alias' -Code "return type(sms.K) == 'table' and sms.K == sms.constants"

Write-Host "==> sms.constants is initialized"
Expect-EqString -Label 'sms.constants table' -Code 'return type(sms.constants)' -Expected 'table'

Write-Host "==> sms.K.countries.USA == 'USA' (key/value identity)"
Expect-EqString -Label 'K.countries.USA' -Code 'return sms.K.countries.USA' -Expected 'USA'

Write-Host "==> sms.K.countries.RUSSIA == 'RUSSIA'"
Expect-EqString -Label 'K.countries.RUSSIA' -Code 'return sms.K.countries.RUSSIA' -Expected 'RUSSIA'

Write-Host "==> sms.K.countries.THE_NETHERLANDS round-trips through resolve_country"
Expect-EqString -Label 'resolve THE_NETHERLANDS' -Code 'return type(sms.utils.resolve_country(sms.K.countries.THE_NETHERLANDS))' -Expected 'number'

Write-Host "==> sms.K.countries.UNKNOWN_COUNTRY is nil (typo guard)"
Expect-EqString -Label 'K.countries UNKNOWN_COUNTRY' -Code 'return tostring(sms.K.countries.UNKNOWN_COUNTRY)' -Expected 'nil'

Write-Host "==> sms.K.countries has at least 80 entries (sanity)"
$r = Invoke-Smoke -Code 'local n = 0; for _ in pairs(sms.K.countries) do n = n + 1 end; return n'
if ($null -eq $r.return_value -or [int]$r.return_value -lt 80) {
    Write-Host "FAIL: expected >=80 entries, got: $($r | ConvertTo-Json -Compress)"
    exit 1
}

Write-Host "==> sms.K.skill.AVERAGE == 'Average'"
Expect-EqString -Label 'K.skill.AVERAGE' -Code 'return sms.K.skill.AVERAGE' -Expected 'Average'

Write-Host "==> sms.K.skill.PLAYER == 'Player' (player-slot marker)"
Expect-EqString -Label 'K.skill.PLAYER' -Code 'return sms.K.skill.PLAYER' -Expected 'Player'

Write-Host "==> sms.K.alt_type.BARO == 'BARO'"
Expect-EqString -Label 'K.alt_type.BARO' -Code 'return sms.K.alt_type.BARO' -Expected 'BARO'

Write-Host "==> sms.K.alt_type.RADIO == 'RADIO'"
Expect-EqString -Label 'K.alt_type.RADIO' -Code 'return sms.K.alt_type.RADIO' -Expected 'RADIO'

Write-Host "==> sms.K.waypoint.type.TURNING_POINT == 'Turning Point'"
Expect-EqString -Label 'K.waypoint.type.TURNING_POINT' -Code 'return sms.K.waypoint.type.TURNING_POINT' -Expected 'Turning Point'

Write-Host "==> sms.K.waypoint.action.OFF_ROAD == 'Off Road'"
Expect-EqString -Label 'K.waypoint.action.OFF_ROAD' -Code 'return sms.K.waypoint.action.OFF_ROAD' -Expected 'Off Road'

Write-Host "==> sms.K.waypoint.type.LANDING_REFUEL_REARM == 'LandingReFuAr' (contracted casing guard)"
Expect-EqString -Label 'K.waypoint.type.LANDING_REFUEL_REARM' -Code 'return sms.K.waypoint.type.LANDING_REFUEL_REARM' -Expected 'LandingReFuAr'

Write-Host "==> sms.K.waypoint.action.LANDING_REFUEL_REARM == 'LandingReFuAr' (contracted casing guard)"
Expect-EqString -Label 'K.waypoint.action.LANDING_REFUEL_REARM' -Code 'return sms.K.waypoint.action.LANDING_REFUEL_REARM' -Expected 'LandingReFuAr'

Write-Host "==> sms.K.targets.AIR == 'Air'"
Expect-EqString -Label 'K.targets.AIR' -Code 'return sms.K.targets.AIR' -Expected 'Air'

Write-Host "==> sms.K.designations.LASER == 'Laser'"
Expect-EqString -Label 'K.designations.LASER' -Code 'return sms.K.designations.LASER' -Expected 'Laser'

Write-Host "==> old sms.countries surface is gone (nil)"
Expect-EqString -Label 'old sms.countries gone' -Code 'return tostring(sms.countries)' -Expected 'nil'

Write-Host "==> old sms.skill surface is gone (nil)"
Expect-EqString -Label 'old sms.skill gone' -Code 'return tostring(sms.skill)' -Expected 'nil'

Write-Host "==> old sms.alt_type surface is gone (nil)"
Expect-EqString -Label 'old sms.alt_type gone' -Code 'return tostring(sms.alt_type)' -Expected 'nil'

Write-Host "==> old sms.waypoint surface is gone (nil)"
Expect-EqString -Label 'old sms.waypoint gone' -Code 'return tostring(sms.waypoint)' -Expected 'nil'

Write-Host "==> old sms.targets surface is gone (nil)"
Expect-EqString -Label 'old sms.targets gone' -Code 'return tostring(sms.targets)' -Expected 'nil'

Write-Host "==> old sms.designations surface is gone (nil)"
Expect-EqString -Label 'old sms.designations gone' -Code 'return tostring(sms.designations)' -Expected 'nil'

# ------------------------------------------------------------------
# Task 3: sms.K option enum tables (roe / alarm_state / formation / etc.)
# ------------------------------------------------------------------

Write-Host "==> sms.K.roe.WEAPON_FREE == 'weapon_free'"
Expect-EqString -Label 'K.roe.WEAPON_FREE' -Code 'return sms.K.roe.WEAPON_FREE' -Expected 'weapon_free'

Write-Host "==> sms.K.roe.WEAPON_HOLD == 'weapon_hold'"
Expect-EqString -Label 'K.roe.WEAPON_HOLD' -Code 'return sms.K.roe.WEAPON_HOLD' -Expected 'weapon_hold'

Write-Host "==> sms.K.alarm_state.RED == 'red'"
Expect-EqString -Label 'K.alarm_state.RED' -Code 'return sms.K.alarm_state.RED' -Expected 'red'

Write-Host "==> sms.K.alarm_state.AUTO == 'auto'"
Expect-EqString -Label 'K.alarm_state.AUTO' -Code 'return sms.K.alarm_state.AUTO' -Expected 'auto'

Write-Host "==> sms.K.formation.WEDGE == 'wedge'"
Expect-EqString -Label 'K.formation.WEDGE' -Code 'return sms.K.formation.WEDGE' -Expected 'wedge'

Write-Host "==> sms.K.formation.FINGER_FOUR == 'finger_four'"
Expect-EqString -Label 'K.formation.FINGER_FOUR' -Code 'return sms.K.formation.FINGER_FOUR' -Expected 'finger_four'

Write-Host "==> sms.K.reaction_on_threat.EVADE_FIRE == 'evade_fire'"
Expect-EqString -Label 'K.reaction_on_threat.EVADE_FIRE' -Code 'return sms.K.reaction_on_threat.EVADE_FIRE' -Expected 'evade_fire'

Write-Host "==> sms.K.radar_using.NEVER == 'never'"
Expect-EqString -Label 'K.radar_using.NEVER' -Code 'return sms.K.radar_using.NEVER' -Expected 'never'

Write-Host "==> sms.K.flare_using.AGAINST_FIRED_MISSILE == 'against_fired_missile'"
Expect-EqString -Label 'K.flare_using.AGAINST_FIRED_MISSILE' -Code 'return sms.K.flare_using.AGAINST_FIRED_MISSILE' -Expected 'against_fired_missile'

Write-Host "==> old sms.options.ROE surface is gone (nil)"
Expect-EqString -Label 'old options.ROE gone' -Code 'return tostring(sms.options.ROE)' -Expected 'nil'

Write-Host "==> old sms.options.ALARM_STATE surface is gone (nil)"
Expect-EqString -Label 'old options.ALARM_STATE gone' -Code 'return tostring(sms.options.ALARM_STATE)' -Expected 'nil'

Write-Host "==> old sms.options.FORMATION surface is gone (nil)"
Expect-EqString -Label 'old options.FORMATION gone' -Code 'return tostring(sms.options.FORMATION)' -Expected 'nil'

Write-Host "==> old sms.options.REACTION_ON_THREAT surface is gone (nil)"
Expect-EqString -Label 'old options.REACTION_ON_THREAT gone' -Code 'return tostring(sms.options.REACTION_ON_THREAT)' -Expected 'nil'

Write-Host "==> old sms.options.RADAR_USING surface is gone (nil)"
Expect-EqString -Label 'old options.RADAR_USING gone' -Code 'return tostring(sms.options.RADAR_USING)' -Expected 'nil'

Write-Host "==> old sms.options.FLARE_USING surface is gone (nil)"
Expect-EqString -Label 'old options.FLARE_USING gone' -Code 'return tostring(sms.options.FLARE_USING)' -Expected 'nil'

Write-Host "==> sms.options.roe is still a function (builder present)"
Expect-EqString -Label 'options.roe is function' -Code 'return type(sms.options.roe)' -Expected 'function'

Write-Host "==> sms.options.alarm_state is still a function (builder present)"
Expect-EqString -Label 'options.alarm_state is function' -Code 'return type(sms.options.alarm_state)' -Expected 'function'

Write-Host "==> sms.options.formation is still a function (builder present)"
Expect-EqString -Label 'options.formation is function' -Code 'return type(sms.options.formation)' -Expected 'function'

Write-Host "==> sms.K.coalition.BLUE == 'blue'"
Expect-EqString -Label 'K.coalition.BLUE' -Code 'return sms.K.coalition.BLUE' -Expected 'blue'

Write-Host "==> sms.K.coalition.RED == 'red'"
Expect-EqString -Label 'K.coalition.RED' -Code 'return sms.K.coalition.RED' -Expected 'red'

Write-Host "==> sms.K.coalition.NEUTRAL == 'neutral'"
Expect-EqString -Label 'K.coalition.NEUTRAL' -Code 'return sms.K.coalition.NEUTRAL' -Expected 'neutral'

Write-Host "==> sms.K.category.AIRPLANE == 'airplane'"
Expect-EqString -Label 'K.category.AIRPLANE' -Code 'return sms.K.category.AIRPLANE' -Expected 'airplane'

Write-Host "==> sms.K.category.HELICOPTER == 'helicopter'"
Expect-EqString -Label 'K.category.HELICOPTER' -Code 'return sms.K.category.HELICOPTER' -Expected 'helicopter'

Write-Host "==> sms.K.category.GROUND == 'ground'"
Expect-EqString -Label 'K.category.GROUND' -Code 'return sms.K.category.GROUND' -Expected 'ground'

Write-Host "==> sms.K.category.SHIP == 'ship'"
Expect-EqString -Label 'K.category.SHIP' -Code 'return sms.K.category.SHIP' -Expected 'ship'

Write-Host "==> sms.K.category.TRAIN == 'train'"
Expect-EqString -Label 'K.category.TRAIN' -Code 'return sms.K.category.TRAIN' -Expected 'train'

Write-Host "==> sms.utils.coalition_int_to_str(1) == 'red'"
Expect-EqString -Label 'coalition_int_to_str(1)' -Code 'return sms.utils.coalition_int_to_str(1)' -Expected 'red'

Write-Host "==> sms.utils.coalition_int_to_str(99) returns nil"
Expect-Nil -Label 'coalition_int_to_str(99)' -Code 'return sms.utils.coalition_int_to_str(99)'

Write-Host "==> sms.utils.deep_copy independent from source"
Expect-EqNumber -Label 'deep_copy independence' -Code 'local a = {x={1,2,3}}; local b = sms.utils.deep_copy(a); b.x[1] = 99; return a.x[1]' -Expected 1

Write-Host "==> sms.utils.normalize_heading(-90) == 270"
Expect-EqNumber -Label 'normalize_heading(-90)' -Code 'return sms.utils.normalize_heading(-90)' -Expected 270

Write-Host "==> sms.utils.normalize_heading(450) == 90"
Expect-EqNumber -Label 'normalize_heading(450)' -Code 'return sms.utils.normalize_heading(450)' -Expected 90

Write-Host "==> sms.utils.normalize_heading('not a number') returns nil"
Expect-Nil -Label 'normalize_heading bogus' -Code "return sms.utils.normalize_heading('bogus')"

Write-Host "==> sms.utils.bearing_to: due east points to 90"
Expect-EqNumber -Label 'bearing_to east' -Code 'return sms.utils.bearing_to({x=0,y=0,z=0}, {x=100,y=0,z=0})' -Expected 90

Write-Host "==> sms.utils.bearing_to: due north points to 0"
Expect-EqNumber -Label 'bearing_to north' -Code 'return sms.utils.bearing_to({x=0,y=0,z=0}, {x=0,y=0,z=100})' -Expected 0

Write-Host "==> sms.utils.bearing_to: due south points to 180"
Expect-EqNumber -Label 'bearing_to south' -Code 'return sms.utils.bearing_to({x=0,y=0,z=0}, {x=0,y=0,z=-100})' -Expected 180

Write-Host "==> sms.utils.bearing_to: due west wraps to 270"
Expect-EqNumber -Label 'bearing_to west' -Code 'return sms.utils.bearing_to({x=0,y=0,z=0}, {x=-100,y=0,z=0})' -Expected 270

Write-Host "==> sms.utils.bearing_to(nil, vec3) logs and returns nil"
Expect-Nil -Label 'bearing_to nil arg' -Code 'return sms.utils.bearing_to(nil, {x=0,y=0,z=0})'

Write-Host "==> sms.log.info('hello from smoke test')"
Invoke-Smoke -Code "sms.log.info('hello from smoke test')" | Out-Null

Write-Host "==> sms.log.error('boom from smoke test')"
Invoke-Smoke -Code "sms.log.error('boom from smoke test')" | Out-Null

Write-Host "==> verify dcs.log captured tagged lines"
Expect-LogContains -Label 'log: utils add_numbers' -Pattern '\[sms\.utils\] add_numbers\(2, 3\)' -Grep '\[sms'
Expect-LogContains -Label 'log: hello'             -Pattern '\[sms\] hello from smoke test'      -Grep '\[sms'
Expect-LogContains -Label 'log: boom'              -Pattern '\[sms\] boom from smoke test'       -Grep '\[sms'

# ------------------------------------------------------------------
# Task 5: sms.K.units catalog under sms.constants.units
# ------------------------------------------------------------------

Write-Host "==> sms.K.units.armor.apc.AAV7 == 'AAV7' (identity key-value)"
Expect-EqString -Label 'K.units.armor.apc.AAV7' -Code 'return sms.K.units.armor.apc.AAV7' -Expected 'AAV7'

Write-Host "==> type(sms.K.units.air_defence) == 'table'"
Expect-EqString -Label 'K.units.air_defence type' -Code 'return type(sms.K.units.air_defence)' -Expected 'table'

Write-Host "==> type(sms.K.units.planes) == 'table'"
Expect-EqString -Label 'K.units.planes type' -Code 'return type(sms.K.units.planes)' -Expected 'table'

Write-Host "==> type(sms.K.units.origin_of) == 'function'"
Expect-EqString -Label 'K.units.origin_of type' -Code 'return type(sms.K.units.origin_of)' -Expected 'function'

Write-Host "==> sms.K.units.origin_of('AAV7') == nil (base-game unit)"
Expect-EqString -Label 'origin_of AAV7' -Code "return tostring(sms.K.units.origin_of('AAV7'))" -Expected 'nil'

Write-Host "==> type(sms.K.units.origin_of('Tiger_I')) == 'string' (WWII Assets pack)"
Expect-EqString -Label 'origin_of Tiger_I type' -Code "return type(sms.K.units.origin_of('Tiger_I'))" -Expected 'string'

Write-Host "==> old sms.units surface is gone (nil)"
Expect-EqString -Label 'old sms.units gone' -Code 'return tostring(sms.units)' -Expected 'nil'

# ------------------------------------------------------------------
# Task 6: sms.K.statics catalog under sms.constants.statics
# ------------------------------------------------------------------

Write-Host "==> type(sms.K.statics.cargos) == 'table'"
Expect-EqString -Label 'K.statics.cargos type' -Code 'return type(sms.K.statics.cargos)' -Expected 'table'

Write-Host "==> type(sms.K.statics.fortifications) == 'table'"
Expect-EqString -Label 'K.statics.fortifications type' -Code 'return type(sms.K.statics.fortifications)' -Expected 'table'

Write-Host "==> type(sms.K.statics.origin_of) == 'function'"
Expect-EqString -Label 'K.statics.origin_of type' -Code 'return type(sms.K.statics.origin_of)' -Expected 'function'

Write-Host "==> sms.K.statics.fortifications.Airshow_Cone == 'Airshow_Cone' (identity key-value)"
Expect-EqString -Label 'K.statics.fortifications.Airshow_Cone' -Code 'return sms.K.statics.fortifications.Airshow_Cone' -Expected 'Airshow_Cone'

Write-Host "==> old sms.statics surface is gone (nil)"
Expect-EqString -Label 'old sms.statics gone' -Code 'return tostring(sms.statics)' -Expected 'nil'

Write-Host ""
Write-Host "smoke ok"
