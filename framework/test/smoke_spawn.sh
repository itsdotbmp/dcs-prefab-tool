#!/usr/bin/env bash
# End-to-end smoke test for sms.group.create + sms.group.clone v1.
# Exercises sms.utils conversions, ground/air create, multi-unit offsets,
# heading-degrees translation, auto-suffix, and clone against an ME template.
# Requires: DCS running with the dcs-sms hook installed and a mission with
# at least one ME-defined group (any kind).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort (set -e). Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates. Includes
# auto-suffix variants (tank-1, tank-2, ...) from the auto-suffix
# section, since those are real groups in DCS even though the smoke
# only writes the base name.
SMOKE_FIXTURES="_smoke_spawn_air _smoke_spawn_air_default_speed _smoke_spawn_cap_4 _smoke_spawn_cap_5 _smoke_spawn_cap_ground _smoke_spawn_clone _smoke_spawn_clone_dup _smoke_spawn_heading _smoke_spawn_multi _smoke_spawn_single tank tank-1 tank-2 tank-3 tank-4 reload_tank reload_tank-1 reload_tank-2"

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

echo "==> hook status"
"${DCSSMS}" status

echo "==> load framework files"
"${DCSSMS}" exec --file sms.lua >/dev/null
"${DCSSMS}" exec --file log.lua >/dev/null
"${DCSSMS}" exec --file utils.lua >/dev/null
"${DCSSMS}" exec --file group.lua >/dev/null
"${DCSSMS}" exec --file unit.lua >/dev/null
"${DCSSMS}" exec --file area.lua >/dev/null
"${DCSSMS}" exec --file spawn.lua >/dev/null

# ----------------------------------------------------------------
# Section 1: sms.utils conversion sanity
# ----------------------------------------------------------------
echo "==> [utils] deg_to_rad(180) approximately math.pi"
expect_true "deg_to_rad 180" '
  local r = sms.utils.deg_to_rad(180)
  return math.abs(r - math.pi) < 1e-9
'

echo "==> [utils] rad_to_deg(math.pi) approximately 180"
expect_true "rad_to_deg pi" '
  local d = sms.utils.rad_to_deg(math.pi)
  return math.abs(d - 180) < 1e-9
'

echo "==> [utils] feet_to_meters(1000) approximately 304.8"
expect_true "feet_to_meters 1000" '
  local m = sms.utils.feet_to_meters(1000)
  return math.abs(m - 304.8) < 1e-9
'

echo "==> [utils] meters_to_feet(304.8) approximately 1000"
expect_true "meters_to_feet 304.8" '
  local f = sms.utils.meters_to_feet(304.8)
  return math.abs(f - 1000) < 1e-9
'

echo "==> [utils] round-trip meters_to_feet(feet_to_meters(5000)) == 5000"
expect_true "round-trip" '
  return math.abs(sms.utils.meters_to_feet(sms.utils.feet_to_meters(5000)) - 5000) < 1e-6
'

echo "==> [utils] non-number input returns nil"
expect_true "deg_to_rad nil" 'return sms.utils.deg_to_rad("not a number") == nil'

