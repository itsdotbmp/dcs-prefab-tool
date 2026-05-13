-- Smoke test for window.filter_rows: pure substring filter over rows by
-- name + theatre, case-insensitive. The window module pulls in dxgui
-- bindings that don't exist in this test VM, so we stub them via
-- package.preload before requiring it — same pattern as smoke_menu.lua.

package.path = package.path
    .. ';./?.lua;./?/init.lua'
    .. ';../lua/?.lua;../lua/?/init.lua'

local stub_widget = function()
    local M = {}
    M.new = function() return setmetatable({}, { __index = function() return function() end end }) end
    return M
end

package.preload['Window']         = stub_widget
package.preload['Static']         = stub_widget
package.preload['Button']         = stub_widget
package.preload['EditBox']        = stub_widget
package.preload['TextBox']        = stub_widget
package.preload['Grid']           = stub_widget
package.preload['GridHeaderCell'] = stub_widget
package.preload['Skin']           = function()
    return setmetatable({}, { __index = function() return function() return {} end end })
end
package.preload['dxgui']          = function() return { GetWindowSize = function() return 1920, 1080 end } end
package.preload['Gui']            = function() return { GetWindowSize = function() return 1920, 1080 end } end
package.preload['me_menubar']     = function() return {} end
package.preload['lfs']            = function() return { dir = function() return function() return nil end end, attributes = function() return nil end, mkdir = function() end } end

-- Stubs for module siblings that window.lua requires.
package.preload['dcs_sms_me.log']        = function() return { write = function() end, INFO = 0, ERROR = 0, WARNING = 0 } end
package.preload['dcs_sms_me.prefab_ops'] = function() return { scan_dir = function() return {} end, save_selection = function() return false, 'stub' end, exists = function() return false end } end
package.preload['dcs_sms_me.selection']  = function() return {} end
package.preload['dcs_sms_me.dtc_skins']  = function()
    return {
        button = function() return nil end,
        grid = function() return nil end,
        grid_header = function() return nil end,
        icon_static = function() return nil end,
    }
end
package.preload['dcs_sms_me.undo']       = function() return { has_record = function() return false end, undo = function() return false end, capture_pre = function() end, record = function() end } end
package.preload['me_multiSelection']     = function() return {} end
package.preload['me_toolbar']            = function() return {} end

local window = require('dcs_sms_me.prefab_manager')
local filter_rows = window._filter_rows
assert(filter_rows, 'window._filter_rows not exposed')

local function pass(label) io.write('PASS ', label, '\n') end
local function eq(label, got, expected)
    if got == expected then pass(label) else
        io.write('FAIL ', label, ' got=', tostring(got), ' expected=', tostring(expected), '\n')
        os.exit(1)
    end
end

local rows = {
    { name = 'farp_alpha',    theatre = 'Caucasus' },
    { name = 'sam_site',      theatre = 'Syria' },
    { name = 'modern_mixed',  theatre = 'Caucasus' },
    { name = 'broken',        theatre = '?', error = 'load failed' },
}

local out = filter_rows(rows, '')
eq('empty filter returns all rows', #out, 4)
assert(out ~= rows, 'empty filter should return a copy, not the same table')

out = filter_rows(rows, 'farp')
eq('substring "farp" matches 1', #out, 1)
eq('  → name', out[1].name, 'farp_alpha')

out = filter_rows(rows, 'caucasus')
eq('theatre "caucasus" matches 2', #out, 2)

out = filter_rows(rows, 'CAUCASUS')
eq('case-insensitive theatre match', #out, 2)

out = filter_rows(rows, 'nope')
eq('no match returns 0', #out, 0)

out = filter_rows(rows, 'mod')
eq('substring "mod" matches modern_mixed', #out, 1)
eq('  → name', out[1].name, 'modern_mixed')

out = filter_rows(rows, 'broken')
eq('error rows are filterable by name', #out, 1)
eq('  → has error', out[1].error, 'load failed')

-- Folder-aware composition: when selected_folder is given, only rows whose
-- row.folder matches (direct-children semantics) are kept; then the text
-- filter applies.
local compose = window._compose_filter or window._filter_rows  -- may be a new helper
if window._compose_filter then
    local sample = {
        { name = 'root_a',  folder = '',           theatre = 'Caucasus' },
        { name = 'cap_a',   folder = 'CAP',        theatre = 'Caucasus' },
        { name = 'cap_b',   folder = 'CAP',        theatre = 'Syria' },
        { name = 'cap_nested', folder = 'CAP/Tomcats', theatre = 'Caucasus' },
        { name = 'sam_a',   folder = 'SAM',        theatre = 'Caucasus' },
    }

    local out = compose(sample, '', '')
    eq('folder="" + text="" returns all', #out, 5)

    out = compose(sample, 'CAP', '')
    eq('folder="CAP" returns direct children only', #out, 2)
    eq('  → no nested', out[1].name ~= 'cap_nested' and out[2].name ~= 'cap_nested', true)

    out = compose(sample, 'CAP', 'a')
    eq('folder="CAP" + text="a" narrows', #out, 2)
    eq('  → cap_a present', (out[1].name == 'cap_a' or out[2].name == 'cap_a'), true)

    out = compose(sample, 'CAP/Tomcats', '')
    eq('folder="CAP/Tomcats" returns just that', #out, 1)
    eq('  → cap_nested', out[1].name, 'cap_nested')

    out = compose(sample, '', 'cap')
    eq('folder="" + text="cap" matches by name across all folders', #out, 3)
end

io.write('All filter_rows tests passed.\n')
