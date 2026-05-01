#!/usr/bin/env bash
# End-to-end smoke test for the dcs-sms framework v1 (logger + utils).
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework/sms.lua"
"${DCSSMS}" exec --file sms.lua >/dev/null

echo "==> load framework/log.lua"
"${DCSSMS}" exec --file log.lua >/dev/null

echo "==> load framework/utils.lua"
"${DCSSMS}" exec --file utils.lua >/dev/null

echo "==> sms.version should be \"0.1.0\""
version_result=$("${DCSSMS}" exec --code "return sms.version")
echo "${version_result}" | grep -q '"return_value":"0.1.0"' \
  || { echo "FAIL: expected sms.version=\"0.1.0\", got: ${version_result}"; exit 1; }

echo "==> sms.utils.add_numbers(2, 3) should return 5"
result=$("${DCSSMS}" exec --code "return sms.utils.add_numbers(2, 3)")
echo "${result}"
echo "${result}" | grep -q '"return_value":5' \
  || { echo "FAIL: expected return_value:5, got: ${result}"; exit 1; }

echo "==> sms.utils.is_vec3 happy path -> true"
result=$("${DCSSMS}" exec --code "return sms.utils.is_vec3({x=1, y=2, z=3})")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: expected return_value:true, got: ${result}"; exit 1; }

echo "==> sms.utils.is_vec3 missing z -> false"
# tostring() works around a bridge serialization bug where Lua false
# returns get serialized to JSON null. The function returns false
# correctly; the bridge just can't transport it.
result=$("${DCSSMS}" exec --code "return tostring(sms.utils.is_vec3({x=1, y=2}))")
echo "${result}" | grep -q '"return_value":"false"' \
  || { echo "FAIL: expected return_value:\"false\", got: ${result}"; exit 1; }

echo "==> sms.utils.vec3_length({x=3, y=4, z=0}) should return 5"
result=$("${DCSSMS}" exec --code "return sms.utils.vec3_length({x=3, y=4, z=0})")
echo "${result}" | grep -q '"return_value":5' \
  || { echo "FAIL: expected return_value:5, got: ${result}"; exit 1; }

echo "==> sms.utils.vec3_length(bad arg) should log and return nil"
result=$("${DCSSMS}" exec --code "return sms.utils.vec3_length('not a vec3')")
echo "${result}" | grep -q '"return_value":null' \
  || { echo "FAIL: expected return_value:null, got: ${result}"; exit 1; }

echo "==> sms.utils.vec3_distance origin to {x=3, y=4, z=0} should return 5"
result=$("${DCSSMS}" exec --code "return sms.utils.vec3_distance({x=0,y=0,z=0}, {x=3,y=4,z=0})")
echo "${result}" | grep -q '"return_value":5' \
  || { echo "FAIL: expected return_value:5, got: ${result}"; exit 1; }

echo "==> sms.utils.vec3_distance(nil, vec3) should log and return nil"
result=$("${DCSSMS}" exec --code "return sms.utils.vec3_distance(nil, {x=0,y=0,z=0})")
echo "${result}" | grep -q '"return_value":null' \
  || { echo "FAIL: expected return_value:null, got: ${result}"; exit 1; }

echo "==> sms.utils.resolve_country('USA') returns an int"
result=$("${DCSSMS}" exec --code "return type(sms.utils.resolve_country('USA'))")
echo "${result}" | grep -q '"return_value":"number"' \
  || { echo "FAIL: expected number, got: ${result}"; exit 1; }

echo "==> sms.utils.resolve_country('united kingdom') case-insensitive + space->underscore"
result=$("${DCSSMS}" exec --code "return sms.utils.resolve_country('united kingdom') == sms.utils.resolve_country('UNITED_KINGDOM')")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: expected return_value:true, got: ${result}"; exit 1; }

echo "==> load framework/constants.lua"
"${DCSSMS}" exec --file constants.lua >/dev/null

echo "==> sms.K is sms.constants alias"
result=$("${DCSSMS}" exec --code "return type(sms.K) == 'table' and sms.K == sms.constants")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: sms.K is not the sms.constants alias, got: ${result}"; exit 1; }

