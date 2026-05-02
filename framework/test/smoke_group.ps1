# End-to-end smoke test for sms.group v1.
# Self-contained: spawns its own test fixture via coalition.addGroup,
# exercises all 5 group methods, destroys the fixture.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run abort.
# Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
$fixtures = @('_sms_test_group', '_sms_test_unit_1')

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua' | Out-Null
    Invoke-Smoke -File 'log.lua' | Out-Null
    Invoke-Smoke -File 'group.lua' | Out-Null

    Write-Host "==> spawn test fixture _sms_test_group"
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
"@
    Expect-True -Label 'spawn _sms_test_group' -Code $spawnCode

    Write-Host "==> is_alive should be true"
    Expect-True -Label 'is_alive' -Code 'return sms.group("_sms_test_group"):is_alive()'

    Write-Host "==> get_name should be _sms_test_group"
    Expect-EqString -Label 'get_name' -Code 'return sms.group("_sms_test_group"):get_name()' -Expected '_sms_test_group'

    Write-Host "==> get_coalition should be blue"
    Expect-EqString -Label 'get_coalition' -Code 'return sms.group("_sms_test_group"):get_coalition()' -Expected 'blue'

    Write-Host "==> get_position should return a {x,y,z} table"
    $posCode = @"
local p = sms.group("_sms_test_group"):get_position()
return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
"@
    Expect-True -Label 'get_position' -Code $posCode

    Write-Host "==> nonexistent group should return nil"
    Expect-True -Label 'nonexistent' -Code 'return sms.group("_definitely_does_not_exist") == nil'

    Write-Host "==> destroy on alive group should return true"
    Expect-True -Label 'destroy' -Code 'return sms.group("_sms_test_group"):destroy()'

    Write-Host "==> after destroy, lookup should return nil"
    Expect-True -Label 'post-destroy' -Code 'return sms.group("_sms_test_group") == nil'

    Write-Host "==> dcs.log should contain [sms.group] miss line"
    Expect-LogContains -Label 'log: nonexistent group' `
        -Pattern "couldn't find group '_definitely_does_not_exist'" `
        -Grep '\[sms.group\]'

    Write-Host ""
    Write-Host "ALL smoke_group checks passed."
} finally {
    Clear-SmokeFixtures -Names $fixtures
}
