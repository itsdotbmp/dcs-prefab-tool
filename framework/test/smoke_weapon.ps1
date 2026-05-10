# End-to-end smoke test for sms.weapon v1.
# Synthetic checks first (load + constants + bad-arg paths). Live DCS
# round-trip lives in later sections (added incrementally as tracking
# capabilities land per task).
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module "$PSScriptRoot/_smoke.psm1" -Force -DisableNameChecking
Initialize-Smoke

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run abort.
# Idempotent -- destroys only what currently exists. Keep this list in sync
# with the names this smoke creates.
$fixtures = @('smoke_weapon_arty', 'smoke_weapon_arty_destroy')

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
    Invoke-Smoke -File 'events.lua'       | Out-Null
    Invoke-Smoke -File 'weapon.lua'       | Out-Null

    Write-Host "==> WEAPON_IMPACT constant exists"
    Expect-EqString -Label 'WEAPON_IMPACT' -Code 'return sms.events.WEAPON_IMPACT' -Expected 'weapon_impact'

    Write-Host "==> wrap with bad input returns nil"
    Expect-True -Label 'wrap nil'    -Code 'return sms.weapon.wrap(nil) == nil'
    Expect-True -Label 'wrap number' -Code 'return sms.weapon.wrap(42) == nil'
    Expect-True -Label 'wrap string' -Code 'return sms.weapon.wrap("hi") == nil'

    Write-Host "==> module getters reject non-handles"
    Expect-True -Label 'get_name on string'  -Code 'return sms.weapon.get_name("nope") == nil'
    Expect-True -Label 'get_type on nil'     -Code 'return sms.weapon.get_type(nil) == nil'
    Expect-True -Label 'get_state on number' -Code 'return sms.weapon.get_state(7) == nil'
    Expect-True -Label 'is_bomb on string'   -Code 'return sms.weapon.is_bomb("nope") == false'

    Write-Host "==> live DCS SHOT round-trip -- spawn artillery and fire a shell"

    # Spawn an M109 self-propelled howitzer far from origin to avoid colliding
    # with concurrent agents. Capture the resolved name (sms.spawn auto-suffixes).
    $spawnArty = @"
_G._sms_weapon_smoke = {
  arty_group  = nil,
  arty_unit   = nil,
  target_pos  = {x = -49500, y = 0, z = -50000},  -- ~500m east of arty
  shot_evt    = nil,   -- captured SHOT event
  shot_count  = 0,     -- only track first shot
}
local g = sms.group.create({
  name = "smoke_weapon_arty",
  position = {x = -50000, y = 0, z = -50000},
  country = sms.K.countries.USA,
  category = sms.K.category.GROUND,
  units = {{ type = "M-109", offset = {x = 0, y = 0, z = 0}, heading = 90 }},
})
if g then
  _G._sms_weapon_smoke.arty_group = g:get_name()
  _G._sms_weapon_smoke.arty_unit  = g:get_units()[1]:get_name()
  -- Anchor target y to terrain (the M-109 lands at ground, not sea level).
  _G._sms_weapon_smoke.target_pos.y = land.getHeight({x = _G._sms_weapon_smoke.target_pos.x, y = _G._sms_weapon_smoke.target_pos.z})
