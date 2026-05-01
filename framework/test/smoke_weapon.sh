#!/usr/bin/env bash
# End-to-end smoke test for sms.weapon v1.
# Synthetic checks first (load + constants + bad-arg paths). Live DCS
# round-trip lives in later sections (added incrementally as tracking
# capabilities land per task).
# Requires DCS running, mission loaded, fresh heartbeat, sim unpaused.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FRAMEWORK_DIR}/.." && pwd)"
DCSSMS="${REPO_ROOT}/tools/dcs-sms.exe"

# Fixture cleanup: nukes anything this smoke spawns, even on mid-run
# abort (set -e). Idempotent — destroys only what currently exists.
# Keep this list in sync with the names this smoke creates.
SMOKE_FIXTURES="smoke_weapon_arty smoke_weapon_arty_destroy"

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

expect_true() {
  local label="$1"
  local code="$2"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q '"return_value":true' \
    || { echo "FAIL: ${label}: ${result}"; exit 1; }
}

expect_str() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":\"${expected}\"" \
    || { echo "FAIL: ${label} (expected '${expected}'): ${result}"; exit 1; }
}

expect_eq() {
  local label="$1"
  local code="$2"
  local expected="$3"
  local result
  result=$("${DCSSMS}" exec --code "${code}")
  echo "${result}" | grep -q "\"return_value\":${expected}," \
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
"${DCSSMS}" exec --file group_spawn.lua >/dev/null
"${DCSSMS}" exec --file static.lua >/dev/null
"${DCSSMS}" exec --file events.lua >/dev/null
"${DCSSMS}" exec --file weapon.lua >/dev/null

echo "==> WEAPON_IMPACT constant exists"
expect_str "WEAPON_IMPACT" 'return sms.events.WEAPON_IMPACT' 'weapon_impact'

echo "==> wrap with bad input returns nil"
expect_true "wrap nil"     'return sms.weapon.wrap(nil) == nil'
expect_true "wrap number"  'return sms.weapon.wrap(42) == nil'
expect_true "wrap string"  'return sms.weapon.wrap("hi") == nil'

echo "==> module getters reject non-handles"
expect_true "get_name on string"    'return sms.weapon.get_name("nope") == nil'
expect_true "get_type on nil"       'return sms.weapon.get_type(nil) == nil'
expect_true "get_state on number"   'return sms.weapon.get_state(7) == nil'
expect_true "is_bomb on string"     'return sms.weapon.is_bomb("nope") == false'

echo "==> verify [sms.weapon] log lines for bad args"
log_window=$("${DCSSMS}" tail-log --grep '\[sms.weapon\]' -n 100)
echo "${log_window}" | grep -q "wrap: argument must be a DCS weapon object" \
  || { echo "FAIL: missing log line for bad wrap arg"; echo "${log_window}"; exit 1; }
echo "${log_window}" | grep -q "get_name: argument must be an sms.weapon handle" \
  || { echo "FAIL: missing log line for bad get_name arg"; echo "${log_window}"; exit 1; }

echo "==> live DCS SHOT round-trip — spawn artillery and fire a shell"
"${DCSSMS}" status | grep -q "fresh: *true" \
  || { echo "FAIL: live DCS section requires fresh heartbeat (mission unpaused)"; exit 1; }

# Spawn an M109 self-propelled howitzer far from origin to avoid colliding
# with concurrent agents. Capture the resolved name (sms.spawn auto-suffixes).
"${DCSSMS}" exec --code '
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
' >/dev/null
expect_true "artillery spawned" \
  'return type(_G._sms_weapon_smoke.arty_unit) == "string" and _G._sms_weapon_smoke.arty_unit ~= ""'

# Subscribe to SHOT and, for the first shell whose launcher is our arty:
#   - capture the event,
#   - snapshot the pre-tracking state (Task 3 assertion checks this),
#   - wire on_tick and start_tracking immediately (Task 4 setup).
# Real users will do the same — they decide whether to track in the SHOT
# handler, not after a delay — so this also matches the canonical use case.
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
"${DCSSMS}" exec --code '
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
' >/dev/null

# Push a FireAtPoint task to the artillery. expendCnt=1 limits to one shell.
"${DCSSMS}" exec --code '
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
' >/dev/null

# Wait for the shell to fire. M109 has a short prep time.
sleep 20

expect_true "SHOT event was captured" \
  'return _G._sms_weapon_smoke.shot_evt ~= nil'
expect_true "evt.weapon is an sms.weapon handle" \
  'local e = _G._sms_weapon_smoke.shot_evt; return e and type(e.weapon) == "table" and type(e.weapon.get_name) == "function"'
expect_str "evt.weapon:get_category() is shell" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:get_category()' 'shell'
expect_true "evt.weapon:is_shell() is true" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_shell()'
expect_true "evt.weapon:is_bomb() is false" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_bomb() == false'
expect_true "evt.weapon:get_launcher() returns a unit handle" \
  'local l = _G._sms_weapon_smoke.shot_evt.weapon:get_launcher(); return type(l) == "table" and l.name == _G._sms_weapon_smoke.arty_unit'
expect_str "evt.weapon state captured at SHOT time" \
  'return _G._sms_weapon_smoke.captured_state_at_shot' 'created'
expect_true "evt.weapon:get_release_position() returns a vec3" \
  'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_release_position(); return p ~= nil and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
expect_true "evt.weapon_type back-compat string still present" \
  'return type(_G._sms_weapon_smoke.shot_evt.weapon_type) == "string"'

echo "==> tracking — start_tracking ran in SHOT handler; verify tick path"
expect_true "start_tracking (called in SHOT handler) returned true" \
  'return _G._sms_weapon_smoke.start_tracking_ok == true'
expect_true "on_tick fired multiple times during flight" \
  'return _G._sms_weapon_smoke.tick_count >= 5'
expect_true "last_pos is a valid vec3" \
  'local p = _G._sms_weapon_smoke.last_pos; return p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
expect_true "double start_tracking returns false" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:start_tracking() == false'

echo "==> impact — verify callback + bus emit + impact getters"
expect_eq "on_impact callback fired exactly once" \
  'return _G._sms_weapon_smoke.impact_callback_fired' 1
expect_eq "WEAPON_IMPACT bus event fired exactly once" \
  'return _G._sms_weapon_smoke.bus_event_fired' 1
expect_str "weapon state is impacted" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:get_state()' 'impacted'
expect_true "is_tracking returns false after impact" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_tracking() == false'
expect_true "is_alive returns false after impact" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:is_alive() == false'
expect_true "get_impact_position returns a vec3" \
  'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_position(); return p and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"'
expect_true "get_last_known_position returns a vec3" \
  'local p = _G._sms_weapon_smoke.shot_evt.weapon:get_last_known_position(); return p and type(p.x) == "number"'
expect_true "get_impact_distance_from(vec3) returns a non-negative number" \
  'local d = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_distance_from(_G._sms_weapon_smoke.target_pos); return type(d) == "number" and d >= 0'
expect_true "bus event payload has weapon, impact_position, time" \
  'local e = _G._sms_weapon_smoke.bus_event_payload; return e and e.weapon and e.impact_position and type(e.time) == "number"'
expect_true "impact landed within reasonable distance of target (within 200m)" \
  'local d = _G._sms_weapon_smoke.shot_evt.weapon:get_impact_distance_from(_G._sms_weapon_smoke.target_pos); return d < 200'

# destroy() on an impacted weapon is rejected (Option A from issue #18):
# "impacted" and "destroyed" describe genuinely different outcomes, so
# destroy()-after-impact returns false and leaves state as "impacted".
expect_true "destroy() on impacted weapon returns false" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:destroy() == false'
expect_str "state remains \"impacted\" after rejected destroy()" \
  'return _G._sms_weapon_smoke.shot_evt.weapon:get_state()' 'impacted'

echo "==> destroy() — silent abort (no impact event)"
"${DCSSMS}" exec --code '
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

  -- Closure-local latch — defends against orphaned SHOT handlers from
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
' >/dev/null

# Poll-and-destroy in a single exec call: as soon as the shell is tracking,
# call destroy() in the SAME Lua frame to avoid a race where the shell
# impacts naturally between the poll and the destroy. The flight time at
# 500m is short (~2-3s). M-109 prep time can be ~15-30s, so the polling
# envelope below covers up to 60s of waiting.
echo "    waiting for shell to fire and tracking to start..."
for i in $(seq 1 120); do
  # Atomic "if tracking, destroy immediately" — eliminates the race
  # between observing tracking state and the destroy call.
  result=$("${DCSSMS}" exec --code '
    local s = _G._sms_weapon_smoke.destroy_test
    if s.weapon == nil or not s.weapon:is_tracking() then return false end
    s.destroy_first  = s.weapon:destroy()
    s.destroy_second = s.weapon:destroy()
    s.state_after    = s.weapon:get_state()
    return true
  ')
  if echo "${result}" | grep -q '"return_value":true'; then
    echo "    shell tracking + destroyed after ${i} polls (~$((i / 2))s)"
    break
  fi
  sleep 0.5
done

expect_str "second weapon reached destroyed state in poll-and-destroy" \
  'return _G._sms_weapon_smoke.destroy_test.state_after' 'destroyed'

# Wait an additional moment to confirm no late impact callbacks slip in.
sleep 3

expect_true "destroy() returned true on first call" \
  'return _G._sms_weapon_smoke.destroy_test.destroy_first == true'
expect_true "destroy() returned false on second call (idempotent)" \
  'return _G._sms_weapon_smoke.destroy_test.destroy_second == false'
expect_str "state is destroyed" \
  'return _G._sms_weapon_smoke.destroy_test.state_after' 'destroyed'
expect_eq "on_impact did NOT fire after destroy()" \
  'return _G._sms_weapon_smoke.destroy_test.callback_fired' 0
expect_eq "WEAPON_IMPACT bus event did NOT fire after destroy()" \
  'return _G._sms_weapon_smoke.destroy_test.bus_fired' 0

# Cleanup destroy-test artillery group.
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_weapon_smoke.destroy_test.arty_group)
  if g then pcall(g.destroy, g) end
' >/dev/null

# Cleanup. Best-effort.
"${DCSSMS}" exec --code '
  local g = Group.getByName(_G._sms_weapon_smoke.arty_group)
  if g then pcall(g.destroy, g) end
' >/dev/null

echo "smoke ok"
