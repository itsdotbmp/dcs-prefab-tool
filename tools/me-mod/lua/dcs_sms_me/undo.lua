-- undo.lua — single-slot undo for prefab place operations.
--
-- Holds the most recent injection_record from prefab_ops.place. On undo(),
-- walks the record's per-type arrays and calls prefab_ops._remove.<type>
-- for each entry (per-entity pcall — partial failures don't abort).
-- Slot is cleared after undo regardless of partial errors.
--
-- Public:
--   M.record(injection_record)      -- replaces the slot
--   M.undo()      → ok, err_string
--   M.has_record() → boolean
--   M.clear()
--
-- injection_record shape (from prefab_ops.place):
--   prefab_name  string
--   groups       [{orig_name, runtime_id, group_obj}]  -- statics ride here too
--   zones        [{orig_name, runtime_id}]
--   drawings     [{orig_name, drawing_obj}]
--   errors       [string]

local prefab_ops = require('prefab_ops')

local M = {}
local slot = nil

function M.record(injection_record)
    slot = injection_record
end

function M.has_record()
    return slot ~= nil
end

function M.clear()
    slot = nil
end

local function remove_groups(arr)
    if not arr then return 0 end
    local errors = 0
    local fn = prefab_ops._remove and prefab_ops._remove.group
    if not fn then return #arr end  -- nothing we can do; count all as errors
    for _, entry in ipairs(arr) do
        local ok = fn(entry.group_obj)
        if not ok then errors = errors + 1 end
    end
    return errors
end

local function remove_zones(arr)
    if not arr then return 0 end
    local errors = 0
    local fn = prefab_ops._remove and prefab_ops._remove.zone
    if not fn then return #arr end
    for _, entry in ipairs(arr) do
        local ok = fn(entry.runtime_id)
        if not ok then errors = errors + 1 end
    end
    return errors
end

local function remove_drawings(arr)
    if not arr then return 0 end
    local errors = 0
    local fn = prefab_ops._remove and prefab_ops._remove.drawing
    if not fn then return #arr end
    for _, entry in ipairs(arr) do
        local ok = fn(entry.drawing_obj)
        if not ok then errors = errors + 1 end
    end
    return errors
end

function M.undo()
    if slot == nil then return nil, 'nothing to undo' end
    local r = slot
    slot = nil  -- clear before doing work — slot consumed regardless of partial failures

    local errors = 0
    errors = errors + remove_groups(r.groups)
    errors = errors + remove_zones(r.zones)
    errors = errors + remove_drawings(r.drawings)

    return true, errors > 0 and (errors .. ' partial failures') or nil
end

return M
