# End-to-end smoke test for sms.static v1.
# Exercises the entity wrapper, create happy + sad paths, auto-suffix,
# clone (skipped if no ME static found),
# and sms.area:is_static_in.
# Requires: DCS running with the dcs-sms hook installed and a mission loaded.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run abort.
# Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
$fixtures = @(
    '_smoke_static_cargo',
    '_smoke_static_clone',
    '_smoke_static_coords',
    '_smoke_static_crate',
    '_smoke_static_crate-1',
    '_smoke_static_crate-2',
    '_smoke_static_dead',
    '_smoke_static_dup',
    '_smoke_static_dup-1',
    '_smoke_static_entity',
    '_smoke_static_hangar',
    '_smoke_static_heading',
    '_smoke_static_in',
    '_smoke_static_ns',
    '_smoke_static_out',
    '_smoke_static_postdestroy',
    '_smoke_static_typecheck'
)

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua'          | Out-Null
    Invoke-Smoke -File 'log.lua'          | Out-Null
    Invoke-Smoke -File 'utils.lua'        | Out-Null
    Invoke-Smoke -File 'group.lua'        | Out-Null
    Invoke-Smoke -File 'unit.lua'         | Out-Null
    Invoke-Smoke -File 'area.lua'         | Out-Null
    Invoke-Smoke -File 'timer.lua'        | Out-Null
    Invoke-Smoke -File 'group_spawn.lua'  | Out-Null
    Invoke-Smoke -File 'static.lua'       | Out-Null

    # ----------------------------------------------------------------
    # Section 1: discover spawn coords from any existing unit
    # (statics use the same world coords; we anchor relative to a
    # known-livable ground spot in the mission.)
    # ----------------------------------------------------------------
    Write-Host "==> discover spawn coords from existing mission"
    $spawnXResp = Invoke-Smoke -Code @'
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
'@
    $SPAWN_X = [double]$spawnXResp.return_value

    $spawnZResp = Invoke-Smoke -Code @'
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
'@
    $SPAWN_Z = [double]$spawnZResp.return_value

    Write-Host "==> using anchor x=$SPAWN_X z=$SPAWN_Z"

    # ----------------------------------------------------------------
    # Section 2: sms.static.create — happy path Hangar B
    # ----------------------------------------------------------------
    Write-Host "==> [create] Hangar B happy path"
    Expect-EqString -Label "Hangar B type" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_hangar',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 50, y = 0, z = $SPAWN_Z + 50},
  country  = sms.K.countries.USA,
})
if not s then return 'NO_HANDLE' end
if not s:is_alive() then return 'NOT_ALIVE' end
return s:get_type()
"@ -Expected "Hangar B"

    Write-Host "==> [create] cleanup hangar"
    Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_hangar')
if s then s:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 3: entity wrapper getters round-trip
    # ----------------------------------------------------------------
    Write-Host "==> [entity] getters return sensible values"
    Expect-True -Label "entity getters" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_entity',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 100, y = 0, z = $SPAWN_Z + 100},
  country  = sms.K.countries.USA,
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
  and cnty == 'usa'
  and typ == 'Hangar B'
"@

    Write-Host "==> [entity] cleanup"
    Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_entity')
if s then s:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 4: DCS-2D coordinate translation
    # ----------------------------------------------------------------
    Write-Host "==> [create] DCS-2D translation: cfg.position.x -> def.x, cfg.position.z -> def.y"
    Expect-True -Label "coord translation" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_coords',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 200, y = 0, z = $SPAWN_Z + 300},
  country  = sms.K.countries.USA,
})
if not s then return false end
local p = s:get_position()
return math.abs(p.x - ($SPAWN_X + 200)) < 1
   and math.abs(p.z - ($SPAWN_Z + 300)) < 1
"@

    Write-Host "==> [create] cleanup coords"
    Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_coords')
if s then s:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 5: heading degrees -> radians at spawn
    # ----------------------------------------------------------------
    Write-Host "==> [create] heading 90 degrees -> ~pi/2 radians applied"
    Expect-True -Label "heading translated" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_heading',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 400, y = 0, z = $SPAWN_Z + 400},
  country  = sms.K.countries.USA,
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
"@

    Write-Host "==> [create] cleanup heading"
    Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_heading')
