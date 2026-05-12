-- Parity test: framework/prefab_distill.lua vs tools/me-mod/lua/dcs_sms_me/prefab_distill.lua.
-- Both must produce deep-equal output for the same input.
-- Run via: lua test_distill_parity.lua  (cwd: tools/me-mod/test/)

-- 1) Load me-mod copy (module-style).
package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local memod_distill = require('prefab_distill').distill

-- 2) Load framework copy. Framework-style: stub sms, sms.log, sms.K.
sms = {}
sms.log = { module = function() return { warn=function() end, error=function() end, info=function() end, debug=function() end } end }
sms.K = { statics = {} }   -- empty catalog → both fall through to shape-inference
sms.prefab = nil
package.path = '../../../framework/?.lua;' .. package.path
dofile('../../../framework/prefab_distill.lua')
local fw_distill = sms.prefab.distill

-- Recursive deep-equal that ignores meta.created_utc (timestamp differs per call).
local function deep_equal(a, b, path)
    path = path or 'root'
    if type(a) ~= type(b) then return false, path .. ': type ' .. type(a) .. ' vs ' .. type(b) end
    if type(a) ~= 'table' then
        if a ~= b then return false, path .. ': ' .. tostring(a) .. ' vs ' .. tostring(b) end
        return true
    end
    for k, v in pairs(a) do
        if not (path == 'root.meta' and k == 'created_utc') then
            local ok, why = deep_equal(v, b[k], path .. '.' .. tostring(k))
            if not ok then return false, why end
        end
    end
    for k, _ in pairs(b) do
        if a[k] == nil and not (path == 'root.meta' and k == 'created_utc') then
            return false, path .. '.' .. tostring(k) .. ': missing in a'
        end
    end
    return true
end

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function load_dump(path)
    local f = assert(loadfile(path))
    return f()
end

local function assert_parity(name, dump, opts)
    local a = memod_distill(dump, opts)
    local b = fw_distill(dump, opts)
    if a == nil and b == nil then
        check(name .. ' (both nil)', true)
        return
    end
    if (a == nil) ~= (b == nil) then
        check(name, false, 'memod=' .. tostring(a) .. ' fw=' .. tostring(b))
        return
    end
    local ok, why = deep_equal(a, b)
    check(name, ok, why)
end

-- Case 1: real synthetic fixture.
local fixture = load_dump('fixtures/dump_synthetic_aerial.lua')
assert_parity('synthetic aerial fixture', fixture, {name='test', theatre='Caucasus'})

-- Case 2: minimal single group.
assert_parity('single group at origin', {
    groups = { { name='G1', x=0, y=0, units={ { name='U1', type='F-16C_50', x=0, y=0, heading=0 } } } }
}, {name='one'})

-- Case 3: two groups for centroid.
assert_parity('two groups for centroid', {
    groups = {
        { name='G1', x=0,   y=0,   units={ { name='U1', type='F-16C_50', x=0,   y=0,   heading=0 } } },
        { name='G2', x=200, y=400, units={ { name='U2', type='F-16C_50', x=200, y=400, heading=math.pi } } },
    }
}, {name='two'})

-- Case 4: opts.name missing → both should return nil.
assert_parity('no name → nil', { groups={ { x=0, y=0 } } }, {})

-- Case 5: empty dump → both should return nil.
assert_parity('empty dump → nil', { groups={}, statics={}, zones={}, drawings={} }, {name='empty'})

-- Case 6: zones + drawings mixed.
assert_parity('zones+drawings', {
    groups = {},
    statics = {},
    zones    = { { name='Z1', x=100, y=200, radius=50, type=0, properties={} } },
    drawings = { { name='D1', primitiveType='Polygon', mapData={ x=300, y=400 }, points={ {x=0,y=0}, {x=10,y=0}, {x=10,y=10} } } },
}, {name='zd'})

-- Case 7: mapObjects (the ME's render-side widget cache) gets stripped
-- during distill. Carrying it over caused GH#56 (duplicate target-zone
-- triangles on placement). Both copies must drop it.
do
    local with_mo = {
        groups = {
            {
                name = 'G1', x = 0, y = 0,
                mapObjects = {
                    route = {
                        points = { { x=0, y=0, id=12, classKey='RoutePoint' } },
                        targetZones = { [4] = { { id=65, classKey='S00000005' } } },
                    },
                    units = {}, zones = {},
                },
                units = { { name='U1', type='F-16C_50', x=0, y=0, heading=0 } },
            },
        },
    }
    local memod_out = memod_distill(with_mo, {name='strip-mo'})
    local fw_out    = fw_distill(with_mo,    {name='strip-mo'})
    check('mapObjects stripped (me-mod)',
          memod_out and memod_out.groups and memod_out.groups[1]
              and memod_out.groups[1].mapObjects == nil,
          'me-mod distill left mapObjects in the output')
    check('mapObjects stripped (framework)',
          fw_out and fw_out.groups and fw_out.groups[1]
              and fw_out.groups[1].mapObjects == nil,
          'framework distill left mapObjects in the output')
    assert_parity('mapObjects parity', with_mo, {name='strip-mo'})
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All distill-parity tests passed.')
