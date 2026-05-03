-- prefab_ops.lua — prefab save / load / place operations.
--
-- This file ships in three parts (one per group). Save + exists land
-- here in Task 4; scan_dir + load in Task 5; place in Task 6.
--
-- All public symbols return either a positive value (path, table,
-- record) on success, or nil + error_string on failure. No throws.

local lfs        = require('lfs')
local paths      = require('dcs_sms_me.paths')
local distill    = require('dcs_sms_me.prefab_distill').distill
local serializer = require('dcs_sms_me.serializer')
local selection  = require('dcs_sms_me.selection')

local M = {}

local function prefab_path(name)
    return paths.PREFABS_DIR .. name .. '.lua'
end

function M.exists(name)
    if type(name) ~= 'string' or name == '' then return false end
    local f = io.open(prefab_path(name), 'r')
    if f then f:close(); return true end
    return false
end

-- Wrap a selection.snapshot() result into the dump-envelope shape that
-- prefab_distill.distill expects (top-level groups/statics/zones/drawings).
local function selection_to_dump(snap)
    return {
        groups   = snap.groups   or {},
        statics  = snap.statics  or {},   -- may be empty if statics ride inside groups (per Sub-project 2)
        zones    = snap.zones    or {},
        drawings = snap.drawings or {},
    }
end

local function any_selection(snap)
    return (#(snap.groups or {})   > 0)
        or (#(snap.statics or {})  > 0)
        or (#(snap.zones or {})    > 0)
        or (#(snap.drawings or {}) > 0)
end

function M.save_selection(name)
    if type(name) ~= 'string' or name == '' then
        return nil, 'name required'
    end

    local snap = selection.snapshot()
    if not snap or not snap.ok then
        return nil, 'selection lookup failed: ' .. tostring(snap and snap.error or 'no snapshot')
    end
    if not any_selection(snap) then
        return nil, 'no selection — nothing to save'
    end

    local dump = selection_to_dump(snap)
    local prefab = distill(dump, { name = name })
    if not prefab then
        return nil, 'distill returned nil — check log for details'
    end

    local serialized = serializer.serialize(prefab)
    if type(serialized) ~= 'string' then
        return nil, 'serialize returned non-string'
    end

    paths.ensure_prefabs()
    local path = prefab_path(name)
    local f, oerr = io.open(path, 'w')
    if not f then
        return nil, 'open failed: ' .. tostring(oerr)
    end
    f:write(serialized)
    f:close()

    return true, path
end

-- ---------------------------------------------------------------------------
-- Load + scan
-- ---------------------------------------------------------------------------

function M.load(path)
    if type(path) ~= 'string' or path == '' then return nil, 'path required' end
    local ok, result = pcall(dofile, path)
    if not ok then return nil, 'dofile failed: ' .. tostring(result) end
    if type(result) ~= 'table' then return nil, 'file did not return a table' end
    if type(result.meta) ~= 'table' or type(result.meta.name) ~= 'string' then
        return nil, 'missing meta.name'
    end
    return result
end

local function count(t)
    if type(t) ~= 'table' then return 0 end
    return #t
end

local function row_from_prefab(name, path, prefab)
    local meta = prefab.meta
    return {
        name          = meta.name or name,
        path          = path,
        theatre       = meta.theatre,
        source_dump   = meta.source_dump,
        group_count   = count(prefab.groups),
        static_count  = count(prefab.statics),
        zone_count    = count(prefab.zones),
        drawing_count = count(prefab.drawings),
    }
end

function M.scan_dir()
    paths.ensure_prefabs()
    local rows = {}
    local ok, iter = pcall(lfs.dir, paths.PREFABS_DIR)
    if not ok then return rows end

    for entry in iter do
        if entry ~= '.' and entry ~= '..' and entry:match('%.lua$') then
            local name = entry:gsub('%.lua$', '')
            local path = paths.PREFABS_DIR .. entry
            local prefab, err = M.load(path)
            if prefab then
                rows[#rows + 1] = row_from_prefab(name, path, prefab)
            else
                rows[#rows + 1] = { name = name, path = path, error = err }
            end
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

return M