echo "==> sms.constants is initialized"
result=$("${DCSSMS}" exec --code "return type(sms.constants)")
echo "${result}" | grep -q '"return_value":"table"' \
  || { echo "FAIL: sms.constants is not a table, got: ${result}"; exit 1; }

echo "==> sms.K.countries.USA == 'USA' (key/value identity)"
result=$("${DCSSMS}" exec --code "return sms.K.countries.USA")
echo "${result}" | grep -q '"return_value":"USA"' \
  || { echo "FAIL: expected USA, got: ${result}"; exit 1; }

echo "==> sms.K.countries.RUSSIA == 'RUSSIA'"
result=$("${DCSSMS}" exec --code "return sms.K.countries.RUSSIA")
echo "${result}" | grep -q '"return_value":"RUSSIA"' \
  || { echo "FAIL: expected RUSSIA, got: ${result}"; exit 1; }

echo "==> sms.K.countries.THE_NETHERLANDS round-trips through resolve_country"
result=$("${DCSSMS}" exec --code "return type(sms.utils.resolve_country(sms.K.countries.THE_NETHERLANDS))")
echo "${result}" | grep -q '"return_value":"number"' \
  || { echo "FAIL: expected number, got: ${result}"; exit 1; }

echo "==> sms.K.countries.UNKNOWN_COUNTRY is nil (typo guard)"
result=$("${DCSSMS}" exec --code "return tostring(sms.K.countries.UNKNOWN_COUNTRY)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected nil, got: ${result}"; exit 1; }

echo "==> sms.K.countries has at least 80 entries (sanity)"
result=$("${DCSSMS}" exec --code "local n = 0; for _ in pairs(sms.K.countries) do n = n + 1 end; return n")
n=$(echo "${result}" | sed -n 's/.*"return_value":\([0-9]*\).*/\1/p')
[ -n "${n}" ] && [ "${n}" -ge 80 ] \
  || { echo "FAIL: expected >=80 entries, got: ${result}"; exit 1; }

echo "==> sms.K.skill.AVERAGE == 'Average'"
result=$("${DCSSMS}" exec --code "return sms.K.skill.AVERAGE")
echo "${result}" | grep -q '"return_value":"Average"' \
  || { echo "FAIL: expected Average, got: ${result}"; exit 1; }

echo "==> sms.K.skill.PLAYER == 'Player' (player-slot marker)"
result=$("${DCSSMS}" exec --code "return sms.K.skill.PLAYER")
echo "${result}" | grep -q '"return_value":"Player"' \
  || { echo "FAIL: expected Player, got: ${result}"; exit 1; }

echo "==> sms.K.alt_type.BARO == 'BARO'"
result=$("${DCSSMS}" exec --code "return sms.K.alt_type.BARO")
echo "${result}" | grep -q '"return_value":"BARO"' \
  || { echo "FAIL: expected BARO, got: ${result}"; exit 1; }

echo "==> sms.K.alt_type.RADIO == 'RADIO'"
result=$("${DCSSMS}" exec --code "return sms.K.alt_type.RADIO")
echo "${result}" | grep -q '"return_value":"RADIO"' \
  || { echo "FAIL: expected RADIO, got: ${result}"; exit 1; }

echo "==> sms.K.waypoint.type.TURNING_POINT == 'Turning Point'"
result=$("${DCSSMS}" exec --code "return sms.K.waypoint.type.TURNING_POINT")
echo "${result}" | grep -q '"return_value":"Turning Point"' \
  || { echo "FAIL: expected 'Turning Point', got: ${result}"; exit 1; }

echo "==> sms.K.waypoint.action.OFF_ROAD == 'Off Road'"
result=$("${DCSSMS}" exec --code "return sms.K.waypoint.action.OFF_ROAD")
echo "${result}" | grep -q '"return_value":"Off Road"' \
  || { echo "FAIL: expected 'Off Road', got: ${result}"; exit 1; }

echo "==> sms.K.waypoint.type.LANDING_REFUEL_REARM == 'LandingReFuAr' (contracted casing guard)"
result=$("${DCSSMS}" exec --code "return sms.K.waypoint.type.LANDING_REFUEL_REARM")
echo "${result}" | grep -q '"return_value":"LandingReFuAr"' \
  || { echo "FAIL: expected 'LandingReFuAr', got: ${result}"; exit 1; }

