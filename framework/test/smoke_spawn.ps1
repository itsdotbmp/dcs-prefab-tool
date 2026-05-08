# End-to-end smoke test for sms.group.create + sms.group.clone v1.
# Exercises sms.utils conversions, ground/air create, multi-unit offsets,
# heading-degrees translation, auto-suffix, and clone against an ME template.
# Requires: DCS running with the dcs-sms hook installed and a mission with
# at least one ME-defined group (any kind).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort. Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates. Includes
# auto-suffix variants (tank-1, tank-2, ...) from the auto-suffix
# section, since those are real groups in DCS even though the smoke
# only writes the base name.
$fixtures = @(
    '_smoke_spawn_air',
    '_smoke_spawn_air_default_speed',
    '_smoke_spawn_cap_4',
    '_smoke_spawn_cap_5',
    '_smoke_spawn_cap_ground',
    '_smoke_spawn_clone',
    '_smoke_spawn_clone_default_pos',
    '_smoke_spawn_clone_dup',
    '_smoke_spawn_clone_dup-1',
    '_smoke_spawn_heading',
    '_smoke_spawn_multi',
    '_smoke_spawn_single',
    'tank',
    'tank-1',
    'tank-2',
    'tank-3',
    'tank-4',
    'reload_tank',
    'reload_tank-1',
    'reload_tank-2'
)

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua' | Out-Null
    Invoke-Smoke -File 'log.lua' | Out-Null
    Invoke-Smoke -File 'utils.lua' | Out-Null
    Invoke-Smoke -File 'group.lua' | Out-Null
    Invoke-Smoke -File 'unit.lua' | Out-Null
    Invoke-Smoke -File 'area.lua' | Out-Null
    Invoke-Smoke -File 'group_spawn.lua' | Out-Null

    # ----------------------------------------------------------------
    # Section 1: sms.utils conversion sanity
    # ----------------------------------------------------------------
    Write-Host "==> [utils] deg_to_rad(180) approximately math.pi"
    Expect-True -Label 'deg_to_rad 180' -Code @'
local r = sms.utils.deg_to_rad(180)
return math.abs(r - math.pi) < 1e-9
'@

    Write-Host "==> [utils] rad_to_deg(math.pi) approximately 180"
    Expect-True -Label 'rad_to_deg pi' -Code @'
local d = sms.utils.rad_to_deg(math.pi)
return math.abs(d - 180) < 1e-9
'@

    Write-Host "==> [utils] feet_to_meters(1000) approximately 304.8"
    Expect-True -Label 'feet_to_meters 1000' -Code @'
local m = sms.utils.feet_to_meters(1000)
return math.abs(m - 304.8) < 1e-9
'@

    Write-Host "==> [utils] meters_to_feet(304.8) approximately 1000"
    Expect-True -Label 'meters_to_feet 304.8' -Code @'
local f = sms.utils.meters_to_feet(304.8)
return math.abs(f - 1000) < 1e-9
'@

    Write-Host "==> [utils] round-trip meters_to_feet(feet_to_meters(5000)) == 5000"
    Expect-True -Label 'round-trip' -Code @'
return math.abs(sms.utils.meters_to_feet(sms.utils.feet_to_meters(5000)) - 5000) < 1e-6
'@

    Write-Host "==> [utils] non-number input returns nil"
    Expect-True -Label 'deg_to_rad nil' -Code 'return sms.utils.deg_to_rad("not a number") == nil'

    # ----------------------------------------------------------------
    # Section 2: discover spawn coords + reset name counters
    # ----------------------------------------------------------------
    Write-Host "==> discover spawn coords from existing mission"
    $spawnResponse = Invoke-Smoke -Code @'
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
'@
    if (-not $spawnResponse.return_value -or $null -eq $spawnResponse.return_value.x) {
        Write-Host "FAIL: could not discover spawn coords"
        exit 1
    }
    $SPAWN_X = [double]$spawnResponse.return_value.x
    $SPAWN_Z = [double]$spawnResponse.return_value.z
    Write-Host "==> using anchor x=$SPAWN_X z=$SPAWN_Z"

    # ----------------------------------------------------------------
    # Section 3: sms.group.create — ground single unit
    # ----------------------------------------------------------------
    Write-Host "==> [create] ground single AAV-7 alive"
    Expect-EqString -Label 'single AAV-7 type' -Code @"
