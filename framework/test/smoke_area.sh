#!/usr/bin/env bash
# End-to-end smoke test for sms.area v1.
# Exercises all 4 construction paths (ME zone, runtime circle, runtime polygon, ME drawing)
# and all 10 methods. ME drawing path is conditional: if no drawing named
# `_sms_test_area_drawing` exists in the mission, those assertions are skipped
# with clear instructions on how to enable them.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded
# that contains at least one ME-defined trigger zone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort (set -e). Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
SMOKE_FIXTURES="_sms_test_area_inside_group _sms_test_area_inside_unit _sms_test_area_outside_group _sms_test_area_outside_unit"

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

# Helpers
expect_true() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_false() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":false' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_eq_string() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
}

expect_eq_number() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":${expected}," \
    || { echo "FAIL: ${label} (expected ${expected}): ${result}"; exit 1; }
}

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file utils.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null
"${DCSSMS}" exec --file area.lua >/dev/null

echo "==> discover an ME zone in the mission"
zone_info=$("${DCSSMS}" exec --code '
  local zones = env.mission and env.mission.triggers and env.mission.triggers.zones
  if not zones or #zones == 0 then return nil end
  for _, z in ipairs(zones) do
    if z.radius and z.radius > 0 then
      return {name = z.name, x = z.x, y = z.y, radius = z.radius}
    end
  end
  return nil
')
echo "${zone_info}"
echo "${zone_info}" | grep -q '"return_value":{' \
  || { echo "FAIL: no ME circle zone found in mission. Add at least one circle zone in the Mission Editor and reload."; exit 1; }

# Extract zone fields via a separate exec for each (jq not assumed to be installed).
ZONE_NAME=$("${DCSSMS}" exec --code '
  for _, z in ipairs(env.mission.triggers.zones) do
    if z.radius and z.radius > 0 then return z.name end
  end
' | sed -n 's/.*"return_value":"\([^"]*\)".*/\1/p')
echo "==> using ME zone: ${ZONE_NAME}"

echo "==> spawn fixture groups (one inside zone, one outside)"
"${DCSSMS}" exec --code "
  local zone = trigger.misc.getZone('${ZONE_NAME}')
  local cx, cz = zone.point.x, zone.point.z
  local r = zone.radius

  -- inside group: at zone center
  coalition.addGroup(country.id.USA, Group.Category.GROUND, {
    name = '_sms_test_area_inside_group',
    task = 'Ground Nothing',
    units = {{name = '_sms_test_area_inside_unit', type = 'Soldier M4',
              x = cx, y = cz, heading = 0, skill = 'Average'}},
  })

  -- outside group: 2*radius east of center
  coalition.addGroup(country.id.USA, Group.Category.GROUND, {
    name = '_sms_test_area_outside_group',
    task = 'Ground Nothing',
    units = {{name = '_sms_test_area_outside_unit', type = 'Soldier M4',
              x = cx + 2 * r, y = cz, heading = 0, skill = 'Average'}},
  })
  return Unit.getByName('_sms_test_area_inside_unit') ~= nil
       and Unit.getByName('_sms_test_area_outside_unit') ~= nil
" >/dev/null
expect_true "fixtures alive" "
  return Unit.getByName('_sms_test_area_inside_unit') ~= nil
     and Unit.getByName('_sms_test_area_outside_unit') ~= nil
"

# ----------------------------------------------------------------
# Section 1: ME zone (circle) construction + method coverage
# ----------------------------------------------------------------
echo "==> [me-circle] get_kind = circle"
expect_eq_string "me-circle kind" "return sms.area('${ZONE_NAME}'):get_kind()" "circle"

echo "==> [me-circle] get_position returns vec3"
expect_true "me-circle position is vec3" "
  local p = sms.area('${ZONE_NAME}'):get_position()
  return p ~= nil and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number'
"

echo "==> [me-circle] get_radius is positive number"
expect_true "me-circle radius positive" "
  local r = sms.area('${ZONE_NAME}'):get_radius()
  return type(r) == 'number' and r > 0
"

echo "==> [me-circle] get_vertices on circle returns nil"
expect_true "me-circle get_vertices nil" "return sms.area('${ZONE_NAME}'):get_vertices() == nil"

echo "==> [me-circle] is_vec3_in zone center -> true"
expect_true "me-circle center inside" "
  local a = sms.area('${ZONE_NAME}')
  local p = a:get_position()
  return a:is_vec3_in(p)
