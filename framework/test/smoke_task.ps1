# End-to-end smoke test for sms.task v1.
# Synthetic checks (no DCS dispatch) verify builder shape + air-only flag.
# Live DCS sections spawn small fixture groups and exercise apply.
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused,
# at least one ME-defined group (any kind).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run abort.
# Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
$fixtures = @(
    '_smoke_task_ground',
    '_smoke_task_air',
    '_smoke_task_target_grp',
    '_smoke_task_target_static',
    '_smoke_task_escort_target',
    '_smoke_task_fac_target',
    '_smoke_task_engage_target'
)

try {
    Clear-SmokeFixtures -Names $fixtures   # idempotent: clear residue from any prior run

    Write-Host "==> hook status"
    Invoke-Status

    Write-Host "==> load framework files"
    Invoke-Smoke -File 'sms.lua' | Out-Null
    Invoke-Smoke -File 'log.lua' | Out-Null
    Invoke-Smoke -File 'utils.lua' | Out-Null
    Invoke-Smoke -File 'constants.lua' | Out-Null
    Invoke-Smoke -File 'group.lua' | Out-Null
    Invoke-Smoke -File 'unit.lua' | Out-Null
    Invoke-Smoke -File 'area.lua' | Out-Null
    Invoke-Smoke -File 'timer.lua' | Out-Null
    Invoke-Smoke -File 'group_spawn.lua' | Out-Null
    Invoke-Smoke -File 'static.lua' | Out-Null
    Invoke-Smoke -File 'events.lua' | Out-Null
    Invoke-Smoke -File 'weapon.lua' | Out-Null
    Invoke-Smoke -File 'task.lua' | Out-Null

    # ----------------------------------------------------------------
    # Section 1: synthetic builder shape checks
    # ----------------------------------------------------------------
    Write-Host "==> [build] move_to(vec3) returns Mission task with one waypoint"
    Expect-EqString -Label 'move_to id'       -Code 'return sms.task.move_to({x=100,y=0,z=200}).id'        -Expected 'Mission'
    Expect-EqString -Label 'move_to verb tag' -Code 'return sms.task.move_to({x=100,y=0,z=200})._sms_verb' -Expected 'move_to'
    Expect-True     -Label 'move_to not air-only' -Code 'return sms.task.move_to({x=100,y=0,z=200})._sms_air_only == nil'

    Write-Host "==> [build] move_to without speed leaves DCS cruise default (no speed/speed_locked field)"
    Expect-True -Label 'move_to no speed' -Code @'
local t = sms.task.move_to({x=100,y=0,z=200})
local p = t.params.route.points[1]
return p.speed == nil and p.speed_locked == nil
'@

    Write-Host "==> [build] move_to with opts.speed sets speed + speed_locked"
    Expect-True -Label 'move_to with speed' -Code @'
local t = sms.task.move_to({x=100,y=0,z=200}, {speed = 50})
local p = t.params.route.points[1]
return p.speed == 50 and p.speed_locked == true
'@

    Write-Host "==> [build] move_to with bad opts.speed -> nil"
    Expect-True -Label 'move_to bad speed' -Code 'return sms.task.move_to({x=100,y=0,z=200}, {speed="fast"}) == nil'

    Write-Host "==> [build] hold() returns Nothing task"
    Expect-EqString -Label 'hold id' -Code 'return sms.task.hold().id' -Expected 'Nothing'

    Write-Host "==> [build] orbit returns air-only Orbit task"
    Expect-EqString -Label 'orbit id'       -Code 'return sms.task.orbit({x=0,y=0,z=0}).id'        -Expected 'Orbit'
    Expect-True     -Label 'orbit air-only' -Code 'return sms.task.orbit({x=0,y=0,z=0})._sms_air_only == true'
    Expect-EqString -Label 'orbit verb tag' -Code 'return sms.task.orbit({x=0,y=0,z=0})._sms_verb' -Expected 'orbit'

    Write-Host "==> [build] orbit pattern defaults to Circle"
    Expect-EqString -Label 'orbit default pattern' -Code 'return sms.task.orbit({x=0,y=0,z=0}).params.pattern' -Expected 'Circle'

    Write-Host "==> [build] orbit Anchored pattern accepted"
    Expect-EqString -Label 'orbit anchored' -Code 'return sms.task.orbit({x=0,y=0,z=0}, {pattern="Anchored"}).params.pattern' -Expected 'Anchored'

    Write-Host "==> [build] orbit Anchored populates hotLegDir/legLength/width/clockWise"
    Expect-True -Label 'orbit anchored fields' -Code @'
local t = sms.task.orbit({x=0,y=0,z=0}, {
  pattern         = 'Anchored',
  hot_leg_bearing = 90,
  leg_length      = 92500,
  width           = 37000,
  clockwise       = true,
})
if not t then return false end
local p = t.params
-- hot_leg_bearing 90° must map to ~pi/2 radians
local rad_ok = math.abs(p.hotLegDir - math.pi/2) < 1e-6
return rad_ok
  and p.legLength == 92500
  and p.width     == 37000
  and p.clockWise == true
'@

    Write-Host "==> [build] orbit Circle ignores Anchored-only opts"
    Expect-True -Label 'orbit circle no anchored fields' -Code @'
local t = sms.task.orbit({x=0,y=0,z=0}, {leg_length = 50000})
return t.params.legLength == nil and t.params.width == nil
'@

    Write-Host "==> [build] orbit invalid pattern -> nil"
    Expect-True -Label 'orbit bad pattern' -Code 'return sms.task.orbit({x=0,y=0,z=0}, {pattern="RaceTrack"}) == nil'

    Write-Host "==> [build] orbit Anchored bad clockwise -> nil"
    Expect-True -Label 'orbit bad clockwise' -Code 'return sms.task.orbit({x=0,y=0,z=0}, {pattern="Anchored", clockwise="yes"}) == nil'

    Write-Host "==> [build] orbit non-vec3 pos -> nil"
    Expect-True -Label 'orbit bad pos' -Code 'return sms.task.orbit("nope") == nil'

    Write-Host "==> [build] bomb returns air-only Bombing task"
    Expect-EqString -Label 'bomb id'       -Code 'return sms.task.bomb({x=0,y=0,z=0}).id' -Expected 'Bombing'
    Expect-True     -Label 'bomb air-only' -Code 'return sms.task.bomb({x=0,y=0,z=0})._sms_air_only == true'

    Write-Host "==> [build] land returns air-only Land task"
    Expect-EqString -Label 'land id'       -Code 'return sms.task.land({x=0,y=0,z=0}).id' -Expected 'Land'
    Expect-True     -Label 'land air-only' -Code 'return sms.task.land({x=0,y=0,z=0})._sms_air_only == true'

    Write-Host "==> [build] combo returns ComboTask"
    Expect-EqString -Label 'combo id' -Code 'return sms.task.combo({sms.task.hold()}).id' -Expected 'ComboTask'

    Write-Host "==> [build] combo propagates air-only when any constituent is air-only"
    Expect-True -Label 'combo air via orbit' -Code 'return sms.task.combo({sms.task.move_to({x=0,y=0,z=0}), sms.task.orbit({x=0,y=0,z=0})})._sms_air_only == true'

    Write-Host "==> [build] combo not air-only when no constituent is"
    Expect-True -Label 'combo no air' -Code 'return sms.task.combo({sms.task.move_to({x=0,y=0,z=0}), sms.task.hold()})._sms_air_only == nil'

    Write-Host "==> [build] combo with non-table constituent -> nil"
    Expect-True -Label 'combo bad constituent' -Code 'return sms.task.combo({sms.task.hold(), "not a task"}) == nil'

    Write-Host "==> [build] combo with empty list -> nil"
    Expect-True -Label 'combo empty' -Code 'return sms.task.combo({}) == nil'

    Write-Host "==> [build] move_to with non-handle -> nil"
    Expect-True -Label 'move_to bad target' -Code 'return sms.task.move_to("nope") == nil'

    # ----------------------------------------------------------------
    # Section: v1.1 role-type builders (no_task, refuel, awacs, tanker, ewr)
    # ----------------------------------------------------------------

    Write-Host "==> [build] no_task returns NoTask, air-only"
    Expect-EqString -Label 'no_task id'       -Code 'return sms.task.no_task().id'        -Expected 'NoTask'
    Expect-True     -Label 'no_task air-only' -Code 'return sms.task.no_task()._sms_air_only == true'
    Expect-EqString -Label 'no_task verb'     -Code 'return sms.task.no_task()._sms_verb' -Expected 'no_task'

    Write-Host "==> [build] refuel returns Refueling, air-only"
    Expect-EqString -Label 'refuel id'       -Code 'return sms.task.refuel().id' -Expected 'Refueling'
    Expect-True     -Label 'refuel air-only' -Code 'return sms.task.refuel()._sms_air_only == true'

    Write-Host "==> [build] awacs returns AWACS with priority default 1, air-only"
    Expect-EqString -Label 'awacs id'           -Code 'return sms.task.awacs().id' -Expected 'AWACS'
    Expect-True     -Label 'awacs default prio' -Code 'return sms.task.awacs().params.priority == 1'
    Expect-True     -Label 'awacs air-only'     -Code 'return sms.task.awacs()._sms_air_only == true'
    Expect-True     -Label 'awacs prio set'     -Code 'return sms.task.awacs({priority=3}).params.priority == 3'
    Expect-True     -Label 'awacs bad prio'     -Code 'return sms.task.awacs({priority="high"}) == nil'

    Write-Host "==> [build] tanker returns Tanker with priority default 1, air-only"
    Expect-EqString -Label 'tanker id'           -Code 'return sms.task.tanker().id' -Expected 'Tanker'
    Expect-True     -Label 'tanker default prio' -Code 'return sms.task.tanker().params.priority == 1'
    Expect-True     -Label 'tanker air-only'     -Code 'return sms.task.tanker()._sms_air_only == true'
    Expect-True     -Label 'tanker prio set'     -Code 'return sms.task.tanker({priority=2}).params.priority == 2'
    Expect-True     -Label 'tanker bad prio'     -Code 'return sms.task.tanker({priority="high"}) == nil'

    Write-Host "==> [build] ewr returns EWR with priority default 1, ground-only"
    Expect-EqString -Label 'ewr id'           -Code 'return sms.task.ewr().id' -Expected 'EWR'
    Expect-True     -Label 'ewr default prio' -Code 'return sms.task.ewr().params.priority == 1'
    Expect-True     -Label 'ewr ground-only'  -Code 'return sms.task.ewr()._sms_ground_only == true'
    Expect-True     -Label 'ewr not air-only' -Code 'return sms.task.ewr()._sms_air_only == nil'
    Expect-True     -Label 'ewr bad opts'     -Code 'return sms.task.ewr("nope") == nil'

    # ----------------------------------------------------------------
    # Section: v1.1 point/runway builders
    # ----------------------------------------------------------------

    Write-Host "==> [build] fire_at_point returns FireAtPoint, ground-only"
    Expect-EqString -Label 'fire_at_point id'        -Code 'return sms.task.fire_at_point({x=0,y=0,z=0}).id' -Expected 'FireAtPoint'
    Expect-True     -Label 'fire_at_point ground'    -Code 'return sms.task.fire_at_point({x=0,y=0,z=0})._sms_ground_only == true'
    Expect-True     -Label 'fire_at_point not air'   -Code 'return sms.task.fire_at_point({x=0,y=0,z=0})._sms_air_only == nil'
    Expect-True     -Label 'fire_at_point radius'    -Code 'return sms.task.fire_at_point({x=0,y=0,z=0}, {radius=200}).params.radius == 200'
    Expect-True     -Label 'fire_at_point bad point' -Code 'return sms.task.fire_at_point("nope") == nil'
    Expect-True     -Label 'fire_at_point bad rad'   -Code 'return sms.task.fire_at_point({x=0,y=0,z=0}, {radius="big"}) == nil'

    Write-Host "==> [build] attack_map_object returns AttackMapObject, air-only"
    Expect-EqString -Label 'amo id'        -Code 'return sms.task.attack_map_object({x=0,y=0,z=0}).id' -Expected 'AttackMapObject'
    Expect-True     -Label 'amo air-only'  -Code 'return sms.task.attack_map_object({x=0,y=0,z=0})._sms_air_only == true'
    Expect-True     -Label 'amo bad point' -Code 'return sms.task.attack_map_object("nope") == nil'
    Expect-True -Label 'amo direction rad' -Code @'
local t = sms.task.attack_map_object({x=0,y=0,z=0}, {direction=90})
return math.abs(t.params.direction - math.pi/2) < 1e-6
'@

    Write-Host "==> [build] bomb_runway returns BombingRunway, air-only"
    Expect-EqString -Label 'bomb_runway id'     -Code 'return sms.task.bomb_runway(7).id' -Expected 'BombingRunway'
    Expect-True     -Label 'bomb_runway air'    -Code 'return sms.task.bomb_runway(7)._sms_air_only == true'
    Expect-True     -Label 'bomb_runway runway' -Code 'return sms.task.bomb_runway(7).params.runwayId == 7'
    Expect-True     -Label 'bomb_runway bad id' -Code 'return sms.task.bomb_runway("seven") == nil'

    # ----------------------------------------------------------------
    # Section: v1.1 escort
    # ----------------------------------------------------------------

    # escort tests need a group in env.mission to resolve groupId; reuse
    # the discovered ME template name from the spawn smoke if available,
    # otherwise spawn one.
    Write-Host "==> [build] escort needs a sms.unit/group handle"
    Expect-True -Label 'escort bad target' -Code 'return sms.task.escort("nope") == nil'

    Write-Host "==> [build] escort spawns group fixture and returns Escort task"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_escort_target')
if not g then
  sms.group.create({
    name='_smoke_task_escort_target',
    position={x=0,y=0,z=0},
    country=sms.K.countries.USA, category=sms.K.category.AIRPLANE,
    units={{type='F-15C', alt=5000}},
  })
end
'@ | Out-Null

    Expect-EqString -Label 'escort id' -Code @'
local g = sms.group('_smoke_task_escort_target')
if not g then return 'NIL' end
local t = sms.task.escort(g, {target_types={sms.K.targets.PLANES}})
return t and t.id or 'NIL'
'@ -Expected 'Escort'

    Expect-True -Label 'escort air-only' -Code @'
local g = sms.group('_smoke_task_escort_target')
if not g then return false end
return sms.task.escort(g)._sms_air_only == true
'@

    Expect-True -Label 'escort default offset' -Code @'
local g = sms.group('_smoke_task_escort_target')
if not g then return false end
local t = sms.task.escort(g)
return t.params.pos.x == -50 and t.params.pos.y == 0 and t.params.pos.z == -50
'@

    Expect-True -Label 'escort last_waypoint flag' -Code @'
local g = sms.group('_smoke_task_escort_target')
if not g then return false end
local t = sms.task.escort(g, {last_waypoint_index=4})
return t.params.lastWptIndexFlag == true and t.params.lastWptIndex == 4
'@

    Write-Host "==> [build] escort cleanup fixture"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_escort_target')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section: v1.1 FAC builders
    # ----------------------------------------------------------------

    # Reuse the escort fixture if still alive, else spawn fresh
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then
  sms.group.create({
    name='_smoke_task_fac_target',
    position={x=0,y=0,z=0},
    country=sms.K.countries.RUSSIA, category=sms.K.category.GROUND,
    units={{type='Tank Maus'}},
  })
end
'@ | Out-Null

    Write-Host "==> [build] fac_attack_group returns FAC_AttackGroup, any-category"
    Expect-EqString -Label 'fac_attack_group id' -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then return 'NIL' end
local t = sms.task.fac_attack_group(g)
return t and t.id or 'NIL'
'@ -Expected 'FAC_AttackGroup'
    Expect-True -Label 'fac_attack_group not air-only' -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then return false end
return sms.task.fac_attack_group(g)._sms_air_only == nil
'@
    Expect-True -Label 'fac_attack_group not ground-only' -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then return false end
return sms.task.fac_attack_group(g)._sms_ground_only == nil
'@
    Expect-True -Label 'fac_attack_group default designation' -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then return false end
return sms.task.fac_attack_group(g).params.designation == 'Auto'
'@
    Expect-True -Label 'fac_attack_group designation constant' -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then return false end
local t = sms.task.fac_attack_group(g, {designation=sms.K.designations.LASER})
return t.params.designation == 'Laser'
'@

    Write-Host "==> [build] fac returns FAC, any-category"
    Expect-EqString -Label 'fac id'               -Code 'return sms.task.fac({radius=10000}).id' -Expected 'FAC'
    Expect-True     -Label 'fac default priority' -Code 'return sms.task.fac({radius=10000}).params.priority == 1'
    Expect-True     -Label 'fac requires radius'  -Code 'return sms.task.fac({}) == nil'
    Expect-True     -Label 'fac not air-only'     -Code 'return sms.task.fac({radius=10000})._sms_air_only == nil'

    Write-Host "==> [build] fac_engage_group returns FAC_EngageGroup with priority"
    Expect-EqString -Label 'fac_engage_group id' -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then return 'NIL' end
return sms.task.fac_engage_group(g).id
'@ -Expected 'FAC_EngageGroup'
    Expect-True -Label 'fac_engage_group default priority' -Code @'
local g = sms.group('_smoke_task_fac_target')
if not g then return false end
return sms.task.fac_engage_group(g).params.priority == 1
'@

    Write-Host "==> [build] FAC fixture cleanup"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_fac_target')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section: v1.1 engage_en_route builders
    # ----------------------------------------------------------------

    Write-Host "==> [build] engage_en_route_targets returns EngageTargets, air-only"
    Expect-EqString -Label 'eert id' -Code @'
return sms.task.engage_en_route_targets({target_types={sms.K.targets.PLANES}}).id
'@ -Expected 'EngageTargets'
    Expect-True -Label 'eert air-only' -Code @'
return sms.task.engage_en_route_targets({target_types={sms.K.targets.PLANES}})._sms_air_only == true
'@
    Expect-True -Label 'eert default priority' -Code @'
return sms.task.engage_en_route_targets({target_types={sms.K.targets.PLANES}}).params.priority == 1
'@
    Expect-True -Label 'eert priority set' -Code @'
return sms.task.engage_en_route_targets({target_types={sms.K.targets.PLANES}, priority=3}).params.priority == 3
'@
    Expect-True -Label 'eert requires target_types' -Code 'return sms.task.engage_en_route_targets({}) == nil'
    Expect-True -Label 'eert bad max_dist' -Code @'
return sms.task.engage_en_route_targets({target_types={sms.K.targets.AIR}, max_dist='close'}) == nil
'@

    # Group/unit engage tests piggyback on the FAC fixture if alive
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_engage_target')
if not g then
  sms.group.create({
    name='_smoke_task_engage_target',
    position={x=0,y=0,z=0},
    country=sms.K.countries.RUSSIA, category=sms.K.category.AIRPLANE,
    units={{type='Su-27', alt=5000}},
  })
end
'@ | Out-Null

    Write-Host "==> [build] engage_en_route_group returns EngageGroup, air-only, priority"
    Expect-EqString -Label 'eerg id' -Code @'
local g = sms.group('_smoke_task_engage_target')
if not g then return 'NIL' end
return sms.task.engage_en_route_group(g).id
'@ -Expected 'EngageGroup'
    Expect-True -Label 'eerg priority' -Code @'
local g = sms.group('_smoke_task_engage_target')
if not g then return false end
return sms.task.engage_en_route_group(g, {priority=2}).params.priority == 2
'@
    Expect-True -Label 'eerg air-only' -Code @'
local g = sms.group('_smoke_task_engage_target')
if not g then return false end
return sms.task.engage_en_route_group(g)._sms_air_only == true
'@
    Expect-True -Label 'eerg bad target' -Code 'return sms.task.engage_en_route_group("nope") == nil'

    Write-Host "==> [build] engage_en_route_unit returns EngageUnit"
    Expect-True -Label 'eeru id' -Code @'
local g = sms.group('_smoke_task_engage_target')
if not g then return false end
local us = g:get_units()
if not us or #us == 0 then return false end
local t = sms.task.engage_en_route_unit(us[1])
return t and t.id == 'EngageUnit'
'@

    Write-Host "==> [build] engage cleanup fixture"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_engage_target')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 2: discover spawn coords from existing mission
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
    # Section 2b: spawn target group + synthetic shape for follow/attack/attack_in_area
    # These three builders need a real DCS handle to inspect IDs at build time,
    # so the synthetic shape tests live after target spawn.
    # ----------------------------------------------------------------
    Write-Host "==> [build] spawn target fixture _smoke_task_target_grp"
    Expect-True -Label 'target spawned' -Code @"
local g = sms.group.create({
  name      = '_smoke_task_target_grp',
  position  = {x = $SPAWN_X - 200, y = 0, z = $SPAWN_Z - 200},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = 'AAV7' }},
})
return g ~= nil
"@

    Write-Host "==> [build] follow(group_handle) returns air-only Follow task"
    Expect-EqString -Label 'follow id'       -Code "return sms.task.follow(sms.group('_smoke_task_target_grp')).id"        -Expected 'Follow'
    Expect-EqString -Label 'follow verb tag' -Code "return sms.task.follow(sms.group('_smoke_task_target_grp'))._sms_verb" -Expected 'follow'
    Expect-True     -Label 'follow air-only' -Code "return sms.task.follow(sms.group('_smoke_task_target_grp'))._sms_air_only == true"

    Write-Host "==> [build] follow with non-handle target -> nil"
    Expect-True -Label 'follow bad target' -Code 'return sms.task.follow("nope") == nil'

    Write-Host "==> [build] follow with bad opts.offset -> nil"
    Expect-True -Label 'follow bad offset' -Code "return sms.task.follow(sms.group('_smoke_task_target_grp'), {offset='not vec3'}) == nil"

    Write-Host "==> [build] attack(group_handle) returns air-only AttackGroup task"
    Expect-EqString -Label 'attack id'       -Code "return sms.task.attack(sms.group('_smoke_task_target_grp')).id"        -Expected 'AttackGroup'
    Expect-EqString -Label 'attack verb tag' -Code "return sms.task.attack(sms.group('_smoke_task_target_grp'))._sms_verb" -Expected 'attack'
    Expect-True     -Label 'attack air-only' -Code "return sms.task.attack(sms.group('_smoke_task_target_grp'))._sms_air_only == true"

    Write-Host "==> [build] attack with non-handle target -> nil"
    Expect-True -Label 'attack bad target' -Code 'return sms.task.attack("nope") == nil'

    Write-Host "==> [build] spawn target fixture _smoke_task_target_static (Hangar B)"
    Expect-True -Label 'static target spawned' -Code @"
