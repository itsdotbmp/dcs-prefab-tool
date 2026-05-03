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

-- ---------------------------------------------------------------------------
-- Place math (unit-testable, exposed under M._<name>)
-- ---------------------------------------------------------------------------

-- Rotate (rel_x, rel_y) by rotation_deg and translate to world coords.
-- DCS map space: x = East, y = North (same as math.cos/sin convention for
-- a CW rotation when viewed from above, but we treat rotation_deg as a
-- standard CCW angle for relative placement).
function M._place_xy(rel_x, rel_y, anchor, rotation_deg)
    local r = (rotation_deg or 0) * (math.pi / 180)
    local c, s = math.cos(r), math.sin(r)
    local rx = rel_x * c - rel_y * s
    local ry = rel_x * s + rel_y * c
    return anchor.x + rx, anchor.y + ry
end

-- Compose a stored heading (degrees) with a placement rotation, normalising
-- the result to [0, 360).  Input may be negative or > 360.
function M._heading_world(file_heading_deg, rotation_deg)
    local h = ((file_heading_deg or 0) + (rotation_deg or 0)) % 360
    if h < 0 then h = h + 360 end
    return h
end

-- Resolve the effective anchor and rotation from opts.
-- Returns anchor_table, rotation_deg — or nil if no valid anchor is available.
--
-- Rules:
--   keep_position = true  → anchor = prefab.meta.world_anchor, rotation forced 0
--   opts.anchor present   → use that anchor, rotation = opts.rotation or 0
--   otherwise             → nil (caller must report error)
function M._resolve_anchor(prefab, opts)
    if opts.keep_position then
        local wa = prefab.meta and prefab.meta.world_anchor
        if not (wa and type(wa.x) == 'number' and type(wa.y) == 'number') then
            return nil
        end
        return { x = wa.x, y = wa.y }, 0
    end
    if not (opts.anchor and type(opts.anchor.x) == 'number' and type(opts.anchor.y) == 'number') then
        return nil
    end
    return { x = opts.anchor.x, y = opts.anchor.y }, opts.rotation or 0
end

-- ---------------------------------------------------------------------------
-- Place — runtime ME-API injection
-- ---------------------------------------------------------------------------
-- The ME mutation API (discovered by reading me_copy_paste.lua and me_mission.lua):
--
--   Groups:
--     INSERT — `Mission.missionCountry[countryName][groupType].group` table is
--     the canonical data store; the blessed add path (from duplicateGroup in
--     me_copy_paste.lua) is:
--       1. Mission.create_group_objects(group)
--       2. table.insert(country[group.type].group, group)
--       3. Mission.create_group_map_objects(group)
--     For simple prefab injection we use `Mission.create_group` to create a
--     new shell, then the pattern above to insert a pre-built group table.
--     Because that still requires ME-internal country resolution, the wrapper
--     falls back to direct table.insert when `Mission.missionCountry` is
--     accessible — and degrades gracefully if it is not.
--     REMOVE — `Mission.remove_group(group)` takes the full group object
--     (NOT a bare ID).
--
--   Trigger zones:
--     INSERT — `TriggerZoneController.addTriggerZone(name, x, y, radius,
--               properties, color, type, points)` returns an id.
--     REMOVE — `TriggerZoneController.removeTriggerZone(id)`
--
--   Drawings:
--     INSERT — `panel_draw.copyObjToCoord(object, x, y)` — creates a copy
--              and returns the new object.  The returned object is what we
--              store in the undo record.
--     REMOVE — `panel_draw.objectDelete(object)` — takes the full object.
--
--   Statics in DCS are modelled as groups of type='static' and live in the
--   same country[type].group table as other group types.  There is no
--   separate addStaticObject symbol in the discovered ME API surface.
--
--   Note: `Mission.addGroup` and `Mission.addStaticObject` (as suggested in
--   the task template) do NOT exist in the examined DCS install
--   (2024-era, checked me_mission.lua 9759 lines). All group injection goes
--   through create_group_objects + missionCountry table.

-- Walk a group/static table and rewrite every {x, y} pair using the
-- place_xy transform. Mutates in place.
local function transform_coords(t, anchor, rotation_deg)
    if type(t) ~= 'table' then return end
    if type(t.x) == 'number' and type(t.y) == 'number' then
        t.x, t.y = M._place_xy(t.x, t.y, anchor, rotation_deg)
    end
    for _, v in pairs(t) do
        if type(v) == 'table' then transform_coords(v, anchor, rotation_deg) end
    end
end

local function transform_headings(t, rotation_deg)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'heading' and type(v) == 'number' then
            -- headings in DCS group tables are in radians; convert deg→rad for storage
            t[k] = M._heading_world(v * (180 / math.pi), rotation_deg) * (math.pi / 180)
        elseif type(v) == 'table' then
            transform_headings(v, rotation_deg)
        end
    end
end

