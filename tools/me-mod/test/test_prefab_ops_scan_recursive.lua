-- Verifies scan_dir recurses into subdirectories and tags each row
-- with row.folder. Uses a real temp directory tree to exercise the
-- lfs.dir + lfs.attributes path.

local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
local run_dir = tmp_dir .. '\\dcs_sms_test_recursive_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')
os.execute('mkdir "' .. run_dir .. 'CAP" 2>nul')
os.execute('mkdir "' .. run_dir .. 'CAP\\Tomcats" 2>nul')
os.execute('mkdir "' .. run_dir .. 'SAM" 2>nul')
os.execute('mkdir "' .. run_dir .. 'Empty" 2>nul')

local function write_prefab(path, name)
    local f = assert(io.open(path, 'w'))
    f:write(string.format(
        'return {\n  ["meta"] = { ["name"] = %q, ["sms_prefab_version"] = "0.1.0" },\n  ["groups"] = {},\n  ["statics"] = {},\n  ["zones"] = {},\n  ["drawings"] = {},\n}\n',
        name))
    f:close()
end

write_prefab(run_dir .. 'rootfab.prefab',           'rootfab')
write_prefab(run_dir .. 'CAP\\hornet.prefab',       'hornet')
write_prefab(run_dir .. 'CAP\\Tomcats\\f14.prefab', 'f14')
write_prefab(run_dir .. 'SAM\\sa10.prefab',         'sa10')

-- Use io.popen to list real dirs; mock lfs.dir + lfs.attributes accordingly.
local function list_dir(path)
    local p = io.popen('dir /b "' .. path:gsub('/', '\\'):gsub('\\$', '') .. '" 2>nul')
    local entries = {}
    if p then
        for line in p:lines() do entries[#entries + 1] = line end
        p:close()
    end
    return entries
end
local function is_dir(path)
    local p = io.popen('if exist "' .. path:gsub('/', '\\') .. '\\*" (echo Y) else (echo N)')
    if not p then return false end
    local r = p:read('*l'); p:close()
    return r and r:match('Y') ~= nil
end

package.preload['lfs'] = function()
    return {
        writedir = function() return '' end,
        mkdir = function() return true end,
        dir = function(p)
            local entries = list_dir(p)
            local i = 0
            return function() i = i + 1; return entries[i] end
        end,
        attributes = function(p)
            if is_dir(p:gsub('\\$', '')) then return { mode = 'directory' } end
            return { mode = 'file' }
        end,
    }
end

package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

log = log or {}
log.INFO    = log.INFO    or 0
log.WARNING = log.WARNING or 0
log.ERROR   = log.ERROR   or 0
log.write   = log.write   or function() end

package.path = package.path .. ';../lua/?.lua;../lua/?/init.lua'

local paths = require('dcs_sms_me.paths')
paths.PREFABS_DIR = run_dir
local prefab_ops = require('dcs_sms_me.prefab_ops')

local function pass(l) io.write('PASS ', l, '\n') end
local function eq(l, got, expected)
    if got == expected then pass(l) else
        io.write('FAIL ', l, ' got=', tostring(got), ' expected=', tostring(expected), '\n')
        os.exit(1)
    end
end

local rows = prefab_ops.scan_dir()
eq('row count', #rows, 4)

-- Build a lookup by name -> folder.
local by_name = {}
for _, r in ipairs(rows) do by_name[r.name] = r end

eq('rootfab in root',     by_name['rootfab'] and by_name['rootfab'].folder, '')
eq('hornet in CAP',       by_name['hornet']  and by_name['hornet'].folder,  'CAP')
eq('f14 in CAP/Tomcats',  by_name['f14']     and by_name['f14'].folder,     'CAP/Tomcats')
eq('sa10 in SAM',         by_name['sa10']    and by_name['sa10'].folder,    'SAM')

-- Clean up.
os.remove(run_dir .. 'rootfab.prefab')
os.remove(run_dir .. 'CAP\\hornet.prefab')
os.remove(run_dir .. 'CAP\\Tomcats\\f14.prefab')
os.remove(run_dir .. 'SAM\\sa10.prefab')
os.execute('rmdir "' .. run_dir .. 'CAP\\Tomcats" 2>nul')
os.execute('rmdir "' .. run_dir .. 'CAP" 2>nul')
os.execute('rmdir "' .. run_dir .. 'SAM" 2>nul')
os.execute('rmdir "' .. run_dir .. 'Empty" 2>nul')
os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

io.write('All scan_dir recursive tests passed.\n')