local g = sms.group.create({
  name      = '_smoke_spawn_single',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7 }},
})
if not g then return 'NO_HANDLE' end
return sms.unit('_smoke_spawn_single_1'):get_type()
"@ -Expected 'AAV7'

    Write-Host "==> [create] cleanup single AAV-7"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_single')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 4: sms.group.create — multi-unit with offsets
    # ----------------------------------------------------------------
    Write-Host "==> [create] multi-unit AAV-7 group with offsets"
    Expect-True -Label '3 units spawned' -Code @"
local g = sms.group.create({
  name      = '_smoke_spawn_multi',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {
    { type = sms.K.units.armor.apc.AAV7, offset = {x = 0, y = 0, z = 0} },
    { type = sms.K.units.armor.apc.AAV7, offset = {x = 0, y = 0, z = 20} },
    { type = sms.K.units.armor.apc.AAV7, offset = {x = 0, y = 0, z = 40} },
  },
})
if not g then return false end
return #g:get_units() == 3
"@

    Write-Host "==> [create] verify offsets translated to world positions"
    Expect-True -Label 'offsets correct' -Code @"
local units = sms.group('_smoke_spawn_multi'):get_units()
if not units or #units ~= 3 then return false end
-- Expected world positions: (x, _, z), (x, _, z+20), (x, _, z+40)
-- Allow floating-point tolerance and terrain-snapped y differences.
local p1 = units[1]:get_position()
local p2 = units[2]:get_position()
local p3 = units[3]:get_position()
local ok1 = math.abs(p1.x - $SPAWN_X) < 1 and math.abs(p1.z - $SPAWN_Z) < 1
local ok2 = math.abs(p2.x - $SPAWN_X) < 1 and math.abs(p2.z - ($SPAWN_Z + 20)) < 1
local ok3 = math.abs(p3.x - $SPAWN_X) < 1 and math.abs(p3.z - ($SPAWN_Z + 40)) < 1
return ok1 and ok2 and ok3
"@

    Write-Host "==> [create] cleanup multi-unit"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_multi')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 5: heading degrees -> radians at spawn
    # ----------------------------------------------------------------
    Write-Host "==> [create] heading 90 degrees -> ~pi/2 radians on the unit"
    Expect-True -Label 'heading translated' -Code @"
local g = sms.group.create({
  name      = '_smoke_spawn_heading',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7, heading = 90 }},
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
"@

    Write-Host "==> [create] cleanup heading"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_heading')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 6: sms.group.create — air with altitude
    # ----------------------------------------------------------------
    Write-Host "==> [create] air F-16 at 5000m altitude"
    Expect-True -Label 'air spawned at altitude' -Code @"
local g = sms.group.create({
  name      = '_smoke_spawn_air',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.AIRPLANE,
  units     = {
    {
      type = sms.K.units.planes.F_16C_50,
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
"@

    Write-Host "==> [create] cleanup air"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_air')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 6b: sms.group.create — air with default speed
    # ----------------------------------------------------------------
    Write-Host "==> [create] air F-16 with no explicit speed (default 200)"
    Expect-True -Label 'air no-speed defaults' -Code @"
local g = sms.group.create({
  name      = '_smoke_spawn_air_default_speed',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.AIRPLANE,
  units     = {{ type = sms.K.units.planes.F_16C_50, alt = 5000 }},
})
if not g then return false end
local u = Unit.getByName('_smoke_spawn_air_default_speed_1')
return u ~= nil and u:isExist()
"@

    Write-Host "==> [create] cleanup air-default-speed"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_air_default_speed')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 7: auto-suffix on name collision
    # ----------------------------------------------------------------
    Write-Host "==> [auto-suffix] first 'tank' resolves to 'tank'"
    Expect-EqString -Label 'tank first' -Code @"
local g = sms.group.create({
  name      = 'tank',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7 }},
})
return g and g:get_name() or 'NIL'
"@ -Expected 'tank'

    Write-Host "==> [auto-suffix] second 'tank' resolves to 'tank-1'"
    Expect-EqString -Label 'tank second' -Code @"
local g = sms.group.create({
  name      = 'tank',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7 }},
})
return g and g:get_name() or 'NIL'
"@ -Expected 'tank-1'

    Write-Host "==> [auto-suffix] third 'tank' resolves to 'tank-2'"
    Expect-EqString -Label 'tank third' -Code @"