local s = sms.static.create({
  name     = '_smoke_task_target_static',
  type     = 'Hangar B',
  position = {x = $SPAWN_X - 400, y = 0, z = $SPAWN_Z - 400},
  country  = sms.K.countries.USA,
})
return s ~= nil
"@

    Write-Host "==> [build] attack(static_handle) returns air-only AttackUnit task"
    Expect-EqString -Label 'attack static id'       -Code "return sms.task.attack(sms.static('_smoke_task_target_static')).id" -Expected 'AttackUnit'
    Expect-True     -Label 'attack static air-only' -Code "return sms.task.attack(sms.static('_smoke_task_target_static'))._sms_air_only == true"

    Write-Host "==> [build] attack_in_area(circular area) returns air-only EngageTargetsInZone"
    Expect-EqString -Label 'attack_in_area id' -Code @"
local a = sms.area.create_circular({x=$SPAWN_X, y=0, z=$SPAWN_Z}, 500, '_smoke_task_zone')
return sms.task.attack_in_area(a).id
"@ -Expected 'EngageTargetsInZone'
    Expect-True -Label 'attack_in_area air-only' -Code @"
local a = sms.area.create_circular({x=$SPAWN_X, y=0, z=$SPAWN_Z}, 500, '_smoke_task_zone')
return sms.task.attack_in_area(a)._sms_air_only == true
"@

    Write-Host "==> [build] attack_in_area with non-area target -> nil"
    Expect-True -Label 'attack_in_area bad target' -Code 'return sms.task.attack_in_area("nope") == nil'

    Write-Host "==> [build] attack_in_area priority defaults to 1"
    Expect-True -Label 'attack_in_area default priority' -Code @'
