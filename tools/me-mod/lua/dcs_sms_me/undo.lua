-- undo.lua — single-slot undo for prefab place operations.
--
-- Holds the most recent injection_record from prefab_ops.place. On undo(),
-- walks the record's per-type arrays and calls prefab_ops._remove.<type>
-- for each entry (per-entity pcall — partial failures don't abort).
-- Slot is cleared after undo regardless of partial errors.
--
-- Airbase warehouse splices done by prefab_ops.apply_airbases are wired
-- through M.add_airbase_snapshots, which augments the current slot with a
-- pre-write snapshot list. undo() restores each via warehouse_ops.apply.
--
-- Public:
--   M.record(injection_record)            -- replaces the slot
--   M.add_airbase_snapshots(snaps)        -- augment slot (no-op if empty)
--   M.undo()      → ok, err_string
--   M.has_record() → boolean
--   M.clear()
--
-- injection_record shape (from prefab_ops.place + add_airbase_snapshots):
--   prefab_name        string
--   groups             [{orig_name, runtime_id, group_obj}]  -- statics ride here too
--   zones              [{orig_name, runtime_id}]
--   drawings           [{orig_name, drawing_obj}]
--   airbase_snapshots? [{airdrome_number, prev}]      -- prev=nil → skipped on undo
--   errors             [string]

local prefab_ops    = require('dcs_sms_me.prefab_ops')
local warehouse_ops = require('dcs_sms_me.warehouse_ops')

local M = {}
local slot = nil

function M.record(injection_record)
    slot = injection_record
end

-- Append airbase pre-write snapshots to the current slot. Called by the
-- apply-prompt callback so the airbase splice is undoable alongside the
-- place. Safe no-op when no slot exists (paranoia — apply runs after place,
-- so a slot should always be present).
function M.add_airbase_snapshots(snaps)
    if slot == nil or type(snaps) ~= 'table' then return end
    slot.airbase_snapshots = slot.airbase_snapshots or {}
    for _, s in ipairs(snaps) do
        slot.airbase_snapshots[#slot.airbase_snapshots + 1] = s
    end
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

-- Restore each pre-write airbase warehouse entry by splicing the snapshot
-- back via warehouse_ops.apply. prev=nil snapshots are skipped: DCS doesn't
-- expose a clean "remove airport entry" path, and nilling the live table
-- would leave the mission in a state that diverges from what's expected on
-- save. Best-effort — the user can still tweak via Resource Manager.
local function restore_airbases(arr)
    if type(arr) ~= 'table' then return 0 end
    local errors = 0
    for _, s in ipairs(arr) do
        if type(s) == 'table' and s.airdrome_number and s.prev ~= nil then
            local ok = warehouse_ops.apply(s.airdrome_number, s.prev)
            if not ok then errors = errors + 1 end
        end
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
    errors = errors + restore_airbases(r.airbase_snapshots)

    return true, errors > 0 and (errors .. ' partial failures') or nil
end

return M