-- Deep-copy a table. Used so place can transform without mutating the
-- registered template (caller may place the same prefab multiple times).
local function deep_copy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, vv in pairs(v) do out[k] = deep_copy(vv, seen) end
    return out
end

-- ME-API call wrappers.
-- Each returns (result_or_id, err_string_or_nil).
-- pcall guards degrade missing symbols to per-entity logged failures;
-- the overall place() still returns a partial record.

-- Groups (and statics, which are groups of type='static').
-- Blessed insertion path from me_copy_paste.lua:duplicateGroup lines 378-382:
--   Mission.create_group_objects(group)
--   table.insert(country[group.type].group, group)
--   Mission.create_group_map_objects(group)
-- We need Mission.missionCountry to resolve country; group.boss should carry
-- the country name when the prefab was distilled from the selection.
local function inject_group(group)
    local ok_req, Mission = pcall(require, 'me_mission')
    if not ok_req or not Mission then
        return nil, 'me_mission not available'
    end
    local country_name = (type(group.boss) == 'table' and group.boss.name)
                      or (type(group.boss) == 'string' and group.boss)
    if not country_name then
        return nil, 'group has no boss.name — cannot resolve country'
    end
    local missionCountry = Mission.missionCountry
    if type(missionCountry) ~= 'table' then
        return nil, 'Mission.missionCountry not available'
    end
    local country = missionCountry[country_name]
    if not country then
        return nil, 'country "' .. country_name .. '" not found in mission'
    end
    local group_type = group.type
    if not group_type then
        return nil, 'group.type is nil'
    end
    if not country[group_type] then
        country[group_type] = { group = {} }
    end

    local ok_cgo, cgo_err = pcall(Mission.create_group_objects, group)
    if not ok_cgo then
        return nil, 'create_group_objects failed: ' .. tostring(cgo_err)
    end
    table.insert(country[group_type].group, group)
    local ok_cgmo, cgmo_err = pcall(Mission.create_group_map_objects, group)
    if not ok_cgmo then
        -- Group is in the data table but map objects failed; still partial success.
        return group.groupId or true, 'create_group_map_objects failed (map may need refresh): ' .. tostring(cgmo_err)
    end
    return group.groupId or true
end

-- Trigger zones via TriggerZoneController.addTriggerZone.
-- Signature: addTriggerZone(name, x, y, radius, properties, color, type, points)
local function inject_zone(zone)
    local ok_req, ctrl = pcall(require, 'Mission.TriggerZoneController')
    if not ok_req or not ctrl then
        return nil, 'Mission.TriggerZoneController not available'
    end
    if type(ctrl.addTriggerZone) ~= 'function' then
        return nil, 'TriggerZoneController.addTriggerZone not available'
    end
    local name   = zone.name or 'Zone'
    local x      = zone.x or 0
    local y      = zone.y or 0
    local radius = zone.radius or 1000
    local props  = zone.properties or {}
    local color  = zone.color  -- may be nil; addTriggerZone accepts nil
    local ztype  = zone.type or 0
    local points = zone.points -- may be nil for circle zones
    local ok, result = pcall(ctrl.addTriggerZone, name, x, y, radius, props, color, ztype, points)
    if not ok then return nil, tostring(result) end
    return result  -- returns the new zone id
end

-- Drawings via panel_draw.copyObjToCoord.
-- copyObjToCoord(object, x, y) creates a copy and returns the new object.
-- The returned object (not just an id) is stored in the undo record so that
-- panel_draw.objectDelete can remove it.
local function inject_drawing(drawing)
    local ok_req, panel = pcall(require, 'me_draw_panel')
    if not ok_req or not panel then
        return nil, 'me_draw_panel not available'
    end
    if type(panel.copyObjToCoord) ~= 'function' then
        return nil, 'panel_draw.copyObjToCoord not available'
    end
    local x = (drawing.mapData and drawing.mapData.x) or drawing.x or 0
    local y = (drawing.mapData and drawing.mapData.y) or drawing.y or 0
    local ok, result = pcall(panel.copyObjToCoord, drawing, x, y)
    if not ok then return nil, tostring(result) end
    return result  -- returns the new drawing object
end

-- Remove wrappers — used by undo.lua.
-- Exposed as M._remove table so undo.lua can call them by entity type.

local function remove_group(group_obj)
    -- Mission.remove_group takes the full group object (not just an id).
    -- See me_copy_paste.lua lines 259 and 541.
    local ok_req, Mission = pcall(require, 'me_mission')
    if not ok_req or not Mission then
        return false, 'me_mission not available'
    end
    if type(Mission.remove_group) ~= 'function' then
        return false, 'Mission.remove_group not available'
    end
    return pcall(Mission.remove_group, group_obj)
end

local function remove_zone(zone_id)
    -- TriggerZoneController.removeTriggerZone(id).
    local ok_req, ctrl = pcall(require, 'Mission.TriggerZoneController')
    if not ok_req or not ctrl then
        return false, 'Mission.TriggerZoneController not available'
    end
    if type(ctrl.removeTriggerZone) ~= 'function' then
        return false, 'TriggerZoneController.removeTriggerZone not available'
    end
    return pcall(ctrl.removeTriggerZone, zone_id)
