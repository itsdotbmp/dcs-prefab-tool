-- Standalone Lua 5.1 test suite for tools/me-mod/lua/dcs_sms_me/serializer.lua.
-- Exits with non-zero status on first failure, prints PASS/FAIL per case.
-- Run via: lua test_serializer.lua  (cwd: tools/me-mod/test/)

package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local serializer = require('serializer')

local failures = 0
local function check(name, ok, msg)
    if ok then
        print('PASS ' .. name)
    else
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
    local chunk = serializer.serialize(value)
    local fn, err = loadstring(chunk)
    if not fn then return nil, 'loadstring failed: ' .. tostring(err) .. ' for chunk:\n' .. chunk end
    local ok, result = pcall(fn)
    if not ok then return nil, 'eval failed: ' .. tostring(result) end
    return result, nil
end

-- 1. Round-trip a flat numeric array.
do
    local input = {1, 2, 3}
    local out, err = roundtrip(input)
    check('flat numeric array', out and tables_equal(input, out), err)
end

-- 2. Round-trip the callsign shape (mixed numeric + string keys).
do
    local input = {[1] = 3, [2] = 1, [3] = 1, name = 'Uzi11'}
    local out, err = roundtrip(input)
    check('mixed numeric+string keys (callsign)', out and tables_equal(input, out), err)
end

-- 3. Round-trip nested tables with strings, numbers, booleans, nils.
do
    local input = {
        name = 'Convoy 1',
        x = 12345.5,
        y = -678.25,
        active = true,
        skill = 'Average',
        units = {
            [1] = {type = 'M-1 Abrams', heading = 0},
            [2] = {type = 'M-2 Bradley', heading = 1.57},
        },
    }
    local out, err = roundtrip(input)
    check('nested mixed types', out and tables_equal(input, out), err)
end

-- 4. Cycle detection: self-referencing table emits a marker, doesn't loop.
do
    local input = {name = 'ouroboros'}
    input.self = input
    local chunk = serializer.serialize(input)
    -- Marker form is "--[[ cycle ]]". Use plain find on the literal substring.
    check('cycle detection emits marker',
        chunk:find('cycle', 1, true) ~= nil,
        'no cycle marker in: ' .. chunk)
end

-- 5. Unsupported types (function/userdata/thread) emit nil placeholder.
do
    local input = {fn = function() end, n = 42}
    local out, err = roundtrip(input)
    check('function emits nil placeholder',
        out and out.n == 42 and out.fn == nil, err)
end

-- 6. Output is byte-identical across two runs (keys always sorted).
do
    local input = {z = 1, a = 2, m = 3, b = 4}
    local first  = serializer.serialize(input)
    local second = serializer.serialize(input)
    check('serialize is byte-stable', first == second,
        'differ:\n' .. first .. '\n---\n' .. second)
end

-- 7. Strings with quotes, backslashes, and newlines round-trip.
do
    local input = {s = 'hello "world"\nbackslash: \\'}
    local out, err = roundtrip(input)
    check('strings with quotes/backslash/newline', out and out.s == input.s, err)
end

-- 8. Top-level emits "return { ... }" (so dofile reconstitutes the value).
do
    local chunk = serializer.serialize({x = 1})
    check('top-level emits return statement',
        chunk:match('^return%s') ~= nil, chunk)
end

-- 9. Numeric keys always emitted as [N], not bare or implicit.
do
    local input = {[1] = 'a', [2] = 'b'}
    local chunk = serializer.serialize(input)
    check('numeric keys use [N] form',
        chunk:find('[1]', 1, true) ~= nil and chunk:find('[2]', 1, true) ~= nil,
        chunk)
end

-- 10. Empty table.
do
    local out, err = roundtrip({})
    check('empty table', out and tables_equal({}, out), err)
end

-- 11. Numeric-key infinity round-trips losslessly (regression: tostring(math.huge)
--     yields "1.#INF" on Windows Lua, which is not a valid Lua literal).
do
    local input = {[math.huge] = 'x'}
    local chunk = serializer.serialize(input)
    local fn, err = loadstring(chunk)
    if not fn then
        check('numeric-key inf round-trips', false,
            'loadstring failed: ' .. tostring(err) .. '\nchunk:\n' .. chunk)
    else
        local ok, result = pcall(fn)
        check('numeric-key inf round-trips',
            ok and type(result) == 'table' and result[math.huge] == 'x',
            'eval/lookup failed; chunk:\n' .. chunk)
    end
end

-- 12. Mutual cycles between two tables: must terminate and emit a cycle marker.
do
    local a, b = {name = 'a'}, {name = 'b'}
    a.b = b
    b.a = a
    local chunk = serializer.serialize(a)
    check('mutual cycles terminate with marker',
        chunk:find('cycle', 1, true) ~= nil,
        'no cycle marker in: ' .. chunk)
end

-- 13. Shared (but acyclic) sub-table: serialized in each location by current
--     design (no shared-reference deduplication). Document via test.
do
    local sub = {x = 1}
    local input = {first = sub, second = sub}
    local chunk = serializer.serialize(input)
    -- Count occurrences of '["x"] = 1' — should appear in both `first` and
    -- `second` (no shared-reference deduplication by current design).
    local needle = '["x"] = 1'
    local count, pos = 0, 1
    while true do
        local s, e = chunk:find(needle, pos, true)
        if not s then break end
        count = count + 1
        pos = e + 1
    end
    check('shared sub-table is duplicated (no dedup by design)',
        count == 2, 'expected 2 occurrences of ' .. needle .. ', got ' .. count
            .. '\nchunk:\n' .. chunk)
end

if failures > 0 then
    print(string.format('\n%d test(s) FAILED', failures))
    os.exit(1)
else
    print('\nall tests passed')
    os.exit(0)
end
