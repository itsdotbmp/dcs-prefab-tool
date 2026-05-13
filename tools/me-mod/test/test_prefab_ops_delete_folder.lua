local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
local run_dir = tmp_dir .. '\\dcs_sms_test_delete_folder_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

local function list_dir(p)
    local pp = io.popen('dir /b "' .. p:gsub('\\$', '') .. '" 2>nul')
    local out = {}
    if pp then for line in pp:lines() do out[#out + 1] = line end; pp:close() end
    return out
end
local function is_dir(p)
    -- Windows-reliable check: a directory can't be opened as a file, but
    -- os.rename(p, p) succeeds for existing entries. (The plan's original
    -- `os.execute('if exist ... exit 0') == 0` always returns 0 on Windows
    -- because cmd.exe exits successfully regardless of the branch taken.)
    local fh = io.open(p, 'rb')
    if fh then fh:close(); return false end
    return os.rename(p, p) == true
end

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             attributes = function(path)
                 if is_dir(path:gsub('\\$', '')) then return { mode = 'directory' } end
                 local f = io.open(path, 'r'); if f then f:close(); return { mode = 'file' } end
                 return nil
             end,
             dir = function(p)
                 local entries = list_dir(p); local i = 0
                 return function() i = i + 1; return entries[i] end
             end,
             rmdir = function(p) return os.execute('rmdir "' .. p:gsub('\\$', '') .. '" 2>nul') == 0 end,
    }
end
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end
log = log or {}; log.write = log.write or function() end
log.INFO, log.WARNING, log.ERROR = 0, 0, 0

package.path = package.path .. ';../lua/?.lua;../lua/?/init.lua'

local paths = require('dcs_sms_me.paths')
paths.PREFABS_DIR = run_dir
local prefab_ops = require('dcs_sms_me.prefab_ops')

local function check(l, ok) if ok then io.write('PASS ', l, '\n') else io.write('FAIL ', l, '\n'); os.exit(1) end end

-- Set up a nested tree:
--   ToDelete/file1.prefab
--   ToDelete/Sub/file2.prefab
os.execute('mkdir "' .. run_dir .. 'ToDelete" 2>nul')
os.execute('mkdir "' .. run_dir .. 'ToDelete\\Sub" 2>nul')
local function write(p) local f = assert(io.open(p, 'w')); f:write('x'); f:close() end
write(run_dir .. 'ToDelete\\file1.prefab')
write(run_dir .. 'ToDelete\\Sub\\file2.prefab')

local ok = prefab_ops.delete_folder('ToDelete')
check('delete ok', ok == true)
check('folder gone', not is_dir(run_dir .. 'ToDelete'))

-- Empty folder.
os.execute('mkdir "' .. run_dir .. 'Empty" 2>nul')
local ok2 = prefab_ops.delete_folder('Empty')
check('empty folder delete ok', ok2 == true)
check('empty folder gone', not is_dir(run_dir .. 'Empty'))

-- Nonexistent.
local ok3, err = prefab_ops.delete_folder('DoesNotExist')
check('missing rejected', ok3 == nil and tostring(err):match('not found') ~= nil)

-- Path-traversal rejection.
local ok5, err5 = prefab_ops.delete_folder('..')
check('.. rejected',
      ok5 == nil and tostring(err5):match('invalid folder') ~= nil)

local ok6, err6 = prefab_ops.delete_folder('CAP/../X')
check('embedded .. rejected',
      ok6 == nil and tostring(err6):match('invalid folder') ~= nil)

-- count_folder_contents must count ALL files (not just .prefab) because
-- delete_folder unconditionally removes every file. The confirmation UI
-- relies on this count to honestly report what's about to be wiped.
os.execute('mkdir "' .. run_dir .. 'MixedTree" 2>nul')
os.execute('mkdir "' .. run_dir .. 'MixedTree\\Sub" 2>nul')
write(run_dir .. 'MixedTree\\a.prefab')
write(run_dir .. 'MixedTree\\notes.txt')
write(run_dir .. 'MixedTree\\legacy.lua')
write(run_dir .. 'MixedTree\\Sub\\b.prefab')
local files, dirs = prefab_ops.count_folder_contents('MixedTree')
check('count_folder_contents counts non-.prefab files too', files == 4 and dirs == 1)
os.execute('rmdir /s /q "' .. run_dir .. 'MixedTree" 2>nul')

os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')
io.write('All delete_folder tests passed.\n')
