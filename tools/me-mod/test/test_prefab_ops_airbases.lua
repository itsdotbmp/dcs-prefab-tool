-- Standalone round-trip test for the airbase-supplies plumbing through
-- distill / save / load / scan_dir.
-- Run via: lua test_prefab_ops_airbases.lua  (cwd: tools/me-mod/test/)

local fake_writedir = 'C:\\fake-saved-games\\'
package.preload['lfs'] = function()
    return {
        writedir = function() return fake_writedir end,
        mkdir = function() return true end,
        attributes = function() return { mode = 'file' } end,
        dir = function() local i = 0; return function() i = i + 1; return nil end end,
    }
end

-- Capture writes.
local captured = { path = nil, content = nil }
local real_open = io.open
io.open = function(path, mode)
    if mode == 'w' then
        return {
            write = function(_, c) captured.path = path; captured.content = c end,
            close = function() end,
        }
    end
    return real_open(path, mode)
end

package.preload['Mission.TheatreOfWarData'] = function()
    return { getName = function() return 'Syria' end }
end

-- Selection stub matching the existing save tests.
package.preload['dcs_sms_me.selection'] = function()
    return {
        snapshot = function()
            return {
                ok = true, timestamp_utc = '2026-05-05T12:00:00Z', selection_mode = 'multi',
                groups = {
                    { name='G1', x=100, y=200,
                      units={ { name='U1', type='F-16C_50', x=100, y=200, heading=0 } },
                      boss = { id=2, name='USA' } },
                },
                statics = {}, zones = {}, drawings = {}, nav_points = {}, raw = {},
            }
        end,
    }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: round-trip via load() — saved file is loadable and meta.airbases is intact.
do
    captured.path, captured.content = nil, nil
    local airbases = {
        {
            name                    = 'Muwaffaq Salti',
            airdrome_number_at_save = 68,
            warehouse = {
                coalition = 'BLUE',
                unlimitedFuel = false,
                jet_fuel  = { InitFuel = 50 },
                aircrafts = { helicopters = { ["AH-64D"] = { initialAmount = 100 } }, planes = {} },
            },
        },
        {
            name                    = 'Khalde',
            airdrome_number_at_save = 12,
            warehouse = { coalition = 'NEUTRAL', jet_fuel = { InitFuel = 80 } },
        },
    }
    local ok, _ = prefab_ops.save_selection('two_bases', false, airbases)
    check('save returns ok', ok == true)

    -- Eval the captured serialized content.
    local fn, err = loadstring(captured.content)
    check('captured content loads', fn ~= nil, tostring(err))
    local prefab = fn and fn()
    check('prefab table returned', type(prefab) == 'table' and prefab.meta ~= nil)
    check('prefab.meta.sms_prefab_version == 0.3.0', prefab.meta.sms_prefab_version == '0.3.0',
          'got ' .. tostring(prefab and prefab.meta and prefab.meta.sms_prefab_version))
    check('prefab.meta.airbases has 2 entries',
          type(prefab.meta.airbases) == 'table' and #prefab.meta.airbases == 2,
          'got ' .. tostring(prefab.meta.airbases and #prefab.meta.airbases))
    check('first airbase name preserved', prefab.meta.airbases[1].name == 'Muwaffaq Salti')
    check('first airbase coalition preserved', prefab.meta.airbases[1].warehouse.coalition == 'BLUE')
    check('first airbase nested AH-64D preserved',
          prefab.meta.airbases[1].warehouse.aircrafts
          and prefab.meta.airbases[1].warehouse.aircrafts.helicopters
          and prefab.meta.airbases[1].warehouse.aircrafts.helicopters['AH-64D']
          and prefab.meta.airbases[1].warehouse.aircrafts.helicopters['AH-64D'].initialAmount == 100)
    check('second airbase preserved', prefab.meta.airbases[2].name == 'Khalde')
end

-- Case: save without airbases omits meta.airbases entirely (no churn for non-airbase prefabs).
do
    captured.path, captured.content = nil, nil
    local ok = prefab_ops.save_selection('no_bases')
    check('save without airbases returns ok', ok == true)
    check('content does not contain "airbases"',
          captured.content and not captured.content:find('airbases', 1, true),
          'unexpected airbases field')
end

-- Case: load() reads an airbases-bearing prefab from disk.
do
    local tmppath = os.tmpname()
    local f = real_open(tmppath, 'w')
    f:write([[return {
  meta = {
    sms_prefab_version = "0.3.0",
    name = "abtest",
    theatre = "Syria",
    world_anchor = { x = 0, y = 0 },
    airbases = {
      { name = "Muwaffaq Salti", airdrome_number_at_save = 68, warehouse = { coalition = "BLUE" } },
      { name = "Khalde",         airdrome_number_at_save = 12, warehouse = { coalition = "NEUTRAL" } },
    },
  },
  groups = {}, statics = {}, zones = {}, drawings = {},
}]])
    f:close()

    local p = prefab_ops.load(tmppath)
    check('load() reads airbases-bearing prefab', p ~= nil and p.meta ~= nil)
    check('loaded prefab.meta.airbases has 2 entries',
          type(p.meta.airbases) == 'table' and #p.meta.airbases == 2,
          'got ' .. tostring(p.meta.airbases and #p.meta.airbases))
    os.remove(tmppath)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops airbases tests passed.')
