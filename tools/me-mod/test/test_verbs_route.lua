-- test_verbs_route.lua — Lua-side unit tests for verbs.lua route/waypoint
-- verbs. Uses mock_me_mission.lua for a synthetic mission table.
--
-- Run via:
--   cd tools/me-mod/test && lua test_verbs_route.lua
-- Or through the harness:
--   pwsh tools/me-mod/test/run-tests.ps1

-- Adjust package.path so require('mock_me_mission') works regardless of
-- which directory we run from (tools/me-mod/test or anywhere else).
local here = (arg and arg[0] and arg[0]:match('^(.*[\\/])')) or './'
package.path = here .. '?.lua;' .. package.path

-- Inject the mock BEFORE requiring verbs.lua so the verbs' calls to
-- require('me_mission') return our mock.
local mock = require('mock_me_mission')
package.preload['me_mission'] = function() return mock end

-- verbs.lua lives under tools/me-mod/lua/dcs_sms_me/. Adjust path so its
-- 'dcs_sms_me.*' requires resolve. The bridge installer copies these
-- under the ME's package.path; here we have to point at the source tree.
package.path = here .. '../lua/?.lua;' .. here .. '../lua/?/init.lua;' .. package.path

local verbs = require('dcs_sms_me.verbs')

-- ============================================================
-- Test helpers
-- ============================================================

local passed, failed, errors = 0, 0, {}