local g = sms.group.create({
  name      = 'tank',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7 }},
})
return g and g:get_name() or 'NIL'
"@ -Expected 'tank-2'

    Write-Host "==> [auto-suffix] cleanup"
    Invoke-Smoke -Code @'
for _, name in ipairs({'tank', 'tank-1', 'tank-2'}) do
  local g = sms.group(name)
  if g then g:destroy() end
end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 7b: auto-suffix reload-recovery (regression for issue #8)
    # ----------------------------------------------------------------
    # group_spawn.lua's module-private _name_counters table is a hint, not the
    # source of truth — reloading the module wipes it, but probing
    # Group/Unit.getByName must still discover already-taken slots and
    # return the next free suffix. If a future refactor turns the counter
    # authoritative (skipping the probe), the bug only surfaces across
    # mission reloads. This section forces that scenario by re-execing
    # group_spawn.lua mid-test.
    Write-Host "==> [auto-suffix reload] first 'reload_tank' resolves to 'reload_tank'"
    Expect-EqString -Label 'reload_tank first' -Code @"
local g = sms.group.create({
  name      = 'reload_tank',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7 }},
})
return g and g:get_name() or 'NIL'
"@ -Expected 'reload_tank'

    Write-Host "==> [auto-suffix reload] second 'reload_tank' resolves to 'reload_tank-1'"
    Expect-EqString -Label 'reload_tank second' -Code @"
local g = sms.group.create({
  name      = 'reload_tank',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7 }},
})
return g and g:get_name() or 'NIL'
"@ -Expected 'reload_tank-1'

    Write-Host "==> [auto-suffix reload] reload group_spawn.lua to wipe _name_counters"
    Invoke-Smoke -File 'group_spawn.lua' | Out-Null

    Write-Host "==> [auto-suffix reload] post-reload 'reload_tank' must probe and resolve to 'reload_tank-2'"
    # After the reload _name_counters is empty, so the counter would naively
    # pick suffix 1 — but 'reload_tank' and 'reload_tank-1' still exist as
    # live groups, so probing must skip past them. Asserting 'reload_tank-2'
    # (not 'reload_tank' or 'reload_tank-1') proves the probe is still the
    # source of truth.
    #
    # Uses 'reload_tank' (not 'tank') so the test is independent of section
    # 7's _name_counters['tank'] state — the counter is module-private and
    # persists across cleanup of the live groups.
    Expect-EqString -Label 'reload_tank post-reload' -Code @"
local g = sms.group.create({
  name      = 'reload_tank',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = sms.K.units.armor.apc.AAV7 }},
})
return g and g:get_name() or 'NIL'
"@ -Expected 'reload_tank-2'

    Write-Host "==> [auto-suffix reload] cleanup"
    Invoke-Smoke -Code @'
for _, name in ipairs({'reload_tank', 'reload_tank-1', 'reload_tank-2'}) do
  local g = sms.group(name)
  if g then g:destroy() end
end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 8: sms.group.create — negative paths
    # ----------------------------------------------------------------
    Write-Host "==> [create] missing config -> nil"
    Expect-True -Label 'no config' -Code 'return sms.group.create() == nil'

    Write-Host "==> [create] non-table config -> nil"
    Expect-True -Label 'string config' -Code 'return sms.group.create("not a table") == nil'

    Write-Host "==> [create] missing name -> nil"
    Expect-True -Label 'no name' -Code @'
