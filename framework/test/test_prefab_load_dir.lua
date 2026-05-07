-- Standalone Lua 5.1 test for sms.prefab.load_dir extension handling.
-- Run via: lua test_prefab_load_dir.lua  (cwd: framework/test/)

-- Bootstrap a minimal sms namespace so prefab.lua's asserts pass.
sms = {
    log = { module = function() return { warn = function() end, error = function() end, info = function() end } end },
    utils = { serialize = function(t) return 'return ' .. tostring(t) end },
    constants = {},
    K = {},
    prefab = { distill = function() return {} end },
    version = '0.0.0',
}
sms.utils.resolve_country = function() return nil end

-- Stub DCS globals referenced at prefab.lua module-load time.
Group = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4 }, getByName = function() return nil end }
StaticObject = { getByName = function() return nil end }
country = { id = {} }
coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }

-- Stub lfs (dir + attributes). dir uses io.popen on Windows.
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
lfs = {
    dir = function(p)
        local files = list_dir(p)
        local i = 0
        return function() i = i + 1; return files[i] end
    end,
    attributes = function(path)
        -- Treat the temp dir itself as a directory; everything else as a file.
        if path:sub(-1) == '\\' or path:sub(-1) == '/' then
            return { mode = 'directory' }
        end
        return { mode = 'file' }
    end,
}

-- Load the framework prefab module (after distill stub).
dofile('../prefab.lua')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Set up a temp dir with one .lua and one .prefab fixture.
local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
local run_dir = tmp_dir .. '\\dcs_sms_test_load_dir_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

local function write_prefab(path, name)
    local f = assert(io.open(path, 'w'))
    f:write(string.format(
        'return {\n  ["meta"] = { ["name"] = %q },\n  ["groups"] = {},\n  ["statics"] = {},\n  ["zones"] = {},\n  ["drawings"] = {},\n}\n',
        name))
    f:close()
end

write_prefab(run_dir .. 'legacy.lua',    'legacy_one')
write_prefab(run_dir .. 'modern.prefab', 'modern_one')

local count = sms.prefab.load_dir(run_dir)
check('load_dir loaded both files', count == 2, 'got ' .. tostring(count))
check('legacy_one registered',      sms.prefab.get('legacy_one') ~= nil)
check('modern_one registered',      sms.prefab.get('modern_one') ~= nil)

-- Cleanup.
os.remove(run_dir .. 'legacy.lua')
os.remove(run_dir .. 'modern.prefab')
os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All sms.prefab.load_dir tests passed.')