local a = sms.area.create_circular({x=0,y=0,z=0}, 5000)
if not a then return false end
return sms.task.attack_in_area(a).params.priority == 1
'@

    Write-Host "==> [build] attack_in_area priority honored"
    Expect-True -Label 'attack_in_area set priority' -Code @'
local a = sms.area.create_circular({x=0,y=0,z=0}, 5000)
if not a then return false end
return sms.task.attack_in_area(a, {priority=5}).params.priority == 5
'@

    Write-Host "==> [build] attack_in_area bad priority -> nil"
    Expect-True -Label 'attack_in_area bad priority' -Code @'
local a = sms.area.create_circular({x=0,y=0,z=0}, 5000)
if not a then return false end
return sms.task.attack_in_area(a, {priority='high'}) == nil
'@

    # ----------------------------------------------------------------
    # Section 3: live ground apply — move_to + air-only rejection
    # ----------------------------------------------------------------
    Write-Host "==> [apply] spawn ground fixture _smoke_task_ground"
    Expect-True -Label 'ground spawned' -Code @"
local g = sms.group.create({
  name      = '_smoke_task_ground',
  position  = {x = $SPAWN_X, y = 0, z = $SPAWN_Z},
  country   = sms.K.countries.USA,
  category  = sms.K.category.GROUND,
  units     = {{ type = 'AAV7' }},
})
return g ~= nil
"@

    Write-Host "==> [apply] sms.group:get_category returns 'ground'"
    Expect-EqString -Label 'category ground' -Code "return sms.group('_smoke_task_ground'):get_category()" -Expected 'ground'

    Write-Host "==> [apply] ground:set_task(move_to) returns true"
    Expect-True -Label 'ground move_to ok' -Code @"
