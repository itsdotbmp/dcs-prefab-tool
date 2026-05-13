package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             attributes = function() return nil end, dir = function() return function() return nil end end }
end
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end
log = log or { write = function() end, INFO = 0, WARNING = 0, ERROR = 0 }

package.path = package.path .. ';../lua/?.lua;../lua/?/init.lua'

local prefab_ops = require('dcs_sms_me.prefab_ops')

local function pass(label) io.write('PASS ', label, '\n') end
local function check(label, ok)
    if ok then pass(label) else
        io.write('FAIL ', label, '\n'); os.exit(1)
    end
end

local v = prefab_ops._validate_folder_name

check('plain name OK',           v('CAP'))
check('with spaces OK',          v('Static defense'))
check('with dash/underscore OK', v('FARP-kits_2'))
check('alphanumeric OK',         v('CAP123'))

check('empty rejected',          not v(''))
check('whitespace-only rejected',not v('   '))
check('nil rejected',            not v(nil))
check('slash rejected',          not v('CAP/Tomcats'))
check('backslash rejected',      not v('CAP\\Tomcats'))
check('colon rejected',          not v('CAP:1'))
check('asterisk rejected',       not v('CAP*'))
check('question rejected',       not v('CAP?'))
check('quote rejected',          not v('CAP"name'))
check('lt rejected',             not v('CAP<'))
check('gt rejected',             not v('CAP>'))
check('pipe rejected',           not v('CAP|x'))
check('leading dot rejected',    not v('.hidden'))
check('reserved DOS name rejected', not v('CON'))
check('CON lowercase rejected',  not v('con'))
check('PRN rejected',            not v('PRN'))
check('NUL rejected',            not v('NUL'))

-- Multi-segment folder-path validation (path-traversal guard).
local vp = prefab_ops._validate_folder_path
check('empty path OK',             vp(''))
check('single segment OK',         vp('CAP'))
check('multi segment OK',          vp('CAP/Tomcats'))
check('deep segment OK',           vp('A/B/C/D'))

check('. segment rejected',        not vp('.'))
check('.. segment rejected',       not vp('..'))
check('nested .. rejected',        not vp('CAP/..'))
check('mid-path .. rejected',      not vp('CAP/../X'))
check('mid-path . rejected',       not vp('CAP/./X'))
check('backslash rejected',        not vp('CAP\\Tomcats'))
check('absolute Windows rejected', not vp('C:/Windows'))
check('reserved segment rejected', not vp('CAP/CON'))
check('trailing slash OK',         vp('CAP/'))    -- single empty segment after split = no segments, so OK
check('reserved char rejected',    not vp('CAP/Bad>Name'))

io.write('All _validate_folder_name tests passed.\n')
