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
-- Test runner
-- ============================================================

test_smoke()

print(string.format('test_verbs_route: %d passed, %d failed', passed, failed))
for _, e in ipairs(errors) do print('  FAIL: ' .. e) end
os.exit(failed == 0 and 0 or 1)
