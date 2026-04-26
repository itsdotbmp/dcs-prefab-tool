#!/usr/bin/env bash
# End-to-end smoke test for sms.static v1.
# Exercises the entity wrapper, create happy + sad paths, auto-suffix,
# clone (skipped if no ME static found), pitch/bank warning,
# and sms.area:is_static_in.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

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
"${DCSSMS}" exec --file timer.lua >/dev/null
"${DCSSMS}" exec --file spawn.lua >/dev/null
"${DCSSMS}" exec --file static.lua >/dev/null

# ----------------------------------------------------------------
# Section 1: discover spawn coords from any existing unit
# (statics use the same world coords; we anchor relative to a
# known-livable ground spot in the mission.)
# ----------------------------------------------------------------
echo "==> discover spawn coords from existing mission"
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
# Section 2: sms.static.create — happy path Hangar B
# ----------------------------------------------------------------
echo "==> [create] Hangar B happy path"
expect_eq_string "Hangar B type" "
  local s = sms.static.create({
    name     = '_smoke_static_hangar',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 50, y = 0, z = ${SPAWN_Z} + 50},
    country  = 'USA',
  })
  if not s then return 'NO_HANDLE' end
  if not s:is_alive() then return 'NOT_ALIVE' end
  return s:get_type()
" "Hangar B"

echo "==> [create] cleanup hangar"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_hangar')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 3: entity wrapper getters round-trip
# ----------------------------------------------------------------
echo "==> [entity] getters return sensible values"
expect_true "entity getters" "
  local s = sms.static.create({
    name     = '_smoke_static_entity',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 100, y = 0, z = ${SPAWN_Z} + 100},
    country  = 'USA',
  })
  if not s then return false end
  local name = s:get_name()
  local pos  = s:get_position()
  local coal = s:get_coalition()
  local cnty = s:get_country()
  local typ  = s:get_type()
  return type(name) == 'string'
    and type(pos) == 'table' and type(pos.x) == 'number' and type(pos.y) == 'number' and type(pos.z) == 'number'
    and (coal == 'red' or coal == 'blue' or coal == 'neutral')
    and cnty == 'USA'
    and typ == 'Hangar B'
"

echo "==> [entity] cleanup"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_entity')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 4: DCS-2D coordinate translation
# ----------------------------------------------------------------
echo "==> [create] DCS-2D translation: cfg.position.x -> def.x, cfg.position.z -> def.y"
expect_true "coord translation" "
  local s = sms.static.create({
    name     = '_smoke_static_coords',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 200, y = 0, z = ${SPAWN_Z} + 300},
    country  = 'USA',
  })
  if not s then return false end
  local p = s:get_position()
  return math.abs(p.x - (${SPAWN_X} + 200)) < 1
     and math.abs(p.z - (${SPAWN_Z} + 300)) < 1
"

echo "==> [create] cleanup coords"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_coords')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 5: heading degrees -> radians at spawn
# ----------------------------------------------------------------
echo "==> [create] heading 90 degrees -> ~pi/2 radians applied"
expect_true "heading translated" "
  local s = sms.static.create({
    name     = '_smoke_static_heading',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 400, y = 0, z = ${SPAWN_Z} + 400},
    country  = 'USA',
    heading  = 90,
  })
  if not s then return false end
  local obj = StaticObject.getByName('_smoke_static_heading')
  if not obj then return false end
  local pos = obj:getPosition()
  -- The static's x basis vector encodes its forward direction.
  -- For heading 0 (north), forward is +DCS-2D-y -> our +z; for heading 90 (east),
  -- forward is +DCS-2D-x -> our +x. atan2 derivation matches DCS conv.
  local yaw = math.atan2(pos.x.z, pos.x.x)
  return math.abs(yaw - math.pi/2) < 0.05 or math.abs(yaw + math.pi/2 - 2*math.pi) < 0.05
"

echo "==> [create] cleanup heading"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_heading')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 6: cargo with mass + canCargo
# ----------------------------------------------------------------
echo "==> [create] cargo iso_container with mass + canCargo"
expect_true "cargo spawned" "
  local s = sms.static.create({
    name     = '_smoke_static_cargo',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 500, y = 0, z = ${SPAWN_Z} + 500},
    country  = 'USA',
    category = 'Cargos',
    mass     = 1000,
    canCargo = true,
  })
  if not s then return false end
  return s:is_alive()