end
"@
    Invoke-Smoke -Code $spawnArty | Out-Null

    Expect-True -Label 'artillery spawned' `
        -Code 'return type(_G._sms_weapon_smoke.arty_unit) == "string" and _G._sms_weapon_smoke.arty_unit ~= ""'

    # Subscribe to SHOT and, for the first shell whose launcher is our arty:
    #   - capture the event,
    #   - snapshot the pre-tracking state (Task 3 assertion checks this),
    #   - wire on_tick and start_tracking immediately (Task 4 setup).
    # Real users will do the same -- they decide whether to track in the SHOT
    # handler, not after a delay -- so this also matches the canonical use case.
    #
    # Note on the closure-local `fired` latch: the lua state persists across
    # `dcs-sms exec` calls, and reloading events.lua leaves orphaned world
    # handlers (their closures capture the previous `_subscribers` table)
    # still wired into world.addEventHandler. Stale subscribers from earlier
    # smoke runs therefore still fire on every SHOT and may race with this
    # run's handler, mutating the shared `_G._sms_weapon_smoke` table. By
    # gating on a fresh closure-local `fired` flag instead of the shared
    # `shot_count`, this run's handler is guaranteed to do its own setup
    # work exactly once even when stale handlers also fire.
    $subscribeShot = @"
_G._sms_weapon_smoke.tick_count = 0
_G._sms_weapon_smoke.last_pos = nil
local fired = false
sms.events.connect(sms.events.SHOT, function(evt)
  if fired then return end
  if not evt.weapon then return end
  local launcher = evt.weapon:get_launcher()
  if not launcher or launcher.name ~= _G._sms_weapon_smoke.arty_unit then return end
  fired = true
  _G._sms_weapon_smoke.shot_count = _G._sms_weapon_smoke.shot_count + 1
  _G._sms_weapon_smoke.shot_evt = evt
  -- Capture state at SHOT time (Task 3 assertion checks this).
  _G._sms_weapon_smoke.captured_state_at_shot = evt.weapon:get_state()
  -- Wire on_tick and start tracking immediately (Task 4).
  evt.weapon:on_tick(function(weapon)
    _G._sms_weapon_smoke.tick_count = _G._sms_weapon_smoke.tick_count + 1
    _G._sms_weapon_smoke.last_pos   = weapon:get_position()
  end)
  _G._sms_weapon_smoke.start_tracking_ok = evt.weapon:start_tracking({rate = 30})
  -- Wire on_impact AND a bus subscriber BEFORE flight time elapses
  -- (the shell may impact at any moment within the next ~10 seconds).
  _G._sms_weapon_smoke.impact_callback_fired = 0
  _G._sms_weapon_smoke.bus_event_fired      = 0
  _G._sms_weapon_smoke.bus_event_payload    = nil
  evt.weapon:on_impact(function(weapon)
    _G._sms_weapon_smoke.impact_callback_fired = _G._sms_weapon_smoke.impact_callback_fired + 1
  end)
  sms.events.connect(sms.events.WEAPON_IMPACT, function(bus_evt)
    -- Filter to OUR weapon (defensive vs concurrent agents firing weapons).
    if bus_evt.weapon and bus_evt.weapon:get_name() == evt.weapon:get_name() then
      _G._sms_weapon_smoke.bus_event_fired   = _G._sms_weapon_smoke.bus_event_fired + 1
      _G._sms_weapon_smoke.bus_event_payload = bus_evt
    end
  end)
end)
"@
    Invoke-Smoke -Code $subscribeShot | Out-Null

    # Push a FireAtPoint task to the artillery. expendCnt=1 limits to one shell.
    $pushFireTask = @"
local u = Unit.getByName(_G._sms_weapon_smoke.arty_unit)
if u then
  local controller = u:getController()
  controller:pushTask({
    id = "FireAtPoint",
    params = {
      point     = { x = _G._sms_weapon_smoke.target_pos.x, y = _G._sms_weapon_smoke.target_pos.z },
      radius    = 5,
      expendQty = 1,
      expendQtyEnabled = true,
    },
  })
end
"@
    Invoke-Smoke -Code $pushFireTask | Out-Null

    # Wait for the shell to fire. M109 has a short prep time.
    Start-Sleep -Seconds 20

    Expect-True -Label 'SHOT event was captured' `
        -Code 'return _G._sms_weapon_smoke.shot_evt ~= nil'
    Expect-True -Label 'evt.weapon is an sms.weapon handle' `
        -Code 'local e = _G._sms_weapon_smoke.shot_evt; return e and type(e.weapon) == "table" and type(e.weapon.get_name) == "function"'
    Expect-EqString -Label 'evt.weapon:get_category() is shell' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:get_category()' -Expected 'shell'
    Expect-True -Label 'evt.weapon:is_shell() is true' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:is_shell()'
    Expect-True -Label 'evt.weapon:is_bomb() is false' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:is_bomb() == false'
    Expect-True -Label 'evt.weapon:get_launcher() returns a unit handle' `
        -Code 'local l = _G._sms_weapon_smoke.shot_evt.weapon:get_launcher(); return type(l) == "table" and l.name == _G._sms_weapon_smoke.arty_unit'
    Expect-EqString -Label 'evt.weapon state captured at SHOT time' `
        -Code 'return _G._sms_weapon_smoke.captured_state_at_shot' -Expected 'created'
    Expect-True -Label 'evt.weapon:get_release_position() returns a vec3' `
        -Code 'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_release_position(); return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
    Expect-True -Label 'evt.weapon_type back-compat string still present' `
        -Code 'return type(_G._sms_weapon_smoke.shot_evt.weapon_type) == "string"'

    Write-Host "==> tracking -- start_tracking ran in SHOT handler; verify tick path"
    Expect-True -Label 'start_tracking (called in SHOT handler) returned true' `
        -Code 'return _G._sms_weapon_smoke.start_tracking_ok == true'
    Expect-True -Label 'on_tick fired multiple times during flight' `
        -Code 'return _G._sms_weapon_smoke.tick_count >= 5'
    Expect-True -Label 'last_pos is a valid vec3' `
        -Code 'local p = _G._sms_weapon_smoke.last_pos; return p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
    Expect-True -Label 'double start_tracking returns false' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:start_tracking() == false'

    Write-Host "==> impact -- verify callback + bus emit + impact getters"
    Expect-Eq -Label 'on_impact callback fired exactly once' `
        -Code 'return _G._sms_weapon_smoke.impact_callback_fired' -Expected 1
    Expect-Eq -Label 'WEAPON_IMPACT bus event fired exactly once' `
        -Code 'return _G._sms_weapon_smoke.bus_event_fired' -Expected 1
    Expect-EqString -Label 'weapon state is impacted' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:get_state()' -Expected 'impacted'
    Expect-True -Label 'is_tracking returns false after impact' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:is_tracking() == false'
    Expect-True -Label 'is_alive returns false after impact' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:is_alive() == false'
    Expect-True -Label 'get_impact_position returns a vec3' `
        -Code 'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_position(); return p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
    Expect-True -Label 'get_last_known_position returns a vec3' `
        -Code 'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_last_known_position(); return p and type(p.x) == "number"'
    Expect-True -Label 'get_impact_distance_from(vec3) returns a non-negative number' `
        -Code 'local d = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_distance_from(_G._sms_weapon_smoke.target_pos); return type(d) == "number" and d >= 0'
    Expect-True -Label 'bus event payload has weapon, impact_position, time' `
        -Code 'local e = _G._sms_weapon_smoke.bus_event_payload; return e and e.weapon and e.impact_position and type(e.time) == "number"'
    Expect-True -Label 'impact landed within reasonable distance of target (within 200m)' `
        -Code 'local d = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_distance_from(_G._sms_weapon_smoke.target_pos); return d < 200'

    # destroy() on an impacted weapon is rejected (Option A from issue #18):
    # "impacted" and "destroyed" describe genuinely different outcomes, so
    # destroy()-after-impact returns false and leaves state as "impacted".
    Expect-True -Label 'destroy() on impacted weapon returns false' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:destroy() == false'
    Expect-EqString -Label 'state remains "impacted" after rejected destroy()' `
        -Code 'return _G._sms_weapon_smoke.shot_evt.weapon:get_state()' -Expected 'impacted'

    Write-Host "==> destroy() -- silent abort (no impact event)"
    $spawnDestroyArty = @"