if s then s:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 6: cargo with mass + canCargo
    # ----------------------------------------------------------------
    Write-Host "==> [create] cargo iso_container with mass + canCargo"
    Expect-True -Label "cargo spawned" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_cargo',
  type     = 'iso_container',
  position = {x = $SPAWN_X + 500, y = 0, z = $SPAWN_Z + 500},
  country  = sms.K.countries.USA,
  category = 'Cargos',
  mass     = 1000,
  canCargo = true,
})
if not s then return false end
return s:is_alive()
"@

    Write-Host "==> [create] cleanup cargo"
    Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_cargo')
if s then s:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 7: dead = true (wreckage)
    # ----------------------------------------------------------------
    Write-Host "==> [create] dead=true spawns"
    Expect-True -Label "dead static spawned" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_dead',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 600, y = 0, z = $SPAWN_Z + 600},
  country  = sms.K.countries.USA,
  dead     = true,
})
if not s then return false end
return s:is_alive()
"@

    Write-Host "==> [create] cleanup dead"
    Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_dead')
if s then s:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 8: auto-suffix on name collision (within static namespace only)
    # ----------------------------------------------------------------
    Write-Host "==> [auto-suffix] first '_smoke_static_crate' resolves to '_smoke_static_crate'"
    Expect-EqString -Label "_smoke_static_crate first" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_crate',
  type     = 'iso_container',
  position = {x = $SPAWN_X + 700, y = 0, z = $SPAWN_Z + 700},
  country  = sms.K.countries.USA,
  category = 'Cargos',
})
return s and s:get_name() or 'NIL'
"@ -Expected "_smoke_static_crate"

    Write-Host "==> [auto-suffix] second '_smoke_static_crate' resolves to '_smoke_static_crate-1'"
    Expect-EqString -Label "_smoke_static_crate second" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_crate',
  type     = 'iso_container',
  position = {x = $SPAWN_X + 720, y = 0, z = $SPAWN_Z + 720},
  country  = sms.K.countries.USA,
  category = 'Cargos',
})
return s and s:get_name() or 'NIL'
"@ -Expected "_smoke_static_crate-1"

    Write-Host "==> [auto-suffix] third '_smoke_static_crate' resolves to '_smoke_static_crate-2'"
    Expect-EqString -Label "_smoke_static_crate third" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_crate',
  type     = 'iso_container',
  position = {x = $SPAWN_X + 740, y = 0, z = $SPAWN_Z + 740},
  country  = sms.K.countries.USA,
  category = 'Cargos',
})
return s and s:get_name() or 'NIL'
"@ -Expected "_smoke_static_crate-2"

    Write-Host "==> [auto-suffix] cleanup"
    Invoke-Smoke -Code @'
for _, name in ipairs({'_smoke_static_crate', '_smoke_static_crate-1', '_smoke_static_crate-2'}) do
  local s = sms.static(name)
  if s then s:destroy() end
end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 9: namespace separation — static & group named the same coexist
    # ----------------------------------------------------------------
    Write-Host "==> [namespace] static '_smoke_static_ns' and group '_smoke_static_ns' coexist (no over-probing)"
    Expect-True -Label "namespace separation" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_ns',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 800, y = 0, z = $SPAWN_Z + 800},
  country  = sms.K.countries.USA,
})
if not s then return false end
if s:get_name() ~= '_smoke_static_ns' then return false end
-- Now spawn a group with the same name. It must succeed (separate namespace).
local g = sms.group.create({
  name     = '_smoke_static_ns',
  position = {x = $SPAWN_X + 850, y = 0, z = $SPAWN_Z + 850},
  country  = sms.K.countries.USA,
  category = sms.K.category.GROUND,
  units    = {{ type = 'AAV7' }},
})
if not g then return false end
-- Both should be alive simultaneously.
return s:is_alive() and g:is_alive()
"@

    Write-Host "==> [namespace] cleanup"
    Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_ns')