# ----------------------------------------------------------------
# Section 2: discover spawn coords + reset name counters
# ----------------------------------------------------------------
echo "==> discover spawn coords from existing mission"
spawn_response=$("${DCSSMS}" exec --code '
  local x, z = 0, 0
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then
          local p = units[1]:getPoint()
          x = p.x
          z = p.z
          break
        end
      end
      if x ~= 0 or z ~= 0 then break end
    end
  end
  return {x = x, z = z}
')
echo "${spawn_response}"
echo "${spawn_response}" | grep -q '"return_value":{' \
  || { echo "FAIL: could not discover spawn coords"; exit 1; }

# Extract x/z via separate exec calls for portability (no jq dependency).
SPAWN_X=$("${DCSSMS}" exec --code '
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then return units[1]:getPoint().x end
      end
    end
  end
  return 0
' | grep -oE '"return_value":[-0-9.]+' | grep -oE '[-0-9.]+$')
SPAWN_Z=$("${DCSSMS}" exec --code '
  for _, side in ipairs({coalition.side.BLUE, coalition.side.RED, coalition.side.NEUTRAL}) do
    local groups = coalition.getGroups(side)
    if groups and #groups > 0 then
      for _, g in ipairs(groups) do
        local units = g:getUnits()
        if units and #units > 0 then return units[1]:getPoint().z end
      end
    end
  end
  return 0
' | grep -oE '"return_value":[-0-9.]+' | grep -oE '[-0-9.]+$')
echo "==> using anchor x=${SPAWN_X} z=${SPAWN_Z}"

# ----------------------------------------------------------------
# Section 3: sms.group.create — ground single unit
# ----------------------------------------------------------------
echo "==> [create] ground single AAV-7 alive"
expect_eq_string "single AAV-7 type" "
  local g = sms.group.create({
    name      = '_smoke_spawn_single',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  if not g then return 'NO_HANDLE' end
  return sms.unit('_smoke_spawn_single_1'):get_type()
" "AAV7"

echo "==> [create] cleanup single AAV-7"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_single')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 4: sms.group.create — multi-unit with offsets
# ----------------------------------------------------------------
echo "==> [create] multi-unit AAV-7 group with offsets"
expect_true "3 units spawned" "
  local g = sms.group.create({
    name      = '_smoke_spawn_multi',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {
      { type = 'AAV7', offset = {x = 0, y = 0, z = 0} },
      { type = 'AAV7', offset = {x = 0, y = 0, z = 20} },
      { type = 'AAV7', offset = {x = 0, y = 0, z = 40} },
    },
  })
  if not g then return false end
  return #g:get_units() == 3
"

echo "==> [create] verify offsets translated to world positions"
expect_true "offsets correct" "
  local units = sms.group('_smoke_spawn_multi'):get_units()
  if not units or #units ~= 3 then return false end
  -- Expected world positions: (x, _, z), (x, _, z+20), (x, _, z+40)
  -- Allow floating-point tolerance and terrain-snapped y differences.
  local p1 = units[1]:get_position()
  local p2 = units[2]:get_position()
  local p3 = units[3]:get_position()
  local ok1 = math.abs(p1.x - ${SPAWN_X}) < 1 and math.abs(p1.z - ${SPAWN_Z}) < 1
  local ok2 = math.abs(p2.x - ${SPAWN_X}) < 1 and math.abs(p2.z - (${SPAWN_Z} + 20)) < 1
  local ok3 = math.abs(p3.x - ${SPAWN_X}) < 1 and math.abs(p3.z - (${SPAWN_Z} + 40)) < 1
  return ok1 and ok2 and ok3
"

echo "==> [create] cleanup multi-unit"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_multi')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 5: heading degrees -> radians at spawn
# ----------------------------------------------------------------
echo "==> [create] heading 90 degrees -> ~pi/2 radians on the unit"
expect_true "heading translated" "
  local g = sms.group.create({
    name      = '_smoke_spawn_heading',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7', heading = 90 }},
  })
  if not g then return false end
  -- Read back unit orientation. unit:getPosition() returns a 4x4 matrix-ish table:
  -- {p = {x,y,z}, x = {x,y,z}, y = {x,y,z}, z = {x,y,z}}
  -- The unit's facing yaw (heading angle in radians, 0=N, pi/2=E in DCS conv)
  -- can be derived from the x-vector (forward-facing direction).
  local u = Unit.getByName('_smoke_spawn_heading_1')
  local pos = u:getPosition()
  -- pos.x.z and pos.x.x give us atan2 for yaw.
  local yaw = math.atan2(pos.x.z, pos.x.x)
  -- Expect yaw close to pi/2 (heading 90 = east = +z direction in our vec3 conv,
  -- which is +y in DCS-2D). With sms.utils.deg_to_rad(90) = pi/2, the unit's
  -- forward should be along +z. Tolerance 0.05 rad (~3 deg) for terrain effects.
  return math.abs(yaw - math.pi/2) < 0.05 or math.abs(yaw - math.pi/2 - 2*math.pi) < 0.05
"

echo "==> [create] cleanup heading"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_heading')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 6: sms.group.create — air with altitude
# ----------------------------------------------------------------
echo "==> [create] air F-16 at 5000m altitude"
expect_true "air spawned at altitude" "
  local g = sms.group.create({
    name      = '_smoke_spawn_air',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'airplane',
    units     = {
      {
        type = 'F-16C_50',
        alt = 5000,
        speed = 200,
      }
    },
  })
  if not g then return false end
  local u = Unit.getByName('_smoke_spawn_air_1')
  if not u then return false end
  local p = u:getPoint()
  -- Altitude (DCS world y) should be ~5000m, allow large tolerance for terrain reference.
  return p.y > 4000 and p.y < 6000
"

echo "==> [create] cleanup air"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_air')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 6b: sms.group.create — air with default speed
# ----------------------------------------------------------------
echo "==> [create] air F-16 with no explicit speed (default 200)"
expect_true "air no-speed defaults" "
  local g = sms.group.create({
    name      = '_smoke_spawn_air_default_speed',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'airplane',
    units     = {{ type = 'F-16C_50', alt = 5000 }},
  })
  if not g then return false end
  local u = Unit.getByName('_smoke_spawn_air_default_speed_1')
  return u ~= nil and u:isExist()
"

echo "==> [create] cleanup air-default-speed"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_air_default_speed')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 7: auto-suffix on name collision
# ----------------------------------------------------------------
echo "==> [auto-suffix] first 'tank' resolves to 'tank'"
expect_eq_string "tank first" "
  local g = sms.group.create({
    name      = 'tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "tank"

echo "==> [auto-suffix] second 'tank' resolves to 'tank-1'"
expect_eq_string "tank second" "
  local g = sms.group.create({
    name      = 'tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "tank-1"

echo "==> [auto-suffix] third 'tank' resolves to 'tank-2'"
expect_eq_string "tank third" "
  local g = sms.group.create({
    name      = 'tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "tank-2"

echo "==> [auto-suffix] cleanup"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'tank', 'tank-1', 'tank-2'}) do
    local g = sms.group(name)
    if g then g:destroy() end
  end
" >/dev/null

# ----------------------------------------------------------------
# Section 7b: auto-suffix reload-recovery (regression for issue #8)
# ----------------------------------------------------------------
# spawn.lua's module-private _name_counters table is a hint, not the
# source of truth — reloading the module wipes it, but probing
# Group/Unit.getByName must still discover already-taken slots and
# return the next free suffix. If a future refactor turns the counter
# authoritative (skipping the probe), the bug only surfaces across
# mission reloads. This section forces that scenario by re-execing
# spawn.lua mid-test.
echo "==> [auto-suffix reload] first 'reload_tank' resolves to 'reload_tank'"
expect_eq_string "reload_tank first" "
  local g = sms.group.create({
    name      = 'reload_tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "reload_tank"

echo "==> [auto-suffix reload] second 'reload_tank' resolves to 'reload_tank-1'"
expect_eq_string "reload_tank second" "
  local g = sms.group.create({
    name      = 'reload_tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "reload_tank-1"

echo "==> [auto-suffix reload] reload spawn.lua to wipe _name_counters"
"${DCSSMS}" exec --file spawn.lua >/dev/null

echo "==> [auto-suffix reload] post-reload 'reload_tank' must probe and resolve to 'reload_tank-2'"
# After the reload _name_counters is empty, so the counter would naively
# pick suffix 1 — but 'reload_tank' and 'reload_tank-1' still exist as
# live groups, so probing must skip past them. Asserting 'reload_tank-2'
# (not 'reload_tank' or 'reload_tank-1') proves the probe is still the
# source of truth.
#
# Uses 'reload_tank' (not 'tank') so the test is independent of section
# 7's _name_counters['tank'] state — the counter is module-private and
# persists across cleanup of the live groups.
expect_eq_string "reload_tank post-reload" "
  local g = sms.group.create({
    name      = 'reload_tank',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'ground',
    units     = {{ type = 'AAV7' }},
  })
  return g and g:get_name() or 'NIL'
" "reload_tank-2"

echo "==> [auto-suffix reload] cleanup"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'reload_tank', 'reload_tank-1', 'reload_tank-2'}) do
    local g = sms.group(name)
    if g then g:destroy() end
  end
" >/dev/null

# ----------------------------------------------------------------
# Section 8: sms.group.create — negative paths
# ----------------------------------------------------------------
echo "==> [create] missing config -> nil"
expect_true "no config" 'return sms.group.create() == nil'

echo "==> [create] non-table config -> nil"
expect_true "string config" 'return sms.group.create("not a table") == nil'

echo "==> [create] missing name -> nil"
expect_true "no name" "
  return sms.group.create({
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] missing position -> nil"
expect_true "no position" "
  return sms.group.create({
    name = 'no_pos',
    country = 'USA',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] missing country -> nil"
expect_true "no country" "
  return sms.group.create({
    name = 'no_country',
    position = {x = 0, y = 0, z = 0},
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] bad country -> nil"
expect_true "bad country" "
  return sms.group.create({
    name = 'bad_country',
    position = {x = 0, y = 0, z = 0},
    country = 'WAKANDA',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] bad category -> nil"
expect_true "bad category" "
  return sms.group.create({
    name = 'bad_cat',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    category = 'submarine',
    units = {{ type = 'AAV7' }}
  }) == nil
"

echo "==> [create] missing units -> nil"
expect_true "no units" "
  return sms.group.create({
    name = 'no_units',
    position = {x = 0, y = 0, z = 0},
    country = 'USA'
  }) == nil
"

echo "==> [create] empty units -> nil"
expect_true "empty units" "
  return sms.group.create({
    name = 'empty_units',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    units = {}
  }) == nil
"

echo "==> [create] unit missing type -> nil"
expect_true "unit no type" "
  return sms.group.create({
    name = 'no_type',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    units = {{ heading = 0 }}
  }) == nil
"

echo "==> [create] air category with no alt -> nil"
expect_true "air no alt" "
  return sms.group.create({
    name = 'air_no_alt',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    category = 'airplane',
    units = {{ type = 'F-16C_50' }}
  }) == nil
"

# ----------------------------------------------------------------
# Section 9: sms.group.clone — discover ME template + clone
# ----------------------------------------------------------------
echo "==> [clone] discover an ME-defined group name"
TEMPLATE_NAME=$("${DCSSMS}" exec --code '
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  local cat_keys = {"plane", "helicopter", "vehicle", "ship"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country in ipairs(side.country) do
        for _, ck in ipairs(cat_keys) do
          local cat = country[ck]
          if cat and cat.group then
            for _, g in ipairs(cat.group) do
              return g.name
            end
          end
        end
      end
    end
  end
  return nil
' | grep -oE '"return_value":"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')

if [ -z "${TEMPLATE_NAME}" ]; then
  echo "FAIL: no ME-defined group found in mission. Add at least one group in the Mission Editor and reload."
  exit 1
fi
echo "==> [clone] using template: ${TEMPLATE_NAME}"

echo "==> [clone] clone with new name + position"
expect_true "clone exists" "
  local g = sms.group.clone('${TEMPLATE_NAME}', {
    name = '_smoke_spawn_clone',
    position = {x = ${SPAWN_X} + 1000, y = 0, z = ${SPAWN_Z}},
  })
  if not g then return false end
  return sms.group(g:get_name()):is_alive()
"

echo "==> [clone] cleanup"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_clone')
  if g then g:destroy() end
" >/dev/null

echo "==> [clone] auto-suffix on second clone with same name"
expect_eq_string "first clone resolved name" "
  local g = sms.group.clone('${TEMPLATE_NAME}', {
    name = '_smoke_spawn_clone_dup',
    position = {x = ${SPAWN_X} + 2000, y = 0, z = ${SPAWN_Z}},
  })
  return g and g:get_name() or 'NIL'
" "_smoke_spawn_clone_dup"

expect_eq_string "second clone resolved name with suffix" "
  local g = sms.group.clone('${TEMPLATE_NAME}', {
    name = '_smoke_spawn_clone_dup',
    position = {x = ${SPAWN_X} + 3000, y = 0, z = ${SPAWN_Z}},
  })
  return g and g:get_name() or 'NIL'
" "_smoke_spawn_clone_dup-1"

echo "==> [clone] cleanup duplicates"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'_smoke_spawn_clone_dup', '_smoke_spawn_clone_dup-1'}) do
    local g = sms.group(name)
    if g then g:destroy() end
  end
" >/dev/null

echo "==> [clone] missing template -> nil"
expect_true "missing template" "
  return sms.group.clone('_definitely_not_a_template_xyz', {
    name = 'never',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] missing name override -> nil"
expect_true "no override name" "
  return sms.group.clone('${TEMPLATE_NAME}', {
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] missing position override -> nil"
expect_true "no override position" "
  return sms.group.clone('${TEMPLATE_NAME}', {
    name = 'no_pos_override',
  }) == nil
"

# ----------------------------------------------------------------
# Section 10: log assertion
# ----------------------------------------------------------------
echo "==> [log] dcs.log should contain [sms.spawn] line for unknown country"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.spawn\]' -n 200)
echo "${log_window}" | grep -q "unknown country" \
  || { echo "FAIL: missing log line for unknown country"; echo "${log_window}"; exit 1; }

# ----------------------------------------------------------------
# Section 11: aircraft 4-unit cap (issue #5)
# DCS silently truncates aircraft groups above 4 units. Framework
# rejects with log + nil rather than auto-truncating; the cap applies
# to airplane and helicopter categories.
# ----------------------------------------------------------------
echo "==> [create] 4-unit airplane group accepted (at the cap)"
expect_true "4 air units ok" "
  local g = sms.group.create({
    name      = '_smoke_spawn_cap_4',
    position  = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country   = 'USA',
    category  = 'airplane',
    units     = {
      { type = 'F-16C_50', alt = 5000 },
      { type = 'F-16C_50', alt = 5000 },
      { type = 'F-16C_50', alt = 5000 },
      { type = 'F-16C_50', alt = 5000 },
    },
  })
  return g ~= nil
"

echo "==> [create] cleanup 4-aircraft cap test"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_cap_4')
  if g then g:destroy() end
" >/dev/null

echo "==> [create] 5-unit airplane group rejected (above the cap) -> nil"
expect_true "5 air units rejected" "
  return sms.group.create({
    name = '_smoke_spawn_cap_5',
    position = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country = 'USA',
    category = 'airplane',
    units = {
      { type = 'F-16C_50', alt = 5000 },
      { type = 'F-16C_50', alt = 5000 },
      { type = 'F-16C_50', alt = 5000 },
      { type = 'F-16C_50', alt = 5000 },
      { type = 'F-16C_50', alt = 5000 },
    },
  }) == nil
"

echo "==> [create] 24-unit ground group accepted (cap is air-only)"
expect_true "ground large group ok" "
  local units = {}
  for i = 1, 8 do
    units[i] = { type = 'AAV7', offset = {x = 0, y = 0, z = i * 20} }
  end
  local g = sms.group.create({
    name     = '_smoke_spawn_cap_ground',
    position = {x = ${SPAWN_X}, y = 0, z = ${SPAWN_Z}},
    country  = 'USA',
    category = 'ground',
    units    = units,
  })
  return g ~= nil
"

echo "==> [create] cleanup ground cap test"
"${DCSSMS}" exec --code "
  local g = sms.group('_smoke_spawn_cap_ground')
  if g then g:destroy() end
" >/dev/null

echo "smoke ok"