_G._sms_weapon_smoke.destroy_test = {
  arty_group     = nil,
  arty_unit      = nil,
  target_pos     = {x = -39500, y = 0, z = -40000},  -- different region, 500m east
  weapon         = nil,
  callback_fired = 0,
  bus_fired      = 0,
}
local g = sms.group.create({
  name = "smoke_weapon_arty_destroy",
  position = {x = -40000, y = 0, z = -40000},
  country = sms.K.countries.USA,
  category = sms.K.category.GROUND,
  units = {{ type = "M-109", offset = {x = 0, y = 0, z = 0}, heading = 90 }},
})
if g then
  _G._sms_weapon_smoke.destroy_test.arty_group = g:get_name()
  _G._sms_weapon_smoke.destroy_test.arty_unit  = g:get_units()[1]:get_name()
  -- Anchor target y to terrain (consistency with the first arty section).
  _G._sms_weapon_smoke.destroy_test.target_pos.y = land.getHeight({
    x = _G._sms_weapon_smoke.destroy_test.target_pos.x,
    y = _G._sms_weapon_smoke.destroy_test.target_pos.z,
  })
end

-- Closure-local latch -- defends against orphaned SHOT handlers from
-- earlier smoke runs. Same pattern as the first arty SHOT handler.
local fired = false
sms.events.connect(sms.events.SHOT, function(evt)
  if fired then return end
  if not evt.weapon then return end
  local launcher = evt.weapon:get_launcher()
  if not launcher or launcher.name ~= _G._sms_weapon_smoke.destroy_test.arty_unit then return end
  fired = true
  _G._sms_weapon_smoke.destroy_test.weapon = evt.weapon
  evt.weapon:on_impact(function(_)
    _G._sms_weapon_smoke.destroy_test.callback_fired = _G._sms_weapon_smoke.destroy_test.callback_fired + 1
  end)
  evt.weapon:start_tracking({rate = 30})
end)

