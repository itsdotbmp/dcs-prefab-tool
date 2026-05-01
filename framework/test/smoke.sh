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

echo "==> load framework/countries.lua"
"${DCSSMS}" exec --file countries.lua >/dev/null

echo "==> sms.countries.USA == 'USA' (key/value identity)"
result=$("${DCSSMS}" exec --code "return sms.countries.USA")
echo "${result}" | grep -q '"return_value":"USA"' \
  || { echo "FAIL: expected USA, got: ${result}"; exit 1; }

echo "==> sms.countries.RUSSIA == 'RUSSIA'"
result=$("${DCSSMS}" exec --code "return sms.countries.RUSSIA")
echo "${result}" | grep -q '"return_value":"RUSSIA"' \
  || { echo "FAIL: expected RUSSIA, got: ${result}"; exit 1; }

echo "==> sms.countries.THE_NETHERLANDS round-trips through resolve_country"
result=$("${DCSSMS}" exec --code "return type(sms.utils.resolve_country(sms.countries.THE_NETHERLANDS))")
echo "${result}" | grep -q '"return_value":"number"' \
  || { echo "FAIL: expected number, got: ${result}"; exit 1; }

echo "==> sms.countries.UNKNOWN_COUNTRY is nil (typo guard)"
result=$("${DCSSMS}" exec --code "return tostring(sms.countries.UNKNOWN_COUNTRY)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected nil, got: ${result}"; exit 1; }

echo "==> sms.countries has at least 80 entries (sanity)"
result=$("${DCSSMS}" exec --code "local n = 0; for _ in pairs(sms.countries) do n = n + 1 end; return n")
n=$(echo "${result}" | sed -n 's/.*"return_value":\([0-9]*\).*/\1/p')
[ -n "${n}" ] && [ "${n}" -ge 80 ] \
  || { echo "FAIL: expected >=80 entries, got: ${result}"; exit 1; }

echo "==> load framework/skill.lua, framework/alt_type.lua, framework/waypoint.lua"
"${DCSSMS}" exec --file skill.lua >/dev/null
"${DCSSMS}" exec --file alt_type.lua >/dev/null
"${DCSSMS}" exec --file waypoint.lua >/dev/null

echo "==> sms.skill.AVERAGE == 'Average'"
result=$("${DCSSMS}" exec --code "return sms.skill.AVERAGE")
echo "${result}" | grep -q '"return_value":"Average"' \
  || { echo "FAIL: expected Average, got: ${result}"; exit 1; }

echo "==> sms.skill.PLAYER == 'Player' (player-slot marker)"
result=$("${DCSSMS}" exec --code "return sms.skill.PLAYER")
echo "${result}" | grep -q '"return_value":"Player"' \
  || { echo "FAIL: expected Player, got: ${result}"; exit 1; }

echo "==> sms.alt_type.BARO == 'BARO'"
result=$("${DCSSMS}" exec --code "return sms.alt_type.BARO")
echo "${result}" | grep -q '"return_value":"BARO"' \
  || { echo "FAIL: expected BARO, got: ${result}"; exit 1; }

echo "==> sms.alt_type.RADIO == 'RADIO'"
result=$("${DCSSMS}" exec --code "return sms.alt_type.RADIO")
echo "${result}" | grep -q '"return_value":"RADIO"' \
  || { echo "FAIL: expected RADIO, got: ${result}"; exit 1; }

echo "==> sms.waypoint.TYPE.TURNING_POINT == 'Turning Point'"
result=$("${DCSSMS}" exec --code "return sms.waypoint.TYPE.TURNING_POINT")
echo "${result}" | grep -q '"return_value":"Turning Point"' \
  || { echo "FAIL: expected 'Turning Point', got: ${result}"; exit 1; }

echo "==> sms.waypoint.ACTION.OFF_ROAD == 'Off Road'"
result=$("${DCSSMS}" exec --code "return sms.waypoint.ACTION.OFF_ROAD")
echo "${result}" | grep -q '"return_value":"Off Road"' \
  || { echo "FAIL: expected 'Off Road', got: ${result}"; exit 1; }

echo "==> sms.waypoint.TYPE.LANDING_REFUEL_REARM == 'LandingReFuAr' (contracted casing guard)"
result=$("${DCSSMS}" exec --code "return sms.waypoint.TYPE.LANDING_REFUEL_REARM")
echo "${result}" | grep -q '"return_value":"LandingReFuAr"' \
  || { echo "FAIL: expected 'LandingReFuAr', got: ${result}"; exit 1; }

echo "==> sms.waypoint.ACTION.LANDING_REFUEL_REARM == 'LandingReFuAr' (contracted casing guard)"
result=$("${DCSSMS}" exec --code "return sms.waypoint.ACTION.LANDING_REFUEL_REARM")
echo "${result}" | grep -q '"return_value":"LandingReFuAr"' \
  || { echo "FAIL: expected 'LandingReFuAr', got: ${result}"; exit 1; }

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

echo "smoke ok"