local g = sms.group('_smoke_task_ground')
local pos = {x = $SPAWN_X + 100, y = 0, z = $SPAWN_Z + 100}
return g:set_task(sms.task.move_to(pos)) == true
"@

    Write-Host "==> [apply] ground:set_task(orbit) rejected with log + false (air-only)"
    Expect-True -Label 'ground orbit rejected' -Code @"
local g = sms.group('_smoke_task_ground')
return g:set_task(sms.task.orbit({x = $SPAWN_X, y = 100, z = $SPAWN_Z})) == false
"@

    Write-Host "==> [apply] verify air-only rejection log line"
    # set_task / push_task live in framework/group.lua (the apply API
    # extends sms.group's namespace), so they log under [sms.group].
    $exe = Get-DcsSmsPath
    $logWindow = & $exe tail-log --grep '\[sms.group\]' -n 50 2>&1 | Out-String
    if ($logWindow -notmatch "set_task: 'orbit' is air-only") {
        Write-Host "FAIL: missing air-only log line"
        Write-Host $logWindow
        exit 1
    }
    if ($logWindow -notmatch "_smoke_task_ground") {
        Write-Host "FAIL: air-only log missing group name"
        Write-Host $logWindow
        exit 1
    }

    Write-Host "==> [apply] cleanup ground fixture"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_ground')
