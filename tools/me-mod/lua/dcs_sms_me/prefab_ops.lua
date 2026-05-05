-- prefab_ops.lua — prefab save / load / place operations.
--
-- This file ships in three parts (one per group). Save + exists land
-- here in Task 4; scan_dir + load in Task 5; place in Task 6.
--
-- All public symbols return either a positive value (path, table,
-- record) on success, or nil + error_string on failure. No throws.

local lfs            = require('lfs')
local paths          = require('dcs_sms_me.paths')
local distill        = require('dcs_sms_me.prefab_distill').distill
local serializer     = require('dcs_sms_me.serializer')
local selection      = require('dcs_sms_me.selection')
local warehouse_ops  = require('dcs_sms_me.warehouse_ops')
local ship_warehouse = require('dcs_sms_me.ship_warehouse')

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

function M.save_selection(name, place_at_origin, airbases)
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

    -- Capture the current theatre via Mission.TheatreOfWarData.getName(); same
    -- accessor ME core uses when serializing a mission (me_mission.lua ~4505)
    -- and when MissionEditor.lua bootstraps. The require path is
    -- `Mission.TheatreOfWarData`, NOT bare `TheatreOfWarData` — the bare path
    -- silently fails the require (was an actual bug here, fixed 2026-05-03).
    -- pcall-guarded so the standalone test VM (no DCS modules) and any future
    -- API rename degrade to no-theatre rather than failing the save.
    local theatre
    pcall(function()
        local TheatreOfWarData = require('Mission.TheatreOfWarData')
        if TheatreOfWarData and type(TheatreOfWarData.getName) == 'function' then
            theatre = TheatreOfWarData.getName()
        end
    end)

    local prefab = distill(dump, {
        name             = name,
        theatre          = theatre,
        place_at_origin  = place_at_origin == true,
        airbases         = airbases,
    })
    if not prefab then
        return nil, 'distill returned nil — check log for details'
    end

    -- After distill, attach per-ship warehouse data inline on each unit.
    -- The data rides through serialization on `unit._sms_warehouse` and
    -- gets spliced back at the new unitId during M.place. is_default
    -- filtering inside attach_to_prefab keeps untouched ships from
    -- bloating the file.
    pcall(ship_warehouse.attach_to_prefab, prefab)

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

-- Split a `groups` array into (non-static, static) counts. DCS represents
-- statics as groups with type='static' (see me_copy_paste.duplicateGroup
-- and the merge in `inject_group`), so prefab.statics is typically empty
-- and statics live inside prefab.groups. Counting them separately is what
-- lets the library's S column show a meaningful number.
local function split_group_counts(groups)
    if type(groups) ~= 'table' then return 0, 0 end
    local g, s = 0, 0
    for _, entry in ipairs(groups) do
        if type(entry) == 'table' and entry.type == 'static' then
            s = s + 1
        else
            g = g + 1
        end
    end
    return g, s
end

local function row_from_prefab(name, path, prefab)
    local meta = prefab.meta
    local g_count, s_inline = split_group_counts(prefab.groups)
    local airbase_count = 0
    if type(meta.airbases) == 'table' then airbase_count = #meta.airbases end
    return {
        name            = meta.name or name,
        path            = path,
        theatre         = meta.theatre,
        source_dump     = meta.source_dump,
        place_at_origin = meta.place_at_origin == true,
        airbase_count   = airbase_count,
        group_count     = g_count,
        -- Statics from inline `type='static'` groups + any in the legacy
        -- top-level statics array (older fixtures / hand-written prefabs).
        static_count    = s_inline + count(prefab.statics),
        zone_count      = count(prefab.zones),
        drawing_count   = count(prefab.drawings),
    }
end

