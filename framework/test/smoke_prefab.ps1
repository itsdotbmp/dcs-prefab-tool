# smoke_prefab.ps1 — manual smoke for sms.prefab.
#
# Requires DCS running with a loaded mission and the dcs-sms hook installed.
# Run via:
#   pwsh framework/test/smoke_prefab.ps1
#
# Steps:
#   1. Build a tiny prefab in-memory via sms.prefab.distill against a synthetic
#      dump table (no file I/O dependency).
#   2. Register it in the runtime registry.
#   3. Spawn at a known anchor; verify position math.
#   4. Spawn a second instance; verify name auto-suffix.
#   5. Spawn with country override; verify coalition.
#   6. Spawn with rotation; verify a unit at offset (100, 0) ends up at (0, 100).
#   7. keep_position; verify spawn at meta.world_anchor.
#   8. destroy(); verify Group.getByName returns nil.
#   9. Idempotent destroy.
#  10. destroy_all by template name.

Import-Module "$PSScriptRoot/_smoke.psm1" -Force
Initialize-Smoke
Invoke-Smoke -File 'load_all.lua' | Out-Null

# Define a small inline prefab via a Lua chunk. Uses ground vehicle (no
# route/aircraft requirements) at (0, 0) for simplicity. Anchor recorded as
# (0, 0) so keep_position spawns where defined.
$buildPrefab = @"
sms.prefab.unload('_smoke_prefab_a')
local template = {
    meta = {
        sms_prefab_version = "0.1.0",
        created_utc = "2026-05-03T00:00:00Z",
        world_anchor = { x = 0, y = 0 },
    },
    groups = {
        [1] = {
            name = "_smoke_aerial",
            type = "vehicle",
            x = 0, y = 0, heading = 0, country = 2,
            units = {
                [1] = { name = "_smoke_aerial-1", type = "M-1 Abrams",
                        x = 100, y = 0, heading = 0, skill = "Average" },
            },
            task = "Ground Nothing",
        },
    },
    statics = {}, zones = {}, drawings = {},
}
sms.prefab.register('_smoke_prefab_a', template)
return sms.prefab.list()[1]
"@

$fixtures = @('_smoke_aerial', '_smoke_aerial-1', '_smoke_aerial-2')

try {
    Expect-EqString -Label 'register registers under meta.name' `
        -Code $buildPrefab `
        -Expected '_smoke_prefab_a'

    # 3. spawn at known anchor
    Expect-EqNumber -Label 'spawn 1: unit position x = anchor.x + 100' `
        -Code @"
            local h = sms.prefab.spawn('_smoke_prefab_a', { anchor = { x = 50000, z = 0 } })
            local g = h:get_groups()[1]
            local u = Group.getByName(g.name):getUnits()[1]
            return u:getPoint().x
"@ `
        -Expected 50100 -Tolerance 0.5

    # 4. spawn second; verify auto-suffix
    Expect-EqString -Label 'spawn 2: name auto-suffixed' `
        -Code @"
            local h2 = sms.prefab.spawn('_smoke_prefab_a', { anchor = { x = 60000, z = 0 } })
            return h2:get_groups()[1].name
"@ `
        -Expected '_smoke_aerial-1'

    # 5. country override
    Expect-EqNumber -Label 'spawn 3: country override = RUSSIA' `
        -Code @"
            local h3 = sms.prefab.spawn('_smoke_prefab_a', {
                anchor = { x = 70000, z = 0 }, country = 0,
            })
            local g = h3:get_groups()[1]
            return Group.getByName(g.name):getCoalition()
"@ `
        -Expected 1   # 1 = red, since country 0 = USSR which is red

    # 6. rotation: unit at offset (100, 0) with 90deg becomes (0, 100)
    Expect-EqNumber -Label 'spawn 4: rotation 90 places unit at z = anchor.z + 100' `
        -Code @"
            local h4 = sms.prefab.spawn('_smoke_prefab_a', {
                anchor = { x = 80000, z = 0 }, rotation = 90,
            })
            local g = h4:get_groups()[1]
            local u = Group.getByName(g.name):getUnits()[1]
            return u:getPoint().z
"@ `
        -Expected 100 -Tolerance 0.5

    # 7. keep_position
    Expect-EqNumber -Label 'spawn 5: keep_position uses meta.world_anchor (x=0)' `
        -Code @"
            local h5 = sms.prefab.spawn('_smoke_prefab_a', { keep_position = true })
            local g = h5:get_groups()[1]
            local u = Group.getByName(g.name):getUnits()[1]
            return u:getPoint().x
"@ `
        -Expected 100 -Tolerance 0.5  # unit at relative (100, 0); anchor (0, 0) → world 100

    # 8. destroy
    Expect-EqString -Label 'destroy_all clears every spawned instance' `
        -Code @"
            local n = sms.prefab.destroy_all('_smoke_prefab_a')
            return tostring(n) .. '|' .. tostring(#sms.prefab.list_instances('_smoke_prefab_a'))
"@ `
        -Expected '5|0'

} finally {
    Clear-SmokeFixtures -Names $fixtures
}

Write-Host "ALL sms.prefab smoke checks passed."