echo "==> sms.K.waypoint.action.LANDING_REFUEL_REARM == 'LandingReFuAr' (contracted casing guard)"
result=$("${DCSSMS}" exec --code "return sms.K.waypoint.action.LANDING_REFUEL_REARM")
echo "${result}" | grep -q '"return_value":"LandingReFuAr"' \
  || { echo "FAIL: expected 'LandingReFuAr', got: ${result}"; exit 1; }

echo "==> sms.K.targets.AIR == 'Air'"
result=$("${DCSSMS}" exec --code "return sms.K.targets.AIR")
echo "${result}" | grep -q '"return_value":"Air"' \
  || { echo "FAIL: expected 'Air', got: ${result}"; exit 1; }

echo "==> sms.K.designations.LASER == 'Laser'"
result=$("${DCSSMS}" exec --code "return sms.K.designations.LASER")
echo "${result}" | grep -q '"return_value":"Laser"' \
  || { echo "FAIL: expected 'Laser', got: ${result}"; exit 1; }

echo "==> old sms.countries surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.countries)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.countries to be nil, got: ${result}"; exit 1; }

echo "==> old sms.skill surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.skill)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.skill to be nil, got: ${result}"; exit 1; }

echo "==> old sms.alt_type surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.alt_type)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.alt_type to be nil, got: ${result}"; exit 1; }

echo "==> old sms.waypoint surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.waypoint)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.waypoint to be nil, got: ${result}"; exit 1; }

echo "==> old sms.targets surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.targets)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.targets to be nil, got: ${result}"; exit 1; }

echo "==> old sms.designations surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.designations)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.designations to be nil, got: ${result}"; exit 1; }

# ------------------------------------------------------------------
# Task 3: sms.K option enum tables (roe / alarm_state / formation / etc.)
# ------------------------------------------------------------------

echo "==> sms.K.roe.WEAPON_FREE == 'weapon_free'"
result=$("${DCSSMS}" exec --code "return sms.K.roe.WEAPON_FREE")
echo "${result}" | grep -q '"return_value":"weapon_free"' \
  || { echo "FAIL: expected weapon_free, got: ${result}"; exit 1; }

echo "==> sms.K.roe.WEAPON_HOLD == 'weapon_hold'"
result=$("${DCSSMS}" exec --code "return sms.K.roe.WEAPON_HOLD")
echo "${result}" | grep -q '"return_value":"weapon_hold"' \
  || { echo "FAIL: expected weapon_hold, got: ${result}"; exit 1; }

echo "==> sms.K.alarm_state.RED == 'red'"
result=$("${DCSSMS}" exec --code "return sms.K.alarm_state.RED")
echo "${result}" | grep -q '"return_value":"red"' \
  || { echo "FAIL: expected red, got: ${result}"; exit 1; }

echo "==> sms.K.alarm_state.AUTO == 'auto'"
result=$("${DCSSMS}" exec --code "return sms.K.alarm_state.AUTO")
echo "${result}" | grep -q '"return_value":"auto"' \
  || { echo "FAIL: expected auto, got: ${result}"; exit 1; }

echo "==> sms.K.formation.WEDGE == 'wedge'"
result=$("${DCSSMS}" exec --code "return sms.K.formation.WEDGE")
echo "${result}" | grep -q '"return_value":"wedge"' \
  || { echo "FAIL: expected wedge, got: ${result}"; exit 1; }

echo "==> sms.K.formation.FINGER_FOUR == 'finger_four'"
result=$("${DCSSMS}" exec --code "return sms.K.formation.FINGER_FOUR")
echo "${result}" | grep -q '"return_value":"finger_four"' \
  || { echo "FAIL: expected finger_four, got: ${result}"; exit 1; }

echo "==> sms.K.reaction_on_threat.EVADE_FIRE == 'evade_fire'"
result=$("${DCSSMS}" exec --code "return sms.K.reaction_on_threat.EVADE_FIRE")
echo "${result}" | grep -q '"return_value":"evade_fire"' \
  || { echo "FAIL: expected evade_fire, got: ${result}"; exit 1; }

echo "==> sms.K.radar_using.NEVER == 'never'"
result=$("${DCSSMS}" exec --code "return sms.K.radar_using.NEVER")
echo "${result}" | grep -q '"return_value":"never"' \
  || { echo "FAIL: expected never, got: ${result}"; exit 1; }