function M.scan_dir()
    paths.ensure_prefabs()
    local rows = {}

    -- lfs.dir returns (iterator, state) — generic-for needs BOTH so
    -- the iterator gets called with its state on each step. An earlier
    -- attempt did `local ok, iter = pcall(lfs.dir, ...)` then `for entry
    -- in iter do`, which discards state and aborts with "bad argument
    -- #1 to '(for generator)'" against DCS's vfs lfs. Wrapping the
    -- entire walk in pcall preserves the multi-return (Lua passes both
    -- values from `lfs.dir(...)` to `for` directly inside the closure)
    -- AND turns any mid-walk VFS error into an empty list instead of a
    -- throw.
    local ok, err = pcall(function()
        for entry in lfs.dir(paths.PREFABS_DIR) do
            if entry ~= '.' and entry ~= '..' and entry:match('%.lua$') then
                local name = entry:gsub('%.lua$', '')
                local path = paths.PREFABS_DIR .. entry
                local prefab, lerr = M.load(path)
                if prefab then
                    rows[#rows + 1] = row_from_prefab(name, path, prefab)
                else
                    rows[#rows + 1] = { name = name, path = path, error = lerr }
                end
            end
        end
    end)
    if not ok then
        if log and log.write then
            log.write('sms.me.prefab', log.WARNING, 'scan_dir failed: ' .. tostring(err))
        end
        return rows
    end

    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

-- ---------------------------------------------------------------------------
-- Place math (unit-testable, exposed under M._<name>)
-- ---------------------------------------------------------------------------

-- Rotate (rel_x, rel_y) by rotation_deg and translate to world coords.
-- DCS 2D map space: x = North, y = East (top-down view of the 3D world
-- space where x = North, z = East, y = altitude). heading 0 = +x = North.
-- We use a standard CCW rotation for relative placement: positive
-- rotation_deg increases heading (e.g. unit pointing North + 90° → East).
-- _rotate_mapData_geometry uses the same matrix so polygons rotate the
-- same way as the groups inside them.
function M._place_xy(rel_x, rel_y, anchor, rotation_deg)
    local r = (rotation_deg or 0) * (math.pi / 180)
    local c, s = math.cos(r), math.sin(r)
    local rx = rel_x * c - rel_y * s
    local ry = rel_x * s + rel_y * c
    return anchor.x + rx, anchor.y + ry
end

-- 0.1.0 back-compat: undo distill's incorrect per-vertex centroid
-- subtraction by adding (ax, ay) (= meta.world_anchor) back to every
-- {x,y} pair inside mapData's geometry sub-arrays. mapData.{x,y} itself
-- is the polygon anchor and stays untouched. No-op when mapData is nil.
function M._unrebase_mapData_geometry(mapData, ax, ay)
    if type(mapData) ~= 'table' then return end
    local function unrebase(t)
        if type(t) ~= 'table' then return end
        if type(t.x) == 'number' and type(t.y) == 'number' then
            t.x = t.x + ax
            t.y = t.y + ay
        end
        for _, sub in pairs(t) do
            if type(sub) == 'table' then unrebase(sub) end
        end
    end
    for k, v in pairs(mapData) do
        if k ~= 'x' and k ~= 'y' and type(v) == 'table' then
            unrebase(v)
        end
    end
end

-- Rotate every {x,y} pair inside mapData's geometry sub-arrays (points,
-- arc_points, etc.) by rotation_deg around the local origin. mapData.{x,y}
-- itself is the polygon's anchor and is NOT touched here — it rotates
-- downstream via _place_xy. No-op when rotation is 0 or mapData is nil.
function M._rotate_mapData_geometry(mapData, rotation_deg)
    if type(mapData) ~= 'table' then return end
    local deg = rotation_deg or 0
    if deg == 0 then return end
    local rad = deg * (math.pi / 180)
    local cs, sn = math.cos(rad), math.sin(rad)
    local function rotate_xy(t)
        if type(t) ~= 'table' then return end
        if type(t.x) == 'number' and type(t.y) == 'number' then
            local px, py = t.x, t.y
            t.x = px * cs - py * sn
            t.y = px * sn + py * cs
        end
        for _, sub in pairs(t) do
            if type(sub) == 'table' then rotate_xy(sub) end
        end
    end
    for k, v in pairs(mapData) do
        if k ~= 'x' and k ~= 'y' and type(v) == 'table' then
            rotate_xy(v)
        end
    end
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

-- Stamp a country override onto a copied group/static and its units. We
-- write country_name (a string) and clear the numeric country id so
-- resolve_country picks up the override at step 1. No-op for nil/empty
-- overrides — caller's signal that the prefab's own country should win.
local function override_country(group, country_name)
    if not country_name or country_name == '' then return end
    if type(group) ~= 'table' then return end
    group.country_name = country_name
    group.country = nil
    if type(group.units) == 'table' then
        for _, u in pairs(group.units) do
            if type(u) == 'table' then
                u.country_name = country_name
                u.country = nil
            end
        end
    end
end
M._override_country = override_country

-- Walk every entity in a loaded prefab and return the axis-aligned bounding
-- box of their positions, in the prefab's anchor-relative coordinate frame
-- (the same frame distill writes). Returns nil if the prefab has no
-- positionable entities. Powers the place-at-click preview overlay.
--
--  groups   — group's own (x, y) plus each unit's (x, y).
--  statics  — same shape as groups (statics inject as type='static' groups).
--  zones    — zone center expanded by its radius.
--  drawings — mapData.x/y plus every point inside mapData.points (deltas
--             from the polygon anchor).
function M.compute_bbox(prefab)
    if type(prefab) ~= 'table' then return nil end
    local minx, miny =  math.huge,  math.huge
    local maxx, maxy = -math.huge, -math.huge
    local seen = false
    local function add(x, y)
        if type(x) ~= 'number' or type(y) ~= 'number' then return end
        seen = true
        if x < minx then minx = x end
        if x > maxx then maxx = x end
        if y < miny then miny = y end
        if y > maxy then maxy = y end
    end
    local function walk_group(g)
        if type(g) ~= 'table' then return end
        if type(g.x) == 'number' and type(g.y) == 'number' then add(g.x, g.y) end
        if type(g.units) == 'table' then
            for _, u in pairs(g.units) do
                if type(u) == 'table' and type(u.x) == 'number' and type(u.y) == 'number' then
                    add(u.x, u.y)
                end
            end
        end
    end
    for _, g in ipairs(prefab.groups   or {}) do walk_group(g) end
    for _, s in ipairs(prefab.statics  or {}) do walk_group(s) end
    for _, z in ipairs(prefab.zones    or {}) do
        if type(z.x) == 'number' and type(z.y) == 'number' then
            local r = tonumber(z.radius) or 0
            add(z.x - r, z.y - r)
            add(z.x + r, z.y + r)
        end
    end
    for _, d in ipairs(prefab.drawings or {}) do
        local md = d.mapData
        if type(md) == 'table' then
            local ax = tonumber(md.x) or 0
            local ay = tonumber(md.y) or 0
            add(ax, ay)
            if type(md.points) == 'table' then
                for _, p in ipairs(md.points) do
                    if type(p) == 'table' then add(ax + (p.x or 0), ay + (p.y or 0)) end
                end
            end
        end
    end
    if not seen then return nil end
    return { min_x = minx, min_y = miny, max_x = maxx, max_y = maxy }
end

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

-- Compose the prefab's stored heading (degrees, written by distill's
-- rad→deg conversion) with the placement rotation (degrees), then convert
-- the composed heading back to radians for DCS injection — DCS group/unit
-- tables expect heading in radians at runtime.
--
-- Earlier version had `v * (180 / math.pi)` here too, treating the file
-- value as radians; that was a bug (file is already in degrees) and caused
-- placed heading = stored * (180/pi) % 360 * (pi/180) ≈ stored * (180/pi)
-- modulo wrap, e.g. 45° → 1.0177 rad (~58.31°).
--
-- Assumption: every `heading` key encountered here is a body-frame
-- orientation that should rotate with the group. That holds for all
-- entities we currently distill (group-level + unit-level on groups and
-- statics; drawings + zones contain no `heading` keys). If a future
-- spec adds a heading-like field that's already in world frame (e.g.
-- a sensor bore-sight), the recursive walk below would incorrectly
-- rotate it — revisit then.
local function transform_headings(t, rotation_deg)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'heading' and type(v) == 'number' then
            t[k] = M._heading_world(v, rotation_deg) * (math.pi / 180)
        elseif type(v) == 'table' then
            transform_headings(v, rotation_deg)
        end
    end
