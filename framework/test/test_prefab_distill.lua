-- Standalone Lua 5.1 test suite for framework/prefab_distill.lua.
-- Run via: lua test_prefab_distill.lua  (cwd: framework/test/)

-- Stub framework module-init contract.
sms = {}
sms.log = { module = function() return { warn = function() end, error = function() end, info = function() end, debug = function() end } end }
sms.utils = sms.utils or {}

-- Minimal sms.K.statics so distill's partition can recognize static type names.
sms.K = sms.K or {}
sms.K.statics = sms.K.statics or { ['Hangar A'] = true }

package.path = '../?.lua;' .. package.path
dofile('../prefab_distill.lua')

local distill = sms.prefab.distill

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name) else
        print('FAIL ' .. name .. ': ' .. tostring(msg))
        failures = failures + 1
    end
end

-- Recursive scan for any key named "boss".
local function has_boss(tbl, seen)
    seen = seen or {}
    if type(tbl) ~= 'table' or seen[tbl] then return false end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if k == 'boss' then return true end
        if type(v) == 'table' and has_boss(v, seen) then return true end
    end
    return false
end

-- Approximately equal for floating-point comparisons.
local function approx(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) <= eps
end

-- 1. Real fixture dump: distill returns a non-nil prefab.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab', theatre = 'Caucasus'})
    check('distill returns non-nil for fixture', prefab ~= nil, 'got nil')
end

-- 2. boss is gone everywhere.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('no boss key anywhere in output', prefab and not has_boss(prefab),
        'boss still present')
end

-- 3. Centroid math: 4 entities at (0,0), (100,200), (50,100), (100,200) → centroid is (62.5, 125).
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('world_anchor in meta is centroid (x)',
        prefab and prefab.meta and approx(prefab.meta.world_anchor.x, 62.5),
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.world_anchor and prefab.meta.world_anchor.x))
    check('world_anchor in meta is centroid (y)',
        prefab and prefab.meta and approx(prefab.meta.world_anchor.y, 125),
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.world_anchor and prefab.meta.world_anchor.y))
end

-- 4. Group coords are anchor-relative.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('group 1 x is anchor-relative (-62.5)',
        prefab and prefab.groups[1] and approx(prefab.groups[1].x, -62.5),
        'got ' .. tostring(prefab and prefab.groups[1] and prefab.groups[1].x))
    check('group 1 y is anchor-relative (-125)',
        prefab and prefab.groups[1] and approx(prefab.groups[1].y, -125),
        'got ' .. tostring(prefab and prefab.groups[1] and prefab.groups[1].y))
end

-- 5. Unit heading converted rad → deg (math.pi/2 → 90).
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    local h = prefab and prefab.groups[1] and prefab.groups[1].units[1].heading
    check('unit heading converted to degrees', h and approx(h, 90),
        'got ' .. tostring(h))
end

-- 6. Country captured from boss before strip.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('group 1 country = 11 (Belgium)',
        prefab and prefab.groups[1] and prefab.groups[1].country == 11,
        'got ' .. tostring(prefab and prefab.groups[1] and prefab.groups[1].country))
end

-- 7. Static partition: hangar ends up in statics, NOT groups.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('statics has 1 entry (Hangar A)',
        prefab and #prefab.statics == 1 and prefab.statics[1].name == 'Hangar A',
        'got ' .. tostring(prefab and #prefab.statics))
    check('groups has 1 entry (Aerial-1, not Hangar A)',
        prefab and #prefab.groups == 1 and prefab.groups[1].name == 'Aerial-1',
        'got ' .. tostring(prefab and #prefab.groups))
end

-- 8. Zone fidelity: properties preserved verbatim, center anchor-relative.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    local z = prefab and prefab.zones[1]
    check('zone properties preserved', z and z.properties and z.properties.alarm == 'yes',
        'properties missing or wrong')
    check('zone center anchor-relative x (~ -12.5)',
        z and approx(z.x, -12.5), 'got ' .. tostring(z and z.x))
    check('zone center anchor-relative y (~ -25)',
        z and approx(z.y, -25), 'got ' .. tostring(z and z.y))
    check('zone radius preserved', z and z.radius == 1500, 'got ' .. tostring(z and z.radius))
end

-- 9. Drawing fidelity: vertices and color preserved.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    local d = prefab and prefab.drawings[1]
    check('drawing has 3 points', d and #d.points == 3,
        'got ' .. tostring(d and #d.points))
    check('drawing color preserved', d and d.color and d.color[1] == 1,
        'color missing')
end

-- 10. Empty input returns nil.
do
    local result = distill({groups = {}, statics = {}, zones = {}, drawings = {}}, {name = 'empty'})
    check('empty dump returns nil', result == nil, 'got non-nil')
end

-- 11. Bad input returns nil.
do
    local result = distill(nil, {name = 'bad'})
    check('nil dump returns nil', result == nil, 'got non-nil')
end

-- 12. Meta block populated.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'sa6_template', theatre = 'Caucasus'})
    check('meta.name set from opts', prefab and prefab.meta and prefab.meta.name == 'sa6_template',
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.name))
    check('meta.theatre set from opts', prefab and prefab.meta and prefab.meta.theatre == 'Caucasus',
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.theatre))
    check('meta.sms_prefab_version set',
        prefab and prefab.meta and type(prefab.meta.sms_prefab_version) == 'string',
        'missing')
    check('meta.created_utc set',
        prefab and prefab.meta and type(prefab.meta.created_utc) == 'string',
        'missing')
end

if failures > 0 then
    print(string.format('\n%d test(s) FAILED', failures))
    os.exit(1)
else
    print('\nall tests passed')
    os.exit(0)
end