"

echo "==> [me-circle] is_vec3_in 2*radius away -> false"
expect_false "me-circle far point outside" "
  local a = sms.area('${ZONE_NAME}')
  local p = a:get_position()
  local r = a:get_radius()
  return a:is_vec3_in({x = p.x + 2*r, y = 0, z = p.z + 2*r})
"

echo "==> [me-circle] is_vec3_in vec2 (missing z) -> false"
expect_false "me-circle vec2 input rejected" "
  return sms.area('${ZONE_NAME}'):is_vec3_in({x = 0, y = 0})
"

echo "==> [me-circle] is_unit_in inside_unit -> true"
expect_true "me-circle inside unit detected" "
  return sms.area('${ZONE_NAME}'):is_unit_in(sms.unit('_sms_test_area_inside_unit'))
"

echo "==> [me-circle] is_unit_in outside_unit -> false"
expect_false "me-circle outside unit excluded" "
  return sms.area('${ZONE_NAME}'):is_unit_in(sms.unit('_sms_test_area_outside_unit'))
"

echo "==> [me-circle] is_unit_in given group handle -> false (wrong type)"
expect_false "me-circle wrong handle type rejected" "
  return sms.area('${ZONE_NAME}'):is_unit_in(sms.group('_sms_test_area_inside_group'))
"

echo "==> [me-circle] is_any_of_group_in inside_group -> true"
expect_true "me-circle any-of inside" "
  return sms.area('${ZONE_NAME}'):is_any_of_group_in(sms.group('_sms_test_area_inside_group'))
"

echo "==> [me-circle] is_any_of_group_in outside_group -> false"
expect_false "me-circle any-of outside" "
  return sms.area('${ZONE_NAME}'):is_any_of_group_in(sms.group('_sms_test_area_outside_group'))
"

echo "==> [me-circle] is_all_of_group_in inside_group -> true"
expect_true "me-circle all-of inside" "
  return sms.area('${ZONE_NAME}'):is_all_of_group_in(sms.group('_sms_test_area_inside_group'))
"

echo "==> [me-circle] is_all_of_group_in outside_group -> false"
expect_false "me-circle all-of outside" "
  return sms.area('${ZONE_NAME}'):is_all_of_group_in(sms.group('_sms_test_area_outside_group'))
"

echo "==> [me-circle] get_random_point returns inside-vec3 (5 trials)"
expect_true "me-circle random points inside" "
  local a = sms.area('${ZONE_NAME}')
  for i = 1, 5 do
    local rp = a:get_random_point()
    if not rp or not a:is_vec3_in(rp) then return false end
  end
  return true
"

echo "==> [me-circle] missing zone returns nil"
expect_true "me-circle missing zone" "return sms.area('_definitely_not_a_zone') == nil"

# ----------------------------------------------------------------
# Section 2: Runtime circle
# ----------------------------------------------------------------
echo "==> [rt-circle] create_circular returns handle"
expect_eq_string "rt-circle kind" "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_kind()" "circle"

echo "==> [rt-circle] get_radius returns 500"
expect_eq_number "rt-circle radius" "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_radius()" "500"

echo "==> [rt-circle] get_name returns 'rt'"
expect_eq_string "rt-circle name" "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_name()" "rt"

echo "==> [rt-circle] anonymous (no name) -> get_name returns nil"
expect_true "rt-circle anon name nil" "
  return sms.area.create_circular({x=0,y=0,z=0}, 500):get_name() == nil
"

echo "==> [rt-circle] is_vec3_in inside point -> true"
expect_true "rt-circle inside" "
  return sms.area.create_circular({x=0,y=0,z=0}, 500):is_vec3_in({x=100,y=0,z=100})
"

echo "==> [rt-circle] is_vec3_in outside point -> false"
expect_false "rt-circle outside" "
  return sms.area.create_circular({x=0,y=0,z=0}, 500):is_vec3_in({x=1000,y=0,z=1000})
"

echo "==> [rt-circle] invalid center -> nil"
expect_true "rt-circle invalid center" "return sms.area.create_circular('not-a-vec3', 500) == nil"

echo "==> [rt-circle] negative radius -> nil"
expect_true "rt-circle negative radius" "return sms.area.create_circular({x=0,y=0,z=0}, -1) == nil"

