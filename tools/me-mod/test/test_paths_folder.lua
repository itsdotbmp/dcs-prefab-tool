-- Pure-Lua test for paths.folder_to_abs.
-- Stubs lfs so paths.lua's `lfs.writedir()` resolves.

package.preload['lfs'] = function()
    return { writedir = function() return 'C:\\Saved Games\\DCS\\' end, mkdir = function() return true end }
end

package.path = package.path .. ';../lua/?.lua;../lua/?/init.lua'

local paths = require('dcs_sms_me.paths')

local function pass(label) io.write('PASS ', label, '\n') end
local function eq(label, got, expected)
    if got == expected then pass(label) else
        io.write('FAIL ', label, ' got=', tostring(got), ' expected=', tostring(expected), '\n')
        os.exit(1)
    end
end

eq('root folder',           paths.folder_to_abs(''),                 paths.PREFABS_DIR)
eq('top-level folder',      paths.folder_to_abs('CAP'),              paths.PREFABS_DIR .. 'CAP\\')
eq('nested folder',         paths.folder_to_abs('CAP/Tomcats'),      paths.PREFABS_DIR .. 'CAP\\Tomcats\\')
eq('deep folder',           paths.folder_to_abs('A/B/C/D'),          paths.PREFABS_DIR .. 'A\\B\\C\\D\\')
eq('nil treated as root',   paths.folder_to_abs(nil),                paths.PREFABS_DIR)

io.write('All folder_to_abs tests passed.\n')