"

echo "==> [create] cleanup cargo"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_cargo')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 7: dead = true (wreckage)
# ----------------------------------------------------------------
echo "==> [create] dead=true spawns"
expect_true "dead static spawned" "
  local s = sms.static.create({
    name     = '_smoke_static_dead',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 600, y = 0, z = ${SPAWN_Z} + 600},
    country  = 'USA',
    dead     = true,
  })
  if not s then return false end
  return s:is_alive()
"

echo "==> [create] cleanup dead"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_dead')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 8: auto-suffix on name collision (within static namespace only)
# ----------------------------------------------------------------
echo "==> [auto-suffix] first '_smoke_static_crate' resolves to '_smoke_static_crate'"
expect_eq_string "_smoke_static_crate first" "
  local s = sms.static.create({
    name     = '_smoke_static_crate',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 700, y = 0, z = ${SPAWN_Z} + 700},
    country  = 'USA',
    category = 'Cargos',
  })
  return s and s:get_name() or 'NIL'
" "_smoke_static_crate"

echo "==> [auto-suffix] second '_smoke_static_crate' resolves to '_smoke_static_crate-1'"
expect_eq_string "_smoke_static_crate second" "
  local s = sms.static.create({
    name     = '_smoke_static_crate',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 720, y = 0, z = ${SPAWN_Z} + 720},
    country  = 'USA',
    category = 'Cargos',
  })
  return s and s:get_name() or 'NIL'
" "_smoke_static_crate-1"

echo "==> [auto-suffix] third '_smoke_static_crate' resolves to '_smoke_static_crate-2'"
expect_eq_string "_smoke_static_crate third" "
  local s = sms.static.create({
    name     = '_smoke_static_crate',
    type     = 'iso_container',
    position = {x = ${SPAWN_X} + 740, y = 0, z = ${SPAWN_Z} + 740},
    country  = 'USA',
    category = 'Cargos',
  })
  return s and s:get_name() or 'NIL'
" "_smoke_static_crate-2"

echo "==> [auto-suffix] cleanup"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'_smoke_static_crate', '_smoke_static_crate-1', '_smoke_static_crate-2'}) do
    local s = sms.static(name)
    if s then s:destroy() end
  end
" >/dev/null

# ----------------------------------------------------------------
# Section 9: namespace separation — static & group named the same coexist
# ----------------------------------------------------------------
echo "==> [namespace] static '_smoke_static_ns' and group '_smoke_static_ns' coexist (no over-probing)"
expect_true "namespace separation" "
  local s = sms.static.create({
    name     = '_smoke_static_ns',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 800, y = 0, z = ${SPAWN_Z} + 800},
    country  = 'USA',
  })
  if not s then return false end
  if s:get_name() ~= '_smoke_static_ns' then return false end
  -- Now spawn a group with the same name. It must succeed (separate namespace).
  local g = sms.group.create({
    name     = '_smoke_static_ns',
    position = {x = ${SPAWN_X} + 850, y = 0, z = ${SPAWN_Z} + 850},
    country  = 'USA',
    category = 'ground',
    units    = {{ type = 'AAV7' }},
  })
  if not g then return false end
  -- Both should be alive simultaneously.
  return s:is_alive() and g:is_alive()
"

echo "==> [namespace] cleanup"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_ns')
  if s then s:destroy() end
  local g = sms.group('_smoke_static_ns')
  if g then g:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 10: pitch/bank warn-and-drop
# ----------------------------------------------------------------
echo "==> [pitch/bank] spawn succeeds with pitch present (DCS ignores it)"
expect_true "pitch warned not failed" "
  local s = sms.static.create({
    name     = '_smoke_static_pitch',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 900, y = 0, z = ${SPAWN_Z} + 900},
    country  = 'USA',
    pitch    = 0.5,
    bank     = 0.5,
  })
  if not s then return false end
  return s:is_alive()
"

echo "==> [pitch/bank] cleanup"
"${DCSSMS}" exec --code "
  local s = sms.static('_smoke_static_pitch')
  if s then s:destroy() end
" >/dev/null

# ----------------------------------------------------------------
# Section 11: create — negative paths
# ----------------------------------------------------------------
echo "==> [create] no config -> nil"
expect_true "no config" 'return sms.static.create() == nil'

