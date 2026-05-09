-- dcs_sms_me/verbs.lua — host module for `dcs-sms me <noun> <verb>` commands.
--
-- Each verb is a Lua function that takes a single args table and returns a
-- result table (JSON-encoded by the bridge for the CLI response). Verb
-- functions live here rather than in the Go CLI because:
--   * the work happens in the ME's Lua state (we'd be string-templating Lua
--     into the bridge anyway), and
--   * keeping the logic in one Lua module makes verbs testable independently
--     of the CLI and reusable across clients (CLI today, possibly other
--     bridges or in-ME UI later).
--
-- Naming convention: verb function names use snake_case to mirror the CLI's
-- `<noun> <verb>` shape (`me file open` → `verbs.file_open(args)`).
--
-- Error handling: each verb wraps its work in pcall and returns a uniform
-- result shape:
--   { ok = true,  ... }       -- success, with verb-specific extra fields
--   { ok = false, error = "..." }  -- failure, error string
-- The CLI side checks resp.return_value.ok to decide its exit code.

local M = {}

-- ============================================================
-- Coordinate convention for placement verbs
-- ============================================================
--
-- All public verbs that take a map position use the flag triplet:
--   north  meters north of theatre origin (positive = north)
--   east   meters east  of theatre origin (positive = east)
--   alt    altitude in meters above sea level (where applicable)
--
-- DCS internally exposes positions in two contradictory forms — both
-- abbreviate to "x/y/z" but with different meanings — and our --north/--east
-- semantic naming hides the trap:
--
--   1. Mission table (the .miz file format, what the ME persists):
--        { x = north_south, y = east_west }            -- no z, alt is separate
--      "y" means east–west on the ground here.
--
--   2. Runtime 3D engine (vec3 in mission-env scripting, terrain.* APIs):
--        { x = north_south, y = altitude, z = east_west }
--      "y" means altitude here, "z" means east–west.
--
-- "y" thus means two completely different things depending on which DCS API
-- you're holding. Rather than picking one and confusing users of the other,
-- our public surface is north / east / alt — semantically unambiguous, and
-- we translate to whatever the underlying API needs (here we write
-- `g.x = args.north`, `g.y = args.east`, since we're storing into the
-- mission table).
--
-- See research/me-bridge-discovery-2026-05-08.md
--   → "DCS ME coordinate axes (critical correction)"
-- for the gotcha that motivated this.

-- ============================================================
-- Shared helpers (used across multiple verbs)
-- ============================================================
--
-- Defined up here so forward-references work — Lua resolves locals at the
-- point they're declared, so any helper called by a verb body must be
-- declared above the verb. Read-side and write-side verbs share these.

-- walk_groups — yields every group in the mission with its country and side.
-- Iterator-friendly via a callback so callers can short-circuit (return
-- false from the callback to stop walking).
local function walk_groups(callback)
    local module_mission = require('me_mission')
    local mission = module_mission.mission
    if type(mission) ~= 'table' or type(mission.coalition) ~= 'table' then
        return
    end
    local cats = { 'plane', 'helicopter', 'vehicle', 'ship', 'static' }
    for side_name, side in pairs(mission.coalition) do
        if type(side) == 'table' and type(side.country) == 'table' then
            for _, country in ipairs(side.country) do
                for _, cat in ipairs(cats) do
                    if country[cat] and type(country[cat].group) == 'table' then
                        for _, g in ipairs(country[cat].group) do
                            if callback(g, country, side_name, cat) == false then
                                return
                            end
                        end
                    end
                end
            end
        end
    end
end

-- strip_back_refs — deep clone, dropping keys that create cycles when
-- serialized (boss = group/country, mapObjects = render-side cache).
local function strip_back_refs(v, depth)
    depth = depth or 0
    if depth > 32 or type(v) ~= 'table' then return v end
    local out = {}
    for k, vv in pairs(v) do
        if k ~= 'boss' and k ~= 'mapObjects' then
            out[k] = strip_back_refs(vv, depth + 1)
        end
    end
    return out
end

-- refresh_group_view — defensive map-objects refresh after a unit-level
-- mutation. Disk-loaded groups have mapObjects=nil until selected; the
-- create_group_map_objects + update_group_map_objects pair handles both
-- the never-rendered and already-rendered cases. Shared by group_set_pos,
-- group_add_unit, and every unit-level setter that moves something.
local function refresh_group_view(g)
    local Mission = require('me_mission')
    if g.mapObjects == nil and type(Mission.create_group_map_objects) == 'function' then
        pcall(Mission.create_group_map_objects, g)
    end
    if type(Mission.update_group_map_objects) == 'function' then
        pcall(Mission.update_group_map_objects, g)
    end
end

-- ============================================================
-- File / mission lifecycle verbs
-- ============================================================

-- file_open — open a .miz file in the Mission Editor.
-- Wraps me_toolbar.loadMission. The actual file read is async (ED's
-- progressBar schedules it on a later UpdateManager tick), so this returns
-- as soon as the call is dispatched — not when the load has completed.
--
-- args: { path: string }     -- absolute path to .miz file (forward slashes
--                                preferred to dodge backslash-escape pain)
function M.file_open(args)
    if type(args) ~= 'table' or type(args.path) ~= 'string' or args.path == '' then
        return { ok = false, error = 'file_open requires args.path (string)' }
    end
    local ok_req, me_toolbar = pcall(require, 'me_toolbar')
    if not ok_req or type(me_toolbar) ~= 'table' or type(me_toolbar.loadMission) ~= 'function' then
        return { ok = false, error = 'me_toolbar.loadMission unavailable' }
    end
    local ok_call, err = pcall(me_toolbar.loadMission, args.path)
    if not ok_call then
        return { ok = false, error = 'loadMission: ' .. tostring(err) }
    end
    return { ok = true, path = args.path }
end

