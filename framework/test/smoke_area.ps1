# End-to-end smoke test for sms.area v1.
# Exercises all 4 construction paths (ME zone, runtime circle, runtime polygon, ME drawing)
# and all 10 methods. ME drawing path is conditional: if no drawing named
# `_sms_test_area_drawing` exists in the mission, those assertions are skipped
# with clear instructions on how to enable them.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded
# that contains at least one ME-defined trigger zone.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run abort.
# Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
$fixtures = @(
    '_sms_test_area_inside_group',
    '_sms_test_area_inside_unit',
    '_sms_test_area_outside_group',
    '_sms_test_area_outside_unit'
)

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua'   | Out-Null
    Invoke-Smoke -File 'log.lua'   | Out-Null
    Invoke-Smoke -File 'utils.lua' | Out-Null
    Invoke-Smoke -File 'group.lua' | Out-Null
    Invoke-Smoke -File 'unit.lua'  | Out-Null
    Invoke-Smoke -File 'area.lua'  | Out-Null
    # Constants catalog (countries, skill, alt_type, units, statics, ...).
    Invoke-Smoke -File 'constants.lua' | Out-Null

    Write-Host "==> discover an ME zone in the mission"
    $zoneInfo = Invoke-Smoke -Code @'
local zones = env.mission and env.mission.triggers and env.mission.triggers.zones
if not zones or #zones == 0 then return nil end
for _, z in ipairs(zones) do
  if z.radius and z.radius > 0 then
    return {name = z.name, x = z.x, y = z.y, radius = z.radius}
  end
end
return nil
'@
    Write-Host ($zoneInfo | ConvertTo-Json -Depth 6 -Compress)
    if ($null -eq $zoneInfo.return_value -or $zoneInfo.return_value -isnot [psobject]) {
        Write-Host "FAIL: no ME circle zone found in mission. Add at least one circle zone in the Mission Editor and reload."
        exit 1
    }

    # Extract zone fields via a separate exec for the name.
    $zoneNameResp = Invoke-Smoke -Code @'
for _, z in ipairs(env.mission.triggers.zones) do
  if z.radius and z.radius > 0 then return z.name end
end
'@
    $ZONE_NAME = [string]$zoneNameResp.return_value
    Write-Host "==> using ME zone: $ZONE_NAME"

    Write-Host "==> spawn fixture groups (one inside zone, one outside)"
    $spawnCode = @"
local zone = trigger.misc.getZone('$ZONE_NAME')
local cx, cz = zone.point.x, zone.point.z
local r = zone.radius

-- inside group: at zone center
coalition.addGroup(country.id.USA, Group.Category.GROUND, {
  name = '_sms_test_area_inside_group',
  task = 'Ground Nothing',
  units = {{name = '_sms_test_area_inside_unit', type = sms.K.units.infantry.Soldier_M4,
            x = cx, y = cz, heading = 0, skill = sms.K.skill.AVERAGE}},
})

-- outside group: 2*radius east of center
coalition.addGroup(country.id.USA, Group.Category.GROUND, {
  name = '_sms_test_area_outside_group',
  task = 'Ground Nothing',
  units = {{name = '_sms_test_area_outside_unit', type = sms.K.units.infantry.Soldier_M4,
            x = cx + 2 * r, y = cz, heading = 0, skill = sms.K.skill.AVERAGE}},
})
return Unit.getByName('_sms_test_area_inside_unit') ~= nil
     and Unit.getByName('_sms_test_area_outside_unit') ~= nil
"@
    Invoke-Smoke -Code $spawnCode | Out-Null
    Expect-True -Label 'fixtures alive' -Code @'
return Unit.getByName('_sms_test_area_inside_unit') ~= nil
   and Unit.getByName('_sms_test_area_outside_unit') ~= nil
'@

    # ----------------------------------------------------------------
    # Section 1: ME zone (circle) construction + method coverage
    # ----------------------------------------------------------------
    Write-Host "==> [me-circle] get_kind = circle"
    Expect-EqString -Label 'me-circle kind' -Code "return sms.area('$ZONE_NAME'):get_kind()" -Expected 'circle'

    Write-Host "==> [me-circle] get_position returns vec3"
    Expect-True -Label 'me-circle position is vec3' -Code @"
local p = sms.area('$ZONE_NAME'):get_position()
return p ~= nil and type(p.x) == 'number' and type(p.y) == 'number' and type(p.z) == 'number'
"@

    Write-Host "==> [me-circle] get_radius is positive number"
    Expect-True -Label 'me-circle radius positive' -Code @"
local r = sms.area('$ZONE_NAME'):get_radius()
return type(r) == 'number' and r > 0
"@

    Write-Host "==> [me-circle] get_vertices on circle returns nil"
    Expect-True -Label 'me-circle get_vertices nil' -Code "return sms.area('$ZONE_NAME'):get_vertices() == nil"

    Write-Host "==> [me-circle] is_vec3_in zone center -> true"
    Expect-True -Label 'me-circle center inside' -Code @"
