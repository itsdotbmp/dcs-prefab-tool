-- Standalone Lua 5.1 test suite for framework/utils_serialize.lua.
-- Mirrors the parity tests for tools/me-mod/lua/dcs_sms_me/serializer.lua,
-- with framework-specific shimming.
--
-- Run via: lua test_utils_serialize.lua  (cwd: framework/test/)

-- Stub the framework's module-init contract so utils_serialize.lua loads
-- standalone (it expects sms and sms.log already present).
sms = {}
sms.log = { module = function() return { warn = function() end, error = function() end, info = function() end, debug = function() end } end }

package.path = '../?.lua;' .. package.path
sms.utils = sms.utils or {}
dofile('../utils_serialize.lua')

local serialize = sms.utils.serialize

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name) else
        print('FAIL ' .. name .. ': ' .. tostring(msg))
        failures = failures + 1
    end
end

local function tables_equal(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not tables_equal(v, b[k]) then return false end end
    for k, _ in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function roundtrip(value)
    local chunk = serialize(value)
    local fn, err = loadstring(chunk)
    if not fn then return nil, 'loadstring failed: ' .. tostring(err) .. '\n' .. chunk end
    local ok, result = pcall(fn)
    if not ok then return nil, 'eval failed: ' .. tostring(result) end
    return result
end

-- 1. Flat numeric array round-trip.
do
    local input = {1, 2, 3}
    local out, err = roundtrip(input)
    check('flat numeric array', out and tables_equal(input, out), err)
end

-- 2. Mixed key shape (the DCS callsign).
do
    local input = {[1] = 3, [2] = 1, [3] = 1, name = 'Uzi11'}
    local out, err = roundtrip(input)
    check('mixed numeric+string keys', out and tables_equal(input, out), err)
end

-- 3. Nested mixed types.
do
    local input = {
        name = 'Convoy',
        x = 12345.5,
        y = -678.25,
        active = true,
        units = {
            [1] = {type = 'M-1', heading = 0},
            [2] = {type = 'M-2', heading = 1.57},
        },
    }
    local out, err = roundtrip(input)
    check('nested mixed types', out and tables_equal(input, out), err)
end

-- 4. Cycle detection.
do
    local input = {name = 'ouroboros'}
    input.self = input
    local chunk = serialize(input)
    check('cycle marker present', chunk:find('cycle', 1, true) ~= nil, chunk)
end

-- 5. Top-level "return ...".
do
    local chunk = serialize({x = 1})
    check('top-level return prefix', chunk:match('^return%s') ~= nil, chunk)
end

-- 6. Inf number key.
do
    local input = {[math.huge] = 'x'}
    local out, err = roundtrip(input)
    check('inf number key roundtrips', out and out[math.huge] == 'x', err)
end

-- 7. Stable byte output across two runs.
do
    local input = {z = 1, a = 2, m = 3, b = 4}
    local first  = serialize(input)
    local second = serialize(input)
    check('output is byte-stable', first == second, 'differ:\n' .. first .. '\n---\n' .. second)
end

-- 8. Empty table.
do
    local out, err = roundtrip({})
    check('empty table', out and tables_equal({}, out), err)
end

if failures > 0 then
    print(string.format('\n%d test(s) FAILED', failures))
    os.exit(1)
else
    print('\nall tests passed')
    os.exit(0)
end
