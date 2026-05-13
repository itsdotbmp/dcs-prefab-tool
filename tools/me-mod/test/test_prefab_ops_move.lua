local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
local run_dir = tmp_dir .. '\\dcs_sms_test_move_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')
os.execute('mkdir "' .. run_dir .. 'src" 2>nul')
os.execute('mkdir "' .. run_dir .. 'dst" 2>nul')

local function write(path, body)
    local f = assert(io.open(path, 'w')); f:write(body); f:close()
end

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             attributes = function() return nil end, dir = function() return function() return nil end end }
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

write(run_dir .. 'src\\hornet.prefab', 'return { meta = { name = "hornet" }, groups = {}, statics = {}, zones = {}, drawings = {} }')

-- Happy path: move from src/ to dst/.
local ok, path_or_err = prefab_ops.move_prefab(run_dir .. 'src\\hornet.prefab', 'hornet', 'dst')
check('move ok', ok == true and io.open(run_dir .. 'dst\\hornet.prefab', 'r') ~= nil)
check('original is gone', io.open(run_dir .. 'src\\hornet.prefab', 'r') == nil)

-- Collision: target already exists.
write(run_dir .. 'src\\hornet.prefab', 'return { meta = { name = "hornet" }, groups = {}, statics = {}, zones = {}, drawings = {} }')
local ok2, err = prefab_ops.move_prefab(run_dir .. 'src\\hornet.prefab', 'hornet', 'dst')
check('collision rejected', ok2 == nil)
check('collision error message', tostring(err):match('already exists') ~= nil)

-- Move to root (folder = '').
local ok3, path3 = prefab_ops.move_prefab(run_dir .. 'src\\hornet.prefab', 'hornet', '')
check('move to root ok', ok3 == true)
check('at root', io.open(run_dir .. 'hornet.prefab', 'r') ~= nil)

-- Source missing.
local ok4, err4 = prefab_ops.move_prefab(run_dir .. 'src\\does_not_exist.prefab', 'x', 'dst')
check('missing source rejected', ok4 == nil and tostring(err4):match('not found') ~= nil)

-- Cleanup
os.remove(run_dir .. 'dst\\hornet.prefab')
os.remove(run_dir .. 'hornet.prefab')
os.execute('rmdir "' .. run_dir .. 'src" 2>nul')
os.execute('rmdir "' .. run_dir .. 'dst" 2>nul')
os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

io.write('All move_prefab tests passed.\n')