end

local function remove_drawing(drawing_obj)
    -- panel_draw.objectDelete(object) — takes the full object.
    -- See me_copy_paste.lua line 554 and me_draw_panel.lua objectDelete.
    local ok_req, panel = pcall(require, 'me_draw_panel')
    if not ok_req or not panel then
        return false, 'me_draw_panel not available'
    end
    if type(panel.objectDelete) ~= 'function' then
        return false, 'panel_draw.objectDelete not available'
    end
    return pcall(panel.objectDelete, drawing_obj)
end

M._remove = {
    group   = remove_group,
    zone    = remove_zone,
    drawing = remove_drawing,
}

-- M.place(prefab, opts) — inject a loaded prefab into the open mission.
--
-- opts fields:
--   anchor         {x, y}  — world map point to place at (required unless keep_position)
--   rotation       number  — clockwise rotation in degrees (default 0)
--   keep_position  bool    — ignore anchor/rotation; use prefab.meta.world_anchor as-is
--
-- Returns injection_record on (partial) success, or nil + error_string if
-- nothing could be injected.
--
-- injection_record fields:
--   prefab_name   string
--   groups        [{orig_name, runtime_id, group_obj}]
--   zones         [{orig_name, runtime_id}]
--   drawings      [{orig_name, drawing_obj}]
--   errors        [string]   — per-entity failures (partial success)
function M.place(prefab, opts)
    if type(prefab) ~= 'table' or type(prefab.meta) ~= 'table' then
        return nil, 'invalid prefab'
    end
    opts = opts or {}

    local anchor, rotation = M._resolve_anchor(prefab, opts)
    if not anchor then
        return nil, 'no anchor (and not keep_position)'
    end

    local record = {
        prefab_name = prefab.meta.name,
        groups   = {},
        zones    = {},
        drawings = {},
        errors   = {},
    }

    local function injection_count()
        return #record.groups + #record.zones + #record.drawings
    end

    -- Groups (includes statics — they are groups with type='static' in DCS).
    for _, g_template in ipairs(prefab.groups or {}) do
        local g = deep_copy(g_template)
        transform_coords(g, anchor, rotation)
        transform_headings(g, rotation)
        local result, err = inject_group(g)
        if result then
            record.groups[#record.groups + 1] = {
                orig_name  = g_template.name,
                runtime_id = (type(result) == 'number') and result or g.groupId,
                group_obj  = g,  -- kept for undo (remove_group needs the full object)
            }
            if err then
                -- Partial success: inserted into data table but map objects failed.
                record.errors[#record.errors + 1] = 'group ' .. tostring(g_template.name) .. ' (partial): ' .. err
            end
        else
            record.errors[#record.errors + 1] = 'group ' .. tostring(g_template.name) .. ': ' .. tostring(err)
        end
    end

    -- Statics (distilled separately from groups in the prefab).
    -- Like groups, statics in DCS are groups with type='static'; inject_group handles them.
    for _, s_template in ipairs(prefab.statics or {}) do
        local s = deep_copy(s_template)
        transform_coords(s, anchor, rotation)
        transform_headings(s, rotation)
        local result, err = inject_group(s)
        if result then
            record.groups[#record.groups + 1] = {
                orig_name  = s_template.name,
                runtime_id = (type(result) == 'number') and result or s.groupId,
                group_obj  = s,
            }
            if err then
                record.errors[#record.errors + 1] = 'static ' .. tostring(s_template.name) .. ' (partial): ' .. err
            end
        else
            record.errors[#record.errors + 1] = 'static ' .. tostring(s_template.name) .. ': ' .. tostring(err)
        end
    end

    -- Zones.
    for _, z_template in ipairs(prefab.zones or {}) do
        local z = deep_copy(z_template)
        transform_coords(z, anchor, rotation)
        local id, err = inject_zone(z)
        if id then
            record.zones[#record.zones + 1] = { orig_name = z_template.name, runtime_id = id }
        else
            record.errors[#record.errors + 1] = 'zone ' .. tostring(z_template.name) .. ': ' .. tostring(err)
        end
    end

    -- Drawings.
    for _, d_template in ipairs(prefab.drawings or {}) do
        local d = deep_copy(d_template)
        transform_coords(d, anchor, rotation)
        local drawing_obj, err = inject_drawing(d)
        if drawing_obj then
            record.drawings[#record.drawings + 1] = {
                orig_name   = d_template.name,
                drawing_obj = drawing_obj,  -- kept for undo (objectDelete needs the full object)
            }
        else
            record.errors[#record.errors + 1] = 'drawing ' .. tostring(d_template.name) .. ': ' .. tostring(err)
        end
    end

    if injection_count() == 0 then
        return nil, 'no entities injected (' .. #record.errors .. ' errors — see log)'
    end
    return record
end

return M
