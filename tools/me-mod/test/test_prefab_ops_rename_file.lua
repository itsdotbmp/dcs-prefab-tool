local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
local run_dir = tmp_dir .. '\\dcs_sms_test_rename_file_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')
os.execute('mkdir "' .. run_dir .. 'CAP" 2>nul')

local function write(path, body)
    local f = assert(io.open(path, 'w')); f:write(body); f:close()
end

local function file_exists(p)
    local f = io.open(p, 'r'); if f then f:close(); return true end
    return false
end

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             attributes = function(p)
                 local f = io.open(p, 'r')
                 if not f then return nil end
                 f:close()
                 return { mode = 'file' }
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

-- Regression: rename of a prefab in a subfolder MUST stay in that subfolder.
-- Previously the destination was always rebuilt at PREFABS_DIR root, dropping
-- the folder.
write(run_dir .. 'CAP\\hornet.prefab',
      'return { meta = { name = "hornet" }, groups = {}, statics = {}, zones = {}, drawings = {} }')
local ok, new_path = prefab_ops.rename_file(run_dir .. 'CAP\\hornet.prefab', 'tomcat')
check('subfolder rename ok', ok == true)
check('new file in subfolder', file_exists(run_dir .. 'CAP\\tomcat.prefab'))
check('root does NOT have the file', not file_exists(run_dir .. 'tomcat.prefab'))
check('old basename gone', not file_exists(run_dir .. 'CAP\\hornet.prefab'))
check('returned path matches', new_path == run_dir .. 'CAP\\tomcat.prefab')

-- meta.name updated inside the file body.
local body
do local f = assert(io.open(run_dir .. 'CAP\\tomcat.prefab', 'r')); body = f:read('*a'); f:close() end
check('meta.name updated', body:match('%["name"%]%s*=%s*"tomcat"') ~= nil)

-- Root-level rename still works.
write(run_dir .. 'viper.prefab',
      'return { meta = { name = "viper" }, groups = {}, statics = {}, zones = {}, drawings = {} }')
local ok2 = prefab_ops.rename_file(run_dir .. 'viper.prefab', 'eagle')
check('root rename ok', ok2 == true)
check('new file at root', file_exists(run_dir .. 'eagle.prefab'))
check('old root file gone', not file_exists(run_dir .. 'viper.prefab'))

-- Collision: same subfolder already has the target. Pre-bug, this would have
-- been mis-detected against the root.
write(run_dir .. 'CAP\\warthog.prefab',
      'return { meta = { name = "warthog" }, groups = {}, statics = {}, zones = {}, drawings = {} }')
local ok3, err3 = prefab_ops.rename_file(run_dir .. 'CAP\\warthog.prefab', 'tomcat')
check('subfolder collision rejected', ok3 == false)
check('collision error', tostring(err3):match('already exists') ~= nil)
check('source untouched after collision', file_exists(run_dir .. 'CAP\\warthog.prefab'))

-- Inverse of the original bug: collision sibling at ROOT must NOT block a
-- subfolder rename when the subfolder slot is free.
write(run_dir .. 'falcon.prefab',
      'return { meta = { name = "falcon" }, groups = {}, statics = {}, zones = {}, drawings = {} }')
write(run_dir .. 'CAP\\harrier.prefab',
      'return { meta = { name = "harrier" }, groups = {}, statics = {}, zones = {}, drawings = {} }')
local ok4 = prefab_ops.rename_file(run_dir .. 'CAP\\harrier.prefab', 'falcon')
check('subfolder rename succeeds despite same name at root', ok4 == true)
check('subfolder destination exists', file_exists(run_dir .. 'CAP\\falcon.prefab'))
check('root sibling untouched', file_exists(run_dir .. 'falcon.prefab'))

-- No-op rename (same name) is a success and leaves the file alone.
local ok5, p5 = prefab_ops.rename_file(run_dir .. 'CAP\\falcon.prefab', 'falcon')
check('no-op rename ok', ok5 == true and p5 == run_dir .. 'CAP\\falcon.prefab')
check('no-op rename leaves file', file_exists(run_dir .. 'CAP\\falcon.prefab'))

-- Invalid new name (separator) rejected.
local ok6, err6 = prefab_ops.rename_file(run_dir .. 'CAP\\falcon.prefab', 'bad/name')
check('separator in new_name rejected', ok6 == false and tostring(err6):match('reserved') ~= nil)

-- Empty / nil old_path rejected.
local ok7, err7 = prefab_ops.rename_file('', 'whatever')
check('empty old_path rejected', ok7 == false and tostring(err7):match('required') ~= nil)

-- Cleanup
os.remove(run_dir .. 'CAP\\tomcat.prefab')
os.remove(run_dir .. 'CAP\\warthog.prefab')
os.remove(run_dir .. 'CAP\\falcon.prefab')
os.remove(run_dir .. 'eagle.prefab')
os.remove(run_dir .. 'falcon.prefab')
os.execute('rmdir "' .. run_dir .. 'CAP" 2>nul')
os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

io.write('All rename_file tests passed.\n')