end
M._transform_headings = transform_headings

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

-- Resolve the country object + name from a prefab group's stored country
-- info. distill captures the numeric country id (group.country); the ME
-- mutation API needs the country NAME (as a key into Mission.missionCountry).
-- Order of attempts:
--   1. group.country_name (forward-compat — if a future distill writes it)
--   2. iterate Mission.missionCountry to find a country whose .id == ours
--   3. CoalitionController.getCountryNameById as a fallback
-- Returns: country_obj, country_name | nil, error_string
local function resolve_country(group)
    local Mission = require('me_mission')
    if type(Mission.missionCountry) ~= 'table' then
        return nil, 'Mission.missionCountry unavailable'
    end

    if type(group.country_name) == 'string'
        and Mission.missionCountry[group.country_name] then
        return Mission.missionCountry[group.country_name], group.country_name
    end

    if type(group.country) == 'number' then
        local id = group.country
        for name, c in pairs(Mission.missionCountry) do
            if type(c) == 'table' and c.id == id then
                return c, name
            end
        end
        local ok, ctrl = pcall(require, 'Mission.CoalitionController')
        if ok and ctrl and type(ctrl.getCountryNameById) == 'function' then
            local ok2, name = pcall(ctrl.getCountryNameById, id)
            if ok2 and type(name) == 'string' then
                local c = Mission.missionCountry[name]
                if c then return c, name end
            end
        end
        return nil, 'no country with id=' .. tostring(id) .. ' in current mission'
    end

    return nil, 'group has no country id or name'