return sms.group.create({
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  units = {{ type = sms.K.units.armor.apc.AAV7 }}
}) == nil
'@

    Write-Host "==> [create] missing position -> nil"
    Expect-True -Label 'no position' -Code @'
return sms.group.create({
  name = 'no_pos',
  country = sms.K.countries.USA,
  units = {{ type = sms.K.units.armor.apc.AAV7 }}
}) == nil
'@

    Write-Host "==> [create] missing country -> nil"
    Expect-True -Label 'no country' -Code @'
return sms.group.create({
  name = 'no_country',
  position = {x = 0, y = 0, z = 0},
  units = {{ type = sms.K.units.armor.apc.AAV7 }}
}) == nil
'@

    Write-Host "==> [create] bad country -> nil"
    Expect-True -Label 'bad country' -Code @'
return sms.group.create({
  name = 'bad_country',
  position = {x = 0, y = 0, z = 0},
  country = 'WAKANDA',
  units = {{ type = sms.K.units.armor.apc.AAV7 }}
}) == nil
'@

    Write-Host "==> [create] bad category -> nil"
    Expect-True -Label 'bad category' -Code @'
return sms.group.create({
  name = 'bad_cat',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  category = 'submarine',
  units = {{ type = sms.K.units.armor.apc.AAV7 }}
}) == nil
'@

    Write-Host "==> [create] missing units -> nil"
    Expect-True -Label 'no units' -Code @'
return sms.group.create({
  name = 'no_units',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA
}) == nil
'@

    Write-Host "==> [create] empty units -> nil"
    Expect-True -Label 'empty units' -Code @'
return sms.group.create({
  name = 'empty_units',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  units = {}
}) == nil
'@

    Write-Host "==> [create] unit missing type -> nil"
    Expect-True -Label 'unit no type' -Code @'
return sms.group.create({
  name = 'no_type',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  units = {{ heading = 0 }}
}) == nil
'@

    Write-Host "==> [create] air category with no alt -> nil"
    Expect-True -Label 'air no alt' -Code @'
return sms.group.create({
  name = 'air_no_alt',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units = {{ type = sms.K.units.planes.F_16C_50 }}
}) == nil
'@

    # ----------------------------------------------------------------
    # Section 9: sms.group.clone — discover ME template + clone
    # ----------------------------------------------------------------
    Write-Host "==> [clone] discover an ME-defined group name"
    $templateResp = Invoke-Smoke -Code @'
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
'@
    $TEMPLATE_NAME = $templateResp.return_value
    if (-not $TEMPLATE_NAME) {
        Write-Host "FAIL: no ME-defined group found in mission. Add at least one group in the Mission Editor and reload."
        exit 1
    }
    Write-Host "==> [clone] using template: $TEMPLATE_NAME"

    Write-Host "==> [clone] clone with new name + position"
    Expect-True -Label 'clone exists' -Code @"
local g = sms.group.clone('$TEMPLATE_NAME', {
  name = '_smoke_spawn_clone',
  position = {x = $SPAWN_X + 1000, y = 0, z = $SPAWN_Z},
})
if not g then return false end
return sms.group(g:get_name()):is_alive()
"@

    Write-Host "==> [clone] cleanup"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_clone')
if g then g:destroy() end
'@ | Out-Null

    Write-Host "==> [clone] auto-suffix on second clone with same name"
    Expect-EqString -Label 'first clone resolved name' -Code @"
local g = sms.group.clone('$TEMPLATE_NAME', {
  name = '_smoke_spawn_clone_dup',
  position = {x = $SPAWN_X + 2000, y = 0, z = $SPAWN_Z},
})
return g and g:get_name() or 'NIL'
"@ -Expected '_smoke_spawn_clone_dup'

    Expect-EqString -Label 'second clone resolved name with suffix' -Code @"