if s then s:destroy() end
local g = sms.group('_smoke_static_ns')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 11: create — negative paths
    # ----------------------------------------------------------------
    Write-Host "==> [create] no config -> nil"
    Expect-True -Label "no config" -Code 'return sms.static.create() == nil'

    Write-Host "==> [create] non-table config -> nil"
    Expect-True -Label "string config" -Code 'return sms.static.create("not a table") == nil'

    Write-Host "==> [create] missing name -> nil"
    Expect-True -Label "no name" -Code @'
return sms.static.create({
  type = 'Hangar B',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
}) == nil
'@

    Write-Host "==> [create] missing type -> nil"
    Expect-True -Label "no type" -Code @'
return sms.static.create({
  name = 'no_type',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
}) == nil
'@

    Write-Host "==> [create] missing position -> nil"
    Expect-True -Label "no position" -Code @'
return sms.static.create({
  name = 'no_pos',
  type = 'Hangar B',
  country = sms.K.countries.USA,
}) == nil
'@

    Write-Host "==> [create] missing country -> nil"
    Expect-True -Label "no country" -Code @'
return sms.static.create({
  name = 'no_country',
  type = 'Hangar B',
  position = {x = 0, y = 0, z = 0},
}) == nil
'@

    Write-Host "==> [create] bad country -> nil"
    Expect-True -Label "bad country" -Code @'
return sms.static.create({
  name = 'bad_country',
  type = 'Hangar B',
  position = {x = 0, y = 0, z = 0},
  country = 'WAKANDA',
}) == nil
'@

    Write-Host "==> [create] non-vec3 position -> nil"
    Expect-True -Label "bad position" -Code @'
return sms.static.create({
  name = 'bad_pos',
  type = 'Hangar B',
  position = 'not a vec3',
  country = sms.K.countries.USA,
}) == nil
'@

    Write-Host "==> [create] non-string type -> nil"
    Expect-True -Label "non-string type" -Code @'
return sms.static.create({
  name = 'numeric_type',
  type = 12345,
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
}) == nil
'@

    Write-Host "==> [create] empty type string -> nil"
    Expect-True -Label "empty type" -Code @'
return sms.static.create({
  name = 'empty_type',
  type = '',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
}) == nil
'@

    Write-Host "==> [create] non-number heading -> nil"
    Expect-True -Label "non-num heading" -Code @'
return sms.static.create({
  name = 'bad_heading',
  type = 'Hangar B',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  heading = 'north',
}) == nil
'@

    Write-Host "==> [create] non-boolean dead -> nil"
    Expect-True -Label "non-bool dead" -Code @'
return sms.static.create({
  name = 'bad_dead',
  type = 'Hangar B',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  dead = 'yes',
}) == nil
'@

    Write-Host "==> [create] non-number mass -> nil"
    Expect-True -Label "non-num mass" -Code @'
return sms.static.create({
  name = 'bad_mass',
  type = 'iso_container',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  category = 'Cargos',
  mass = 'heavy',
}) == nil
'@

    Write-Host "==> [create] non-boolean canCargo -> nil"
    Expect-True -Label "non-bool canCargo" -Code @'
return sms.static.create({
  name = 'bad_cancargo',
  type = 'iso_container',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  category = 'Cargos',
  canCargo = 'yes',
}) == nil
'@

    Write-Host "==> [create] non-string shape_name -> nil"
    Expect-True -Label "non-string shape_name" -Code @'
return sms.static.create({
  name = 'bad_shape',
  type = 'Hangar B',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  shape_name = 12345,
}) == nil
'@

    Write-Host "==> [create] non-string livery_id -> nil"
    Expect-True -Label "non-string livery_id" -Code @'
