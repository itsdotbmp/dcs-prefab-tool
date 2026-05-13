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

-- ensure_prefab_folder calls lfs.mkdir once per segment, top-down.
do
    local mkdir_calls = {}
    package.loaded['lfs'] = { writedir = function() return 'C:\\Saved Games\\DCS\\' end,
                              mkdir = function(p) mkdir_calls[#mkdir_calls + 1] = p; return true end }
    paths = nil
    package.loaded['dcs_sms_me.paths'] = nil
    paths = require('dcs_sms_me.paths')

    mkdir_calls = {}
    paths.ensure_prefab_folder('')
    eq('ensure root: 2 mkdirs (root + prefabs)', #mkdir_calls, 2)

    mkdir_calls = {}
    paths.ensure_prefab_folder('CAP')
    eq('ensure CAP: 3 mkdirs (root + prefabs + CAP)', #mkdir_calls, 3)
    eq('  -> last segment is CAP', mkdir_calls[3]:sub(-4), 'CAP\\')

    mkdir_calls = {}
    paths.ensure_prefab_folder('A/B/C')
    eq('ensure A/B/C: 5 mkdirs', #mkdir_calls, 5)
    eq('  -> 3rd is A',   mkdir_calls[3]:sub(-2),  'A\\')
    eq('  -> 4th is A/B', mkdir_calls[4]:sub(-4),  'A\\B\\')
    eq('  -> 5th is A/B/C', mkdir_calls[5]:sub(-6), 'A\\B\\C\\')
end

io.write('All folder_to_abs tests passed.\n')