local a = sms.area('$ZONE_NAME')
local p = a:get_position()
return a:is_vec3_in(p)
"@

    Write-Host "==> [me-circle] is_vec3_in 2*radius away -> false"
    Expect-False -Label 'me-circle far point outside' -Code @"
local a = sms.area('$ZONE_NAME')
local p = a:get_position()
local r = a:get_radius()
return a:is_vec3_in({x = p.x + 2*r, y = 0, z = p.z + 2*r})
"@

    Write-Host "==> [me-circle] is_vec3_in vec2 (missing z) -> false"
    Expect-False -Label 'me-circle vec2 input rejected' -Code @"
return sms.area('$ZONE_NAME'):is_vec3_in({x = 0, y = 0})
"@

    Write-Host "==> [me-circle] is_unit_in inside_unit -> true"
    Expect-True -Label 'me-circle inside unit detected' -Code @"
return sms.area('$ZONE_NAME'):is_unit_in(sms.unit('_sms_test_area_inside_unit'))
"@

    Write-Host "==> [me-circle] is_unit_in outside_unit -> false"
    Expect-False -Label 'me-circle outside unit excluded' -Code @"
return sms.area('$ZONE_NAME'):is_unit_in(sms.unit('_sms_test_area_outside_unit'))
"@

    Write-Host "==> [me-circle] is_unit_in given group handle -> false (wrong type)"
    Expect-False -Label 'me-circle wrong handle type rejected' -Code @"
return sms.area('$ZONE_NAME'):is_unit_in(sms.group('_sms_test_area_inside_group'))
"@

    Write-Host "==> [me-circle] is_any_of_group_in inside_group -> true"
    Expect-True -Label 'me-circle any-of inside' -Code @"
return sms.area('$ZONE_NAME'):is_any_of_group_in(sms.group('_sms_test_area_inside_group'))
"@

    Write-Host "==> [me-circle] is_any_of_group_in outside_group -> false"
    Expect-False -Label 'me-circle any-of outside' -Code @"
return sms.area('$ZONE_NAME'):is_any_of_group_in(sms.group('_sms_test_area_outside_group'))
"@

    Write-Host "==> [me-circle] is_all_of_group_in inside_group -> true"
    Expect-True -Label 'me-circle all-of inside' -Code @"
return sms.area('$ZONE_NAME'):is_all_of_group_in(sms.group('_sms_test_area_inside_group'))
"@

    Write-Host "==> [me-circle] is_all_of_group_in outside_group -> false"
    Expect-False -Label 'me-circle all-of outside' -Code @"
return sms.area('$ZONE_NAME'):is_all_of_group_in(sms.group('_sms_test_area_outside_group'))
"@

    Write-Host "==> [me-circle] get_random_point returns inside-vec3 (5 trials)"
    Expect-True -Label 'me-circle random points inside' -Code @"
local a = sms.area('$ZONE_NAME')
for i = 1, 5 do
  local rp = a:get_random_point()
  if not rp or not a:is_vec3_in(rp) then return false end
end
return true
"@

    Write-Host "==> [me-circle] missing zone returns nil"
    Expect-True -Label 'me-circle missing zone' -Code "return sms.area('_definitely_not_a_zone') == nil"

    # ----------------------------------------------------------------
    # Section 2: Runtime circle
    # ----------------------------------------------------------------
    Write-Host "==> [rt-circle] create_circular returns handle"
    Expect-EqString -Label 'rt-circle kind' -Code "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_kind()" -Expected 'circle'

    Write-Host "==> [rt-circle] get_radius returns 500"
    Expect-EqNumber -Label 'rt-circle radius' -Code "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_radius()" -Expected 500

    Write-Host "==> [rt-circle] get_name returns 'rt'"
    Expect-EqString -Label 'rt-circle name' -Code "return sms.area.create_circular({x=0,y=0,z=0}, 500, 'rt'):get_name()" -Expected 'rt'

    Write-Host "==> [rt-circle] anonymous (no name) -> get_name returns nil"
    Expect-True -Label 'rt-circle anon name nil' -Code @'
return sms.area.create_circular({x=0,y=0,z=0}, 500):get_name() == nil
'@

    Write-Host "==> [rt-circle] is_vec3_in inside point -> true"
    Expect-True -Label 'rt-circle inside' -Code @'
return sms.area.create_circular({x=0,y=0,z=0}, 500):is_vec3_in({x=100,y=0,z=100})
'@

    Write-Host "==> [rt-circle] is_vec3_in outside point -> false"
    Expect-False -Label 'rt-circle outside' -Code @'