if g then g:destroy() end
'@ | Out-Null

    # ----------------------------------------------------------------
    # Section 4: live air apply — orbit + push + combo
    # ----------------------------------------------------------------
    Write-Host "==> [apply] spawn air fixture _smoke_task_air"
    Expect-True -Label 'air spawned' -Code @"
local g = sms.group.create({
  name      = '_smoke_task_air',
  position  = {x = $SPAWN_X + 5000, y = 0, z = $SPAWN_Z + 5000},
  country   = sms.K.countries.USA,
  category  = sms.K.category.AIRPLANE,
  units     = {{ type = 'F-16C_50', alt = 5000 }},
})
return g ~= nil
"@

    Write-Host "==> [apply] air:get_category returns 'airplane'"
    Expect-EqString -Label 'category airplane' -Code "return sms.group('_smoke_task_air'):get_category()" -Expected 'airplane'

    Write-Host "==> [apply] air:set_task(orbit) returns true"
    Expect-True -Label 'air orbit ok' -Code @"
local g = sms.group('_smoke_task_air')
return g:set_task(sms.task.orbit({x = $SPAWN_X, y = 5000, z = $SPAWN_Z}, {altitude=5000})) == true
"@

    Write-Host "==> [apply] air:push_task(orbit) returns true"
    Expect-True -Label 'air push ok' -Code @"