-- file_new — create a fresh empty mission on the given map, no UI dialog.
--
-- Mirrors what clicking OK on the "New Mission Settings" dialog does, by
-- replicating the body of CoalitionPanel.startME / initTerr (DCS file
-- MissionEditor/modules/Mission/CoalitionPanel.lua, ~line 313/430). The dialog
-- itself is bypassed: we set default coalitions, select the theatre, then
-- schedule MapWindow.initTerrain → module_mission.create_new_mission →
-- MapWindow.show via ProgressBarDialog (the same async dispatcher used by the
-- panel's OK handler).
--
-- The discovery-log "needs-more" note about create_new_mission crashing in
-- me_weather (SW_bound nil) was caused by skipping MapWindow.initTerrain —
-- initTerrain is what populates the map data me_weather.initModule reads. With
-- the correct order, it just works.
--
-- args:
--   map:   string            theatre name e.g. "Syria" / "Caucasus" — must
--                            match TheatreOfWarData.verifyTheatreOfWar
--   force: bool (optional)   discard unsaved changes in the current mission;
--                            if false (default) we refuse when the current
--                            mission is dirty, mirroring the DCS save-prompt
function M.file_new(args)
    if type(args) ~= 'table' or type(args.map) ~= 'string' or args.map == '' then
        return { ok = false, error = 'file_new requires args.map (string)' }
    end
    local map = args.map

    local ok_tow, TheatreOfWarData = pcall(require, 'Mission.TheatreOfWarData')
    if not ok_tow or type(TheatreOfWarData) ~= 'table' then
        return { ok = false, error = 'Mission.TheatreOfWarData unavailable' }
    end
    if type(TheatreOfWarData.verifyTheatreOfWar) ~= 'function'
            or not TheatreOfWarData.verifyTheatreOfWar(map) then
        local available = {}
        if type(TheatreOfWarData.getTheatresOfWar) == 'function' then
            for _, t in ipairs(TheatreOfWarData.getTheatresOfWar() or {}) do
                if type(t) == 'table' and t.name then
                    table.insert(available, t.name)
                end
            end
        end
        return { ok = false, error = 'unknown map: ' .. tostring(map),
                 available_maps = available }
    end

    local ok_mw, MapWindow = pcall(require, 'me_map_window')
    local ok_mm, module_mission = pcall(require, 'me_mission')
    if not ok_mw or not ok_mm then
        return { ok = false, error = 'me_map_window / me_mission unavailable' }
    end

    if args.force ~= true then
        local empty = type(MapWindow.isEmptyME) == 'function' and MapWindow.isEmptyME()
        local modified = type(module_mission.isMissionModified) == 'function'
                and module_mission.isMissionModified()
        if not empty and modified then
            return { ok = false,
                     error = 'current mission has unsaved changes; pass force=true to discard' }
        end
    end

    local ok_cc, CoalitionController = pcall(require, 'Mission.CoalitionController')
    local ok_pb, progressBar = pcall(require, 'ProgressBarDialog')
    if not ok_cc or not ok_pb then
        return { ok = false, error = 'CoalitionController / ProgressBarDialog unavailable' }
    end

    local ok_def, def_err = pcall(CoalitionController.setDefaultCoalitions)
    if not ok_def then
        return { ok = false, error = 'setDefaultCoalitions: ' .. tostring(def_err) }
    end
    local ok_sel, sel_err = pcall(CoalitionController.selectTheatreOfWar, map, true)
    if not ok_sel then
        return { ok = false, error = 'selectTheatreOfWar: ' .. tostring(sel_err) }
    end

    -- The actual terrain init + mission reset is heavy and must run on a
    -- later tick (matches what the OK button does). We can't surface its
    -- pass/fail synchronously — caller polls ME state afterwards.
    local function init_terrain_then_mission()
        MapWindow.initTerrain(false, false, 'ME', module_mission.getDefaultDate())
        module_mission.create_new_mission(true)
        MapWindow.show(true)
        return true
    end

    local ok_sched, sched_err = pcall(progressBar.setUpdateFunction, init_terrain_then_mission)
    if not ok_sched then
        return { ok = false, error = 'schedule init: ' .. tostring(sched_err) }
    end

    return { ok = true, map = map, async = true }
end

-- refresh_menubar_title — keep the ME's top-bar filename label in sync with
-- the actual saved path. DCS native flows update this via the post-save
-- reload (module_mission.load → MenuBar.setFileName at me_mission.lua:2550),
-- but in the no-reload path we have to do it ourselves.
local function refresh_menubar_title(path)
    pcall(function()
        local mb = require('me_menubar')
        local U = require('me_utilities')
        if type(mb.setFileName) == 'function' and type(U.extractFileName) == 'function' then
            mb.setFileName(U.extractFileName(path))
        end
    end)
end

-- file_save — save the current mission to its existing path.
--
-- Wraps module_mission.save_mission_safe(path, false, noLoad).
--   showError=false: no UI popup on error (we surface it in the response)
--   noLoad:          when reopen=true (default), DCS re-loads the file we
--                    just wrote — same as clicking Ctrl+S in the ME. This
--                    refreshes the title bar, dictionary state, etc.
--                    when reopen=false, we skip the reload to avoid the
--                    F-16-waypoint reload-crash documented in the discovery
--                    log (me_route.lua:2413, post-save load() of a mission
--                    with un-fix'd waypoints corrupts the .miz and hangs
--                    DCS). We still refresh the title bar manually so the
--                    user sees the right filename.
--
-- args:
--   reopen: bool (optional, default true) — match DCS-native behavior; pass
--                false only when you've just inject'd groups but haven't run
--                Mission.fixWaypointForGroup yet
--
-- Errors if the mission has no real path yet (i.e. it's the temp/new
-- placeholder) — use file_save_as for that case.
function M.file_save(args)
    local reopen = true
    if type(args) == 'table' and args.reopen ~= nil then reopen = (args.reopen == true) end
    local ok_mm, module_mission = pcall(require, 'me_mission')
    if not ok_mm or type(module_mission) ~= 'table' then
        return { ok = false, error = 'me_mission unavailable' }
    end
    if type(module_mission.save_mission_safe) ~= 'function' then
        return { ok = false, error = 'me_mission.save_mission_safe unavailable' }
    end
    if type(module_mission.getMissionPathIsSaved) ~= 'function'
            or not module_mission.getMissionPathIsSaved() then
        return { ok = false,
                 error = 'mission has no saved path; use file save-as --path <X.miz>' }
    end
    local path = module_mission.mission and module_mission.mission.path
    if type(path) ~= 'string' or path == '' then
        return { ok = false, error = 'mission.path missing' }
    end
    local noLoad = not reopen
    local ok_call, ok_or_err = pcall(module_mission.save_mission_safe, path, false, noLoad)
    if not ok_call then
        return { ok = false,
                 error = 'save_mission_safe: ' .. tostring(ok_or_err)
                         .. ' (file written; post-save reload crashed — try --reopen=false)' }
    end
    if ok_or_err ~= true then
        return { ok = false, error = 'save failed (mission validation or I/O); enable showError to see details' }
    end
    if noLoad then refresh_menubar_title(path) end
    return { ok = true, path = path, reopen = reopen }
end

-- file_save_as — save the current mission to a new path.
--
-- args:
--   path:   string  — absolute path to write (forward slashes preferred)
--   reopen: bool (optional, default true) — see file_save for semantics
--
-- Updates module_mission.mission.path and MeSettings.missionPath so the next
-- bare file_save targets the new file (matching what me_toolbar's Save-As
-- flow does after FileDialog.save returns a filename). When reopen=true the
-- post-save load() also resets mission.path internally and refreshes the
-- title bar; when reopen=false we maintain that state ourselves.
function M.file_save_as(args)
    if type(args) ~= 'table' or type(args.path) ~= 'string' or args.path == '' then
        return { ok = false, error = 'file_save_as requires args.path (string)' }
    end
    local reopen = true
    if args.reopen ~= nil then reopen = (args.reopen == true) end
    local ok_mm, module_mission = pcall(require, 'me_mission')
    if not ok_mm or type(module_mission) ~= 'table' then
        return { ok = false, error = 'me_mission unavailable' }
    end
    if type(module_mission.save_mission_safe) ~= 'function' then
        return { ok = false, error = 'me_mission.save_mission_safe unavailable' }
    end
    local noLoad = not reopen
    local ok_call, ok_or_err = pcall(module_mission.save_mission_safe, args.path, false, noLoad)
    if not ok_call then
        return { ok = false,
                 error = 'save_mission_safe: ' .. tostring(ok_or_err)
                         .. ' (file written; post-save reload crashed — try --reopen=false)' }
    end
    if ok_or_err ~= true then
        return { ok = false, error = 'save failed (mission validation or I/O); enable showError to see details' }
    end
    -- Always sync MeSettings (the DCS user-flow does this in me_toolbar; load() doesn't).
    local ok_ms, MeSettings = pcall(require, 'MeSettings')
    if ok_ms and type(MeSettings) == 'table' and type(MeSettings.setMissionPath) == 'function' then
        pcall(MeSettings.setMissionPath, args.path)
    end
    if noLoad then
        -- load() would have set these for us; in the no-reload path do it manually.
        if module_mission.mission then module_mission.mission.path = args.path end
        refresh_menubar_title(args.path)
    end
    return { ok = true, path = args.path, reopen = reopen }
end

-- ============================================================
-- Group lifecycle verbs (private helpers + public verbs)
-- ============================================================

-- find_group_in_mission — walk the coalition tree and return the first group
-- matching either an exact name or a numeric groupId. Returns (group, country,
-- side, category) or nil. Walks all 5 categories (plane / helicopter /
-- vehicle / ship / static) across all 3 sides.
local function find_group_in_mission(by_name, by_id)
    local module_mission = require('me_mission')
    local mission = module_mission.mission
    if type(mission) ~= 'table' or type(mission.coalition) ~= 'table' then
        return nil, nil, nil, nil
    end
    local cats = { 'plane', 'helicopter', 'vehicle', 'ship', 'static' }
    for side_name, side in pairs(mission.coalition) do
        if type(side) == 'table' and type(side.country) == 'table' then
            for _, country in ipairs(side.country) do
                for _, cat in ipairs(cats) do
                    if country[cat] and type(country[cat].group) == 'table' then
                        for _, g in ipairs(country[cat].group) do
                            if (by_name and g.name == by_name)
                                    or (by_id and g.groupId == by_id) then
                                return g, country, side_name, cat
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil, nil
end

-- find_country_by_name — case-insensitive country lookup in the mission's
-- coalition tree. Returns (country_table, side_name) or nil.
local function find_country_by_name(name)
    local module_mission = require('me_mission')
    local mission = module_mission.mission
    if type(mission) ~= 'table' or type(mission.coalition) ~= 'table' then
        return nil, nil
    end
    local target = string.lower(name)
    for side_name, side in pairs(mission.coalition) do
        if type(side) == 'table' and type(side.country) == 'table' then
            for _, country in ipairs(side.country) do
                if type(country.name) == 'string' and string.lower(country.name) == target then
                    return country, side_name
                end
            end
        end
    end
    return nil, nil
end

-- inject_group — the canonical 11-step group injection sequence documented in
-- research/me-bridge-discovery-2026-05-08.md ("inject a single group
-- ME-perfect"). Takes a fully-built group table `g`, the target country
-- table, and the group_type string ('plane' / 'helicopter' / 'vehicle' /
-- 'ship' / 'static'). Mutates `g` and the mission tables in-place.
--
-- Returns g, nil on success; nil, error_string on failure.
--
-- This is shared between group_create_* verbs. Keeping it private (M.* not
-- exported) avoids leaking the injection sequence as public surface — callers
-- should go through group_create_<category> verbs which build the right
-- defaults and validate inputs.
local function inject_group(g, country, group_type)
    local Mission = require('me_mission')
    g.type = group_type
    g.groupId = Mission.getNewGroupId()

    -- Reserve collision-safe group name (allocates a new name only if needed).
    if type(Mission.check_group_name) == 'function' then
        local ok, n = pcall(Mission.check_group_name, g.name)
        if ok and type(n) == 'string' and n ~= '' then g.name = n end
    end

    -- Lookup table registration BEFORE create_group_objects (Selection / Unit
    -- List / panel updates all read these).
    if type(Mission.group_by_name) == 'table' then Mission.group_by_name[g.name] = g end
    if type(Mission.group_by_id) == 'table' then Mission.group_by_id[g.groupId] = g end

    -- Boss back-references + map-objects scaffold + color.
    g.boss = country
    g.mapObjects = { units = {}, zones = {}, route = {} }
    if type(Mission.countryCoalition) == 'table'
            and Mission.countryCoalition[country.name]
            and Mission.countryCoalition[country.name].color then
        g.color = Mission.countryCoalition[country.name].color
    end

    -- Defensive country.boss = side. me_units_list.applyFilter does
    -- group.boss.boss.name; nil there crashes the Unit List window.
    if not country.boss then
        local mission = Mission.mission or {}
        for side_name, side in pairs(mission.coalition or {}) do
            if type(side) == 'table' and type(side.country) == 'table' then
                for _, c in ipairs(side.country) do
                    if c == country then country.boss = side; break end
                end
            end
            if country.boss then break end
        end
    end

    -- Per-unit work — id → name → register → boss — must be ONE loop
    -- (getUnitName reads unit_by_name to find a free slot, so prior units
    -- must be registered before the next call).
    for _, u in ipairs(g.units) do
        u.unitId = Mission.getNewUnitId()
        if type(Mission.getUnitName) == 'function' then
            local ok, nm = pcall(Mission.getUnitName, g.name)
            if ok and type(nm) == 'string' and nm ~= '' then u.name = nm end
        end
        if type(Mission.unit_by_name) == 'table' then Mission.unit_by_name[u.name] = u end
        if type(Mission.unit_by_id) == 'table' then Mission.unit_by_id[u.unitId] = u end
        u.boss = g
    end

    -- Waypoint boss back-references.
    if g.route and type(g.route.points) == 'table' then
        for _, wpt in ipairs(g.route.points) do wpt.boss = g end
    end

    -- Canonical insertion order — do not deviate.
    local ok_cgo, cgo_err = pcall(Mission.create_group_objects, g)
    if not ok_cgo then return nil, 'create_group_objects: ' .. tostring(cgo_err) end
    if type(country[group_type]) ~= 'table' then
        country[group_type] = { name = group_type, group = {} }
    end
    table.insert(country[group_type].group, g)
    local ok_cgmo, cgmo_err = pcall(Mission.create_group_map_objects, g)
    if not ok_cgmo then return g, 'create_group_map_objects: ' .. tostring(cgmo_err) end

    -- fixAddPropAircraft fills airframe-specific defaults (F-16's
    -- STN_L16/HMD/etc). fixWaypointForGroup is MANDATORY for save survival —
    -- without it, ED's save path writes nil/nil to wpt.type.type/.action and
    -- the post-save reload crashes at me_route.lua:2413, hanging DCS and
    -- corrupting the .miz.
    pcall(Mission.fixAddPropAircraft)
    pcall(Mission.fixWaypointForGroup, g)

    return g, nil
end

-- group_remove — remove a group from the mission by name or id.
--
-- args: { name = "<group name>" } OR { id = <groupId> }. Exactly one
-- required. Returns { ok = true, name = ..., id = ..., category = ... } on
-- success or { ok = false, error = "..." } on failure.
function M.group_remove(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_remove requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then  -- both or neither
        return { ok = false, error = 'group_remove requires exactly one of args.name (string) or args.id (number)' }
    end

    local g, country, side_name, cat = find_group_in_mission(has_name and args.name or nil,
                                                              has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end

    local resolved = { name = g.name, id = g.groupId, category = cat,
                       country = country and country.name, side = side_name }

    local Mission = require('me_mission')
    -- Disk-loaded groups have mapObjects = nil until the user selects them
    -- (the ME populates it lazily). Mission.remove_group → remove_group_map_objects
    -- (me_mission.lua:7881) iterates group.mapObjects.units and crashes on nil.
    -- create_group_map_objects builds the proper structure; if it fails for
    -- any reason, fall back to a minimal stub so the remove iteration is empty.
    if g.mapObjects == nil and type(Mission.create_group_map_objects) == 'function' then
        pcall(Mission.create_group_map_objects, g)
    end
    if g.mapObjects == nil or type(g.mapObjects.units) ~= 'table' then
        g.mapObjects = g.mapObjects or {}
        g.mapObjects.units = g.mapObjects.units or {}
        g.mapObjects.zones = g.mapObjects.zones or {}
    end

    local ok_call, err = pcall(Mission.remove_group, g)
    if not ok_call then
        return { ok = false, error = 'remove_group: ' .. tostring(err), resolved = resolved }
    end

    return { ok = true, name = resolved.name, id = resolved.id,
             category = resolved.category, country = resolved.country,
             side = resolved.side }
end

-- group_create_plane — synthesize and inject a single-unit fixed-wing
-- aircraft group, single waypoint at the spawn point with an empty ComboTask.
-- Survives save (runs fixWaypointForGroup), is fully selectable in the ME,
-- and runs in mission.
--
-- args (required):
--   country: string  -- e.g. "USA", "Russia". Must already exist in the
--                       mission's coalition tree (file_new sets defaults).
--   type:    string  -- airframe id, e.g. "F-16C_50", "Su-27"
--   north:   number  -- meters north of theatre origin (north positive)
--   east:    number  -- meters east  of theatre origin (east  positive)
--                       See top-of-file comment for why we use north/east
--                       instead of DCS's contradictory x/y/z naming.
--
-- args (optional, with defaults):
--   name:        group name (auto-allocated if nil/empty via check_group_name)
--   alt:         8000 (meters above sea level)
--   alt_type:    'BARO'
--   speed:       220 (m/s ~ 428 kts)
--   heading:     0 (radians)
--   skill:       'Average'
--   livery:      ''
--   frequency:   251 (MHz)
--   onboard_num: '010'
--
-- Returns { ok = true, groupId, name, unitId, unitName } on success.
function M.group_create_plane(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_create_plane requires args (table)' }
    end
    if type(args.country) ~= 'string' or args.country == '' then
        return { ok = false, error = 'group_create_plane requires args.country (string)' }
    end
    if type(args.type) ~= 'string' or args.type == '' then
        return { ok = false, error = 'group_create_plane requires args.type (string, airframe id)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'group_create_plane requires args.north and args.east (numbers, meters)' }
    end

    local country, side_name = find_country_by_name(args.country)
    if not country then
        return { ok = false,
                 error = 'country "' .. args.country .. '" not in mission coalition tree; '
                         .. 'use a country active on this mission (file_new sets defaults)' }
    end

    -- Translate semantic --north / --east to mission-table fields:
    -- the .miz format stores the ground plane as (x = N–S, y = E–W).
    local x, y = args.north, args.east
    local alt = args.alt or 8000
    local alt_type = args.alt_type or 'BARO'
    local speed = args.speed or 220
    local heading = args.heading or 0
    local skill = args.skill or 'Average'
    local livery = args.livery or ''
    local frequency = args.frequency or 251
    local onboard_num = args.onboard_num or '010'

    local group_name = (type(args.name) == 'string' and args.name ~= '') and args.name
                       or (args.type .. ' #001')

    local g = {
        name = group_name,
        x = x, y = y,
        task = 'Nothing',
        hidden = false,
        hiddenOnPlanner = false,
        hiddenOnMFD = {},
        modulation = 0,
        frequency = frequency,
        uncontrolled = false,
        start_time = 0,
        units = {
            {
                name = group_name .. '-1',  -- placeholder; getUnitName replaces
                type = args.type,
                x = x, y = y,
                alt = alt, alt_type = alt_type,
                speed = speed,
                heading = heading,
                psi = 0,
                skill = skill,
                livery_id = livery,
                onboard_num = onboard_num,
                callsign = { 1, 1, 1, name = 'Enfield11' },
                payload = {
                    pylons = {},
                    fuel = '9999',
                    flare = 0,
                    chaff = 0,
                    gun = 100,
                },
                AddPropAircraft = nil,  -- fixAddPropAircraft fills this
            },
        },
        route = {
            points = {
                {
                    x = x, y = y,
                    alt = alt, alt_type = alt_type,
                    speed = speed,
                    action = 'Turning Point',
                    type = 'Turning Point',
                    ETA = 0, ETA_locked = true,
                    formation_template = '',
                    task = { id = 'ComboTask', params = { tasks = {} } },
                },
            },
            routeRelativeTOT = false,
        },
    }

    local injected, err = inject_group(g, country, 'plane')
    if not injected then
        return { ok = false, error = err or 'inject_group failed' }
    end

    return {
        ok = true,
        groupId = injected.groupId,
        name = injected.name,
        unitId = injected.units[1].unitId,
        unitName = injected.units[1].name,
        country = country.name,
        side = side_name,
    }
end

-- group_create_helicopter — single-unit rotary-wing group with the same
-- shape as create_plane but a helo-typical default profile (lower alt,
-- slower speed). Single waypoint at the spawn point with an empty ComboTask,
-- save-survives via fixWaypointForGroup.
--
-- args (required): country, type, north, east
-- args (optional): name, alt (default 1000), alt_type (BARO), speed (50),
--                  heading (radians, 0), skill (Average), livery (''),
--                  frequency (127.5), onboard_num ('010')
function M.group_create_helicopter(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_create_helicopter requires args (table)' }
    end
    if type(args.country) ~= 'string' or args.country == '' then
        return { ok = false, error = 'group_create_helicopter requires args.country (string)' }
    end
    if type(args.type) ~= 'string' or args.type == '' then
        return { ok = false, error = 'group_create_helicopter requires args.type (string, airframe id)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'group_create_helicopter requires args.north and args.east (numbers, meters)' }
    end

    local country, side_name = find_country_by_name(args.country)
    if not country then
        return { ok = false,
                 error = 'country "' .. args.country .. '" not in mission coalition tree' }
    end

    local x, y = args.north, args.east
    local alt = args.alt or 1000
    local alt_type = args.alt_type or 'BARO'
    local speed = args.speed or 50
    local heading = args.heading or 0
    local skill = args.skill or 'Average'
    local livery = args.livery or ''
    local frequency = args.frequency or 127.5
    local onboard_num = args.onboard_num or '010'

    local group_name = (type(args.name) == 'string' and args.name ~= '') and args.name
                       or (args.type .. ' #001')

    local g = {
        name = group_name,
        x = x, y = y,
        task = 'Transport',
        hidden = false,
        hiddenOnPlanner = false,
        hiddenOnMFD = {},
        modulation = 0,
        frequency = frequency,
        uncontrolled = false,
        start_time = 0,
        units = {
            {
                name = group_name .. '-1',
                type = args.type,
                x = x, y = y,
                alt = alt, alt_type = alt_type,
                speed = speed,
                heading = heading,
                psi = 0,
                skill = skill,
                livery_id = livery,
                onboard_num = onboard_num,
                callsign = { 1, 1, 1, name = 'Enfield11' },
                payload = {
                    pylons = {},
                    fuel = '1100',
                    flare = 0,
                    chaff = 0,
                    gun = 100,
                },
                AddPropAircraft = nil,
            },
        },
        route = {
            points = {
                {
                    x = x, y = y,
                    alt = alt, alt_type = alt_type,
                    speed = speed,
                    action = 'Turning Point',
                    type = 'Turning Point',
                    ETA = 0, ETA_locked = true,
                    formation_template = '',
                    task = { id = 'ComboTask', params = { tasks = {} } },
                },
            },
            routeRelativeTOT = false,
        },
    }

    local injected, err = inject_group(g, country, 'helicopter')
    if not injected then
        return { ok = false, error = err or 'inject_group failed' }
    end

    return {
        ok = true,
        groupId = injected.groupId,
        name = injected.name,
        unitId = injected.units[1].unitId,
        unitName = injected.units[1].name,
        country = country.name,
        side = side_name,
    }
end

-- group_create_vehicle — single-unit ground-vehicle group, stationary
-- (Off Road action, speed=0, speed_locked). No alt / alt_type / payload —
-- those are aircraft-only fields.
--
-- args (required): country, type, north, east
-- args (optional): name, heading (radians, 0), skill (Average)
function M.group_create_vehicle(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_create_vehicle requires args (table)' }
    end
    if type(args.country) ~= 'string' or args.country == '' then
        return { ok = false, error = 'group_create_vehicle requires args.country (string)' }
    end
    if type(args.type) ~= 'string' or args.type == '' then
        return { ok = false, error = 'group_create_vehicle requires args.type (string, vehicle id)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'group_create_vehicle requires args.north and args.east (numbers, meters)' }
    end

    local country, side_name = find_country_by_name(args.country)
    if not country then
        return { ok = false,
                 error = 'country "' .. args.country .. '" not in mission coalition tree' }
    end

    local x, y = args.north, args.east
    local heading = args.heading or 0
    local skill = args.skill or 'Average'

    local group_name = (type(args.name) == 'string' and args.name ~= '') and args.name
                       or (args.type .. ' #001')

    local g = {
        name = group_name,
        x = x, y = y,
        task = 'Ground Nothing',
        hidden = false,
        hiddenOnPlanner = false,
        hiddenOnMFD = {},
        modulation = 0,
        frequency = 0,
        uncontrolled = false,
        start_time = 0,
        units = {
            {
                name = group_name .. '-1',
                type = args.type,
                x = x, y = y,
                heading = heading,
                playerCanDrive = false,
                skill = skill,
            },
        },
        route = {
            points = {
                {
                    x = x, y = y,
                    alt = 0, alt_type = 'BARO',
                    speed = 0, speed_locked = true,
                    action = 'Off Road',
                    type = 'Turning Point',
                    ETA = 0, ETA_locked = true,
                    formation_template = '',
                    task = { id = 'ComboTask', params = { tasks = {} } },
                },
            },
            routeRelativeTOT = false,
        },
    }

    local injected, err = inject_group(g, country, 'vehicle')
    if not injected then
        return { ok = false, error = err or 'inject_group failed' }
    end

    return {
        ok = true,
        groupId = injected.groupId,
        name = injected.name,
        unitId = injected.units[1].unitId,
        unitName = injected.units[1].name,
        country = country.name,
        side = side_name,
    }
end

-- group_create_ship — single-unit naval-vessel group. Same shape as vehicle
-- (stationary, ground-style waypoint), but the position MUST be over water
-- — we check terrain.GetSurfaceType to fail fast rather than letting the
-- ship spawn on a beach and look broken.
--
-- args (required): country, type, north, east
-- args (optional): name, heading (radians, 0), skill (Average)
function M.group_create_ship(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_create_ship requires args (table)' }
    end
    if type(args.country) ~= 'string' or args.country == '' then
        return { ok = false, error = 'group_create_ship requires args.country (string)' }
    end
    if type(args.type) ~= 'string' or args.type == '' then
        return { ok = false, error = 'group_create_ship requires args.type (string, ship id)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'group_create_ship requires args.north and args.east (numbers, meters)' }
    end

    local country, side_name = find_country_by_name(args.country)
    if not country then
        return { ok = false,
                 error = 'country "' .. args.country .. '" not in mission coalition tree' }
    end

    -- Water-surface check. terrain.GetSurfaceType uses mission-table coords
    -- (x = N–S, y = E–W). Returns lowercase strings; sea-ish responses are
    -- 'sea' / 'shallow_water'. force=true skips the check (escape hatch).
    if args.force ~= true then
        local ok_terr, terrain = pcall(require, 'terrain')
        if ok_terr and type(terrain) == 'table' and type(terrain.GetSurfaceType) == 'function' then
            local surf = terrain.GetSurfaceType(args.north, args.east)
            if surf ~= 'sea' and surf ~= 'shallow_water' then
                return { ok = false,
                         error = 'ship spawn at (' .. args.north .. ', ' .. args.east .. ') is over '
                                 .. tostring(surf) .. ', not water; pass force=true to override' }
            end
        end
    end

    local x, y = args.north, args.east
    local heading = args.heading or 0
    local skill = args.skill or 'Average'

    local group_name = (type(args.name) == 'string' and args.name ~= '') and args.name
                       or (args.type .. ' #001')

    local g = {
        name = group_name,
        x = x, y = y,
        task = 'CAP',
        hidden = false,
        hiddenOnPlanner = false,
        hiddenOnMFD = {},
        modulation = 0,
        frequency = 0,
        uncontrolled = false,
        start_time = 0,
        units = {
            {
                name = group_name .. '-1',
                type = args.type,
                x = x, y = y,
                heading = heading,
                skill = skill,
                modulation = 0,
                transportable = { randomTransportable = false },
            },
        },
        route = {
            points = {
                {
                    x = x, y = y,
                    alt = 0, alt_type = 'BARO',
                    -- Ship waypoints need `depth` (positive metres). Save's
                    -- unload_ship_groups computes `pt.alt = -s.depth`
                    -- (me_mission.lua:4239) and crashes on nil here.
                    depth = 0,
                    speed = 0, speed_locked = true,
                    action = 'Turning Point',
                    type = 'Turning Point',
                    ETA = 0, ETA_locked = true,
                    formation_template = '',
                    task = { id = 'ComboTask', params = { tasks = {} } },
                },
            },
            routeRelativeTOT = false,
        },
    }

    local injected, err = inject_group(g, country, 'ship')
    if not injected then
        return { ok = false, error = err or 'inject_group failed' }
    end

    return {
        ok = true,
        groupId = injected.groupId,
        name = injected.name,
        unitId = injected.units[1].unitId,
        unitName = injected.units[1].name,
        country = country.name,
        side = side_name,
    }
end

-- group_create_static — static-object group. Statics are different:
-- one "unit" representing the object, no waypoints / route, no AI behavior.
-- They're stored under country.static.group same as vehicles, but shape is
-- minimal — a single position, heading, dead flag, category, shape_name.
--
-- args (required): country, type, north, east
-- args (optional): name, heading (radians, 0), category (Cargos / Fortifications
--                  / Warehouses / etc.), shape_name (model id), dead (false),
--                  can_cargo (false), mass (0)
function M.group_create_static(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_create_static requires args (table)' }
    end
    if type(args.country) ~= 'string' or args.country == '' then
        return { ok = false, error = 'group_create_static requires args.country (string)' }
    end
    if type(args.type) ~= 'string' or args.type == '' then
        return { ok = false, error = 'group_create_static requires args.type (string, static id)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'group_create_static requires args.north and args.east (numbers, meters)' }
    end

    local country, side_name = find_country_by_name(args.country)
    if not country then
        return { ok = false,
                 error = 'country "' .. args.country .. '" not in mission coalition tree' }
    end

    local x, y = args.north, args.east
    local heading = args.heading or 0
    local category = args.category or 'Fortifications'
    local shape_name = args.shape_name or ''
    local dead = (args.dead == true)
    local can_cargo = (args.can_cargo == true)
    local mass = args.mass or 0

    local group_name = (type(args.name) == 'string' and args.name ~= '') and args.name
                       or (args.type .. ' #001')

    -- Static groups still have a route (single point) so the canonical
    -- inject_group sequence's fixWaypointForGroup is happy.
    local g = {
        name = group_name,
        x = x, y = y,
        hidden = false,
        dead = dead,
        heading = heading,
        units = {
            {
                name = group_name,  -- statics use the group name as unit name
                type = args.type,
                x = x, y = y,
                heading = heading,
                category = category,
                shape_name = shape_name,
                rate = 100,
                canCargo = can_cargo,
                mass = mass,
                dead = dead,
            },
        },
        route = {
            points = {
                {
                    x = x, y = y,
                    action = 'Off Road',
                    type = 'Turning Point',
                    ETA = 0, ETA_locked = true,
                    formation_template = '',
                    speed = 0, speed_locked = true,
                    task = { id = 'ComboTask', params = { tasks = {} } },
                },
            },
            routeRelativeTOT = false,
        },
    }

    local injected, err = inject_group(g, country, 'static')
    if not injected then
        return { ok = false, error = err or 'inject_group failed' }
    end

    return {
        ok = true,
        groupId = injected.groupId,
        name = injected.name,
        unitId = injected.units[1].unitId,
        unitName = injected.units[1].name,
        country = country.name,
        side = side_name,
    }
end

-- group_add_unit — add a unit to an existing group, copying defaults from
-- the group's last unit (matching the ME's own "+" button behaviour).
--
-- Position semantics:
--   * --offset-north / --offset-east (either or both) → unit at
--     (g.x + offset_north, g.y + offset_east) — relative to the group
--     anchor, NOT cumulative across calls.
--   * Neither passed → let Mission.insert_unit apply its built-in index-
--     cumulative spread (40m south / 40m east per added unit), which is
--     what the ME does when you click + with nothing selected.
--
-- Type rule for air groups: plane / helicopter groups can't be
-- heterogeneous (no F-16 + F-14 in one group — DCS doesn't permit it).
-- We refuse if --type is given and differs from g.units[1].type, and
-- default to g.units[1].type when --type is omitted. Vehicle / ship /
-- static groups allow mixed types (Hawk SAM site = PCP + SR + TR + LN).
--
-- Field defaults: skill / livery / heading / alt / alt_type / payload
-- copy from the LAST unit in the group, so adding a unit to a 4-ship
-- F-16 flight with one weapon load keeps the same load on #5. Any field
-- can be overridden via the matching arg.
--
-- args (required):
--   name | id   group selector (mutually exclusive)
--
-- args (optional):
--   type           string  (auto-fill from last/first unit if absent)
--   offset_north   number  (meters; nil → insert_unit default spread)
--   offset_east    number  (meters; nil → insert_unit default spread)
--   skill / livery / heading_deg / alt / alt_type
--   onboard_num / callsign / frequency  (set after insert_unit)
function M.group_add_unit(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_add_unit requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_add_unit requires exactly one of args.name or args.id' }
    end

    local g, country, side_name, cat = find_group_in_mission(
        has_name and args.name or nil, has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    if type(g.units) ~= 'table' or #g.units == 0 then
        return { ok = false, error = 'group has no existing units to derive defaults from' }
    end

    local first_unit = g.units[1]
    local last_unit = g.units[#g.units]

    -- Type resolution + air-group homogeneity check.
    local utype = (type(args.type) == 'string' and args.type ~= '') and args.type or last_unit.type
    if (cat == 'plane' or cat == 'helicopter') and utype ~= first_unit.type then
        return { ok = false,
                 error = cat .. ' groups can only contain one airframe; existing="'
                         .. tostring(first_unit.type) .. '", requested="' .. utype .. '"' }
    end

    -- Field defaults — explicit args win, otherwise inherit from last unit.
    local skill = (type(args.skill) == 'string' and args.skill ~= '') and args.skill
                  or last_unit.skill or 'Average'
    local livery = (type(args.livery) == 'string') and args.livery
                   or last_unit.livery_id or ''
    local heading_rad
    if type(args.heading_deg) == 'number' then
        heading_rad = math.rad(args.heading_deg)
    else
        heading_rad = last_unit.heading or 0
    end

    -- Position. Pass nil for x/y to Mission.insert_unit when no offset
    -- supplied — it then applies its index-cumulative 40m spread.
    local x, y
    if type(args.offset_north) == 'number' or type(args.offset_east) == 'number' then
        x = g.x + (args.offset_north or 0)
        y = g.y + (args.offset_east or 0)
    end

    local Mission = require('me_mission')

    -- check_unit_name (called inside insert_unit) crashes on a nil seed —
    -- it does string.reverse(seed) to find a base for suffix-uniquify.
    -- Use the LAST unit's name as the seed: it already has the
    -- "<group>-N" shape so check_unit_name picks the next free index
    -- cleanly (CAP4-1 → CAP4-2 → CAP4-3 …). Using g.name as the seed
    -- gives back g.name itself for the first add (group names live in
    -- group_by_name, unit names in unit_by_name — no collision).
    local index = #g.units + 1
    local ok_call, u_or_err = pcall(Mission.insert_unit,
        g, utype, skill, index, last_unit.name, x, y, heading_rad, nil, livery)
    if not ok_call then
        return { ok = false, error = 'insert_unit: ' .. tostring(u_or_err) }
    end
    local u = u_or_err
    if type(u) ~= 'table' then
        return { ok = false, error = 'insert_unit returned no unit table' }
    end

    -- Air-only fields. insert_unit doesn't set u.alt — copy from the last
    -- unit (or use --alt). Same for alt_type. Payload defaults from
    -- unitDef inside insert_unit; we override with last-unit's payload
    -- so #5 in a flight inherits the loadout (deep copy to avoid shared
    -- mutation). Allow explicit args.payload to skip the copy.
    if cat == 'plane' or cat == 'helicopter' then
        u.alt = (type(args.alt) == 'number') and args.alt or last_unit.alt
        u.alt_type = (type(args.alt_type) == 'string' and args.alt_type ~= '')
                     and args.alt_type or last_unit.alt_type or 'BARO'
        if last_unit.payload and not args.payload then
            local copy = {}
            for k, v in pairs(last_unit.payload) do
                if k == 'pylons' and type(v) == 'table' then
                    copy.pylons = {}
                    for pk, pv in pairs(v) do copy.pylons[pk] = pv end
                else
                    copy[k] = v
                end
            end
            u.payload = copy
        end
    end

    -- Optional explicit overrides for fields the user might want to set
    -- right at add-time without a follow-up `unit set-*` call.
    if type(args.onboard_num) == 'string' and args.onboard_num ~= '' then
        u.onboard_num = args.onboard_num
    end
    if type(args.callsign) == 'string' and args.callsign ~= '' then
        local existing = (type(u.callsign) == 'table') and u.callsign or {}
        local sq = (type(existing[1]) == 'number' and existing[1]) or 1
        local fl = (type(existing[2]) == 'number' and existing[2]) or 1
        local pl = (type(existing[3]) == 'number' and existing[3]) or 1
        u.callsign = { sq, fl, pl, name = args.callsign }
    end
    if type(args.frequency) == 'number' and args.frequency > 0 then
        u.frequency = args.frequency
    end

    -- Refresh visuals — insert_unit_symbol drew the sprite, but the rest
    -- of the group (e.g. existing units' positions if anything cares) is
    -- safe-to-update via the standard helper.
    refresh_group_view(g)

    return {
        ok = true,
        groupId = g.groupId,
        group = g.name,
        category = cat,
        country = country and country.name,
        side = side_name,
        unitId = u.unitId,
        unitName = u.name,
        type = u.type,
        north = u.x,
        east = u.y,
        unit_count = #g.units,
    }
end

-- ============================================================
-- Group setters (per-field)
-- ============================================================
--
-- Note: set-country isn't here yet. Moving a group between coalition
-- branches needs custom remove + reinsert + boss/color refresh — there's no
-- Mission.* helper for it. Workaround until we ship one: capture state with
-- group_get, group_remove, then group_create_<cat> with the new country.

-- group_set_name — rename a group via Mission.renameGroup. Refuses on name
-- collision (returns false from renameGroup) — does NOT silently uniquify.
function M.group_set_name(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_set_name requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_set_name requires exactly one of args.name or args.id' }
    end
    if type(args.new_name) ~= 'string' or args.new_name == '' then
        return { ok = false, error = 'group_set_name requires args.new_name (non-empty string)' }
    end
    local g = find_group_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    local Mission = require('me_mission')
    local ok = Mission.renameGroup(g, args.new_name)
    if not ok then
        return { ok = false, error = 'name "' .. args.new_name .. '" already in use' }
    end
    return { ok = true, id = g.groupId, name = args.new_name }
end

-- group_set_task — set the group-level task field (g.task). Doesn't touch
-- per-waypoint ComboTasks. Strings the ME accepts include CAP, CAS, Escort,
-- Nothing, etc. — no validation here, the ME stores the value verbatim.
function M.group_set_task(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_set_task requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_set_task requires exactly one of args.name or args.id' }
    end
    if type(args.task) ~= 'string' or args.task == '' then
        return { ok = false, error = 'group_set_task requires args.task (non-empty string)' }
    end
    local g = find_group_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    g.task = args.task
    return { ok = true, id = g.groupId, name = g.name, task = g.task }
end

-- group_set_hidden — toggle g.hidden. Requires explicit args.hidden bool.
function M.group_set_hidden(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_set_hidden requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_set_hidden requires exactly one of args.name or args.id' }
    end
    if type(args.hidden) ~= 'boolean' then
        return { ok = false, error = 'group_set_hidden requires args.hidden (boolean)' }
    end
    local g = find_group_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    g.hidden = args.hidden
    return { ok = true, id = g.groupId, name = g.name, hidden = g.hidden }
end

-- group_set_frequency — set g.frequency in MHz.
function M.group_set_frequency(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_set_frequency requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_set_frequency requires exactly one of args.name or args.id' }
    end
    if type(args.frequency) ~= 'number' or args.frequency <= 0 then
        return { ok = false, error = 'group_set_frequency requires args.frequency (positive number, MHz)' }
    end
    local g = find_group_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    g.frequency = args.frequency
    return { ok = true, id = g.groupId, name = g.name, frequency = g.frequency }
end

-- group_set_pos — translate the entire group to a new center.
--
-- Computes delta = (north - g.x, east - g.y) and applies it to g, every
-- unit, and every waypoint. Preserves intra-group offsets (formations,
-- SAM-site geometry).
--
-- Refreshes Mission.update_group_map_objects so the ME view reflects the
-- new positions immediately (without it the sprites would lag the data
-- until the user clicked the group).
function M.group_set_pos(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_set_pos requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_set_pos requires exactly one of args.name or args.id' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'group_set_pos requires args.north and args.east (numbers, meters)' }
    end
    local g = find_group_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end

    -- mission-table fields: x = north, y = east
    local dx = args.north - (g.x or 0)
    local dy = args.east - (g.y or 0)

    g.x = args.north
    g.y = args.east

    for _, u in ipairs(g.units or {}) do
        u.x = (u.x or 0) + dx
        u.y = (u.y or 0) + dy
    end
    if g.route and type(g.route.points) == 'table' then
        for _, wpt in ipairs(g.route.points) do
            wpt.x = (wpt.x or 0) + dx
            wpt.y = (wpt.y or 0) + dy
        end
    end

    -- Refresh visual state so the ME view tracks the data move. Build map
    -- objects first if they're nil (disk-loaded groups have mapObjects=nil
    -- until selected; same defensive pattern as group_remove).
    local Mission = require('me_mission')
    if g.mapObjects == nil and type(Mission.create_group_map_objects) == 'function' then
        pcall(Mission.create_group_map_objects, g)
    end
    if type(Mission.update_group_map_objects) == 'function' then
        pcall(Mission.update_group_map_objects, g)
    end

    return { ok = true, id = g.groupId, name = g.name,
             north = g.x, east = g.y, delta = { north = dx, east = dy } }
end

-- ============================================================
-- Unit setters (per-field)
-- ============================================================

-- find_unit_in_mission — locate a unit by name or id, returning
-- (unit, group, country, side, category) or nil. Mirrors find_group_in_mission
-- but walks down to unit level. Shared by all unit_set_* verbs.
local function find_unit_in_mission(by_name, by_id)
    local found_unit, found_group, found_country, found_side, found_cat
    walk_groups(function(g, country, side_name, cat)
        for _, u in ipairs(g.units or {}) do
            if (by_name and u.name == by_name) or (by_id and u.unitId == by_id) then
                found_unit, found_group, found_country = u, g, country
                found_side, found_cat = side_name, cat
                return false
            end
        end
    end)
    return found_unit, found_group, found_country, found_side, found_cat
end

-- unit_set_name — rename via Mission.renameUnit. Refuses on collision.
function M.unit_set_name(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_name requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_name requires exactly one of args.name or args.id' }
    end
    if type(args.new_name) ~= 'string' or args.new_name == '' then
        return { ok = false, error = 'unit_set_name requires args.new_name (non-empty string)' }
    end
    local u = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    local Mission = require('me_mission')
    local ok = Mission.renameUnit(u, args.new_name)
    if not ok then
        return { ok = false, error = 'name "' .. args.new_name .. '" already in use' }
    end
    return { ok = true, id = u.unitId, name = args.new_name }
end

-- unit_set_skill — set u.skill (Average / Good / High / Excellent / Random / Player / Client).
function M.unit_set_skill(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_skill requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_skill requires exactly one of args.name or args.id' }
    end
    if type(args.skill) ~= 'string' or args.skill == '' then
        return { ok = false, error = 'unit_set_skill requires args.skill (non-empty string)' }
    end
    local u = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    u.skill = args.skill
    return { ok = true, id = u.unitId, name = u.name, skill = u.skill }
end

-- unit_set_livery — set u.livery_id (string, airframe-specific).
function M.unit_set_livery(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_livery requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_livery requires exactly one of args.name or args.id' }
    end
    if type(args.livery) ~= 'string' then
        return { ok = false, error = 'unit_set_livery requires args.livery (string; "" for default)' }
    end
    local u = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    u.livery_id = args.livery
    return { ok = true, id = u.unitId, name = u.name, livery = u.livery_id }
end

-- unit_set_pos — move a single unit to (north, east). Refreshes the group's
-- map objects so the ME view updates immediately.
function M.unit_set_pos(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_pos requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_pos requires exactly one of args.name or args.id' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'unit_set_pos requires args.north and args.east (numbers, meters)' }
    end
    local u, g = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    -- mission-table fields: x = north, y = east
    u.x = args.north
    u.y = args.east
    refresh_group_view(g)
    return { ok = true, id = u.unitId, name = u.name, north = u.x, east = u.y }
end

-- unit_set_heading — set u.heading and u.psi from a degrees input.
-- DCS stores radians internally, with 0 = north and clockwise = positive.
function M.unit_set_heading(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_heading requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_heading requires exactly one of args.name or args.id' }
    end
    if type(args.heading_deg) ~= 'number' then
        return { ok = false, error = 'unit_set_heading requires args.heading_deg (degrees)' }
    end
    local u, g = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    local rad = math.rad(args.heading_deg)
    u.heading = rad
    u.psi = rad
    refresh_group_view(g)
    return { ok = true, id = u.unitId, name = u.name,
             heading_deg = args.heading_deg, heading_rad = rad }
end

-- unit_set_alt — set u.alt and u.alt_type. Doesn't touch waypoint altitudes.
function M.unit_set_alt(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_alt requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_alt requires exactly one of args.name or args.id' }
    end
    if type(args.alt) ~= 'number' then
        return { ok = false, error = 'unit_set_alt requires args.alt (number, meters)' }
    end
    local alt_type = args.alt_type or 'BARO'
    if alt_type ~= 'BARO' and alt_type ~= 'RADIO' then
        return { ok = false, error = 'unit_set_alt: args.alt_type must be "BARO" or "RADIO"' }
    end
    local u = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    u.alt = args.alt
    u.alt_type = alt_type
    return { ok = true, id = u.unitId, name = u.name, alt = u.alt, alt_type = u.alt_type }
end

-- unit_set_onboard_num — set u.onboard_num.
function M.unit_set_onboard_num(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_onboard_num requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_onboard_num requires exactly one of args.name or args.id' }
    end
    if type(args.onboard_num) ~= 'string' or args.onboard_num == '' then
        return { ok = false, error = 'unit_set_onboard_num requires args.onboard_num (non-empty string)' }
    end
    local u = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    u.onboard_num = args.onboard_num
    return { ok = true, id = u.unitId, name = u.name, onboard_num = u.onboard_num }
end

-- unit_set_callsign — set u.callsign. Mandatory args.callsign (string, the
-- radio label); optional args.squadron / flight / plane integers — when 0
-- (default), preserve the existing numeric prefix value.
function M.unit_set_callsign(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_set_callsign requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_set_callsign requires exactly one of args.name or args.id' }
    end
    if type(args.callsign) ~= 'string' or args.callsign == '' then
        return { ok = false, error = 'unit_set_callsign requires args.callsign (non-empty string)' }
    end
    local u = find_unit_in_mission(has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    -- Preserve existing numeric prefix by default (CLI passes 0 to mean "no change").
    local existing = (type(u.callsign) == 'table') and u.callsign or {}
    local sq = (type(args.squadron) == 'number' and args.squadron > 0) and args.squadron
               or (type(existing[1]) == 'number' and existing[1]) or 1
    local fl = (type(args.flight) == 'number' and args.flight > 0) and args.flight
               or (type(existing[2]) == 'number' and existing[2]) or 1
    local pl = (type(args.plane) == 'number' and args.plane > 0) and args.plane
               or (type(existing[3]) == 'number' and existing[3]) or 1
    u.callsign = { sq, fl, pl, name = args.callsign }
    return { ok = true, id = u.unitId, name = u.name,
             callsign = { sq, fl, pl, name = args.callsign } }
end

-- ============================================================
-- Trigger zone lifecycle verbs
-- ============================================================

-- DCS trigger zone types (from Mission.TriggerZone.lua line 9):
--   TYPE_CIRCLE    = 0
--   TYPE_RECTANGLE = 1   (unused at the ME UI level — quads use type 2)
--   TYPE_POLYGON   = 2   (4 vertices = "Quad-Point Zone" in the ME UI)
local ZONE_TYPE_CIRCLE = 0
local ZONE_TYPE_POLYGON = 2

-- Default color matches what TriggerZone.construct sets internally:
-- {r=1, g=1, b=1, a=0.15} — translucent white. RGBA components are floats 0..1.
local function default_zone_color() return { 1, 1, 1, 0.15 } end

-- find_zone_by_name / find_zone_by_id — TriggerZoneData doesn't expose a
-- by-name lookup directly; we iterate getTriggerZoneIds() and match.
local function find_zone(by_name, by_id)
    local TZD = require('Mission.TriggerZoneData')
    if type(TZD) ~= 'table' or type(TZD.getTriggerZoneIds) ~= 'function' then
        return nil, nil
    end
    for _, zid in ipairs(TZD.getTriggerZoneIds() or {}) do
        if by_id and zid == by_id then return zid, TZD.getTriggerZoneName(zid) end
        if by_name then
            local n = TZD.getTriggerZoneName(zid)
            if n == by_name then return zid, n end
        end
    end
    return nil, nil
end

-- zone_create_circle — circular trigger zone at (north, east) with given radius.
--
-- args (required):
--   name:   string  -- zone name (uniquified by TriggerZoneData if duplicate)
--   north:  number  -- meters north of theatre origin
--   east:   number  -- meters east of theatre origin
--   radius: number  -- meters
--
-- args (optional):
--   color:  { r, g, b, a } floats 0..1; defaults to translucent white
--   hidden: bool, default false
--   properties: table, default {}
--
-- Returns { ok = true, zoneId, name } on success.
function M.zone_create_circle(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_create_circle requires args (table)' }
    end
    if type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'zone_create_circle requires args.name (string)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'zone_create_circle requires args.north and args.east (numbers, meters)' }
    end
    if type(args.radius) ~= 'number' or args.radius <= 0 then
        return { ok = false, error = 'zone_create_circle requires args.radius (positive number, meters)' }
    end

    local ok_tzd, TZD = pcall(require, 'Mission.TriggerZoneData')
    if not ok_tzd or type(TZD) ~= 'table' or type(TZD.addTriggerZone) ~= 'function' then
        return { ok = false, error = 'Mission.TriggerZoneData unavailable' }
    end

    local color = (type(args.color) == 'table') and args.color or default_zone_color()
    local properties = (type(args.properties) == 'table') and args.properties or {}

    -- mission-table fields: x = north, y = east
    local x, y = args.north, args.east

    -- addTriggerZone returns the allocated zoneId on success.
    local ok_call, zid_or_err = pcall(TZD.addTriggerZone, args.name, x, y, args.radius,
                                       properties, color, ZONE_TYPE_CIRCLE, nil)
    if not ok_call then
        return { ok = false, error = 'addTriggerZone: ' .. tostring(zid_or_err) }
    end
    if type(zid_or_err) ~= 'number' then
        return { ok = false, error = 'addTriggerZone returned non-number: ' .. tostring(zid_or_err) }
    end

    -- Name may have been uniquified by TZD.makeTriggerZoneNameUnique.
    local final_name = TZD.getTriggerZoneName and TZD.getTriggerZoneName(zid_or_err) or args.name

    if args.hidden == true and type(TZD.setTriggerZoneHidden) == 'function' then
        pcall(TZD.setTriggerZoneHidden, zid_or_err, true)
    end

    return { ok = true, zoneId = zid_or_err, name = final_name, type = 'circle' }
end

-- zone_create_quad — polygon trigger zone with 4 vertices (the ME's
-- "Quad-Point Zone"). Despite the name we accept any N>=3 vertex count —
-- the underlying type=2 polygon supports it.
--
-- args (required):
--   name:     string
--   vertices: list of { north = N, east = E } in absolute world meters
--             (NOT relative to center — we compute the center for you).
--
-- args (optional):
--   color, hidden, properties — see zone_create_circle
--   radius:   icon radius in meters; defaults to half the bounding-box diagonal
--             (matches what the ME would compute for a rectangular quad).
--
-- Returns { ok = true, zoneId, name, center = { north, east } } on success.
function M.zone_create_quad(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_create_quad requires args (table)' }
    end
    if type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'zone_create_quad requires args.name (string)' }
    end
    if type(args.vertices) ~= 'table' or #args.vertices < 3 then
        return { ok = false, error = 'zone_create_quad requires args.vertices (>= 3 {north,east} pairs)' }
    end

    -- Validate each vertex.
    for i, v in ipairs(args.vertices) do
        if type(v) ~= 'table' or type(v.north) ~= 'number' or type(v.east) ~= 'number' then
            return { ok = false,
                     error = 'vertex ' .. i .. ' missing/invalid {north,east} numbers' }
        end
    end

    -- Compute center as average of vertices.
    local cx, cy = 0, 0
    for _, v in ipairs(args.vertices) do
        cx = cx + v.north
        cy = cy + v.east
    end
    cx = cx / #args.vertices
    cy = cy / #args.vertices

    -- Convert absolute vertices to points relative to center
    -- (mission-table fields: x = north, y = east).
    local points = {}
    local minN, maxN, minE, maxE = math.huge, -math.huge, math.huge, -math.huge
    for _, v in ipairs(args.vertices) do
        table.insert(points, { x = v.north - cx, y = v.east - cy })
        if v.north < minN then minN = v.north end
        if v.north > maxN then maxN = v.north end
        if v.east  < minE then minE = v.east  end
        if v.east  > maxE then maxE = v.east  end
    end

    -- Default radius = half bounding-box diagonal — sized so the icon
    -- circumscribes the quad. User can override.
    local default_radius = 0.5 * math.sqrt((maxN - minN) ^ 2 + (maxE - minE) ^ 2)
    local radius = (type(args.radius) == 'number' and args.radius > 0) and args.radius
                   or math.max(default_radius, 1)

    local ok_tzd, TZD = pcall(require, 'Mission.TriggerZoneData')
    if not ok_tzd or type(TZD) ~= 'table' or type(TZD.addTriggerZone) ~= 'function' then
        return { ok = false, error = 'Mission.TriggerZoneData unavailable' }
    end

    local color = (type(args.color) == 'table') and args.color or default_zone_color()
    local properties = (type(args.properties) == 'table') and args.properties or {}

    local ok_call, zid_or_err = pcall(TZD.addTriggerZone, args.name, cx, cy, radius,
                                       properties, color, ZONE_TYPE_POLYGON, points)
    if not ok_call then
        return { ok = false, error = 'addTriggerZone: ' .. tostring(zid_or_err) }
    end
    if type(zid_or_err) ~= 'number' then
        return { ok = false, error = 'addTriggerZone returned non-number: ' .. tostring(zid_or_err) }
    end

    local final_name = TZD.getTriggerZoneName and TZD.getTriggerZoneName(zid_or_err) or args.name

    if args.hidden == true and type(TZD.setTriggerZoneHidden) == 'function' then
        pcall(TZD.setTriggerZoneHidden, zid_or_err, true)
    end

    return { ok = true, zoneId = zid_or_err, name = final_name, type = 'quad',
             center = { north = cx, east = cy }, vertex_count = #points }
end

-- ============================================================
-- Zone setters (per-field)
-- ============================================================
--
-- Each setter takes { name = "<X>" | id = <N>, <field> = <value> } and wraps
-- the matching Mission.TriggerZoneData.setTriggerZone* call. Returns the new
-- value on success so callers can confirm the write took.

-- zone_set_color — change RGBA color of a zone.
-- args: { name | id, color = { r, g, b[, a] } } floats 0..1.
-- Alpha defaults to 0.15 (DCS's translucent fill alpha) if missing.
function M.zone_set_color(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_set_color requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_set_color requires exactly one of args.name or args.id' }
    end
    if type(args.color) ~= 'table' or type(args.color[1]) ~= 'number'
            or type(args.color[2]) ~= 'number' or type(args.color[3]) ~= 'number' then
        return { ok = false, error = 'zone_set_color requires args.color = { r, g, b[, a] } floats 0..1' }
    end
    local zid, zname = find_zone(has_name and args.name or nil,
                                 has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end
    local r, g, b = args.color[1], args.color[2], args.color[3]
    local a = (type(args.color[4]) == 'number') and args.color[4] or 0.15
    local TZD = require('Mission.TriggerZoneData')
    local ok_call, err = pcall(TZD.setTriggerZoneColor, zid, r, g, b, a)
    if not ok_call then
        return { ok = false, error = 'setTriggerZoneColor: ' .. tostring(err) }
    end
    return { ok = true, id = zid, name = zname, color = { r, g, b, a } }
end

-- zone_set_name — rename a zone. ME enforces uniqueness via
-- makeTriggerZoneNameUnique, so the stored name may include a suffix.
function M.zone_set_name(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_set_name requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_set_name requires exactly one of args.name or args.id' }
    end
    if type(args.new_name) ~= 'string' or args.new_name == '' then
        return { ok = false, error = 'zone_set_name requires args.new_name (non-empty string)' }
    end
    local zid = find_zone(has_name and args.name or nil, has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end
    local TZD = require('Mission.TriggerZoneData')
    local ok_call, err = pcall(TZD.setTriggerZoneName, zid, args.new_name)
    if not ok_call then
        return { ok = false, error = 'setTriggerZoneName: ' .. tostring(err) }
    end
    -- Read back what TZD actually stored — the ME may have appended a suffix.
    local final = TZD.getTriggerZoneName(zid)
    return { ok = true, id = zid, name = final, requested_name = args.new_name }
end

-- zone_set_pos — move zone center to (north, east).
-- For circles, this just moves the center. For quads, the relative points
-- ride along (translation), but the shape doesn't reshape — use
-- zone_set_vertices for that.
function M.zone_set_pos(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_set_pos requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_set_pos requires exactly one of args.name or args.id' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'zone_set_pos requires args.north and args.east (numbers, meters)' }
    end
    local zid, zname = find_zone(has_name and args.name or nil, has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end
    local TZD = require('Mission.TriggerZoneData')
    -- mission-table fields: x = north, y = east
    local ok_call, err = pcall(TZD.setTriggerZonePosition, zid, args.north, args.east)
    if not ok_call then
        return { ok = false, error = 'setTriggerZonePosition: ' .. tostring(err) }
    end
    return { ok = true, id = zid, name = zname, north = args.north, east = args.east }
end

-- zone_set_radius — set zone radius (circle: trigger radius; quad: icon radius).
function M.zone_set_radius(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_set_radius requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_set_radius requires exactly one of args.name or args.id' }
    end
    if type(args.radius) ~= 'number' or args.radius <= 0 then
        return { ok = false, error = 'zone_set_radius requires args.radius (positive number, meters)' }
    end
    local zid, zname = find_zone(has_name and args.name or nil, has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end
    local TZD = require('Mission.TriggerZoneData')
    local ok_call, err = pcall(TZD.setTriggerZoneRadius, zid, args.radius)
    if not ok_call then
        return { ok = false, error = 'setTriggerZoneRadius: ' .. tostring(err) }
    end
    return { ok = true, id = zid, name = zname, radius = args.radius }
end

-- zone_set_hidden — toggle zone visibility in the ME view.
-- Caller must pass an explicit boolean — the CLI rejects missing --hidden.
function M.zone_set_hidden(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_set_hidden requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_set_hidden requires exactly one of args.name or args.id' }
    end
    if type(args.hidden) ~= 'boolean' then
        return { ok = false, error = 'zone_set_hidden requires args.hidden (boolean)' }
    end
    local zid, zname = find_zone(has_name and args.name or nil, has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end
    local TZD = require('Mission.TriggerZoneData')
    local ok_call, err = pcall(TZD.setTriggerZoneHidden, zid, args.hidden)
    if not ok_call then
        return { ok = false, error = 'setTriggerZoneHidden: ' .. tostring(err) }
    end
    return { ok = true, id = zid, name = zname, hidden = args.hidden }
end

-- zone_set_vertices — reshape a quad zone in absolute world coords.
-- Computes a new center (average of vertices) and stores points relative to
-- that center — same shape zone_create_quad produces, so save+reload behavior
-- is identical. Refuses on non-quad zones.
--
-- args: { name|id, vertices = { { north=N, east=E }, ... } } (>= 3)
function M.zone_set_vertices(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_set_vertices requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_set_vertices requires exactly one of args.name or args.id' }
    end
    if type(args.vertices) ~= 'table' or #args.vertices < 3 then
        return { ok = false, error = 'zone_set_vertices requires args.vertices (>= 3 {north,east} pairs)' }
    end
    for i, v in ipairs(args.vertices) do
        if type(v) ~= 'table' or type(v.north) ~= 'number' or type(v.east) ~= 'number' then
            return { ok = false, error = 'vertex ' .. i .. ' missing/invalid {north,east} numbers' }
        end
    end

    local zid, zname = find_zone(has_name and args.name or nil, has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end

    local TZD = require('Mission.TriggerZoneData')
    -- Refuse on circle zones — they have no vertices to reshape. The user
    -- almost certainly wanted set-radius / set-pos.
    if TZD.getTriggerZoneType(zid) ~= 2 then  -- 2 = polygon/quad
        return { ok = false, error = 'zone is not a quad; use set-radius/set-pos for circle zones' }
    end

    -- Average vertices for new center, then compute relative points.
    local cx, cy = 0, 0
    for _, v in ipairs(args.vertices) do
        cx = cx + v.north; cy = cy + v.east
    end
    cx = cx / #args.vertices; cy = cy / #args.vertices
    local rel = {}
    for _, v in ipairs(args.vertices) do
        table.insert(rel, { x = v.north - cx, y = v.east - cy })
    end

    local ok_pos, err_pos = pcall(TZD.setTriggerZonePosition, zid, cx, cy)
    if not ok_pos then
        return { ok = false, error = 'setTriggerZonePosition: ' .. tostring(err_pos) }
    end
    local ok_pts, err_pts = pcall(TZD.setTriggerZonePoints, zid, rel)
    if not ok_pts then
        return { ok = false, error = 'setTriggerZonePoints: ' .. tostring(err_pts) }
    end
    return { ok = true, id = zid, name = zname,
             center = { north = cx, east = cy },
             vertex_count = #rel }
end

-- zone_remove — remove a trigger zone by name or id (mutually exclusive).
function M.zone_remove(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_remove requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_remove requires exactly one of args.name (string) or args.id (number)' }
    end

    local zid, zname = find_zone(has_name and args.name or nil,
                                 has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end

    local TZD = require('Mission.TriggerZoneData')
    local ok_call, err = pcall(TZD.removeTriggerZone, zid)
    if not ok_call then
        return { ok = false, error = 'removeTriggerZone: ' .. tostring(err),
                 resolved = { id = zid, name = zname } }
    end

    return { ok = true, id = zid, name = zname }
end

-- ============================================================
-- Read-side verbs: list / get
-- ============================================================
--
-- Output convention:
--   * list verbs return concise summaries with translated north / east
--     (matching our --north / --east flag convention)
--   * get verbs return the raw mission-table structure (so callers can see
--     the underlying field names — useful when designing future setter
--     verbs or scripting). Cycle-causing back-references (boss, mapObjects)
--     are stripped to keep JSON serializable.

-- group_list — return concise summaries of all groups, with optional filters.
--
-- args (all optional):
--   side:     "red" | "blue" | "neutrals"      (the mission table's key name)
--   country:  string  -- country name (case-insensitive exact match)
--   category: "plane"|"helicopter"|"vehicle"|"ship"|"static"
--   name:     string  -- case-insensitive substring match
--
-- Returns { ok = true, groups = [ ... summaries ... ], count = N }.
function M.group_list(args)
    args = args or {}
    local f_side = args.side and string.lower(args.side) or nil
    local f_country = args.country and string.lower(args.country) or nil
    local f_category = args.category and string.lower(args.category) or nil
    local f_name = args.name and string.lower(args.name) or nil

    local out = {}
    walk_groups(function(g, country, side_name, cat)
        if f_side and string.lower(side_name) ~= f_side then return end
        if f_country and string.lower(country.name or '') ~= f_country then return end
        if f_category and cat ~= f_category then return end
        if f_name and not string.find(string.lower(g.name or ''), f_name, 1, true) then return end
        table.insert(out, {
            id = g.groupId,
            name = g.name,
            category = cat,
            country = country.name,
            side = side_name,
            north = g.x,
            east = g.y,
            unit_count = g.units and #g.units or 0,
            hidden = g.hidden or false,
            task = g.task,
        })
    end)
    return { ok = true, groups = out, count = #out }
end

-- group_get — full mission-table snapshot of a single group, by name or id.
-- Strips boss / mapObjects (cycle-causing).
function M.group_get(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_get requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_get requires exactly one of args.name or args.id' }
    end
    local g, country, side_name, cat = find_group_in_mission(has_name and args.name or nil,
                                                              has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    local snapshot = strip_back_refs(g)
    snapshot._side = side_name
    snapshot._country = country and country.name
    snapshot._category = cat
    return { ok = true, group = snapshot }
end

-- unit_list — return concise per-unit summaries from all groups, with filters.
--
-- args (all optional):
--   country, category, side — same as group_list
--   group:  group name (exact match)
--   name:   unit-name substring (case-insensitive)
--   type:   unit type (e.g. "F-16C_50") exact match
--
-- Returns { ok = true, units = [ ... ], count = N }.
function M.unit_list(args)
    args = args or {}
    local f_side = args.side and string.lower(args.side) or nil
    local f_country = args.country and string.lower(args.country) or nil
    local f_category = args.category and string.lower(args.category) or nil
    local f_group = args.group or nil
    local f_name = args.name and string.lower(args.name) or nil
    local f_type = args.type or nil

    local out = {}
    walk_groups(function(g, country, side_name, cat)
        if f_side and string.lower(side_name) ~= f_side then return end
        if f_country and string.lower(country.name or '') ~= f_country then return end
        if f_category and cat ~= f_category then return end
        if f_group and g.name ~= f_group then return end
        for _, u in ipairs(g.units or {}) do
            if not (f_name and not string.find(string.lower(u.name or ''), f_name, 1, true)) then
                if not (f_type and u.type ~= f_type) then
                    table.insert(out, {
                        id = u.unitId,
                        name = u.name,
                        type = u.type,
                        group_name = g.name,
                        group_id = g.groupId,
                        category = cat,
                        country = country.name,
                        side = side_name,
                        north = u.x,
                        east = u.y,
                        alt = u.alt,
                        heading = u.heading,
                        skill = u.skill,
                    })
                end
            end
        end
    end)
    return { ok = true, units = out, count = #out }
end

-- unit_get — full raw unit table (back-refs stripped), by name or id.
function M.unit_get(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'unit_get requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'unit_get requires exactly one of args.name or args.id' }
    end

    local found_unit, found_group, found_country, found_side, found_cat
    walk_groups(function(g, country, side_name, cat)
        for _, u in ipairs(g.units or {}) do
            if (has_name and u.name == args.name)
                    or (has_id and u.unitId == args.id) then
                found_unit, found_group, found_country = u, g, country
                found_side, found_cat = side_name, cat
                return false
            end
        end
    end)

    if not found_unit then
        return { ok = false, error = 'unit not found' }
    end
    local snapshot = strip_back_refs(found_unit)
    snapshot._group_name = found_group.name
    snapshot._group_id = found_group.groupId
    snapshot._country = found_country.name
    snapshot._side = found_side
    snapshot._category = found_cat
    return { ok = true, unit = snapshot }
end

-- zone_list — return concise summaries of all trigger zones.
--
-- args (optional):
--   shape: "circle" | "quad"  -- numeric type 0 / 2 in mission-table
--   name:  string  -- substring (case-insensitive)
--
-- Returns { ok = true, zones = [ ... ], count = N }.
function M.zone_list(args)
    args = args or {}
    local f_shape = args.shape and string.lower(args.shape) or nil
    local f_name = args.name and string.lower(args.name) or nil

    local ok_tzd, TZD = pcall(require, 'Mission.TriggerZoneData')
    if not ok_tzd or type(TZD) ~= 'table' then
        return { ok = false, error = 'Mission.TriggerZoneData unavailable' }
    end

    local out = {}
    for _, zid in ipairs(TZD.getTriggerZoneIds() or {}) do
        local nm = TZD.getTriggerZoneName(zid)
        local tnum = TZD.getTriggerZoneType(zid)
        local shape = (tnum == 0 and 'circle') or (tnum == 2 and 'quad') or ('type=' .. tostring(tnum))
        if not (f_shape and shape ~= f_shape)
                and not (f_name and nm and not string.find(string.lower(nm), f_name, 1, true)) then
            local x, y = TZD.getTriggerZonePosition(zid)
            local r, g, b, a = TZD.getTriggerZoneColor(zid)
            local pts = TZD.getTriggerZonePoints(zid) or {}
            table.insert(out, {
                id = zid,
                name = nm,
                shape = shape,
                type = tnum,
                north = x,
                east = y,
                radius = TZD.getTriggerZoneRadius(zid),
                color = { r, g, b, a },
                hidden = TZD.getTriggerZoneHidden(zid),
                vertex_count = (tnum == 2) and #pts or nil,
            })
        end
    end
    return { ok = true, zones = out, count = #out }
end

-- zone_get — full zone detail by name or id.
function M.zone_get(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_get requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_get requires exactly one of args.name or args.id' }
    end

    local zid, _ = find_zone(has_name and args.name or nil,
                             has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end

    local TZD = require('Mission.TriggerZoneData')
    local x, y = TZD.getTriggerZonePosition(zid)
    local r, g, b, a = TZD.getTriggerZoneColor(zid)
    local tnum = TZD.getTriggerZoneType(zid)
    local shape = (tnum == 0 and 'circle') or (tnum == 2 and 'quad') or ('type=' .. tostring(tnum))
    local pts_rel = TZD.getTriggerZonePoints(zid) or {}

    -- Convert relative points back to absolute for user clarity (matches the
    -- shape of --vertices on input). Keep raw relative points too.
    local pts_abs = {}
    for _, p in ipairs(pts_rel) do
        table.insert(pts_abs, { north = p.x + x, east = p.y + y })
    end

    return {
        ok = true,
        zone = {
            id = zid,
            name = TZD.getTriggerZoneName(zid),
            shape = shape,
            type = tnum,
            north = x,
            east = y,
            radius = TZD.getTriggerZoneRadius(zid),
            color = { r, g, b, a },
            hidden = TZD.getTriggerZoneHidden(zid),
            properties = TZD.getTriggerZoneProperties(zid),
            link_unit_id = TZD.getLinkUnitId(zid),
            heading = TZD.getTriggerZone(zid) and TZD.getTriggerZone(zid):getHeading() or 0,
            points_relative = pts_rel,
            vertices_absolute = (tnum == 2) and pts_abs or nil,
        },
    }
end

return M