echo "==> [create] non-table config -> nil"
expect_true "string config" 'return sms.static.create("not a table") == nil'

echo "==> [create] missing name -> nil"
expect_true "no name" "
  return sms.static.create({
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] missing type -> nil"
expect_true "no type" "
  return sms.static.create({
    name = 'no_type',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] missing position -> nil"
expect_true "no position" "
  return sms.static.create({
    name = 'no_pos',
    type = 'Hangar B',
    country = 'USA',
  }) == nil
"

echo "==> [create] missing country -> nil"
expect_true "no country" "
  return sms.static.create({
    name = 'no_country',
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [create] bad country -> nil"
expect_true "bad country" "
  return sms.static.create({
    name = 'bad_country',
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
    country = 'WAKANDA',
  }) == nil
"

echo "==> [create] non-vec3 position -> nil"
expect_true "bad position" "
  return sms.static.create({
    name = 'bad_pos',
    type = 'Hangar B',
    position = 'not a vec3',
    country = 'USA',
  }) == nil
"

echo "==> [create] non-string type -> nil"
expect_true "non-string type" "
  return sms.static.create({
    name = 'numeric_type',
    type = 12345,
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] empty type string -> nil"
expect_true "empty type" "
  return sms.static.create({
    name = 'empty_type',
    type = '',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
  }) == nil
"

echo "==> [create] non-number heading -> nil"
expect_true "non-num heading" "
  return sms.static.create({
    name = 'bad_heading',
    type = 'Hangar B',
    position = {x = 0, y = 0, z = 0},
    country = 'USA',
    heading = 'north',
  }) == nil
"

# ----------------------------------------------------------------
# Section 12: clone — discover ME-defined static template (skip if none)
# ----------------------------------------------------------------
echo "==> [clone] discover ME-defined static name (if any)"
TEMPLATE_NAME=$("${DCSSMS}" exec --code '
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country_entry in ipairs(side.country) do
        if country_entry.static and country_entry.static.group then
          for _, sg in ipairs(country_entry.static.group) do
            if sg.units and sg.units[1] then return sg.name end
          end
        end
      end
    end
  end
  return nil
' | grep -oE '"return_value":"[^"]+"' | grep -oE '"[^"]+"$' | tr -d '"')

if [ -z "${TEMPLATE_NAME}" ]; then
  echo "==> [clone] no ME-defined static found in mission, skipping clone tests (Sections 12-13)"
else
  echo "==> [clone] using template: ${TEMPLATE_NAME}"

  echo "==> [clone] clone with new name + position"
  expect_true "clone alive" "
    local s = sms.static.clone('${TEMPLATE_NAME}', {
      name     = '_smoke_static_clone',
      position = {x = ${SPAWN_X} + 1000, y = 0, z = ${SPAWN_Z} + 1000},
    })
    if not s then return false end
    return s:is_alive()
  "

  echo "==> [clone] cleanup first clone"
  "${DCSSMS}" exec --code "
    local s = sms.static('_smoke_static_clone')
    if s then s:destroy() end
  " >/dev/null

  echo "==> [clone] auto-suffix: first '_smoke_static_dup' resolves to '_smoke_static_dup'"
  expect_eq_string "_smoke_static_dup first" "
    local s = sms.static.clone('${TEMPLATE_NAME}', {
      name     = '_smoke_static_dup',
      position = {x = ${SPAWN_X} + 1100, y = 0, z = ${SPAWN_Z} + 1100},
    })
    return s and s:get_name() or 'NIL'
  " "_smoke_static_dup"

  echo "==> [clone] auto-suffix: second '_smoke_static_dup' resolves to '_smoke_static_dup-1'"
  expect_eq_string "_smoke_static_dup second" "
    local s = sms.static.clone('${TEMPLATE_NAME}', {
      name     = '_smoke_static_dup',
      position = {x = ${SPAWN_X} + 1150, y = 0, z = ${SPAWN_Z} + 1150},
    })
    return s and s:get_name() or 'NIL'
  " "_smoke_static_dup-1"

  echo "==> [clone] cleanup duplicates"
  "${DCSSMS}" exec --code "
    for _, name in ipairs({'_smoke_static_dup', '_smoke_static_dup-1'}) do
      local s = sms.static(name)
      if s then s:destroy() end
    end
  " >/dev/null
fi

# ----------------------------------------------------------------
# Section 13: clone — negative paths
# ----------------------------------------------------------------
echo "==> [clone] missing template -> nil"
expect_true "missing template" "
  return sms.static.clone('_definitely_not_a_template_xyz', {
    name = 'never',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] non-string template_name -> nil"
expect_true "non-string template" "
  return sms.static.clone(12345, {
    name = 'never',
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] non-table overrides -> nil"
expect_true "non-table overrides" "
  return sms.static.clone('any', 'not a table') == nil
"

echo "==> [clone] missing name override -> nil"
expect_true "no override name" "
  return sms.static.clone('any', {
    position = {x = 0, y = 0, z = 0},
  }) == nil
"

echo "==> [clone] missing position override -> nil"
expect_true "no override position" "
  return sms.static.clone('any', {
    name = 'no_pos_override',
  }) == nil
"

# ----------------------------------------------------------------
# Section 14: sms.area:is_static_in
# ----------------------------------------------------------------
echo "==> [area] is_static_in true when static is inside circle"
expect_true "inside circle" "
  local center = {x = ${SPAWN_X} + 2000, y = 0, z = ${SPAWN_Z} + 2000}
  local area = sms.area.create_circular(center, 100)
  if not area then return false end
  local s = sms.static.create({
    name     = '_smoke_static_in',
    type     = 'Hangar B',
    position = {x = center.x, y = 0, z = center.z},
    country  = 'USA',
  })
  if not s then return false end
  return area:is_static_in(s)
"

echo "==> [area] is_static_in false when static is outside circle"
expect_false "outside circle" "
  local center = {x = ${SPAWN_X} + 3000, y = 0, z = ${SPAWN_Z} + 3000}
  local area = sms.area.create_circular(center, 50)
  if not area then return false end
  local s = sms.static.create({
    name     = '_smoke_static_out',
    type     = 'Hangar B',
    position = {x = center.x + 200, y = 0, z = center.z + 200},
    country  = 'USA',
  })
  if not s then return false end
  return area:is_static_in(s)
"

echo "==> [area] cleanup"
"${DCSSMS}" exec --code "
  for _, name in ipairs({'_smoke_static_in', '_smoke_static_out'}) do
    local s = sms.static(name)
    if s then s:destroy() end
  end
" >/dev/null

echo "==> [area] is_static_in non-static handle -> false + log"
expect_false "non-static target" "
  local center = {x = 0, y = 0, z = 0}
  local area = sms.area.create_circular(center, 100)
  return area:is_static_in('not a handle')
"

echo "==> [area] is_static_in non-area handle -> false + log"
expect_false "non-area self" "
  local s = sms.static.create({
    name     = '_smoke_static_typecheck',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 4000, y = 0, z = ${SPAWN_Z} + 4000},
    country  = 'USA',
  })
  if not s then return true end -- if create failed, the typecheck below is moot; treat as 'no false positive'
  -- Pass a non-area first arg by calling sms.area.is_static_in directly.
  local result = sms.area.is_static_in('not an area', s)
  s:destroy()
  return result
"

# ----------------------------------------------------------------
# Section 15: handle methods on dead static -> nil + log
# ----------------------------------------------------------------
echo "==> [entity] get_position on destroyed static -> nil"
expect_true "destroyed get_position nil" "
  local s = sms.static.create({
    name     = '_smoke_static_dead_test',
    type     = 'Hangar B',
    position = {x = ${SPAWN_X} + 5000, y = 0, z = ${SPAWN_Z} + 5000},
    country  = 'USA',
  })
  if not s then return false end
  s:destroy()
  return s:get_position() == nil
"

# ----------------------------------------------------------------
# Section 16: tail-log assertion
# ----------------------------------------------------------------
echo "==> [log] dcs.log should contain [sms.static] line for unknown country"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.static\]' -n 200)
echo "${log_window}" | grep -q "unknown country" \
  || { echo "FAIL: missing log line for unknown country"; echo "${log_window}"; exit 1; }

echo "==> [log] dcs.log should contain [sms.static] pitch/bank warning"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.static\]' -n 200)
echo "${log_window}" | grep -q "pitch/bank" \
  || { echo "FAIL: missing log line for pitch/bank warning"; echo "${log_window}"; exit 1; }

echo "smoke ok"