local function assert_eq(actual, expected, name)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        table.insert(errors, string.format(
            "%s: expected %s, got %s",
            name, tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, name)
    assert_eq(cond and true or false, true, name)
end

local function assert_false(cond, name)
    assert_eq(cond and true or false, false, name)
end

local function assert_contains(haystack, needle, name)
    if type(haystack) == 'string' and haystack:find(needle, 1, true) then
        passed = passed + 1
    else
        failed = failed + 1
        table.insert(errors, string.format(
            "%s: expected string containing %q, got %s",
            name, needle, tostring(haystack)))
    end
end

local function deep_eq(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
    for k, v in pairs(b) do if not deep_eq(v, a[k]) then return false end end
    return true
end

local function assert_deep_eq(actual, expected, name)
    if deep_eq(actual, expected) then
        passed = passed + 1
    else
        failed = failed + 1
        table.insert(errors, string.format(
            "%s: deep_eq failed", name))
    end
end

-- ============================================================
-- Smoke test — verify mock + verbs module both load cleanly
-- ============================================================

local function test_smoke()
    mock.new_mission()
    local g = mock.add_plane({ name = 'smoke-1' })
    assert_true(g ~= nil, 'smoke: add_plane returns a group')
    assert_eq(g.name, 'smoke-1', 'smoke: group name set')
    assert_true(#g.route.points == 1, 'smoke: group has a default waypoint')
end

-- ============================================================
-- Helper tests — exercised through public verbs but with focused
-- assertions on inheritance / range-checking behaviour.
-- ============================================================

local function test_find_route_happy()
    mock.new_mission()
    local g = mock.add_plane({ name = 'h1' })
    local res = verbs.route_list({ name = 'h1' })
    assert_true(res.ok, 'find_route: by name → ok')
    assert_eq(res.group, 'h1', 'find_route: returns group name')
    assert_eq(#res.points, 1, 'find_route: default route has 1 wp')
end

local function test_find_route_not_found()
    mock.new_mission()
    local res = verbs.route_list({ name = 'nope' })
    assert_false(res.ok, 'find_route: missing group → not ok')
    assert_contains(res.error, 'group not found', 'find_route: error message')
end

local function test_find_route_args_mutex()
    mock.new_mission()
    local r1 = verbs.route_list({ name = 'a', id = 1 })
    assert_false(r1.ok, 'find_route: both name and id rejected')
    local r2 = verbs.route_list({})
    assert_false(r2.ok, 'find_route: neither name nor id rejected')
end

local function test_find_waypoint_range()
    mock.new_mission()
    local g = mock.add_plane({ name = 'wp1' })
    -- add two more WPs to make the route 3 deep
    table.insert(g.route.points, mock.make_waypoint('plane', { x = 1000, y = 2000 }))
    table.insert(g.route.points, mock.make_waypoint('plane', { x = 2000, y = 3000 }))
    local r_ok = verbs.waypoint_get({ name = 'wp1', index = 2 })
    assert_true(r_ok.ok, 'find_waypoint: index 2 of 3 → ok')
    local r_oob = verbs.waypoint_get({ name = 'wp1', index = 3 })
    assert_false(r_oob.ok, 'find_waypoint: index 3 of 3 → out of range')
    assert_contains(r_oob.error, 'out of range', 'find_waypoint: out-of-range message')
    local r_neg = verbs.waypoint_get({ name = 'wp1', index = -1 })
    assert_false(r_neg.ok, 'find_waypoint: negative index rejected')
end

local function test_inherit_waypoint_empty_route_uses_category_defaults()
    mock.new_mission()
    local g = mock.add_plane({ name = 'inh1' })
    g.route.points = {}  -- empty route
    local r = verbs.waypoint_add({ name = 'inh1', north = 100, east = 200 })
    assert_true(r.ok, 'inherit (plane, empty): add → ok')
    local wp = g.route.points[1]
    assert_eq(wp.alt, 8000, 'inherit (plane, empty): alt = 8000')
    assert_eq(wp.alt_type, 'BARO', 'inherit (plane, empty): alt_type = BARO')
    assert_eq(wp.speed, 220, 'inherit (plane, empty): speed = 220')
    assert_eq(wp.type, 'Turning Point', 'inherit (plane, empty): type')
    assert_eq(wp.action, 'Turning Point', 'inherit (plane, empty): action')
end

local function test_inherit_waypoint_from_source()
    mock.new_mission()
    local g = mock.add_helicopter({ name = 'inh2' })
    -- mutate the existing WP so we can verify inheritance differs from defaults
    g.route.points[1].alt = 1234
    g.route.points[1].speed = 77
    g.route.points[1].formation_template = 'Diamond'
    -- add a WP with task non-empty on source so we can verify task is wiped
    g.route.points[1].task.params.tasks = { { id = 'Orbit', params = {} } }
    local r = verbs.waypoint_add({ name = 'inh2', north = 500, east = 600 })
    assert_true(r.ok, 'inherit (helo, from source): add → ok')
    local wp = g.route.points[2]
    assert_eq(wp.alt, 1234, 'inherit: alt from source')
    assert_eq(wp.speed, 77, 'inherit: speed from source')
    assert_eq(wp.formation_template, 'Diamond', 'inherit: formation from source')
    assert_eq(wp.name, '', 'inherit: name NOT inherited (empty)')
    assert_eq(wp.ETA, 0, 'inherit: ETA NOT inherited (0)')
    assert_deep_eq(wp.task,
        { id = 'ComboTask', params = { tasks = {} } },
        'inherit: task is empty ComboTask regardless of source')
end

local function test_inherit_overrides_win()
    mock.new_mission()
    local g = mock.add_plane({ name = 'inh3' })
    local r = verbs.waypoint_add({
        name = 'inh3', north = 100, east = 200,
        alt = 5000, speed = 180, alt_type = 'RADIO',
        type = 'Land', action = 'Landing',
    })
    assert_true(r.ok, 'inherit (overrides win): ok')
    local wp = g.route.points[2]
    assert_eq(wp.alt, 5000, 'override: alt')
    assert_eq(wp.speed, 180, 'override: speed')
    assert_eq(wp.alt_type, 'RADIO', 'override: alt_type')
    assert_eq(wp.type, 'Land', 'override: type')
    assert_eq(wp.action, 'Landing', 'override: action')
end

local function test_route_list_summary_fields()
    mock.new_mission()
    local g = mock.add_plane({ name = 'rl1', x = 100, y = 200 })
    g.route.points[1].name = 'WP0'
    g.route.points[1].task.params.tasks = { { id = 'Orbit', params = {} } }
    table.insert(g.route.points, mock.make_waypoint('plane', { x = 1000, y = 2000, name = 'WP1' }))
    local r = verbs.route_list({ name = 'rl1' })
    assert_true(r.ok, 'route_list: ok')
    assert_eq(#r.points, 2, 'route_list: 2 points')
    assert_eq(r.points[1].index, 0, 'route_list: index 0 first')
    assert_eq(r.points[1].name, 'WP0', 'route_list: name preserved')
    assert_eq(r.points[1].north, 100, 'route_list: north mapping')
    assert_eq(r.points[1].east, 200, 'route_list: east mapping')
    assert_true(r.points[1].has_task, 'route_list: has_task true when tasks present')
    assert_false(r.points[2].has_task, 'route_list: has_task false when empty')
end

local function test_route_get_preserves_task()
    mock.new_mission()
    local g = mock.add_helicopter({ name = 'rg1' })
    g.route.points[1].task.params.tasks = {
        { id = 'Orbit', params = { altitude = 500, pattern = 'Circle' } }
    }
    local r = verbs.route_get({ name = 'rg1' })
    assert_true(r.ok, 'route_get: ok')
    assert_eq(#r.route.points, 1, 'route_get: 1 point')
    assert_eq(r.route.points[1].task.params.tasks[1].id, 'Orbit',
              'route_get: task subtree preserved verbatim')
    assert_eq(r.route.points[1].task.params.tasks[1].params.altitude, 500,
              'route_get: task params preserved')
end

local function test_route_clear_ground()
    mock.new_mission()
    local g = mock.add_vehicle({ name = 'rc1' })
    -- 3 points
    table.insert(g.route.points, mock.make_waypoint('vehicle'))
    table.insert(g.route.points, mock.make_waypoint('vehicle'))
    assert_eq(#g.route.points, 3, 'route_clear-setup: 3 pts')
    local r = verbs.route_clear({ name = 'rc1' })
    assert_true(r.ok, 'route_clear (ground): ok')
    assert_eq(r.points_removed, 3, 'route_clear: returns count')
    assert_eq(#g.route.points, 0, 'route_clear: route is empty')
end

local function test_route_clear_air_refused()
    mock.new_mission()
    local g = mock.add_plane({ name = 'rc2' })
    local r = verbs.route_clear({ name = 'rc2' })
    assert_false(r.ok, 'route_clear (air): refused')
    assert_contains(r.error, 'air group', 'route_clear (air): air-group error message')
    assert_eq(#g.route.points, 1, 'route_clear (air): route untouched')
end

local function test_waypoint_get_full_fields()
    mock.new_mission()
    local g = mock.add_plane({ name = 'wg1', x = 50, y = 60 })
    g.route.points[1].name = 'IP'
    g.route.points[1].alt = 6000
    g.route.points[1].speed = 250
    local r = verbs.waypoint_get({ name = 'wg1', index = 0 })
    assert_true(r.ok, 'waypoint_get: ok')
    assert_eq(r.waypoint.name, 'IP', 'waypoint_get: name')
    assert_eq(r.waypoint.alt, 6000, 'waypoint_get: alt')
    assert_eq(r.waypoint.speed, 250, 'waypoint_get: speed')
    assert_eq(r.waypoint.task.id, 'ComboTask', 'waypoint_get: task field present')
end

local function test_refresh_called_on_clear()
    mock.new_mission()
    local g = mock.add_vehicle({ name = 'rf1' })
    mock.reset_refresh_counters()
    verbs.route_clear({ name = 'rf1' })
    assert_eq(mock.refresh_calls.update, 1, 'route_clear: update_group_map_objects called once')
end

-- ============================================================
-- Test runner
-- ============================================================

test_smoke()
test_find_route_happy()
test_find_route_not_found()
test_find_route_args_mutex()
test_find_waypoint_range()
test_inherit_waypoint_empty_route_uses_category_defaults()
test_inherit_waypoint_from_source()
test_inherit_overrides_win()
test_route_list_summary_fields()
test_route_get_preserves_task()
test_route_clear_ground()
test_route_clear_air_refused()
test_waypoint_get_full_fields()
test_refresh_called_on_clear()

print(string.format('test_verbs_route: %d passed, %d failed', passed, failed))
for _, e in ipairs(errors) do print('  FAIL: ' .. e) end
os.exit(failed == 0 and 0 or 1)