local g = sms.group('_smoke_task_air')
return g:push_task(sms.task.orbit({x = $SPAWN_X + 1000, y = 5000, z = $SPAWN_Z + 1000})) == true
"@

    Write-Host "==> [apply] air:set_task(combo of move_to + orbit) returns true"
    Expect-True -Label 'air combo ok' -Code @"
local g = sms.group('_smoke_task_air')
local task = sms.task.combo({
  sms.task.move_to({x = $SPAWN_X + 2000, y = 5000, z = $SPAWN_Z + 2000}),
  sms.task.orbit({x = $SPAWN_X + 2000, y = 5000, z = $SPAWN_Z + 2000}),
})
return g:set_task(task) == true
"@

    # ----------------------------------------------------------------
    # Section 5: bad-arg matrix on apply
    # ----------------------------------------------------------------
    Write-Host "==> [apply] set_task with non-handle -> false"
    Expect-True -Label 'set_task bad handle' -Code 'return sms.group.set_task("not a handle", sms.task.hold()) == false'

    Write-Host "==> [apply] set_task with non-table task -> false"
    Expect-True -Label 'set_task bad task' -Code @'
local g = sms.group('_smoke_task_air')
return g:set_task(42) == false
'@

    Write-Host "==> [apply] set_task with task missing id -> false"
    Expect-True -Label 'set_task no id' -Code @'
local g = sms.group('_smoke_task_air')
return g:set_task({params = {}}) == false
'@

    Write-Host "==> [apply] cleanup air fixture"
    Invoke-Smoke -Code @'
local g = sms.group('_smoke_task_air')
if g then g:destroy() end
'@ | Out-Null

    Write-Host "==> [apply] set_task on dead group -> false"
    Expect-True -Label 'set_task dead' -Code @'
return sms.group.set_task(sms._make_handle(sms.group, '_smoke_task_air'), sms.task.hold()) == false
'@

    Write-Host ""
    Write-Host "ALL smoke_task checks passed."
} finally {
    Clear-SmokeFixtures -Names $fixtures
}
