#!/usr/bin/env bash
# End-to-end smoke test for sms.unit v1.
# Self-contained: spawns its own test fixture via coalition.addGroup,
# exercises all 7 sms.unit methods plus the new sms.group:get_units(),
# verifies the unit<->group round-trip, then destroys the fixture.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

cd "${FRAMEWORK_DIR}"

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null

echo "==> spawn test fixture _sms_test_unit_group with unit _sms_test_unit"
# Try to derive viable spawn coords from an existing mission unit;
# fall back to {0, 0} if no existing units found.
spawn_response=$("${DCSSMS}" exec --code '
  local fixture_x, fixture_y = 0, 0
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then
          local p = units[1]:getPoint()
          fixture_x = p.x
          fixture_y = p.z
          break
        end
      end
      if fixture_x ~= 0 or fixture_y ~= 0 then break end
    end
  end

  local group_def = {
    name = "_sms_test_unit_group",
    task = "Ground Nothing",
    units = {{
      name = "_sms_test_unit",
      type = "Soldier M4",
      x = fixture_x,
      y = fixture_y,
      heading = 0,
      skill = "Average",
    }},
  }
  coalition.addGroup(country.id.USA, Group.Category.GROUND, group_def)
  return Unit.getByName("_sms_test_unit") ~= nil
')
echo "${spawn_response}"
echo "${spawn_response}" | grep -q '"return_value":true' \
  || { echo "FAIL: could not spawn _sms_test_unit"; exit 1; }

echo "==> is_alive should be true"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):is_alive()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: is_alive: ${result}"; exit 1; }

echo "==> get_name should be _sms_test_unit"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_unit"' \
  || { echo "FAIL: get_name: ${result}"; exit 1; }

echo "==> get_coalition should be blue"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_coalition()")
echo "${result}" | grep -q '"return_value":"blue"' \
  || { echo "FAIL: get_coalition: ${result}"; exit 1; }

echo "==> get_position should return a {x,y,z} table"
result=$("${DCSSMS}" exec --code '
  local p = sms.unit("_sms_test_unit"):get_position()
  return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_position: ${result}"; exit 1; }

echo "==> get_type should be Soldier M4"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_type()")
echo "${result}" | grep -q '"return_value":"Soldier M4"' \
  || { echo "FAIL: get_type: ${result}"; exit 1; }

echo "==> get_group():get_name() should be _sms_test_unit_group (unit -> group round-trip)"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):get_group():get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_unit_group"' \
  || { echo "FAIL: get_group round-trip: ${result}"; exit 1; }

echo "==> group:get_units() should return one handle"
result=$("${DCSSMS}" exec --code "return #sms.group(\"_sms_test_unit_group\"):get_units()")
echo "${result}" | grep -q '"return_value":1' \
  || { echo "FAIL: get_units count: ${result}"; exit 1; }

echo "==> group:get_units()[1]:get_name() should be _sms_test_unit (group -> unit round-trip)"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_unit_group\"):get_units()[1]:get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_unit"' \
  || { echo "FAIL: get_units round-trip: ${result}"; exit 1; }

echo "==> nonexistent unit should return nil"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_definitely_not_a_unit\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: nonexistent unit: ${result}"; exit 1; }

echo "==> destroy on alive unit should return true"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\"):destroy()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: destroy: ${result}"; exit 1; }

echo "==> after destroy, lookup should return nil"
result=$("${DCSSMS}" exec --code "return sms.unit(\"_sms_test_unit\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: post-destroy: ${result}"; exit 1; }

echo "==> dcs.log should contain [sms.unit] miss line"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.unit\]' -n 200)
echo "${log_window}" | grep -q "couldn't find unit '_definitely_not_a_unit'" \
  || { echo "FAIL: missing log line for nonexistent unit"; echo "${log_window}"; exit 1; }

echo "==> cleanup: destroy parent group (best-effort)"
"${DCSSMS}" exec --code "
  local g = sms.group('_sms_test_unit_group')
  if g then g:destroy() end
" >/dev/null

echo "smoke ok"