echo "==> sms.K.flare_using.AGAINST_FIRED_MISSILE == 'against_fired_missile'"
result=$("${DCSSMS}" exec --code "return sms.K.flare_using.AGAINST_FIRED_MISSILE")
echo "${result}" | grep -q '"return_value":"against_fired_missile"' \
  || { echo "FAIL: expected against_fired_missile, got: ${result}"; exit 1; }

echo "==> old sms.options.ROE surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.options.ROE)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.options.ROE to be nil, got: ${result}"; exit 1; }

echo "==> old sms.options.ALARM_STATE surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.options.ALARM_STATE)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.options.ALARM_STATE to be nil, got: ${result}"; exit 1; }

echo "==> old sms.options.FORMATION surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.options.FORMATION)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.options.FORMATION to be nil, got: ${result}"; exit 1; }

echo "==> old sms.options.REACTION_ON_THREAT surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.options.REACTION_ON_THREAT)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.options.REACTION_ON_THREAT to be nil, got: ${result}"; exit 1; }

echo "==> old sms.options.RADAR_USING surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.options.RADAR_USING)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.options.RADAR_USING to be nil, got: ${result}"; exit 1; }

echo "==> old sms.options.FLARE_USING surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.options.FLARE_USING)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.options.FLARE_USING to be nil, got: ${result}"; exit 1; }

echo "==> sms.options.roe is still a function (builder present)"
result=$("${DCSSMS}" exec --code "return type(sms.options.roe)")
echo "${result}" | grep -q '"return_value":"function"' \
  || { echo "FAIL: expected sms.options.roe to be a function, got: ${result}"; exit 1; }

echo "==> sms.options.alarm_state is still a function (builder present)"
result=$("${DCSSMS}" exec --code "return type(sms.options.alarm_state)")
echo "${result}" | grep -q '"return_value":"function"' \
  || { echo "FAIL: expected sms.options.alarm_state to be a function, got: ${result}"; exit 1; }

echo "==> sms.options.formation is still a function (builder present)"
result=$("${DCSSMS}" exec --code "return type(sms.options.formation)")
echo "${result}" | grep -q '"return_value":"function"' \
  || { echo "FAIL: expected sms.options.formation to be a function, got: ${result}"; exit 1; }

echo "==> sms.K.coalition.BLUE == 'blue'"
result=$("${DCSSMS}" exec --code "return sms.K.coalition.BLUE")
echo "${result}" | grep -q '"return_value":"blue"' \
  || { echo "FAIL: expected blue, got: ${result}"; exit 1; }

echo "==> sms.K.coalition.RED == 'red'"
result=$("${DCSSMS}" exec --code "return sms.K.coalition.RED")
echo "${result}" | grep -q '"return_value":"red"' \
  || { echo "FAIL: expected red, got: ${result}"; exit 1; }

echo "==> sms.K.coalition.NEUTRAL == 'neutral'"
result=$("${DCSSMS}" exec --code "return sms.K.coalition.NEUTRAL")
echo "${result}" | grep -q '"return_value":"neutral"' \
  || { echo "FAIL: expected neutral, got: ${result}"; exit 1; }

echo "==> sms.K.category.AIRPLANE == 'airplane'"
result=$("${DCSSMS}" exec --code "return sms.K.category.AIRPLANE")
echo "${result}" | grep -q '"return_value":"airplane"' \
  || { echo "FAIL: expected airplane, got: ${result}"; exit 1; }

echo "==> sms.K.category.HELICOPTER == 'helicopter'"
result=$("${DCSSMS}" exec --code "return sms.K.category.HELICOPTER")
echo "${result}" | grep -q '"return_value":"helicopter"' \
  || { echo "FAIL: expected helicopter, got: ${result}"; exit 1; }

echo "==> sms.K.category.GROUND == 'ground'"
result=$("${DCSSMS}" exec --code "return sms.K.category.GROUND")
echo "${result}" | grep -q '"return_value":"ground"' \
  || { echo "FAIL: expected ground, got: ${result}"; exit 1; }

echo "==> sms.K.category.SHIP == 'ship'"
result=$("${DCSSMS}" exec --code "return sms.K.category.SHIP")
echo "${result}" | grep -q '"return_value":"ship"' \
  || { echo "FAIL: expected ship, got: ${result}"; exit 1; }