local g = sms.group.clone('$TEMPLATE_NAME', {
  name = '_smoke_spawn_clone_dup',
  position = {x = $SPAWN_X + 3000, y = 0, z = $SPAWN_Z},
})
return g and g:get_name() or 'NIL'
"@ -Expected '_smoke_spawn_clone_dup-1'

    Write-Host "==> [clone] cleanup duplicates"
    Invoke-Smoke -Code @'
for _, name in ipairs({'_smoke_spawn_clone_dup', '_smoke_spawn_clone_dup-1'}) do
  local g = sms.group(name)
  if g then g:destroy() end
end
'@ | Out-Null

    Write-Host "==> [clone] missing template -> nil"
    Expect-True -Label 'missing template' -Code @'
return sms.group.clone('_definitely_not_a_template_xyz', {
  name = 'never',
  position = {x = 0, y = 0, z = 0},
}) == nil
'@

    Write-Host "==> [clone] missing name override -> nil"
    Expect-True -Label 'no override name' -Code @"
return sms.group.clone('$TEMPLATE_NAME', {
  position = {x = 0, y = 0, z = 0},
}) == nil
"@

    Write-Host "==> [clone] missing position override -> spawns at template's ME anchor"
    Expect-True -Label 'no override position' -Code @"
local g = sms.group.clone('$TEMPLATE_NAME', {
  name = '_smoke_spawn_clone_default_pos',
})
return g ~= nil
"@

    Write-Host "==> [clone] cleanup default-position clone"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_clone_default_pos')
if g then g:destroy() end
'@ | Out-Null

    Write-Host "==> [clone] non-vec3 position override -> nil"
    Expect-True -Label 'bad position type' -Code @"
return sms.group.clone('$TEMPLATE_NAME', {
  name = 'bad_pos_override',
  position = 'not a vec3',
}) == nil
"@

    # ----------------------------------------------------------------
    # Section 10: log assertion
    # ----------------------------------------------------------------
    Write-Host "==> [log] dcs.log should contain [sms.spawn] line for unknown country"
    Expect-LogContains -Label 'log: unknown country' -Pattern 'unknown country' -Grep '\[sms.spawn\]'

    # ----------------------------------------------------------------
    # Section 11: aircraft 4-unit cap (issue #5)
    # DCS silently truncates aircraft groups above 4 units. Framework
    # rejects with log + nil rather than auto-truncating; the cap applies
    # to airplane and helicopter categories.
    # ----------------------------------------------------------------
    Write-Host "==> [create] 4-unit airplane group accepted (at the cap)"
    Expect-True -Label '4 air units ok' -Code @"
local g = sms.group.create({
  name      = '_smoke_spawn_cap_4',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.AIRPLANE,
  units     = {
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
  },
})
return g ~= nil
"@

    Write-Host "==> [create] cleanup 4-aircraft cap test"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_cap_4')
if g then g:destroy() end
'@ | Out-Null

    Write-Host "==> [create] 5-unit airplane group rejected (above the cap) -> nil"
    Expect-True -Label '5 air units rejected' -Code @"
return sms.group.create({
  name = '_smoke_spawn_cap_5',
  position = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units = {
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
    { type = sms.K.units.planes.F_16C_50, alt = 5000 },
  },
}) == nil
"@

    Write-Host "==> [create] 24-unit ground group accepted (cap is air-only)"
    Expect-True -Label 'ground large group ok' -Code @"
local units = {}
for i = 1, 8 do
  units[i] = { type = sms.K.units.armor.apc.AAV7, offset = {x = 0, y = 0, z = i * 20} }
end
local g = sms.group.create({
  name     = '_smoke_spawn_cap_ground',
  position = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country  = sms.K.countries.USA,
  category = sms.K.category.GROUND,
  units    = units,
})
return g ~= nil
"@

    Write-Host "==> [create] cleanup ground cap test"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_spawn_cap_ground')
if g then g:destroy() end
'@ | Out-Null

    Write-SmokeSummary
}
finally {
    Clear-SmokeFixtures -Names $fixtures
}
