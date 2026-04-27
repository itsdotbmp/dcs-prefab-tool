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
result=$("${DCSSMS}" exec --code "return sms.utils.is_vec3({x=1, y=2})")
echo "${result}" | grep -q '"return_value":false' \
  || { echo "FAIL: expected return_value:false, got: ${result}"; exit 1; }

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