return sms.area.create_circular({x=0,y=0,z=0}, 500):is_vec3_in({x=1000,y=0,z=1000})
'@

    Write-Host "==> [rt-circle] invalid center -> nil"
    Expect-True -Label 'rt-circle invalid center' -Code "return sms.area.create_circular('not-a-vec3', 500) == nil"

    Write-Host "==> [rt-circle] negative radius -> nil"
    Expect-True -Label 'rt-circle negative radius' -Code 'return sms.area.create_circular({x=0,y=0,z=0}, -1) == nil'

    Write-Host "==> [rt-circle] zero radius -> nil"
    Expect-True -Label 'rt-circle zero radius' -Code 'return sms.area.create_circular({x=0,y=0,z=0}, 0) == nil'

    # ----------------------------------------------------------------
    # Section 3: Runtime polygon
    # ----------------------------------------------------------------
    Write-Host "==> [rt-poly] create_polygon (1km square) returns polygon"
    Expect-EqString -Label 'rt-poly kind' -Code @'
return sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
}, 'sq'):get_kind()
'@ -Expected 'polygon'

    Write-Host "==> [rt-poly] get_vertices returns 4-element list"
    Expect-EqNumber -Label 'rt-poly vertex count' -Code @'
return #sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
}, 'sq'):get_vertices()
'@ -Expected 4

    Write-Host "==> [rt-poly] get_radius on polygon -> nil"
    Expect-True -Label 'rt-poly radius nil' -Code @'
return sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
}):get_radius() == nil
'@

    Write-Host "==> [rt-poly] get_position returns centroid"
    Expect-True -Label 'rt-poly centroid' -Code @'
local c = sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
}):get_position()
return c.x == 500 and c.z == 500
'@

    Write-Host "==> [rt-poly] is_vec3_in center point -> true"
    Expect-True -Label 'rt-poly center inside' -Code @'
return sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
}):is_vec3_in({x=500,y=0,z=500})
'@

    Write-Host "==> [rt-poly] is_vec3_in near corner inside -> true"
    Expect-True -Label 'rt-poly corner inside' -Code @'
return sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
}):is_vec3_in({x=999,y=0,z=999})
'@

    Write-Host "==> [rt-poly] is_vec3_in outside -> false"
    Expect-False -Label 'rt-poly outside' -Code @'
return sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
}):is_vec3_in({x=1500,y=0,z=500})
'@

    Write-Host "==> [rt-poly] get_random_point inside (5 trials)"
    Expect-True -Label 'rt-poly random inside' -Code @'
local a = sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1000,y=0,z=0}, {x=1000,y=0,z=1000}, {x=0,y=0,z=1000}
})
for i = 1, 5 do
  local rp = a:get_random_point()
  if not rp or not a:is_vec3_in(rp) then return false end
end
return true
'@

    Write-Host "==> [rt-poly] empty vertices -> nil"
    Expect-True -Label 'rt-poly empty rejected' -Code 'return sms.area.create_polygon({}) == nil'

    Write-Host "==> [rt-poly] 2 vertices -> nil"
    Expect-True -Label 'rt-poly 2-vert rejected' -Code @'
return sms.area.create_polygon({{x=0,y=0,z=0}, {x=1,y=0,z=0}}) == nil
'@

    Write-Host "==> [rt-poly] non-vec3 vertex -> nil"
    Expect-True -Label 'rt-poly non-vec3 rejected' -Code @'
return sms.area.create_polygon({
  {x=0,y=0,z=0}, {x=1,y=0,z=0}, 'not a vec3'
}) == nil
'@

    # ----------------------------------------------------------------
    # Section 4: from_drawing (conditional)
    # ----------------------------------------------------------------
    Write-Host "==> [drawing] check for _sms_test_area_drawing in mission"
    $drawingResp = Invoke-Smoke -Code @'
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
'@

    if ($drawingResp.return_value -eq $true) {
        Write-Host "==> [drawing] _sms_test_area_drawing found, exercising from_drawing"
        Expect-EqString -Label 'drawing kind' -Code @'
return sms.area.from_drawing('_sms_test_area_drawing'):get_kind()
'@ -Expected 'polygon'
        Expect-True -Label 'drawing has vertices' -Code @'
local v = sms.area.from_drawing('_sms_test_area_drawing'):get_vertices()
return v ~= nil and #v >= 3
'@
    } else {
        Write-Host "==> [drawing] skipping from_drawing assertions"
        Write-Host "    (to enable, add a freeform polygon drawing named '_sms_test_area_drawing' to the mission)"
    }

    Write-Host "==> [drawing] missing drawing returns nil"
    Expect-True -Label 'drawing missing' -Code "return sms.area.from_drawing('_no_such_drawing_xyz') == nil"

    # ----------------------------------------------------------------
    # Cleanup
    # ----------------------------------------------------------------
    Write-Host "==> cleanup: destroy fixture groups"
    Invoke-Smoke -Code @'
local g1 = sms.group('_sms_test_area_inside_group')
if g1 then g1:destroy() end
local g2 = sms.group('_sms_test_area_outside_group')
if g2 then g2:destroy() end
'@ | Out-Null

    Write-Host "==> dcs.log should contain [sms.area] miss line"
    Expect-LogContains -Label 'log: nonexistent area' `
        -Pattern "couldn't find area '_definitely_not_a_zone'" `
        -Grep '\[sms.area\]'

    Write-Host ""
    Write-Host "ALL smoke_area checks passed."
} finally {
    Clear-SmokeFixtures -Names $fixtures
}