echo "==> sms.K.category.TRAIN == 'train'"
result=$("${DCSSMS}" exec --code "return sms.K.category.TRAIN")
echo "${result}" | grep -q '"return_value":"train"' \
  || { echo "FAIL: expected train, got: ${result}"; exit 1; }

echo "==> sms.utils.coalition_int_to_str(1) == 'red'"
result=$("${DCSSMS}" exec --code "return sms.utils.coalition_int_to_str(1)")
echo "${result}" | grep -q '"return_value":"red"' \
  || { echo "FAIL: expected red, got: ${result}"; exit 1; }

echo "==> sms.utils.coalition_int_to_str(99) returns nil"
result=$("${DCSSMS}" exec --code "return sms.utils.coalition_int_to_str(99)")
echo "${result}" | grep -q '"return_value":null' \
  || { echo "FAIL: expected null, got: ${result}"; exit 1; }

echo "==> sms.utils.deep_copy independent from source"
result=$("${DCSSMS}" exec --code "local a = {x={1,2,3}}; local b = sms.utils.deep_copy(a); b.x[1] = 99; return a.x[1]")
echo "${result}" | grep -q '"return_value":1' \
  || { echo "FAIL: deep_copy not independent, got: ${result}"; exit 1; }

echo "==> sms.utils.normalize_heading(-90) == 270"
result=$("${DCSSMS}" exec --code "return sms.utils.normalize_heading(-90)")
echo "${result}" | grep -q '"return_value":270' \
  || { echo "FAIL: expected 270, got: ${result}"; exit 1; }

echo "==> sms.utils.normalize_heading(450) == 90"
result=$("${DCSSMS}" exec --code "return sms.utils.normalize_heading(450)")
echo "${result}" | grep -q '"return_value":90' \
  || { echo "FAIL: expected 90, got: ${result}"; exit 1; }

echo "==> sms.utils.normalize_heading('not a number') returns nil"
result=$("${DCSSMS}" exec --code "return sms.utils.normalize_heading('bogus')")
echo "${result}" | grep -q '"return_value":null' \
  || { echo "FAIL: expected null, got: ${result}"; exit 1; }

echo "==> sms.utils.bearing_to: due east points to 90"
result=$("${DCSSMS}" exec --code "return sms.utils.bearing_to({x=0,y=0,z=0}, {x=100,y=0,z=0})")
echo "${result}" | grep -q '"return_value":90' \
  || { echo "FAIL: expected 90, got: ${result}"; exit 1; }

echo "==> sms.utils.bearing_to: due north points to 0"
result=$("${DCSSMS}" exec --code "return sms.utils.bearing_to({x=0,y=0,z=0}, {x=0,y=0,z=100})")
echo "${result}" | grep -q '"return_value":0' \
  || { echo "FAIL: expected 0, got: ${result}"; exit 1; }

echo "==> sms.utils.bearing_to: due south points to 180"
result=$("${DCSSMS}" exec --code "return sms.utils.bearing_to({x=0,y=0,z=0}, {x=0,y=0,z=-100})")
echo "${result}" | grep -q '"return_value":180' \
  || { echo "FAIL: expected 180, got: ${result}"; exit 1; }

echo "==> sms.utils.bearing_to: due west wraps to 270"
result=$("${DCSSMS}" exec --code "return sms.utils.bearing_to({x=0,y=0,z=0}, {x=-100,y=0,z=0})")
echo "${result}" | grep -q '"return_value":270' \
  || { echo "FAIL: expected 270, got: ${result}"; exit 1; }

echo "==> sms.utils.bearing_to(nil, vec3) logs and returns nil"
result=$("${DCSSMS}" exec --code "return sms.utils.bearing_to(nil, {x=0,y=0,z=0})")
echo "${result}" | grep -q '"return_value":null' \
  || { echo "FAIL: expected null, got: ${result}"; exit 1; }

echo "==> sms.log.info('hello from smoke test')"
"${DCSSMS}" exec --code "sms.log.info('hello from smoke test')" >/dev/null

echo "==> sms.log.error('boom from smoke test')"
"${DCSSMS}" exec --code "sms.log.error('boom from smoke test')" >/dev/null

