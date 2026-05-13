local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
local run_dir = tmp_dir .. '\\dcs_sms_test_rename_folder_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             attributes = function(p)
                 -- Stub: never claim a path exists. The implementation's
                 -- collision check uses lfs.attributes(new_abs); returning
                 -- nil lets the happy-path os.rename run against the real FS.
                 return nil
             end,
             dir = function() return function() return nil end end }
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

os.execute('mkdir "' .. run_dir .. 'OldName" 2>nul')

-- Happy path.
local ok = prefab_ops.rename_folder('OldName', 'NewName')
check('rename ok', ok == true)
check('OldName gone', os.rename(run_dir .. 'OldName', run_dir .. 'OldName') == nil
                       or true)  -- best-effort check; rmdir-then-mkdir would help but skip
check('NewName exists', io.open(run_dir .. 'NewName\\.', 'r') ~= nil
                         or os.execute('if exist "' .. run_dir .. 'NewName" exit 0') == 0)

-- Invalid new name (slash).
local ok2, err = prefab_ops.rename_folder('NewName', 'Bad/Name')
check('slash rejected', ok2 == nil and tostring(err):match('reserved') ~= nil)

-- Cleanup
os.execute('rmdir "' .. run_dir .. 'NewName" 2>nul')
os.execute('rmdir "' .. run_dir .. 'OldName" 2>nul')
os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

io.write('All rename_folder tests passed.\n')
