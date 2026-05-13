local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
local run_dir = tmp_dir .. '\\dcs_sms_test_rename_folder_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

-- Reliable Windows-only is_dir check: os.rename(p,p) succeeds on existing
-- paths (file or dir), fails on missing ones; io.open detects files.
local function is_dir(p)
    local fh = io.open(p, 'rb')
    if fh then fh:close(); return false end
    return os.rename(p, p) == true
end

local function list_dir(p)
    local pp = io.popen('dir /b "' .. p:gsub('\\$', '') .. '" 2>nul')
    local out = {}
    if pp then for line in pp:lines() do out[#out + 1] = line end; pp:close() end
    return out
end

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             attributes = function(path)
                 local p = path:gsub('\\$', '')
                 if is_dir(p) then return { mode = 'directory' } end
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

-- Happy path.
os.execute('mkdir "' .. run_dir .. 'OldName" 2>nul')
local ok = prefab_ops.rename_folder('OldName', 'NewName')
check('rename ok', ok == true)
check('OldName gone',   not is_dir(run_dir .. 'OldName'))
check('NewName exists', is_dir(run_dir .. 'NewName'))

-- Invalid new name (slash).
local ok2, err = prefab_ops.rename_folder('NewName', 'Bad/Name')
check('slash rejected', ok2 == nil and tostring(err):match('reserved') ~= nil)

-- Source missing.
local ok3, err3 = prefab_ops.rename_folder('DoesNotExist', 'Whatever')
check('missing source rejected', ok3 == nil and tostring(err3):match('not found') ~= nil)

-- Target already exists (collision).
os.execute('mkdir "' .. run_dir .. 'OldName2" 2>nul')
os.execute('mkdir "' .. run_dir .. 'NewName" 2>nul')  -- still exists from happy-path
local ok4, err4 = prefab_ops.rename_folder('OldName2', 'NewName')
check('collision rejected',
      ok4 == nil and tostring(err4):match('already exists') ~= nil)

-- Cleanup
os.execute('rmdir "' .. run_dir .. 'NewName" 2>nul')
os.execute('rmdir "' .. run_dir .. 'OldName2" 2>nul')
os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

io.write('All rename_folder tests passed.\n')
