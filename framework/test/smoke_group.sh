#!/usr/bin/env bash
# End-to-end smoke test for sms.group v1.
# Self-contained: spawns its own test fixture via coalition.addGroup,
# exercises all 5 group methods, destroys the fixture.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort (set -e). Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
SMOKE_FIXTURES="_sms_test_group _sms_test_unit_1"

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

echo "==> spawn test fixture _sms_test_group"
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
    name = "_sms_test_group",
    task = "Ground Nothing",
    units = {{
      name = "_sms_test_unit_1",
      type = "Soldier M4",
      x = fixture_x,
      y = fixture_y,
      heading = 0,
      skill = sms.K.skill.AVERAGE,
    }},
  }
  coalition.addGroup(country.id.USA, Group.Category.GROUND, group_def)
  return Group.getByName("_sms_test_group") ~= nil
')
echo "${spawn_response}"
echo "${spawn_response}" | grep -q '"return_value":true' \
  || { echo "FAIL: could not spawn _sms_test_group"; exit 1; }

echo "==> is_alive should be true"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):is_alive()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: is_alive: ${result}"; exit 1; }

echo "==> get_name should be _sms_test_group"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):get_name()")
echo "${result}" | grep -q '"return_value":"_sms_test_group"' \
  || { echo "FAIL: get_name: ${result}"; exit 1; }

echo "==> get_coalition should be blue"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):get_coalition()")
echo "${result}" | grep -q '"return_value":"blue"' \
  || { echo "FAIL: get_coalition: ${result}"; exit 1; }

echo "==> get_position should return a {x,y,z} table"
result=$("${DCSSMS}" exec --code '
  local p = sms.group("_sms_test_group"):get_position()
  return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
')
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: get_position: ${result}"; exit 1; }

echo "==> nonexistent group should return nil"
result=$("${DCSSMS}" exec --code "return sms.group(\"_definitely_does_not_exist\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: nonexistent: ${result}"; exit 1; }

echo "==> destroy on alive group should return true"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\"):destroy()")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: destroy: ${result}"; exit 1; }

echo "==> after destroy, lookup should return nil"
result=$("${DCSSMS}" exec --code "return sms.group(\"_sms_test_group\") == nil")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: post-destroy: ${result}"; exit 1; }

echo "==> dcs.log should contain [sms.group] miss line"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.group\]' -n 200)
echo "${log_window}" | grep -q "couldn't find group '_definitely_does_not_exist'" \
  || { echo "FAIL: missing log line for nonexistent group"; echo "${log_window}"; exit 1; }

echo "smoke ok"