return sms.static.create({
  name = 'bad_livery',
  type = 'Hangar B',
  position = {x = 0, y = 0, z = 0},
  country = sms.K.countries.USA,
  livery_id = 12345,
}) == nil
'@

    # ----------------------------------------------------------------
    # Section 12: clone — discover ME-defined static template (skip if none)
    # ----------------------------------------------------------------
    Write-Host "==> [clone] discover ME-defined static name (if any)"
    $templateResp = Invoke-Smoke -Code @'
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
'@
    $TEMPLATE_NAME = $templateResp.return_value

    if (-not $TEMPLATE_NAME) {
        Write-Host "==> [clone] no ME-defined static found in mission, skipping clone tests (Sections 12-13)"
    } else {
        Write-Host "==> [clone] using template: $TEMPLATE_NAME"

        Write-Host "==> [clone] clone with new name + position"
        Expect-True -Label "clone alive" -Code @"
local s = sms.static.clone('$TEMPLATE_NAME', {
  name     = '_smoke_static_clone',
  position = {x = $SPAWN_X + 1000, y = 0, z = $SPAWN_Z + 1000},
})
if not s then return false end
return s:is_alive()
"@

        Write-Host "==> [clone] cleanup first clone"
        Invoke-Smoke -Code @'
local s = sms.static('_smoke_static_clone')
if s then s:destroy() end
'@ | Out-Null

        Write-Host "==> [clone] auto-suffix: first '_smoke_static_dup' resolves to '_smoke_static_dup'"
        Expect-EqString -Label "_smoke_static_dup first" -Code @"
local s = sms.static.clone('$TEMPLATE_NAME', {
  name     = '_smoke_static_dup',
  position = {x = $SPAWN_X + 1100, y = 0, z = $SPAWN_Z + 1100},
})
return s and s:get_name() or 'NIL'
"@ -Expected "_smoke_static_dup"

        Write-Host "==> [clone] auto-suffix: second '_smoke_static_dup' resolves to '_smoke_static_dup-1'"
        Expect-EqString -Label "_smoke_static_dup second" -Code @"
local s = sms.static.clone('$TEMPLATE_NAME', {
  name     = '_smoke_static_dup',
  position = {x = $SPAWN_X + 1150, y = 0, z = $SPAWN_Z + 1150},
})
return s and s:get_name() or 'NIL'
"@ -Expected "_smoke_static_dup-1"

        Write-Host "==> [clone] cleanup duplicates"
        Invoke-Smoke -Code @'
for _, name in ipairs({'_smoke_static_dup', '_smoke_static_dup-1'}) do
  local s = sms.static(name)
  if s then s:destroy() end
end
'@ | Out-Null
    }

    # ----------------------------------------------------------------
    # Section 13: clone — negative paths
    # ----------------------------------------------------------------
    Write-Host "==> [clone] missing template -> nil"
    Expect-True -Label "missing template" -Code @'
return sms.static.clone('_definitely_not_a_template_xyz', {
  name = 'never',
  position = {x = 0, y = 0, z = 0},
}) == nil
'@

    Write-Host "==> [clone] non-string template_name -> nil"
    Expect-True -Label "non-string template" -Code @'
return sms.static.clone(12345, {
  name = 'never',
  position = {x = 0, y = 0, z = 0},
}) == nil
'@

    Write-Host "==> [clone] non-table overrides -> nil"
    Expect-True -Label "non-table overrides" -Code @'
return sms.static.clone('any', 'not a table') == nil
'@

    Write-Host "==> [clone] missing name override -> nil"
    Expect-True -Label "no override name" -Code @'
return sms.static.clone('any', {
  position = {x = 0, y = 0, z = 0},
}) == nil
'@

    Write-Host "==> [clone] missing position override -> nil"
    Expect-True -Label "no override position" -Code @'
return sms.static.clone('any', {
  name = 'no_pos_override',
}) == nil
'@

    # ----------------------------------------------------------------
    # Section 14: sms.area:is_static_in
    # ----------------------------------------------------------------
    Write-Host "==> [area] is_static_in true when static is inside circle"
    Expect-True -Label "inside circle" -Code @"
local center = {x = $SPAWN_X + 2000, y = 0, z = $SPAWN_Z + 2000}
local area = sms.area.create_circular(center, 100)
if not area then return false end
local s = sms.static.create({
  name     = '_smoke_static_in',
  type     = 'Hangar B',
  position = {x = center.x, y = 0, z = center.z},
  country  = sms.K.countries.USA,
})
if not s then return false end
return area:is_static_in(s)
"@

    Write-Host "==> [area] is_static_in false when static is outside circle"
    Expect-False -Label "outside circle" -Code @"