echo "==> verify dcs.log captured tagged lines"
log_window=$("${DCSSMS}" tail-log --grep '\[sms' -n 200)

echo "${log_window}" | grep -q '\[sms.utils\] add_numbers(2, 3)' \
  || { echo "FAIL: missing [sms.utils] add_numbers line in dcs.log"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q '\[sms\] hello from smoke test' \
  || { echo "FAIL: missing [sms] hello line in dcs.log"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q '\[sms\] boom from smoke test' \
  || { echo "FAIL: missing [sms] boom line in dcs.log"; echo "${log_window}"; exit 1; }

# ------------------------------------------------------------------
# Task 5: sms.K.units catalog under sms.constants.units
# ------------------------------------------------------------------

echo "==> sms.K.units.armor.apc.AAV7 == 'AAV7' (identity key-value)"
result=$("${DCSSMS}" exec --code "return sms.K.units.armor.apc.AAV7")
echo "${result}" | grep -q '"return_value":"AAV7"' \
  || { echo "FAIL: expected AAV7, got: ${result}"; exit 1; }

echo "==> type(sms.K.units.air_defence) == 'table'"
result=$("${DCSSMS}" exec --code "return type(sms.K.units.air_defence)")
echo "${result}" | grep -q '"return_value":"table"' \
  || { echo "FAIL: expected table, got: ${result}"; exit 1; }

echo "==> type(sms.K.units.planes) == 'table'"
result=$("${DCSSMS}" exec --code "return type(sms.K.units.planes)")
echo "${result}" | grep -q '"return_value":"table"' \
  || { echo "FAIL: expected table, got: ${result}"; exit 1; }

echo "==> type(sms.K.units.origin_of) == 'function'"
result=$("${DCSSMS}" exec --code "return type(sms.K.units.origin_of)")
echo "${result}" | grep -q '"return_value":"function"' \
  || { echo "FAIL: expected function, got: ${result}"; exit 1; }

echo "==> sms.K.units.origin_of('AAV7') == nil (base-game unit)"
result=$("${DCSSMS}" exec --code "return tostring(sms.K.units.origin_of('AAV7'))")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected nil, got: ${result}"; exit 1; }

echo "==> type(sms.K.units.origin_of('Tiger_I')) == 'string' (WWII Assets pack)"
result=$("${DCSSMS}" exec --code "return type(sms.K.units.origin_of('Tiger_I'))")
echo "${result}" | grep -q '"return_value":"string"' \
  || { echo "FAIL: expected string, got: ${result}"; exit 1; }

echo "==> old sms.units surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.units)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.units to be nil, got: ${result}"; exit 1; }

# ------------------------------------------------------------------
# Task 6: sms.K.statics catalog under sms.constants.statics
# ------------------------------------------------------------------

echo "==> type(sms.K.statics.cargos) == 'table'"
result=$("${DCSSMS}" exec --code "return type(sms.K.statics.cargos)")
echo "${result}" | grep -q '"return_value":"table"' \
  || { echo "FAIL: expected table, got: ${result}"; exit 1; }

echo "==> type(sms.K.statics.fortifications) == 'table'"
result=$("${DCSSMS}" exec --code "return type(sms.K.statics.fortifications)")
echo "${result}" | grep -q '"return_value":"table"' \
  || { echo "FAIL: expected table, got: ${result}"; exit 1; }

echo "==> type(sms.K.statics.origin_of) == 'function'"
result=$("${DCSSMS}" exec --code "return type(sms.K.statics.origin_of)")
echo "${result}" | grep -q '"return_value":"function"' \
  || { echo "FAIL: expected function, got: ${result}"; exit 1; }

echo "==> sms.K.statics.fortifications.Airshow_Cone == 'Airshow_Cone' (identity key-value)"
result=$("${DCSSMS}" exec --code "return sms.K.statics.fortifications.Airshow_Cone")
echo "${result}" | grep -q '"return_value":"Airshow_Cone"' \
  || { echo "FAIL: expected Airshow_Cone, got: ${result}"; exit 1; }

echo "==> old sms.statics surface is gone (nil)"
result=$("${DCSSMS}" exec --code "return tostring(sms.statics)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected sms.statics to be nil, got: ${result}"; exit 1; }

echo "smoke ok"
