-- Standalone test for prefab_ops.scan_dir + load.
-- Run via: lua test_prefab_ops_load.lua  (cwd: tools/me-mod/test/)

local fake_writedir = 'fixtures\\fake_root\\'  -- relative; we don't actually need lfs.writedir to be Windows-style
local fixtures_dir  = 'fixtures/prefabs_dir/'

-- Stub lfs.writedir to point at fixtures, and lfs.dir to enumerate files.
local function list_dir(path)
    local fixtures_path = path:gsub('\\', '/'):gsub('/$', '')
    local p = io.popen('dir /b "' .. fixtures_path:gsub('/', '\\') .. '" 2>nul')
    local files = {}
    if p then
        for line in p:lines() do files[#files + 1] = line end
        p:close()
    end
    return files
end

package.preload['lfs'] = function()
    return {
        writedir = function() return '' end,  -- unused for these tests
        mkdir    = function() return true end,
        attributes = function(path) return { mode = 'file' } end,
        dir = function(p)
            local files = list_dir(p)
            local i = 0
            return function()
                i = i + 1
                return files[i]
            end
        end,
    }
end

-- Override paths.PREFABS_DIR to point at fixtures.
package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local paths = require('dcs_sms_me.paths')
paths.PREFABS_DIR = fixtures_dir

-- Stub selection (not used by load, but prefab_ops requires it).
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: scan_dir returns one row per .lua file.
do
    local rows = prefab_ops.scan_dir()
    check('scan_dir returns array of length 4', type(rows) == 'table' and #rows == 4,
          'got ' .. tostring(rows and #rows or nil))

    -- Find each row by name.
    local by_name = {}
    for _, r in ipairs(rows) do by_name[r.name] = r end

    check('farp_alpha row present',   by_name['farp_alpha']   ~= nil)
    check('sam_site row present',     by_name['sam_site']     ~= nil)
    check('broken row present',       by_name['broken']       ~= nil)
    check('modern_mixed row present', by_name['modern_mixed'] ~= nil)

    if by_name['farp_alpha'] then
        local r = by_name['farp_alpha']
        check('farp_alpha theatre', r.theatre == 'Caucasus')
        check('farp_alpha group_count == 2',  r.group_count == 2,  'got ' .. tostring(r.group_count))
        check('farp_alpha static_count == 1', r.static_count == 1, 'got ' .. tostring(r.static_count))
        check('farp_alpha no error',          r.error == nil)
    end
    if by_name['sam_site'] then
        local r = by_name['sam_site']
        check('sam_site source_dump', r.source_dump == 'selection-2026-05-03T091254Z.lua',
              'got ' .. tostring(r.source_dump))
        check('sam_site zone_count == 1', r.zone_count == 1, 'got ' .. tostring(r.zone_count))
    end
    if by_name['broken'] then
        local r = by_name['broken']
        check('broken row has error', type(r.error) == 'string',
              'expected error string, got ' .. tostring(r.error))
    end
    if by_name['modern_mixed'] then
        -- 3 entries inside `groups`: vehicle + plane + static. The static
        -- should be pulled out of group_count and surface as static_count.
        local r = by_name['modern_mixed']
        check('modern_mixed group_count == 2 (excludes type=static)',
              r.group_count == 2, 'got ' .. tostring(r.group_count))
        check('modern_mixed static_count == 1 (from inline type=static)',
              r.static_count == 1, 'got ' .. tostring(r.static_count))
        check('modern_mixed zone_count == 1',
              r.zone_count == 1, 'got ' .. tostring(r.zone_count))
    end
end

-- Case: load returns the table or nil+error.
do
    local p, err = prefab_ops.load(fixtures_dir .. 'farp_alpha.lua')
    check('load returns table',     type(p) == 'table' and p.meta and p.meta.name == 'farp_alpha',
          'got ' .. tostring(p))

    local bad, berr = prefab_ops.load(fixtures_dir .. 'broken.lua')
    check('load broken returns nil',       bad == nil)
    check('load broken returns error str', type(berr) == 'string')
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops load tests passed.')