local center = {x = $SPAWN_X + 3000, y = 0, z = $SPAWN_Z + 3000}
local area = sms.area.create_circular(center, 50)
if not area then return false end
local s = sms.static.create({
  name     = '_smoke_static_out',
  type     = 'Hangar B',
  position = {x = center.x + 200, y = 0, z = center.z + 200},
  country  = sms.K.countries.USA,
})
if not s then return false end
return area:is_static_in(s)
"@

    Write-Host "==> [area] cleanup"
    Invoke-Smoke -Code @'
for _, name in ipairs({'_smoke_static_in', '_smoke_static_out'}) do
  local s = sms.static(name)
  if s then s:destroy() end
end
'@ | Out-Null

    Write-Host "==> [area] is_static_in non-static handle -> false + log"
    Expect-False -Label "non-static target" -Code @'
local center = {x = 0, y = 0, z = 0}
local area = sms.area.create_circular(center, 100)
return area:is_static_in('not a handle')
'@

    Write-Host "==> [area] is_static_in non-area handle -> false + log"
    Expect-False -Label "non-area self" -Code @"
local s = sms.static.create({
  name     = '_smoke_static_typecheck',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 4000, y = 0, z = $SPAWN_Z + 4000},
  country  = sms.K.countries.USA,
})
if not s then return true end -- if create failed, the typecheck below is moot; treat as 'no false positive'
-- Pass a non-area first arg by calling sms.area.is_static_in directly.
local result = sms.area.is_static_in('not an area', s)
s:destroy()
return result
"@

    # ----------------------------------------------------------------
    # Section 15: handle methods on a no-longer-existing static -> nil + log
    #
    # Note: DCS doesn't reflect destroy() within the same frame — getByName still
    # returns the object in the same exec call. So we spawn+destroy in one exec
    # and verify the destroyed state in a SEPARATE exec call (separate frame),
    # where DCS has cleared the lookup. The sms.static() callable returning nil
    # is the canonical "no longer in the world" signal.
    # ----------------------------------------------------------------
    Write-Host "==> [entity] spawn + destroy a static (frame 1)"
    Invoke-Smoke -Code @"
local s = sms.static.create({
  name     = '_smoke_static_postdestroy',
  type     = 'Hangar B',
  position = {x = $SPAWN_X + 5000, y = 0, z = $SPAWN_Z + 5000},
  country  = sms.K.countries.USA,
})
if s then s:destroy() end
return 'destroyed'
"@ | Out-Null

    Write-Host "==> [entity] sms.static lookup of destroyed name -> nil (frame 2)"
    Expect-True -Label "destroyed lookup nil" -Code @'
return sms.static('_smoke_static_postdestroy') == nil
'@

    Write-Host "==> [entity] method on stale handle hits is_alive gate -> nil + log (frame 2)"
    # Reconstruct a handle by name (bypassing the sms.static() callable so we get
    # a handle even though DCS no longer knows the name) and call get_position.
    # Exercises static.lua's is_alive gate against a name DCS has cleared, which
    # the same-frame variant of this test could not observe.
    Expect-True -Label "stale handle get_position nil" -Code @'
local s = setmetatable({name = '_smoke_static_postdestroy'}, {__index = sms.static})
return s:get_position() == nil
'@

    # ----------------------------------------------------------------
    # Section 16: tail-log assertion
    # ----------------------------------------------------------------
    Write-Host "==> [log] dcs.log should contain [sms.static] line for unknown country"
    $exe = Get-DcsSmsPath
    $logWindow = & $exe tail-log --grep '\[sms.static\]' -n 200 -since 60s | Out-String
    if ($logWindow -notmatch 'unknown country') {
        Write-Host "FAIL: missing log line for unknown country"
        Write-Host $logWindow
        exit 1
    }

    Write-Host ""
    Write-Host "ALL smoke_static checks passed."
}
finally {
    Clear-SmokeFixtures -Names $fixtures
}
