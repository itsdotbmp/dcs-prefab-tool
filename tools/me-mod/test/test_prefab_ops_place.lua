-- Standalone test for prefab_ops place math (rotate + translate).
-- The ME-API injection itself is not unit-testable; covered by manual smoke.
-- Run via: lua test_prefab_ops_place.lua  (cwd: tools/me-mod/test/)

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             dir = function() return function() return nil end end }
end
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function approx(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) <= eps
end

-- Math helper: place_xy(rel_x, rel_y, anchor, rotation_deg) → (world_x, world_y)
do
    local x, y = prefab_ops._place_xy(100, 0, { x = 1000, y = 2000 }, 0)
    check('rot 0: (100, 0) at anchor (1000, 2000) → (1100, 2000)',
          approx(x, 1100) and approx(y, 2000), 'got ' .. x .. ', ' .. y)

    local x2, y2 = prefab_ops._place_xy(100, 0, { x = 0, y = 0 }, 90)
    check('rot 90: (100, 0) → (0, 100)',
          approx(x2, 0) and approx(y2, 100), 'got ' .. x2 .. ', ' .. y2)

    local x3, y3 = prefab_ops._place_xy(0, 100, { x = 0, y = 0 }, 90)
    check('rot 90: (0, 100) → (-100, 0)',
          approx(x3, -100) and approx(y3, 0), 'got ' .. x3 .. ', ' .. y3)

    local x4, y4 = prefab_ops._place_xy(100, 0, { x = 500, y = 500 }, 180)
    check('rot 180: (100, 0) at anchor (500, 500) → (400, 500)',
          approx(x4, 400) and approx(y4, 500), 'got ' .. x4 .. ', ' .. y4)
end

-- Heading composition: world_heading_deg = (file_heading_deg + rotation_deg) mod 360
do
    check('heading 30 + rotation 60 = 90', prefab_ops._heading_world(30, 60) == 90)
    check('heading 350 + rotation 20 = 10', prefab_ops._heading_world(350, 20) == 10)
    check('heading -30 + rotation 0 = 330', prefab_ops._heading_world(-30, 0) == 330)
end

-- Resolve effective anchor: keep_position uses meta.world_anchor.
do
    local prefab = { meta = { world_anchor = { x = 5000, y = 6000 } }, groups = {}, statics = {}, zones = {}, drawings = {} }
    local a, r = prefab_ops._resolve_anchor(prefab, { keep_position = true, anchor = { x = 1, y = 1 }, rotation = 30 })
    check('keep_position: anchor from meta', a.x == 5000 and a.y == 6000)
    check('keep_position: rotation forced 0', r == 0)

    local a2, r2 = prefab_ops._resolve_anchor(prefab, { anchor = { x = 100, y = 200 }, rotation = 45 })
    check('non-keep_position: anchor from opts', a2.x == 100 and a2.y == 200)
    check('non-keep_position: rotation passed through', r2 == 45)

    local a3 = prefab_ops._resolve_anchor(prefab, { rotation = 0 })
    check('no anchor + no keep_position: returns nil', a3 == nil)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops place tests passed.')
