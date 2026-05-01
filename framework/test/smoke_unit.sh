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

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort (set -e). Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
SMOKE_FIXTURES="_sms_test_unit _sms_test_unit_group"

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
      skill = sms.K.skill.AVERAGE,
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

echo "==> get_heading should be a number in [0, 360)"
result=$("${DCSSMS}" exec --code '
  local h = sms.unit("_sms_test_unit"):get_heading()
  return type(h) == "number" and h >= 0 and h < 360
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_heading: ${result}"; exit 1; }

echo "==> get_pitch should be a number near 0 for a ground unit"
result=$("${DCSSMS}" exec --code '
  local p = sms.unit("_sms_test_unit"):get_pitch()
  return type(p) == "number" and math.abs(p) < 5
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_pitch: ${result}"; exit 1; }

echo "==> get_altitude (ASL) should be a number"
result=$("${DCSSMS}" exec --code '
  local a = sms.unit("_sms_test_unit"):get_altitude()
  return type(a) == "number"
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_altitude ASL: ${result}"; exit 1; }

echo "==> get_altitude (AGL) should equal ASL minus terrain height at unit position"
result=$("${DCSSMS}" exec --code '
  local u = sms.unit("_sms_test_unit")
  local asl = u:get_altitude()
  local agl = u:get_altitude(true)
  if type(asl) ~= "number" or type(agl) ~= "number" then return false end
  local p = Unit.getByName("_sms_test_unit"):getPoint()
  local terrain = land.getHeight({x = p.x, y = p.z})
  -- (asl - agl) should equal terrain height (within small floating-point margin)
  return math.abs((asl - agl) - terrain) < 0.1
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_altitude AGL: ${result}"; exit 1; }

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