-- Bus subscriber filtered to OUR weapon (defensive vs concurrent agents).
sms.events.connect(sms.events.WEAPON_IMPACT, function(bus_evt)
  if bus_evt.weapon and _G._sms_weapon_smoke.destroy_test.weapon
     and bus_evt.weapon:get_name() == _G._sms_weapon_smoke.destroy_test.weapon:get_name() then
    _G._sms_weapon_smoke.destroy_test.bus_fired = _G._sms_weapon_smoke.destroy_test.bus_fired + 1
  end
end)

local u = Unit.getByName(_G._sms_weapon_smoke.destroy_test.arty_unit)
if u then
  u:getController():pushTask({
    id = "FireAtPoint",
    params = {
      point     = { x = _G._sms_weapon_smoke.destroy_test.target_pos.x,
                    y = _G._sms_weapon_smoke.destroy_test.target_pos.z },
      radius    = 5,
      expendQty = 1,
      expendQtyEnabled = true,
    },
  })
end
"@
    Invoke-Smoke -Code $spawnDestroyArty | Out-Null

    # Poll-and-destroy in a single exec call: as soon as the shell is tracking,
    # call destroy() in the SAME Lua frame to avoid a race where the shell
    # impacts naturally between the poll and the destroy. The flight time at
    # 500m is short (~2-3s). M-109 prep time can be ~15-30s, so the polling
    # envelope below covers up to 60s of waiting.
    Write-Host "    waiting for shell to fire and tracking to start..."
    $pollCode = @"
local s = _G._sms_weapon_smoke.destroy_test
if s.weapon == nil or not s.weapon:is_tracking() then return false end
s.destroy_first  = s.weapon:destroy()
s.destroy_second = s.weapon:destroy()
s.state_after    = s.weapon:get_state()
return true
"@
    for ($i = 1; $i -le 120; $i++) {
        # Atomic "if tracking, destroy immediately" -- eliminates the race
        # between observing tracking state and the destroy call.
        $r = Invoke-Smoke -Code $pollCode
        if ($r.return_value -eq $true) {
            $approx = [int]($i / 2)
            Write-Host "    shell tracking + destroyed after $i polls (~${approx}s)"
            break
        }
        Start-Sleep -Milliseconds 500
    }

    Expect-EqString -Label 'second weapon reached destroyed state in poll-and-destroy' `
        -Code 'return _G._sms_weapon_smoke.destroy_test.state_after' -Expected 'destroyed'

    # Wait an additional moment to confirm no late impact callbacks slip in.
    Start-Sleep -Seconds 3

    Expect-True -Label 'destroy() returned true on first call' `
        -Code 'return _G._sms_weapon_smoke.destroy_test.destroy_first == true'
    Expect-True -Label 'destroy() returned false on second call (idempotent)' `
        -Code 'return _G._sms_weapon_smoke.destroy_test.destroy_second == false'
    Expect-EqString -Label 'state is destroyed' `
        -Code 'return _G._sms_weapon_smoke.destroy_test.state_after' -Expected 'destroyed'
    Expect-Eq -Label 'on_impact did NOT fire after destroy()' `
        -Code 'return _G._sms_weapon_smoke.destroy_test.callback_fired' -Expected 0
    Expect-Eq -Label 'WEAPON_IMPACT bus event did NOT fire after destroy()' `
        -Code 'return _G._sms_weapon_smoke.destroy_test.bus_fired' -Expected 0
}
finally {
    Clear-SmokeFixtures -Names $fixtures
}

Write-SmokeSummary