echo "==> [rt-circle] zero radius -> nil"
expect_true "rt-circle zero radius" "return sms.area.create_circular({x=0,y=0,z=0}, 0) == nil"

# ----------------------------------------------------------------
# Section 3: Runtime polygon
# ----------------------------------------------------------------
echo "==> [rt-poly] create_polygon (1km square) returns polygon"
expect_eq_string "rt-poly kind" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }, 'sq'):get_kind()
" "polygon"

echo "==> [rt-poly] get_vertices returns 4-element list"
expect_eq_number "rt-poly vertex count" "
  return #sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }, 'sq'):get_vertices()
" "4"

echo "==> [rt-poly] get_radius on polygon -> nil"
expect_true "rt-poly radius nil" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):get_radius() == nil
"

echo "==> [rt-poly] get_position returns centroid"
expect_true "rt-poly centroid" "
  local c = sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):get_position()
  return c.x == 500 and c.z == 500
"

echo "==> [rt-poly] is_vec3_in center point -> true"
expect_true "rt-poly center inside" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):is_vec3_in({x=500,y=0,z=500})
"

echo "==> [rt-poly] is_vec3_in near corner inside -> true"
expect_true "rt-poly corner inside" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):is_vec3_in({x=999,y=0,z=999})
"

echo "==> [rt-poly] is_vec3_in outside -> false"
expect_false "rt-poly outside" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  }):is_vec3_in({x=1500,y=0,z=500})
"

echo "==> [rt-poly] get_random_point inside (5 trials)"
expect_true "rt-poly random inside" "
  local a = sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
  })
  for i = 1, 5 do
    local rp = a:get_random_point()
    if not rp or not a:is_vec3_in(rp) then return false end
  end
  return true
"

echo "==> [rt-poly] empty vertices -> nil"
expect_true "rt-poly empty rejected" "return sms.area.create_polygon({}) == nil"

echo "==> [rt-poly] 2 vertices -> nil"
expect_true "rt-poly 2-vert rejected" "
  return sms.area.create_polygon({{x=0,y=0,z=0}, {x=1,y=0,z=0}}) == nil
"

echo "==> [rt-poly] non-vec3 vertex -> nil"
expect_true "rt-poly non-vec3 rejected" "
  return sms.area.create_polygon({
    {x=0,y=0,z=0}, {x=1,y=0,z=0}, 'not a vec3'
  }) == nil
"

# ----------------------------------------------------------------
# Section 4: from_drawing (conditional)
# ----------------------------------------------------------------
echo "==> [drawing] check for _sms_test_area_drawing in mission"
drawing_present=$("${DCSSMS}" exec --code '
  local d = env.mission and env.mission.drawings
  if not d or not d.layers then return false end
  for _, layer in ipairs(d.layers) do
    if layer.objects then
      for _, obj in ipairs(layer.objects) do
        if obj.name == "_sms_test_area_drawing" then return true end
      end
    end
  end
  return false
')

if echo "${drawing_present}" | grep -q '"return_value":true'; then
  echo "==> [drawing] _sms_test_area_drawing found, exercising from_drawing"
  expect_eq_string "drawing kind" "
    return sms.area.from_drawing('_sms_test_area_drawing'):get_kind()
  " "polygon"
  expect_true "drawing has vertices" "
    local v = sms.area.from_drawing('_sms_test_area_drawing'):get_vertices()
    return v ~= nil and #v >= 3
  "
else
  echo "==> [drawing] skipping from_drawing assertions"
  echo "    (to enable, add a freeform polygon drawing named '_sms_test_area_drawing' to the mission)"
fi

echo "==> [drawing] missing drawing returns nil"
expect_true "drawing missing" "return sms.area.from_drawing('_no_such_drawing_xyz') == nil"

# ----------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------
echo "==> cleanup: destroy fixture groups"
"${DCSSMS}" exec --code "
  local g1 = sms.group('_sms_test_area_inside_group')
  if g1 then g1:destroy() end
  local g2 = sms.group('_sms_test_area_outside_group')
  if g2 then g2:destroy() end
" >/dev/null

echo "==> dcs.log should contain [sms.area] miss line"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.area\]' -n 200)
echo "${log_window}" | grep -q "couldn't find area '_definitely_not_a_zone'" \
  || { echo "FAIL: missing log line for nonexistent area"; echo "${log_window}"; exit 1; }

echo "smoke ok"
