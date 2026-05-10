# End-to-end smoke test for sms.unit v1.
# Self-contained: spawns its own test fixture via coalition.addGroup,
# exercises all 7 sms.unit methods plus the new sms.group:get_units(),
# verifies the unit<->group round-trip, then destroys the fixture.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run abort.
# Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
$fixtures = @('_sms_test_unit', '_sms_test_unit_group')

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua' | Out-Null
    Invoke-Smoke -File 'log.lua' | Out-Null
    Invoke-Smoke -File 'group.lua' | Out-Null
    Invoke-Smoke -File 'unit.lua' | Out-Null

    Write-Host "==> spawn test fixture _sms_test_unit_group with unit _sms_test_unit"
    # Try to derive viable spawn coords from an existing mission unit;
    # fall back to {0, 0} if no existing units found.
    $spawnCode = @"
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
"@
    Expect-True -Label 'spawn _sms_test_unit' -Code $spawnCode

    Write-Host "==> is_alive should be true"
    Expect-True -Label 'is_alive' -Code 'return sms.unit("_sms_test_unit"):is_alive()'

    Write-Host "==> get_name should be _sms_test_unit"
    Expect-EqString -Label 'get_name' -Code 'return sms.unit("_sms_test_unit"):get_name()' -Expected '_sms_test_unit'

    Write-Host "==> get_coalition should be blue"
    Expect-EqString -Label 'get_coalition' -Code 'return sms.unit("_sms_test_unit"):get_coalition()' -Expected 'blue'

    Write-Host "==> get_position should return a {x,y,z} table"
    $posCode = @"
local p = sms.unit("_sms_test_unit"):get_position()
return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
"@
    Expect-True -Label 'get_position' -Code $posCode

    Write-Host "==> get_type should be Soldier M4"
    Expect-EqString -Label 'get_type' -Code 'return sms.unit("_sms_test_unit"):get_type()' -Expected 'Soldier M4'

    Write-Host "==> get_heading should be a number in [0, 360)"
    $headingCode = @"
local h = sms.unit("_sms_test_unit"):get_heading()
return type(h) == "number" and h >= 0 and h < 360
"@
    Expect-True -Label 'get_heading' -Code $headingCode

    Write-Host "==> get_pitch should be a number near 0 for a ground unit"
    $pitchCode = @"
local p = sms.unit("_sms_test_unit"):get_pitch()
return type(p) == "number" and math.abs(p) < 5
"@
    Expect-True -Label 'get_pitch' -Code $pitchCode

    Write-Host "==> get_altitude (ASL) should be a number"
    $aslCode = @"
local a = sms.unit("_sms_test_unit"):get_altitude()
return type(a) == "number"
"@
    Expect-True -Label 'get_altitude ASL' -Code $aslCode

    Write-Host "==> get_altitude (AGL) should equal ASL minus terrain height at unit position"
    $aglCode = @"
local u = sms.unit("_sms_test_unit")
local asl = u:get_altitude()
local agl = u:get_altitude(true)
if type(asl) ~= "number" or type(agl) ~= "number" then return false end
local p = Unit.getByName("_sms_test_unit"):getPoint()
local terrain = land.getHeight({x = p.x, y = p.z})
-- (asl - agl) should equal terrain height (within small floating-point margin)
return math.abs((asl - agl) - terrain) < 0.1
"@
    Expect-True -Label 'get_altitude AGL' -Code $aglCode

    Write-Host "==> get_group():get_name() should be _sms_test_unit_group (unit -> group round-trip)"
    Expect-EqString -Label 'get_group round-trip' -Code 'return sms.unit("_sms_test_unit"):get_group():get_name()' -Expected '_sms_test_unit_group'

    Write-Host "==> group:get_units() should return one handle"
    Expect-EqNumber -Label 'get_units count' -Code 'return #sms.group("_sms_test_unit_group"):get_units()' -Expected 1

    Write-Host "==> group:get_units()[1]:get_name() should be _sms_test_unit (group -> unit round-trip)"
    Expect-EqString -Label 'get_units round-trip' -Code 'return sms.group("_sms_test_unit_group"):get_units()[1]:get_name()' -Expected '_sms_test_unit'

    Write-Host "==> nonexistent unit should return nil"
    Expect-True -Label 'nonexistent unit' -Code 'return sms.unit("_definitely_not_a_unit") == nil'

    Write-Host "==> destroy on alive unit should return true"
    Expect-True -Label 'destroy' -Code 'return sms.unit("_sms_test_unit"):destroy()'

    Write-Host "==> after destroy, lookup should return nil"
    Expect-True -Label 'post-destroy' -Code 'return sms.unit("_sms_test_unit") == nil'

    Write-Host "==> dcs.log should contain [sms.unit] miss line"
    Expect-LogContains -Label 'log: nonexistent unit' `
        -Pattern "couldn't find unit '_definitely_not_a_unit'" `
        -Grep '\[sms.unit\]'

    Write-Host "==> cleanup: destroy parent group (best-effort)"
    $cleanupCode = @"
local g = sms.group('_sms_test_unit_group')
if g then g:destroy() end
"@
    Invoke-Smoke -Code $cleanupCode | Out-Null

    Write-SmokeSummary
} finally {
    Clear-SmokeFixtures -Names $fixtures
}