end

-- Groups (and statics, which are groups of type='static') — full
-- duplicateGroup-style injection: regenerate ids, set boss links,
-- prep mapObjects, then create + insert + create_map_objects.
--
-- Mirrors the behavior of me_copy_paste.duplicateGroup but:
--   - resolves country from numeric id (we strip boss during distill)
--   - skips the Surface check (would pop a UI warning on water-placed)
--   - skips EPLRS / INUFixPoints / NavTargetPoints regeneration (rare;
--     v2 work if a real prefab needs them)
--   - skips link-waypoint resolution (linkUnit/linkParent reference IDs
--     from the source mission and won't resolve here — nilled out)
--
-- Removal (undo) goes through Mission.remove_group(group_obj) — see the
-- M._remove.group wrapper below.
local function inject_group(group)
    local Mission = require('me_mission')

    local country, country_name_or_err = resolve_country(group)
    if not country then return nil, country_name_or_err end
    local country_name = country_name_or_err

    if not group.type or group.type == '' then
        return nil, 'group has no type field'
    end
    if not country[group.type] then country[group.type] = { group = {} } end
    if not country[group.type].group then country[group.type].group = {} end

    -- Regenerate group identity. check_group_name appends -1, -2, ... if
    -- the name is taken; getNewGroupId reserves a fresh id. Both are
    -- module-public functions in me_mission.
    local fresh_name = group.name or 'group'
    if type(Mission.check_group_name) == 'function' then
        local ok, n = pcall(Mission.check_group_name, fresh_name)
        if ok and type(n) == 'string' then fresh_name = n end
    end
    group.name = fresh_name
    if type(Mission.getNewGroupId) == 'function' then
        local ok, gid = pcall(Mission.getNewGroupId)
        if ok then group.groupId = gid end
    end
    if type(Mission.group_by_name) == 'table' then
        Mission.group_by_name[group.name] = group
    end
    if type(Mission.group_by_id) == 'table' and group.groupId then
        Mission.group_by_id[group.groupId] = group
    end
    group.boss = country
    group.mapObjects = group.mapObjects or { units = {}, zones = {}, route = {} }

    -- Color (best-effort — non-static groups carry color from coalition)
    if type(Mission.countryCoalition) == 'table'
        and Mission.countryCoalition[country_name]
        and Mission.countryCoalition[country_name].color then
        group.color = Mission.countryCoalition[country_name].color
    end

    -- Regenerate units. Each unit needs a fresh name+id and back-link to
    -- the group. Strip parking links — they reference airfield slots from
    -- the source mission that won't be valid at the new anchor.
    if type(group.units) == 'table' then
        for _, u in pairs(group.units) do
            if type(u) == 'table' then
                if type(Mission.getUnitName) == 'function' then
                    local ok, nm = pcall(Mission.getUnitName, group.name)
                    if ok and type(nm) == 'string' then u.name = nm end
                end
                if type(Mission.getNewUnitId) == 'function' then
                    local ok, uid = pcall(Mission.getNewUnitId)
                    if ok then u.unitId = uid end
                end
                u.boss = group
                u.parking = nil
                u.parking_landing = nil
                u.parking_id = nil
                u.parking_landing_id = nil
                if type(Mission.unit_by_name) == 'table' and u.name then
                    Mission.unit_by_name[u.name] = u
                end
                if type(Mission.unit_by_id) == 'table' and u.unitId then
                    Mission.unit_by_id[u.unitId] = u
                end
            end
        end
    end

    -- Reset route waypoints (only present on non-static groups). Clear
    -- linkUnit/linkParent — they reference units from the source mission
    -- that don't exist here. Targets array also gets cleared (per
    -- duplicateGroup line 306) since target IDs are source-mission-scoped.
    if type(group.route) == 'table' and type(group.route.points) == 'table' then
        for _, wpt in pairs(group.route.points) do
            if type(wpt) == 'table' then
                wpt.boss = group
                wpt.linkUnit = nil
                wpt.linkParent = nil
                wpt.targets = {}
                wpt.airdromeId = nil
                wpt.helipadId = nil
            end
        end
    end

    -- Insertion sequence (me_copy_paste.duplicateGroup lines 380-382)
    local ok_cgo, cgo_err = pcall(Mission.create_group_objects, group)
    if not ok_cgo then
        return nil, 'create_group_objects: ' .. tostring(cgo_err)
    end

    table.insert(country[group.type].group, group)

    local ok_cgmo, cgmo_err = pcall(Mission.create_group_map_objects, group)
    if not ok_cgmo then
        -- Already in the country's group table; visuals failed though.
        return group.groupId or true,
            'create_group_map_objects: ' .. tostring(cgmo_err)
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
--
-- copyObjToCoord(drawing, target_x, target_y) creates a copy and returns
-- the new object. Internally it calls MapWindow.createDrawObject(mapData)
-- to render at the geometry's current absolute coords, then
-- MapWindow.updateDrawObject(mapId, {target_x, target_y}) which shifts
-- the visual by (target_x - drawing.mapData.x).
--
-- Caller MUST pass target_{x,y} as the desired new world anchor and
-- leave drawing.mapData.{x,y} at the source coords so the shift delta
-- is non-zero. This is why we don't pre-set mapData.x/y in M.place's
-- drawing loop — see the comment block there.
--
-- The returned object (not just an id) is stored in the undo record so
-- that panel_draw.objectDelete can remove it.
local function inject_drawing(drawing, target_x, target_y)
    local ok_req, panel = pcall(require, 'me_draw_panel')
    if not ok_req or not panel then
        return nil, 'me_draw_panel not available'
    end
    if type(panel.copyObjToCoord) ~= 'function' then
        return nil, 'panel_draw.copyObjToCoord not available'
    end
    -- If caller didn't supply explicit target coords, fall back to
    -- whatever the drawing's mapData/top-level says (legacy paths).
    local tx = target_x or (drawing.mapData and drawing.mapData.x) or drawing.x or 0
    local ty = target_y or (drawing.mapData and drawing.mapData.y) or drawing.y or 0
    local ok, result = pcall(panel.copyObjToCoord, drawing, tx, ty)
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
--   country_name   string  — override every group/static/unit to this country
--                            (a key in Mission.missionCountry). Drawings and
--                            zones are unaffected. Nil/empty = use the country
--                            stored in the prefab.
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

    -- Validate country override against the open mission's country table.
    -- An override the mission can't satisfy means the user picked from a
    -- stale dropdown — surface as a hard error rather than silently falling
    -- back to the stored country.
    if opts.country_name and opts.country_name ~= '' then
        local Mission = require('me_mission')
        if type(Mission.missionCountry) ~= 'table'
            or not Mission.missionCountry[opts.country_name] then
            return nil, 'country "' .. tostring(opts.country_name) ..
                '" is not available in the current mission'
        end
    end

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
        override_country(g, opts.country_name)
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
        override_country(s, opts.country_name)
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

    -- Drawings — pipeline notes:
    --
    -- ME stores polygon vertices (mapData.points[i].{x,y}) RELATIVE to
    -- mapData.{x,y}. The renderer computes vertex world position as
    -- `mapData.x + points[i].x`. ME's own copy/paste (me_copy_paste.lua:651-653)
    -- just translates mapData.{x,y} and never touches the inner points.
    --
    -- distill at sms_prefab_version >= "0.2.0" preserves this invariant
    -- (skips geometry sub-arrays inside mapData when subtracting the
    -- centroid). Earlier versions ("0.1.0", or unset) had a bug that
    -- subtracted the centroid from each inner vertex too, breaking the
    -- relative-to-mapData invariant. We keep an un-rebase shim here that
    -- reverses that subtraction on those legacy files; it's gated on the
    -- meta.sms_prefab_version field so 0.2.0 saves don't get touched.
    --
    -- copyObjToCoord internals: createDrawObject(mapData) + moveObject
    -- (which updates mapData.{x,y} via updateDrawObject). So we LEAVE
    -- mapData.{x,y} at the post-distill (anchor-relative) value and pass
    -- target = anchor + rotated(post-distill xy) as the world center.
    local ax, ay = 0, 0
    if prefab.meta and prefab.meta.world_anchor then
        ax = prefab.meta.world_anchor.x or 0
        ay = prefab.meta.world_anchor.y or 0
    end
    -- Opt IN to the un-rebase shim for known-broken versions only. Earlier
    -- code did `~= '0.2.0'`, which would have silently fired the shim on a
    -- hypothetical future 0.3.0 save and double-added world_anchor into
    -- vertices that were never rebased. Treating it as a known-bad list
    -- means new versions stay safe by default; add to this list if a future
    -- format reintroduces the same bug.
    local v = (prefab.meta and prefab.meta.sms_prefab_version) or ''
    local needs_unrebase_shim = (v == '' or v == '0.1.0')

    for _, d_template in ipairs(prefab.drawings or {}) do
        local d = deep_copy(d_template)

        -- 0.1.0 back-compat: undo the over-rebase distill applied to
        -- vertices on legacy saves. New saves at 0.2.0+ skip this.
        if needs_unrebase_shim then
            M._unrebase_mapData_geometry(d.mapData, ax, ay)
        end

        -- Drawing rotation: vertices inside mapData are deltas relative to
        -- mapData.{x,y}, so rotating them around the local origin (0,0) is
        -- equivalent to rotating the polygon around its anchor. mapData.x/y
        -- itself rotates downstream via _place_xy.
        M._rotate_mapData_geometry(d.mapData, rotation)

        -- mapData.x/y is at anchor-relative coords from distill. Compute
        -- the new world center; pass it to copyObjToCoord as the target.
        local rel_x = (d.mapData and d.mapData.x) or d.x or 0
        local rel_y = (d.mapData and d.mapData.y) or d.y or 0
        local world_x, world_y = M._place_xy(rel_x, rel_y, anchor, rotation)

        local drawing_obj, err = inject_drawing(d, world_x, world_y)
        if drawing_obj then
            record.drawings[#record.drawings + 1] = {
                orig_name   = d_template.name,
                drawing_obj = drawing_obj,  -- kept for undo (objectDelete needs the full object)
            }
        else
            record.errors[#record.errors + 1] = 'drawing ' .. tostring(d_template.name) .. ': ' .. tostring(err)
        end
    end

    -- Log per-entity errors so the user can see WHY entities failed,
    -- not just a count. The 'see log' message above only helps if the
    -- log actually has the lines.
    if log and log.write and #record.errors > 0 then
        for _, e in ipairs(record.errors) do
            log.write('sms.me.prefab', log.ERROR, 'place: ' .. tostring(e))
        end
    end

    if injection_count() == 0 then
        return nil, 'no entities injected (' .. #record.errors .. ' errors — see log)'
    end

    -- Splice per-ship warehouse entries into mission.AirportsEquipment.warehouses
    -- using each placed unit's freshly-allocated unitId. Coalition is overridden
    -- by opts.override_coalition (lowercased) when the user picked a country
    -- whose coalition differs from what was saved.
    pcall(ship_warehouse.apply_from_record, record, {
        override_coalition = opts and opts.override_coalition,
    })

    return record
end

-- Apply meta.airbases to the live mission state. Re-resolves each entry by
-- airbase name (the airdromeNumber at save time may not match in the
-- destination mission). Theatre mismatch (or unknown prefab theatre)
-- refuses the whole step. Returns (true, summary) on success or
-- (nil, summary_with_error) on failure.
--
-- opts = {
--     current_theatre    = string?,  -- if set, refuse on theatre mismatch OR
--                                    -- when prefab has no recorded theatre
--                                    -- (we extracted these airbases from SOME
--                                    -- map; without provenance we can't verify
--                                    -- the destination is the right one)
--     override_coalition = string?,  -- if set ('RED'/'BLUE'/'NEUTRAL'), every applied
--                                    -- airbase ends up under this coalition instead
--                                    -- of whatever was saved into the prefab
-- }
--
-- summary = {
--     applied = N,                  -- count of warehouses successfully spliced
--     skipped = N,                  -- count of named airdromes NOT found in destination
--     missing = { name1, ... },     -- names that were skipped
--     error   = string?,            -- set on hard failure (theatre mismatch, etc.)
-- }
function M.apply_airbases(prefab, opts)
    if type(prefab) ~= 'table' or type(prefab.meta) ~= 'table' then
        return nil, { applied = 0, skipped = 0, missing = {}, error = 'prefab missing meta' }
    end
    local airbases = prefab.meta.airbases
    if type(airbases) ~= 'table' or #airbases == 0 then
        return true, { applied = 0, skipped = 0, missing = {} }
    end

    opts = opts or {}
    local current_theatre = opts.current_theatre
    if current_theatre then
        if not prefab.meta.theatre or prefab.meta.theatre == '' then
            return nil, {
                applied = 0, skipped = #airbases, missing = {},
                error = 'prefab has no recorded theatre; cannot verify destination is the right map. Refusing to apply.',
            }
        end
        if prefab.meta.theatre ~= current_theatre then
            return nil, {
                applied = 0, skipped = #airbases, missing = {},
                error = 'theatre mismatch: prefab=' .. tostring(prefab.meta.theatre)
                        .. ' destination=' .. tostring(current_theatre),
            }
        end
    end

    local AC_ok, AC = pcall(require, 'Mission.AirdromeController')
    if not AC_ok or not AC or type(AC.getAirdromes) ~= 'function' then
        return nil, {
            applied = 0, skipped = #airbases, missing = {},
            error = 'AirdromeController unavailable',
        }
    end

    local by_name = {}
    for _, ad in ipairs(AC.getAirdromes() or {}) do
        if ad.getName then by_name[ad:getName()] = ad end
    end

    local override_coalition = opts.override_coalition
    local applied, skipped, missing = 0, 0, {}
    for _, ab in ipairs(airbases) do
        local ad = ab.name and by_name[ab.name] or nil
        if ad and ad.getAirdromeNumber then
            local n = ad:getAirdromeNumber()
            -- If an override coalition is supplied, build a shallow wrapper
            -- around the saved warehouse with the override applied. We don't
            -- mutate ab.warehouse — warehouse_ops.apply deep-copies what it
            -- receives, so a shallow wrapper is enough to keep the prefab
            -- table intact for any subsequent calls.
            local warehouse_to_apply = ab.warehouse
            if override_coalition and type(warehouse_to_apply) == 'table' then
                local wrapped = {}
                for k, v in pairs(warehouse_to_apply) do wrapped[k] = v end
                wrapped.coalition = override_coalition
                warehouse_to_apply = wrapped
            end
            local ok = warehouse_ops.apply(n, warehouse_to_apply)
            if ok then applied = applied + 1
            else skipped = skipped + 1; missing[#missing + 1] = ab.name
            end
        else
            skipped = skipped + 1
            if ab.name then missing[#missing + 1] = ab.name end
        end
    end
    return true, { applied = applied, skipped = skipped, missing = missing }
end

return M
