-- Standalone test for undo.lua. Stubs prefab_ops._remove to capture the
-- objects/ids that would be removed without actually calling DCS.
-- Run via: lua test_undo.lua  (cwd: tools/me-mod/test/)

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             dir = function() return function() return nil end end }
end
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path

-- Stub out prefab_ops._remove BEFORE undo loads. Must use the qualified
-- name so the same module instance is shared with undo.lua's require.
local removed = { group = {}, zone = {}, drawing = {} }
local prefab_ops = require('dcs_sms_me.prefab_ops')
prefab_ops._remove = {
    group   = function(obj) removed.group[#removed.group + 1] = obj; return true end,
    zone    = function(id)  removed.zone[#removed.zone + 1] = id; return true end,
    drawing = function(obj) removed.drawing[#removed.drawing + 1] = obj; return true end,
}

local undo = require('undo')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- has_record() false initially.
check('has_record() initial false', undo.has_record() == false)

-- After record(), undo() removes everything in the record.
do
    local g1 = { __id = 101 }
    local g2 = { __id = 102 }
    local d1 = { __id = 901 }
    undo.record({
        prefab_name = 'farp_alpha',
        groups   = {
            { orig_name = 'G1', runtime_id = 101, group_obj = g1 },
            { orig_name = 'G2', runtime_id = 102, group_obj = g2 },
        },
        zones    = { { orig_name = 'Z1', runtime_id = 301 } },
        drawings = { { orig_name = 'D1', drawing_obj = d1 } },
        errors   = {},
    })
    check('has_record() after record', undo.has_record() == true)

    removed = { group = {}, zone = {}, drawing = {} }
    prefab_ops._remove.group   = function(obj) removed.group[#removed.group + 1] = obj; return true end
    prefab_ops._remove.zone    = function(id)  removed.zone[#removed.zone + 1] = id; return true end
    prefab_ops._remove.drawing = function(obj) removed.drawing[#removed.drawing + 1] = obj; return true end

    local ok, err = undo.undo()
    check('undo returns ok', ok == true, 'got ' .. tostring(ok) .. ', err=' .. tostring(err))
    check('removed 2 groups by obj',
          #removed.group == 2 and removed.group[1] == g1 and removed.group[2] == g2)
    check('removed 1 zone by id',
          #removed.zone == 1 and removed.zone[1] == 301)
    check('removed 1 drawing by obj',
          #removed.drawing == 1 and removed.drawing[1] == d1)
    check('has_record() false after undo', undo.has_record() == false)
end

-- undo() on empty slot returns nil + 'nothing to undo'.
do
    local ok, err = undo.undo()
    check('undo on empty slot returns nil', ok == nil)
    check('undo on empty slot returns reason', type(err) == 'string' and err:find('nothing') ~= nil)
end

-- record() replaces the slot (no stack).
do
    local g_a = { __id = 1 }
    local g_b = { __id = 2 }
    undo.record({ prefab_name = 'a', groups = { { orig_name = 'X', runtime_id = 1, group_obj = g_a } }, zones = {}, drawings = {}, errors = {} })
    undo.record({ prefab_name = 'b', groups = { { orig_name = 'Y', runtime_id = 2, group_obj = g_b } }, zones = {}, drawings = {}, errors = {} })

    removed = { group = {}, zone = {}, drawing = {} }
    prefab_ops._remove.group = function(obj) removed.group[#removed.group + 1] = obj; return true end

    undo.undo()
    check('second record overwrites first', #removed.group == 1 and removed.group[1] == g_b)
end

-- Per-entity remove failure: undo continues, slot still cleared.
do
    local g1 = { __id = 11 }
    local g2 = { __id = 12 }
    undo.record({
        prefab_name = 'c',
        groups   = {
            { orig_name = 'G1', runtime_id = 11, group_obj = g1 },
            { orig_name = 'G2', runtime_id = 12, group_obj = g2 },
        },
        zones = {}, drawings = {}, errors = {},
    })
    local calls = 0
    prefab_ops._remove.group = function(obj)
        calls = calls + 1
        if calls == 1 then return false, 'simulated failure' end
        return true
    end
    local ok = undo.undo()
    check('undo with one per-entity failure still returns ok', ok == true)
    check('all entities attempted', calls == 2)
    check('slot cleared after partial-failure undo', undo.has_record() == false)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All undo tests passed.')
