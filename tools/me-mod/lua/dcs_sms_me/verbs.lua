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

-- find_unit_in_mission — locate a unit by name or id, returning
-- (unit, group, country, side, category) or nil. Walks the coalition
-- tree via walk_groups. Shared by every unit_set_* verb plus
-- group_remove_unit.
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

-- _save_mission_with_reopen_dance — shared body for file_save / file_save_as.
--
-- module_mission.save_mission_safe(path, false, noLoad=false) writes the .miz
-- and synchronously calls module_mission.load(fName) inside save() (line
-- ~4889 in me_mission.lua). load() rebuilds the entire mission table:
-- coalition[].country[].<cat>.group lists, unit_by_name, group_by_name, and
-- the per-group/per-unit map objects. **Any reference held outside that
-- table becomes stale.**
--
-- The ME-native saveMission flow at me_toolbar.lua:769-803 mirrors this with
-- two cleanup steps that our verbs must reproduce when reopen=true:
--   1. BEFORE save: MapWindow.unselectAll() — clears MapWindow.selectedGroup
--      / selectedUnit and the selection sprites. Without this, after load()
--      rebuilds the tables those references point at orphan objects: the
--      title bar updates correctly (it's just a string) but the user can't
--      select anything new because the ME's click handlers walk the dangling
--      selection state and short-circuit on stale identity checks.
--   2. AFTER save: MapWindow.show(true) — re-creates / re-renders the map
--      against the new mission data.
--
-- When reopen=false we skip both: there's no rebuild, references stay valid.
local function _save_mission_with_reopen_dance(verb, path, reopen)
    local ok_mm, module_mission = pcall(require, 'me_mission')
    if not ok_mm or type(module_mission) ~= 'table' then
        return { ok = false, error = 'me_mission unavailable' }
    end
    if type(module_mission.save_mission_safe) ~= 'function' then
        return { ok = false, error = 'me_mission.save_mission_safe unavailable' }
    end

    -- Pre-save: clear stale selection refs so they don't survive into the
    -- post-load() ME state.
    local MapWindow
    if reopen then
        local ok_mw
        ok_mw, MapWindow = pcall(require, 'me_map_window')
        if ok_mw and type(MapWindow) == 'table' and type(MapWindow.unselectAll) == 'function' then
            pcall(MapWindow.unselectAll)
        end
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

    -- Post-save: refresh the map view against the rebuilt tables. Mirrors
    -- saveMissionFileDialog at me_toolbar.lua:757.
    if reopen and MapWindow and type(MapWindow.show) == 'function' then
        pcall(MapWindow.show, true)
    end

    return { ok = true, path = path, reopen = reopen }
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
    if type(module_mission.getMissionPathIsSaved) ~= 'function'
            or not module_mission.getMissionPathIsSaved() then
        return { ok = false,
                 error = 'mission has no saved path; use file save-as --path <X.miz>' }
    end
    local path = module_mission.mission and module_mission.mission.path
    if type(path) ~= 'string' or path == '' then
        return { ok = false, error = 'mission.path missing' }
    end
    local result = _save_mission_with_reopen_dance('file_save', path, reopen)
    if not result.ok then return result end
    if not reopen then refresh_menubar_title(path) end
    return result
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
    local result = _save_mission_with_reopen_dance('file_save_as', args.path, reopen)
    if not result.ok then return result end
    -- Always sync MeSettings (the DCS user-flow does this in me_toolbar; load() doesn't).
    local ok_ms, MeSettings = pcall(require, 'MeSettings')
    if ok_ms and type(MeSettings) == 'table' and type(MeSettings.setMissionPath) == 'function' then
        pcall(MeSettings.setMissionPath, args.path)
    end
    if not reopen then
        -- load() would have set these for us; in the no-reload path do it manually.
        local ok_mm, module_mission = pcall(require, 'me_mission')
        if ok_mm and module_mission.mission then module_mission.mission.path = args.path end
        refresh_menubar_title(args.path)
    end
    return result
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
    local heading = math.rad(args.heading_deg or 0)
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
    local heading = math.rad(args.heading_deg or 0)
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
    local heading = math.rad(args.heading_deg or 0)
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
    local heading = math.rad(args.heading_deg or 0)
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
    local heading = math.rad(args.heading_deg or 0)
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
-- AIR-GROUP CAVEAT: per-unit (x, y) is decorative for plane / helicopter
-- groups. DCS overrides it at mission load and lays out the flight via
-- group.units[1].route.points[1] (or wherever the route starts) +
-- formation_template — every wingman is positioned by the formation, not
-- by their stored x/y. The offset survives in the ME view and on disk
-- but doesn't reach runtime. Ground / ship / static groups respect
-- per-unit positions verbatim. A future formation setter is the right
-- lever for air-group runtime layout.
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

-- group_remove_unit — remove a single unit from a group, mirroring the
-- ME UI's per-unit "x" button. Wraps Mission.remove_unit, which handles
-- the unlink dance (waypoints, required units, trigger zones), warehouse
-- cleanup, unit_by_name / unit_by_id deregistration, and panel refresh.
--
-- Selection is by --name or --id (mutually exclusive) — the unit's, not
-- the group's. The verb walks the coalition tree to find the unit.
--
-- Refuses to remove the last unit in a group: that would leave an empty
-- group, which the rest of the ME doesn't expect (the Unit List panel,
-- selection helpers, etc. all assume #units >= 1). To remove the whole
-- group use `me group remove`.
--
-- Mission.remove_unit reads `unit.index` (its position in g.units).
-- Units inserted via insert_unit have it set; the seed unit synthesised
-- by group_create_<cat> doesn't, so we populate it defensively here by
-- walking g.units before the call.
function M.group_remove_unit(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_remove_unit requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_remove_unit requires exactly one of args.name or args.id' }
    end

    local u, g, country, side_name, cat = find_unit_in_mission(
        has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end
    if type(g.units) ~= 'table' or #g.units <= 1 then
        return { ok = false,
                 error = 'cannot remove the last unit in a group; use `me group remove` instead' }
    end

    -- Make sure unit.index is set; remove_unit relies on it for table.remove.
    if type(u.index) ~= 'number' then
        for i, gu in ipairs(g.units) do
            if gu == u then u.index = i; break end
        end
    end

    local resolved = {
        name = u.name, id = u.unitId, type = u.type,
        group = g.name, group_id = g.groupId,
        category = cat,
        country = country and country.name, side = side_name,
    }

    local Mission = require('me_mission')
    local ok_call, err = pcall(Mission.remove_unit, u)
    if not ok_call then
        return { ok = false, error = 'remove_unit: ' .. tostring(err), resolved = resolved }
    end

    refresh_group_view(g)

    return {
        ok = true,
        name = resolved.name,
        id = resolved.id,
        type = resolved.type,
        group = resolved.group,
        group_id = resolved.group_id,
        category = resolved.category,
        country = resolved.country,
        side = resolved.side,
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

-- group_set_formation — set the per-waypoint formation for a vehicle group.
--
-- Vehicle waypoints carry a "formation action" (wp.type, the action table
-- reference): one of Off Road / On Road / Rank / Cone / Vee / Diamond /
-- Echelon L / Echelon R / Custom. For Custom, wp.formation_template names
-- a DB.templates entry (e.g. "Hawk SAM Battery"). For built-ins, the
-- formation_template field is irrelevant and gets cleared so it doesn't
-- linger as stale state.
--
-- Vehicle groups only:
--   * plane / helicopter: formation is per-WrappedAction-task on the
--     waypoint, not via wp.type. Hidden from the route panel
--     (me_route.lua:2084: c_form_templ:setVisible(not isAirGroup)). A
--     future air-formation verb will do task surgery — out of scope here.
--   * ship: only the turningPoint action is valid (me_route.lua:204) —
--     formation actions don't apply.
--   * static: no route, no formations.
--
-- args:
--   name | id        group selector (mutually exclusive)
--   formation        formation name; built-in alias OR a DB.templates entry.
--                    Built-in aliases (case-insensitive, dash/space tolerant):
--                      off-road, on-road, rank, cone, vee, diamond,
--                      echelon-left (echelonl), echelon-right (echelonr),
--                      custom (just sets the action; no template name)
--                    Any other string is treated as a custom template name —
--                    must be a DB.templates key. Sets wp.type=actions.customForm
--                    AND wp.formation_template=<name>.
--   waypoint         1-indexed waypoint number (default 1)
function M.group_set_formation(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_set_formation requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_set_formation requires exactly one of args.name or args.id' }
    end
    if type(args.formation) ~= 'string' or args.formation == '' then
        return { ok = false, error = 'group_set_formation requires args.formation (non-empty string)' }
    end
    local g, _, _, cat = find_group_in_mission(has_name and args.name or nil,
                                                has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    if cat ~= 'vehicle' then
        local why
        if cat == 'plane' or cat == 'helicopter' then
            why = ' — air-group formations are per-waypoint tasks, not yet exposed'
        elseif cat == 'ship' then
            why = ' — ship waypoints only support the turningPoint action'
        elseif cat == 'static' then
            why = ' — statics do not have a route'
        else
            why = ''
        end
        return { ok = false,
                 error = 'group_set_formation only applies to vehicle groups (got '
                         .. cat .. ')' .. why }
    end
    local wp_idx = (type(args.waypoint) == 'number') and args.waypoint or 1
    if wp_idx < 1 then
        return { ok = false, error = 'group_set_formation: args.waypoint must be >= 1' }
    end
    if not g.route or type(g.route.points) ~= 'table' or not g.route.points[wp_idx] then
        return { ok = false, error = 'group_set_formation: waypoint ' .. tostring(wp_idx) .. ' not found' }
    end

    -- Resolve formation name. Built-in aliases first; otherwise treat as a
    -- DB.templates name and require Custom action.
    local key = string.lower(args.formation):gsub('[%s_-]', '')
    local builtin_aliases = {
        offroad     = 'offRoad',
        onroad      = 'onRoad',
        rank        = 'rank',
        cone        = 'cone',
        vee         = 'vee',
        diamond     = 'diamond',
        echelonleft = 'echelonL',
        echelonl    = 'echelonL',
        echelonright= 'echelonR',
        echelonr    = 'echelonR',
        custom      = 'customForm',
        customform  = 'customForm',
    }
    local action_key = builtin_aliases[key]
    local UC = require('utils_common')
    if type(UC) ~= 'table' or type(UC.actions) ~= 'table' then
        return { ok = false, error = 'group_set_formation: utils_common.actions unavailable' }
    end
    local wp = g.route.points[wp_idx]
    local resolved_template = ''
    local resolved_action_name
    if action_key then
        wp.type = UC.actions[action_key]
        if action_key ~= 'customForm' then
            wp.formation_template = ''  -- clear stale Custom state
        else
            -- Custom alias without a template name keeps any existing template.
            resolved_template = wp.formation_template or ''
        end
        resolved_action_name = action_key
    else
        -- Treat as a DB.templates key — must exist, sets Custom + template.
        local ok_db, DB = pcall(require, 'me_db_api')
        local exists = ok_db and type(DB) == 'table' and type(DB.templates) == 'table'
                       and DB.templates[args.formation] ~= nil
        if not exists then
            return { ok = false,
                     error = 'group_set_formation: unknown formation "' .. args.formation
                             .. '" (not a built-in alias and not in DB.templates)' }
        end
        wp.type = UC.actions.customForm
        wp.formation_template = args.formation
        resolved_template = args.formation
        resolved_action_name = 'customForm'
    end

    return { ok = true, id = g.groupId, name = g.name,
             waypoint = wp_idx,
             action = resolved_action_name,
             formation_template = resolved_template }
end

-- group_set_country — change a group's country (and possibly coalition).
--
-- Replicates the data-side flow of me_aircraft.lua:1460 changeCountry.
-- ED's panel function does both the data mutation AND a pile of UI refreshes
-- (combo boxes, task list, callsign refresh, panel_loadout.update). Those
-- panels read from the mutated mission state when next opened, so we skip
-- them here — the mutation alone is enough for save-survival and runtime.
--
-- Steps:
--   1. resolve target country (must already exist in mission tree)
--   2. detect coalition change (side flip)
--   3. remove group from oldCountry[cat].group
--   4. update g.boss = newCountry, defensive newCountry.boss = side
--   5. insert into newCountry[cat].group (create sub-table if missing)
--   6. update g.color = newCountry.boss.color
--   7. fixup unit liveries via panel_payload.setDefaultLivery (air groups —
--      schemes are country-keyed, defaults differ per country)
--   8. re-attract first waypoint if it's a takeoff/landing airfield action
--      (the old airfield may not exist in the new coalition)
--   9. refresh map objects (color updates immediately)
--
-- ME does NOT refuse country changes that would make unit types invalid for
-- the new country (e.g. moving an Su-27 to USA). The unit type persists; the
-- livery list goes empty. Mirror that behavior — log a warning if liveries
-- come back empty but don't refuse.
--
-- args:
--   name | id  group selector (mutually exclusive)
--   country    target country name (case-insensitive)
function M.group_set_country(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'group_set_country requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'group_set_country requires exactly one of args.name or args.id' }
    end
    if type(args.country) ~= 'string' or args.country == '' then
        return { ok = false, error = 'group_set_country requires args.country (string)' }
    end
    local g, oldCountry, oldSide, cat = find_group_in_mission(
        has_name and args.name or nil, has_id and args.id or nil)
    if not g then
        return { ok = false, error = 'group not found' }
    end
    local newCountry, newSide = find_country_by_name(args.country)
    if not newCountry then
        return { ok = false,
                 error = 'group_set_country: country "' .. args.country .. '" not in mission tree' }
    end
    if newCountry == oldCountry then
        return { ok = true, id = g.groupId, name = g.name,
                 country = newCountry.name, side = newSide,
                 coalition_changed = false, no_op = true }
    end
    local coalition_changed = newSide ~= oldSide

    local Mission = require('me_mission')

    -- Step 3: remove from old country list.
    if oldCountry and oldCountry[cat] and type(oldCountry[cat].group) == 'table' then
        for i, v in ipairs(oldCountry[cat].group) do
            if v == g then
                table.remove(oldCountry[cat].group, i)
                break
            end
        end
    end

    -- Step 4: update boss back-reference + defensive country.boss = side.
    g.boss = newCountry
    if not newCountry.boss then
        local mission = Mission.mission or {}
        for sn, side in pairs(mission.coalition or {}) do
            if type(side) == 'table' and type(side.country) == 'table' then
                for _, c in ipairs(side.country) do
                    if c == newCountry then newCountry.boss = side; break end
                end
            end
            if newCountry.boss then break end
        end
    end

    -- Step 5: insert into new country list (create sub-table if missing).
    if type(newCountry[cat]) ~= 'table' then
        newCountry[cat] = { name = cat, group = {} }
    end
    if type(newCountry[cat].group) ~= 'table' then
        newCountry[cat].group = {}
    end
    table.insert(newCountry[cat].group, g)

    -- Step 6: color = new coalition color (via newCountry.boss.color).
    if newCountry.boss and newCountry.boss.color then
        g.color = newCountry.boss.color
    end

    -- Step 7: livery fixup (air groups — countries with non-overlapping
    -- airframe rosters end up with empty livery lists; that's fine, ME
    -- doesn't refuse it either).
    local empty_liveries = 0
    if cat == 'plane' or cat == 'helicopter' then
        local ok_pl, panel_payload = pcall(require, 'me_payload')
        if ok_pl and type(panel_payload) == 'table' and type(panel_payload.setDefaultLivery) == 'function' then
            for _, u in ipairs(g.units or {}) do
                pcall(panel_payload.setDefaultLivery, u)
                if u.livery_id == nil or u.livery_id == '' then
                    empty_liveries = empty_liveries + 1
                end
            end
        end
    end

    -- Step 8: airfield re-attract for takeoff/landing waypoints. Only
    -- meaningful for plane/helicopter groups.
    local airfield_reattracted = false
    if (cat == 'plane' or cat == 'helicopter')
            and g.route and type(g.route.points) == 'table' and g.route.points[1] then
        local ok_pr, panel_route = pcall(require, 'me_route')
        if ok_pr and type(panel_route) == 'table'
                and type(panel_route.isAirfieldWaypoint) == 'function'
                and type(panel_route.attractToAirfield) == 'function' then
            local wpt = g.route.points[1]
            if wpt.type and panel_route.isAirfieldWaypoint(wpt.type) then
                local ok_at, _ = pcall(panel_route.attractToAirfield, wpt, g)
                airfield_reattracted = ok_at
            end
        end
    end

    -- Step 9: refresh map objects (color update reflects immediately).
    refresh_group_view(g)

    return { ok = true, id = g.groupId, name = g.name,
             country = newCountry.name, side = newSide,
             previous_country = oldCountry and oldCountry.name,
             previous_side = oldSide,
             coalition_changed = coalition_changed,
             empty_liveries = empty_liveries,
             airfield_reattracted = airfield_reattracted }
end

-- ============================================================
-- Unit setters (per-field)
-- ============================================================

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
--
-- AIR-GROUP CAVEAT: for plane / helicopter units this only affects the
-- ME view and the saved .miz — at mission load DCS overrides every
-- wingman's position from the group's formation_template, so the new
-- (x, y) doesn't survive into runtime. Ground / ship / static units
-- honour the position verbatim.
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
-- Unit payload verbs (plane / helicopter only)
-- ============================================================
--
-- Payload data shape on a plane/heli unit:
--   u.payload = {
--     name   = "CAP",                       -- named loadout selector
--     pylons = {                            -- pylonNumber → weapon entry
--       [1] = { CLSID = "{...GUID...}", settings = { ... } | nil },
--       [3] = { CLSID = "ALQ_184",          settings = nil },
--       ...                                 -- non-contiguous
--     },
--     fuel  = 2500,    -- kg
--     chaff = 150,     -- count
--     flare = 120,     -- count
--     gun   = 100,     -- ammo % (0-100)
--   }
--
-- CLSID format is mixed: GUIDs ("{B6...}") and human-readable codes
-- ("ALQ_184", "{Mk82AIR}"). The pylon-specific weapon list lives at
-- DB.unit_by_type[u.type].Pylons[i].Launchers and is the source of truth
-- for what's valid where.

-- _resolve_weapon — accept either a CLSID or a display name, return the
-- CLSID. Looks up against the pylon's Launchers list. Returns nil + error
-- if no match.
local function _resolve_weapon(pylon_def, weapon_arg)
    if type(weapon_arg) ~= 'string' or weapon_arg == '' then
        return nil, 'weapon must be a non-empty string'
    end
    if type(pylon_def) ~= 'table' or type(pylon_def.Launchers) ~= 'table' then
        return nil, 'pylon has no Launchers list'
    end
    -- 1) exact CLSID match (skip obsolete launchers).
    for _, lnch in pairs(pylon_def.Launchers) do
        if type(lnch) == 'table' and lnch.CLSID == weapon_arg and not lnch.obsolete then
            return weapon_arg, nil
        end
    end
    -- 2) display-name match. base.get_weapon_display_name_by_clsid is the
    --    same lookup the ME panel uses; available globally in ME context.
    if type(get_weapon_display_name_by_clsid) == 'function' then
        local target = string.lower(weapon_arg)
        for _, lnch in pairs(pylon_def.Launchers) do
            if type(lnch) == 'table' and lnch.CLSID and not lnch.obsolete then
                local dn = get_weapon_display_name_by_clsid(lnch.CLSID)
                if type(dn) == 'string' and string.lower(dn) == target then
                    return lnch.CLSID, nil
                end
            end
        end
    end
    return nil, 'weapon "' .. weapon_arg .. '" not valid for this pylon'
end

-- _find_pylon_def — locate the pylon definition table for a given airframe
-- type and pylon number. Returns the pylon-def table or nil + error.
local function _find_pylon_def(unit_type, pylon_number)
    local ok_db, DB = pcall(require, 'me_db_api')
    if not ok_db or type(DB) ~= 'table' or type(DB.unit_by_type) ~= 'table' then
        return nil, 'me_db_api.unit_by_type unavailable'
    end
    local def = DB.unit_by_type[unit_type]
    if type(def) ~= 'table' or type(def.Pylons) ~= 'table' then
        return nil, 'unit type "' .. tostring(unit_type) .. '" has no Pylons'
    end
    for _, p in pairs(def.Pylons) do
        if type(p) == 'table' and p.Number == pylon_number then
            return p, nil
        end
    end
    return nil, 'pylon ' .. tostring(pylon_number) .. ' not valid for ' .. tostring(unit_type)
end

-- _check_air_unit — shared up-front guard. Resolves the unit and refuses
-- on non-air categories (only planes/helicopters carry payloads).
local function _check_air_unit(verb, args)
    if type(args) ~= 'table' then
        return nil, verb .. ' requires args (table)'
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return nil, verb .. ' requires exactly one of args.name or args.id'
    end
    local u, g, _, _, cat = find_unit_in_mission(
        has_name and args.name or nil, has_id and args.id or nil)
    if not u then
        return nil, 'unit not found'
    end
    if cat ~= 'plane' and cat ~= 'helicopter' then
        return nil, verb .. ' only applies to plane / helicopter units (got ' .. tostring(cat) .. ')'
    end
    return { unit = u, group = g, cat = cat }, nil
end

-- unit_set_loadout — apply a named loadout (e.g. "CAP", "CAS", "Empty").
-- Looks up the loadout via me_loadoututils.getUnitPylons, replaces
-- u.payload.pylons with its contents, and sets u.payload.name. Other
-- payload fields (chaff, flare, fuel, gun) are preserved.
function M.unit_set_loadout(args)
    local ctx, err = _check_air_unit('unit_set_loadout', args)
    if not ctx then return { ok = false, error = err } end
    if type(args.loadout) ~= 'string' or args.loadout == '' then
        return { ok = false, error = 'unit_set_loadout requires args.loadout (string)' }
    end
    local ok_lu, loadoutUtils = pcall(require, 'me_loadoututils')
    if not ok_lu or type(loadoutUtils) ~= 'table'
            or type(loadoutUtils.getUnitPylons) ~= 'function' then
        return { ok = false, error = 'me_loadoututils.getUnitPylons unavailable' }
    end
    local pylons = loadoutUtils.getUnitPylons(ctx.unit.type, args.loadout)
    if type(pylons) ~= 'table' then
        return { ok = false,
                 error = 'unit_set_loadout: loadout "' .. args.loadout
                         .. '" not found for ' .. ctx.unit.type }
    end
    local u = ctx.unit
    u.payload = u.payload or {}
    u.payload.name = args.loadout
    u.payload.pylons = {}
    local pylon_count = 0
    for pylonNumber, v in pairs(pylons) do
        if type(v) == 'table' and v.CLSID then
            u.payload.pylons[pylonNumber] = { CLSID = v.CLSID, settings = v.settings }
            pylon_count = pylon_count + 1
        end
    end
    return { ok = true, id = u.unitId, name = u.name,
             loadout = args.loadout, pylon_count = pylon_count }
end

-- unit_payload_set — set a single pylon's weapon by CLSID or display name.
-- Validates the pylon number against the airframe's Pylons table and the
-- weapon against that pylon's Launchers list. Refuses obsolete launchers.
function M.unit_payload_set(args)
    local ctx, err = _check_air_unit('unit_payload_set', args)
    if not ctx then return { ok = false, error = err } end
    if type(args.pylon) ~= 'number' or args.pylon < 1 then
        return { ok = false, error = 'unit_payload_set requires args.pylon (positive integer)' }
    end
    if type(args.weapon) ~= 'string' or args.weapon == '' then
        return { ok = false, error = 'unit_payload_set requires args.weapon (CLSID or display name)' }
    end
    local pylon_def, perr = _find_pylon_def(ctx.unit.type, args.pylon)
    if not pylon_def then
        return { ok = false, error = 'unit_payload_set: ' .. perr }
    end
    local clsid, werr = _resolve_weapon(pylon_def, args.weapon)
    if not clsid then
        return { ok = false, error = 'unit_payload_set: ' .. werr }
    end
    local u = ctx.unit
    u.payload = u.payload or {}
    u.payload.pylons = u.payload.pylons or {}
    u.payload.pylons[args.pylon] = { CLSID = clsid, settings = nil }
    return { ok = true, id = u.unitId, name = u.name,
             pylon = args.pylon, clsid = clsid }
end

-- unit_payload_clear — remove a single pylon's weapon entry.
function M.unit_payload_clear(args)
    local ctx, err = _check_air_unit('unit_payload_clear', args)
    if not ctx then return { ok = false, error = err } end
    if type(args.pylon) ~= 'number' or args.pylon < 1 then
        return { ok = false, error = 'unit_payload_clear requires args.pylon (positive integer)' }
    end
    -- Pylon-existence check (ergonomic — refuse on a pylon that's not a
    -- valid hardpoint for the airframe even though clearing nothing is
    -- a no-op data-wise).
    local _, perr = _find_pylon_def(ctx.unit.type, args.pylon)
    if perr then
        return { ok = false, error = 'unit_payload_clear: ' .. perr }
    end
    local u = ctx.unit
    local had_weapon = u.payload and u.payload.pylons and u.payload.pylons[args.pylon]
    u.payload = u.payload or {}
    u.payload.pylons = u.payload.pylons or {}
    u.payload.pylons[args.pylon] = nil
    return { ok = true, id = u.unitId, name = u.name,
             pylon = args.pylon, had_weapon = had_weapon ~= nil }
end

-- unit_set_chaff — set u.payload.chaff (count).
function M.unit_set_chaff(args)
    local ctx, err = _check_air_unit('unit_set_chaff', args)
    if not ctx then return { ok = false, error = err } end
    if type(args.count) ~= 'number' or args.count < 0 then
        return { ok = false, error = 'unit_set_chaff requires args.count (non-negative number)' }
    end
    local u = ctx.unit
    u.payload = u.payload or {}
    u.payload.chaff = args.count
    return { ok = true, id = u.unitId, name = u.name, chaff = u.payload.chaff }
end

-- unit_set_flare — set u.payload.flare (count).
function M.unit_set_flare(args)
    local ctx, err = _check_air_unit('unit_set_flare', args)
    if not ctx then return { ok = false, error = err } end
    if type(args.count) ~= 'number' or args.count < 0 then
        return { ok = false, error = 'unit_set_flare requires args.count (non-negative number)' }
    end
    local u = ctx.unit
    u.payload = u.payload or {}
    u.payload.flare = args.count
    return { ok = true, id = u.unitId, name = u.name, flare = u.payload.flare }
end

-- unit_set_fuel — set u.payload.fuel (kg). No max validation (the panel
-- clamps to airframe max; we let the user pass any non-negative number).
function M.unit_set_fuel(args)
    local ctx, err = _check_air_unit('unit_set_fuel', args)
    if not ctx then return { ok = false, error = err } end
    if type(args.fuel) ~= 'number' or args.fuel < 0 then
        return { ok = false, error = 'unit_set_fuel requires args.fuel (non-negative kg)' }
    end
    local u = ctx.unit
    u.payload = u.payload or {}
    u.payload.fuel = args.fuel
    return { ok = true, id = u.unitId, name = u.name, fuel = u.payload.fuel }
end

-- unit_set_gun — set u.payload.gun (ammo percent, 0-100).
function M.unit_set_gun(args)
    local ctx, err = _check_air_unit('unit_set_gun', args)
    if not ctx then return { ok = false, error = err } end
    if type(args.percent) ~= 'number' or args.percent < 0 or args.percent > 100 then
        return { ok = false, error = 'unit_set_gun requires args.percent (0-100)' }
    end
    local u = ctx.unit
    u.payload = u.payload or {}
    u.payload.gun = args.percent
    return { ok = true, id = u.unitId, name = u.name, gun = u.payload.gun }
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

-- zone_set_link — link a trigger zone to a unit (so the zone's center
-- follows the unit), or clear an existing link.
--
-- Wraps Mission.linkTriggerZone / Mission.unlinkTriggerZone (the
-- high-level wrappers used by the ME's panel UI), NOT the lower-level
-- TZD.linkToUnit directly. The wrappers do TWO things on link:
--   1. TriggerZoneController.linkToUnit(zid, uid) — sets the zone's
--      linkUnitId, captures local coords, captures heading.
--   2. table.insert(unit.linkChildrenTZone, zid) — back-reference on
--      the unit so the unit's drag/move handlers (in me_map_window,
--      me_aircraft, me_ship, me_vehicle, me_static) know to refresh
--      this zone's position when the unit moves.
--
-- Calling only step 1 (the bare TZD function) leaves the link visible
-- in the LINK UNIT dropdown and persisted to .miz, but the zone won't
-- move with the unit in the live ME view — save+reload "fixes" it
-- because load reconstructs linkChildrenTZone from the zone's stored
-- linkUnitId, but in-session drag is broken without the back-ref.
--
-- args (zone selector — required): name | id (mutually exclusive)
-- args (action — exactly one required):
--   unit:     string  — link to unit by name
--   unit_id:  number  — link to unit by id
--   clear:    true    — remove the link
function M.zone_set_link(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'zone_set_link requires args (table)' }
    end
    local has_name = type(args.name) == 'string' and args.name ~= ''
    local has_id = type(args.id) == 'number'
    if has_name == has_id then
        return { ok = false, error = 'zone_set_link requires exactly one of args.name or args.id' }
    end

    local has_unit = type(args.unit) == 'string' and args.unit ~= ''
    local has_unit_id = type(args.unit_id) == 'number'
    local has_clear = (args.clear == true)
    local action_count = (has_unit and 1 or 0) + (has_unit_id and 1 or 0) + (has_clear and 1 or 0)
    if action_count ~= 1 then
        return { ok = false,
                 error = 'zone_set_link requires exactly one of args.unit, args.unit_id, or args.clear=true' }
    end

    local zid, zname = find_zone(has_name and args.name or nil, has_id and args.id or nil)
    if not zid then
        return { ok = false, error = 'zone not found' }
    end

    local Mission = require('me_mission')

    if has_clear then
        if type(Mission.unlinkTriggerZone) ~= 'function' then
            return { ok = false, error = 'Mission.unlinkTriggerZone unavailable' }
        end
        local ok_call, err = pcall(Mission.unlinkTriggerZone, zid)
        if not ok_call then
            return { ok = false, error = 'unlinkTriggerZone: ' .. tostring(err) }
        end
        return { ok = true, id = zid, name = zname, cleared = true }
    end

    -- Resolve target unit.
    local u = find_unit_in_mission(has_unit and args.unit or nil,
                                   has_unit_id and args.unit_id or nil)
    if not u then
        return { ok = false, error = 'unit not found' }
    end

    if type(Mission.linkTriggerZone) ~= 'function' then
        return { ok = false, error = 'Mission.linkTriggerZone unavailable' }
    end

    -- linkTriggerZone tolerates re-linking but doesn't dedupe the
    -- linkChildrenTZone back-reference list — calling it twice on the
    -- same (zone, unit) pair would push the zoneId in twice. Defensively
    -- unlink first if the zone is currently linked.
    if type(Mission.unlinkTriggerZone) == 'function' then
        local TZD = require('Mission.TriggerZoneData')
        if type(TZD.getLinkUnitId) == 'function' and TZD.getLinkUnitId(zid) then
            pcall(Mission.unlinkTriggerZone, zid)
        end
    end

    local ok_call, err = pcall(Mission.linkTriggerZone, zid, u.unitId)
    if not ok_call then
        return { ok = false, error = 'linkTriggerZone: ' .. tostring(err) }
    end

    return {
        ok = true,
        id = zid,
        name = zname,
        unit_id = u.unitId,
        unit_name = u.name,
    }
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
-- Drawings — shared helpers + read-side
-- ============================================================
--
-- Drawings live in mission.drawings under a layered structure: the ME has
-- 5 layers (Red / Blue / Neutral / Common / Author) and each layer carries
-- a list of objects. Each object has a primitiveType (Line / Polygon /
-- TextBox / Icon) plus shape-specific fields. Polygon further splits into
-- 5 sub-modes (circle / oval / rect / free / arrow) — 9 distinct shapes
-- in total counting Line's segments / segment / free sub-modes.
--
-- The me_draw_panel module exposes saveToMission / loadFromMission as the
-- canonical IO pair, plus getObjects / objectDelete for read/destroy. It
-- does NOT expose objectAdd / layers_, so to inject a new drawing we go
-- through a save → modify → reload cycle:
--
--   data = panel.saveToMission()    -- current state
--   table.insert(data.layers[k].objects, new_object)
--   panel.loadFromMission(data)     -- resets and rebuilds with new state
--
-- Round-trip-tested against save+full-DCS-reload during the probe phase
-- (the injected circle survived). One-shot reset+rebuild is fine for
-- ME-time editing — drawings are at most a few dozen objects per mission.

-- mutate_drawing — modify an existing drawing in place. Routes through
-- the same saveToMission → modify → loadFromMission cycle as
-- inject_drawing because the panel doesn't expose any granular
-- mutation hook. fn is called with the on-disk shape of the matching
-- object (saveToMission's flat shape — every field is writable here)
-- and any mutation it does is persisted on the loadFromMission
-- rebuild. Returns the mutated object on success, or nil + error on
-- not-found / fn-error.
local function mutate_drawing(name, fn)
    local panel = require('me_draw_panel')
    local data = panel.saveToMission()
    local found
    for _, layer in ipairs(data.layers or {}) do
        for _, obj_save in ipairs(layer.objects or {}) do
            if obj_save.name == name then
                local ok, err = pcall(fn, obj_save)
                if not ok then return nil, 'mutate fn: ' .. tostring(err) end
                found = obj_save
                break
            end
        end
        if found then break end
    end
    if not found then return nil, 'drawing not found' end
    local ok_call, err = pcall(panel.loadFromMission, data)
    if not ok_call then return nil, 'loadFromMission: ' .. tostring(err) end
    return found, nil
end

-- inject_drawing — add a single drawing object to a named layer using
-- the panel's saveToMission/loadFromMission cycle. The new object must
-- carry all required fields for its primitiveType (lineLoad /
-- polygonCircleLoad / etc. expect specific shapes — see saveToMission's
-- per-shape savers for the exact field set).
local function inject_drawing(new_object, layer_name)
    local panel = require('me_draw_panel')
    local data = panel.saveToMission()
    layer_name = layer_name or 'Common'

    local target_layer
    for _, layer in ipairs(data.layers or {}) do
        if layer.name == layer_name then target_layer = layer; break end
    end
    if not target_layer then
        return nil, 'unknown layer: ' .. tostring(layer_name)
            .. ' (valid: Red, Blue, Neutral, Common, Author)'
    end

    new_object.layerName = layer_name
    table.insert(target_layer.objects, new_object)

    local ok_call, err = pcall(panel.loadFromMission, data)
    if not ok_call then
        return nil, 'loadFromMission: ' .. tostring(err)
    end
    return new_object, nil
end

-- find_drawing_by_name — return the live drawing object (with its
-- primitiveType, mapData, etc.) by name. Walks all layers via
-- panel.getObjects() which produces a name → object map. Returns nil if
-- not found.
local function find_drawing_by_name(name)
    local panel = require('me_draw_panel')
    local objs = panel.getObjects()
    return objs[name]
end

-- unique_drawing_name — allocate the next free name with the given
-- prefix. Walks existing drawings; if "Circle-1" through "Circle-N" are
-- in use, returns "Circle-(N+1)". Mirrors the ME's own "Line-1" /
-- "Polygon-1" / "Text Box-1" / "Icon-1" naming but lets us pick the
-- prefix per shape for clarity.
local function unique_drawing_name(prefix)
    local panel = require('me_draw_panel')
    local objs = panel.getObjects()
    local n = 0
    repeat
        n = n + 1
    until objs[prefix .. '-' .. n] == nil
    return prefix .. '-' .. n
end

-- summarize_drawing — concise list-row shape (matches the convention used
-- by group_list / zone_list — translated north / east, the underlying
-- type, and the shape-defining field where relevant).
local function summarize_drawing(obj)
    local mode = obj.polygonMode or obj.lineMode
    return {
        name = obj.name,
        type = obj.primitiveType,
        mode = mode,
        layer = obj.layerName,
        north = obj.mapData and obj.mapData.x,
        east = obj.mapData and obj.mapData.y,
        color = obj.colorString,
        fill_color = obj.fillColorString,
        visible = obj.visible,
        hidden_on_planner = obj.hiddenOnPlanner,
    }
end

-- drawing_list — concise per-drawing summaries from all layers.
--
-- args (all optional):
--   layer:  Red | Blue | Neutral | Common | Author  (exact match)
--   type:   Line | Polygon | TextBox | Icon          (exact match)
--   mode:   circle | oval | rect | free | arrow | segments | segment
--   name:   substring (case-insensitive)
function M.drawing_list(args)
    args = args or {}
    local f_layer = args.layer
    local f_type = args.type
    local f_mode = args.mode and string.lower(args.mode) or nil
    local f_name = args.name and string.lower(args.name) or nil

    local panel = require('me_draw_panel')
    local out = {}
    for name, obj in pairs(panel.getObjects()) do
        local mode = obj.polygonMode or obj.lineMode
        if not (f_layer and obj.layerName ~= f_layer)
                and not (f_type and obj.primitiveType ~= f_type)
                and not (f_mode and (not mode or string.lower(mode) ~= f_mode))
                and not (f_name and not string.find(string.lower(name), f_name, 1, true)) then
            table.insert(out, summarize_drawing(obj))
        end
    end
    -- Stable order by name so the CLI output is repeatable.
    table.sort(out, function(a, b) return (a.name or '') < (b.name or '') end)
    return { ok = true, drawings = out, count = #out }
end

-- drawing_get — full structure of a single drawing by name.
-- Returns the on-disk (saveToMission) shape rather than the runtime
-- object, because per-shape fields live in different places at runtime:
--   * Polygon shapes: radius / width / height / r1 / r2 / length live
--     at the object level (good for runtime but on-disk too).
--   * TextBox: text / fontSize / borderThickness / font / angle live in
--     mapData only — runtime object doesn't promote them.
--   * Icon: file / scale / angle live both in mapData and object.
-- The on-disk shape unifies these — saveToMission's per-shape savers
-- produce a flat object with every field needed to round-trip the
-- drawing through loadFromMission. Use that as the canonical writable
-- surface, plus translated north / east at the top level.
function M.drawing_get(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_get requires args.name (string)' }
    end
    local panel = require('me_draw_panel')
    local data = panel.saveToMission()
    for _, layer in ipairs(data.layers or {}) do
        for _, obj_save in ipairs(layer.objects or {}) do
            if obj_save.name == args.name then
                local snapshot = {}
                for k, v in pairs(obj_save) do snapshot[k] = v end
                -- Surface position in our --north/--east convention at top
                -- level (matches the get-verb shape used elsewhere).
                snapshot.north = obj_save.mapX
                snapshot.east = obj_save.mapY
                return { ok = true, drawing = snapshot }
            end
        end
    end
    return { ok = false, error = 'drawing not found' }
end

-- drawing_remove — remove a drawing by name. Wraps panel.objectDelete.
function M.drawing_remove(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_remove requires args.name (string)' }
    end
    local panel = require('me_draw_panel')
    local obj = panel.getObjects()[args.name]
    if not obj then
        return { ok = false, error = 'drawing not found' }
    end
    local ok_call, err = pcall(panel.objectDelete, obj)
    if not ok_call then
        return { ok = false, error = 'objectDelete: ' .. tostring(err) }
    end
    return { ok = true, name = args.name }
end

-- ============================================================
-- Drawings — create-* verbs
-- ============================================================
--
-- Each builds the right on-disk shape (per saveToMission's per-shape
-- savers in me_draw_panel.lua) and routes through inject_drawing.
--
-- Common fields every shape needs:
--   primitiveType  Line | Polygon | TextBox | Icon
--   name           unique across all layers (verifyName enforces)
--   colorString    '0xRRGGBBAA' (outline color)
--   mapX, mapY     world coords (mission-table x = N–S, y = E–W)
--   visible        bool
--   layerName      Red | Blue | Neutral | Common | Author
--   hiddenOnPlanner  bool
--
-- Polygon adds: polygonMode (circle/oval/rect/free/arrow), style,
-- thickness, fillColorString, plus mode-specific shape fields.
-- Line adds:    lineMode (segments/segment/free), style, thickness,
--               closed, points (relative to mapX/mapY).
-- TextBox adds: text, font, fontSize, borderThickness, angle.
-- Icon adds:    file (relative to icons folder), scale, angle.

-- DEFAULT_LINE_STYLE / DEFAULT_THICKNESS — match the panel's own
-- newPrimitiveInfo_ defaults at me_draw_panel.lua:157. lineStyles_ holds
-- per-style canonical thickness; without a panel hook we hard-code
-- 'solid' = 2 which matches ED's polyline_solid.png pixel height.
local DEFAULT_LINE_STYLE = 'solid'
local DEFAULT_THICKNESS = 2

-- drawing_create_circle — disk-shape polygon (filled disc with outline).
--
-- args (required):
--   north, east   meters; center of the circle
--   radius        meters
--
-- args (optional):
--   name             default 'Circle-N' (auto-incremented)
--   color            '0xRRGGBBAA' (outline; default red, opaque)
--   fill_color       '0xRRGGBBAA' (fill;    default red, half-alpha)
--   thickness        outline thickness in pixels (default 2)
--   style            line style: solid / dot / dash / boundry1 ... (default 'solid')
--   layer            Red | Blue | Neutral | Common | Author (default 'Common')
--   hidden_on_planner   bool (default false)
function M.drawing_create_circle(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_circle requires args (table)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'drawing_create_circle requires args.north and args.east (numbers, meters)' }
    end
    if type(args.radius) ~= 'number' or args.radius <= 0 then
        return { ok = false, error = 'drawing_create_circle requires args.radius (positive number, meters)' }
    end

    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Circle')
    local obj = {
        primitiveType = 'Polygon',
        polygonMode = 'circle',
        name = name,
        colorString = args.color or '0xff0000ff',
        fillColorString = args.fill_color or '0xff000080',
        mapX = args.north, mapY = args.east,
        visible = true,
        hiddenOnPlanner = (args.hidden_on_planner == true),
        style = args.style or DEFAULT_LINE_STYLE,
        thickness = args.thickness or DEFAULT_THICKNESS,
        radius = args.radius,
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'Polygon', mode = 'circle',
             north = args.north, east = args.east, radius = args.radius,
             layer = args.layer or 'Common' }
end

-- drawing_create_rect — axis-aligned rectangle (or rotated, via --angle).
-- args (required): north, east, width, height
-- args (optional): name, color, fill_color, thickness, style, layer,
--                  hidden_on_planner, angle (radians, default 0)
function M.drawing_create_rect(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_rect requires args (table)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'drawing_create_rect requires args.north and args.east (numbers, meters)' }
    end
    if type(args.width) ~= 'number' or args.width <= 0
            or type(args.height) ~= 'number' or args.height <= 0 then
        return { ok = false, error = 'drawing_create_rect requires args.width and args.height (positive numbers, meters)' }
    end
    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Rect')
    -- IMPORTANT: drawing `angle` is stored in DEGREES, not radians. The ME's
    -- own draw panel reads/writes mapData.angle as a 0..360 integer
    -- (objectUpdateSpinBoxAngle at me_draw_panel.lua:558 clamps to that
    -- range with math.floor(angle + 0.5)) — this is opposite to unit/group
    -- heading which IS radians. Don't math.rad it.
    local angle = args.angle_deg or 0
    local obj = {
        primitiveType = 'Polygon', polygonMode = 'rect', name = name,
        colorString = args.color or '0xff0000ff',
        fillColorString = args.fill_color or '0xff000080',
        mapX = args.north, mapY = args.east,
        visible = true, hiddenOnPlanner = (args.hidden_on_planner == true),
        style = args.style or DEFAULT_LINE_STYLE,
        thickness = args.thickness or DEFAULT_THICKNESS,
        width = args.width, height = args.height,
        angle = angle,
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'Polygon', mode = 'rect',
             north = args.north, east = args.east,
             width = args.width, height = args.height, angle = angle,
             layer = args.layer or 'Common' }
end

-- drawing_create_oval — ellipse with semi-axes r1 (along local X) and r2.
-- args (required): north, east, r1, r2
-- args (optional): name, color, fill_color, thickness, style, layer,
--                  hidden_on_planner, angle (radians, default 0)
function M.drawing_create_oval(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_oval requires args (table)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'drawing_create_oval requires args.north and args.east (numbers, meters)' }
    end
    if type(args.r1) ~= 'number' or args.r1 <= 0
            or type(args.r2) ~= 'number' or args.r2 <= 0 then
        return { ok = false, error = 'drawing_create_oval requires args.r1 and args.r2 (positive numbers, meters)' }
    end
    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Oval')
    -- See drawing_create_rect for why angle is degrees, not radians.
    local angle = args.angle_deg or 0
    local obj = {
        primitiveType = 'Polygon', polygonMode = 'oval', name = name,
        colorString = args.color or '0xff0000ff',
        fillColorString = args.fill_color or '0xff000080',
        mapX = args.north, mapY = args.east,
        visible = true, hiddenOnPlanner = (args.hidden_on_planner == true),
        style = args.style or DEFAULT_LINE_STYLE,
        thickness = args.thickness or DEFAULT_THICKNESS,
        r1 = args.r1, r2 = args.r2,
        angle = angle,
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'Polygon', mode = 'oval',
             north = args.north, east = args.east,
             r1 = args.r1, r2 = args.r2, angle = angle,
             layer = args.layer or 'Common' }
end

-- drawing_create_arrow — arrow-shape polygon. The shape's body points are
-- generated by polygonArrowMakePoints(length) at load time, so we don't
-- have to compute them — providing length + angle is enough. The
-- saveToMission output stores points (the runtime values), but they're
-- regenerated from length on load, so any value here is overwritten.
--
-- args (required): north, east, length
-- args (optional): name, color, fill_color, thickness, style, layer,
--                  hidden_on_planner, angle (radians, default 0)
function M.drawing_create_arrow(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_arrow requires args (table)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'drawing_create_arrow requires args.north and args.east (numbers, meters)' }
    end
    if type(args.length) ~= 'number' or args.length <= 0 then
        return { ok = false, error = 'drawing_create_arrow requires args.length (positive number, meters)' }
    end
    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Arrow')
    -- See drawing_create_rect for why angle is degrees, not radians.
    local angle = args.angle_deg or 0
    local obj = {
        primitiveType = 'Polygon', polygonMode = 'arrow', name = name,
        colorString = args.color or '0xff0000ff',
        fillColorString = args.fill_color or '0xff000080',
        mapX = args.north, mapY = args.east,
        visible = true, hiddenOnPlanner = (args.hidden_on_planner == true),
        style = args.style or DEFAULT_LINE_STYLE,
        thickness = args.thickness or DEFAULT_THICKNESS,
        length = args.length,
        angle = angle,
        -- points field is required by saveToMission but regenerated on
        -- load via polygonArrowMakePoints(length). Empty placeholder.
        points = {},
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'Polygon', mode = 'arrow',
             north = args.north, east = args.east, length = args.length,
             angle = angle, layer = args.layer or 'Common' }
end

-- compute_center_and_relative_points — shared helper for line and free
-- polygon. Takes a list of {north, east} absolute world coords and
-- returns center (mapX, mapY) + relative points table {{x, y}, ...}
-- where (x, y) is each vertex's offset from the center. Same convention
-- as zone_create_quad uses internally.
local function compute_center_and_relative_points(vertices)
    local cx, cy = 0, 0
    for _, v in ipairs(vertices) do
        cx = cx + v.north; cy = cy + v.east
    end
    cx = cx / #vertices; cy = cy / #vertices
    local rel = {}
    for _, v in ipairs(vertices) do
        table.insert(rel, { x = v.north - cx, y = v.east - cy })
    end
    return cx, cy, rel
end

-- drawing_create_line — multi-segment line / polyline.
--
-- args (required):
--   vertices  list of { north, east } in absolute world meters (>= 2)
--
-- args (optional):
--   name, color, thickness, style, layer, hidden_on_planner
--   closed     bool (default false; closes the polyline back to first vertex)
--   line_mode  segments | segment | free  (default 'segments')
function M.drawing_create_line(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_line requires args (table)' }
    end
    if type(args.vertices) ~= 'table' or #args.vertices < 2 then
        return { ok = false, error = 'drawing_create_line requires args.vertices (>= 2 {north,east} pairs)' }
    end
    for i, v in ipairs(args.vertices) do
        if type(v) ~= 'table' or type(v.north) ~= 'number' or type(v.east) ~= 'number' then
            return { ok = false, error = 'vertex ' .. i .. ' missing/invalid {north, east} numbers' }
        end
    end

    local cx, cy, rel = compute_center_and_relative_points(args.vertices)
    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Line')

    local obj = {
        primitiveType = 'Line',
        name = name,
        colorString = args.color or '0xff0000ff',
        mapX = cx, mapY = cy,
        visible = true,
        hiddenOnPlanner = (args.hidden_on_planner == true),
        lineMode = args.line_mode or 'segments',
        style = args.style or DEFAULT_LINE_STYLE,
        thickness = args.thickness or DEFAULT_THICKNESS,
        closed = (args.closed == true),
        points = rel,
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'Line', mode = obj.lineMode,
             north = cx, east = cy, vertex_count = #rel,
             closed = obj.closed, layer = args.layer or 'Common' }
end

-- drawing_create_polygon — free-shape polygon (closed, filled).
--
-- DCS's free-polygon renderer auto-connects the last vertex back to the
-- first to close the shape. Sub-pixel artifacts on the closing edge
-- have been reported when the agent supplies "exactly the right number
-- of distinct vertices" — e.g. a 5-point star drawn as 10 alternating
-- outer/inner vertices, where the close-edge from p10 back to p1
-- doesn't render cleanly. Defensively: if the last supplied vertex is
-- not already a copy of the first, we append a duplicate of the first
-- as the closing vertex. Zero-length edge geometrically; better
-- rendering in practice.
--
-- args (required): vertices (>= 3)
-- args (optional): name, color, fill_color, thickness, style, layer,
--                  hidden_on_planner
function M.drawing_create_polygon(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_polygon requires args (table)' }
    end
    if type(args.vertices) ~= 'table' or #args.vertices < 3 then
        return { ok = false, error = 'drawing_create_polygon requires args.vertices (>= 3 {north,east} pairs)' }
    end
    for i, v in ipairs(args.vertices) do
        if type(v) ~= 'table' or type(v.north) ~= 'number' or type(v.east) ~= 'number' then
            return { ok = false, error = 'vertex ' .. i .. ' missing/invalid {north, east} numbers' }
        end
    end

    -- Defensive close: append a duplicate of the first vertex if it
    -- isn't already the last one. See block comment above for why.
    local first = args.vertices[1]
    local last = args.vertices[#args.vertices]
    if first.north ~= last.north or first.east ~= last.east then
        table.insert(args.vertices, { north = first.north, east = first.east })
    end

    local cx, cy, rel = compute_center_and_relative_points(args.vertices)
    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Polygon')

    local obj = {
        primitiveType = 'Polygon', polygonMode = 'free', name = name,
        colorString = args.color or '0xff0000ff',
        fillColorString = args.fill_color or '0xff000080',
        mapX = cx, mapY = cy,
        visible = true,
        hiddenOnPlanner = (args.hidden_on_planner == true),
        style = args.style or DEFAULT_LINE_STYLE,
        thickness = args.thickness or DEFAULT_THICKNESS,
        points = rel,
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'Polygon', mode = 'free',
             north = cx, east = cy, vertex_count = #rel,
             layer = args.layer or 'Common' }
end

-- drawing_create_textbox — text label at a map point.
--
-- args (required):
--   north, east   meters; anchor of the textbox
--   text          string to display
--
-- args (optional):
--   name              default 'Text Box-N'
--   color             text color (default 0x00ff00ff = green opaque)
--   fill_color        background fill (default 0xff000080 = red 50%)
--   font              ttf file name (default 'DejaVuLGCSansCondensed.ttf')
--   font_size         pixels (default 24)
--   border_thickness  pixels (default 4)
--   angle             radians (default 0)
--   layer             default 'Common'
--   hidden_on_planner default false
function M.drawing_create_textbox(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_textbox requires args (table)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'drawing_create_textbox requires args.north and args.east (numbers, meters)' }
    end
    if type(args.text) ~= 'string' or args.text == '' then
        return { ok = false, error = 'drawing_create_textbox requires args.text (non-empty string)' }
    end
    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Text Box')
    -- See drawing_create_rect for why angle is degrees, not radians.
    local angle = args.angle_deg or 0
    local obj = {
        primitiveType = 'TextBox', name = name,
        colorString = args.color or '0x00ff00ff',
        fillColorString = args.fill_color or '0xff000080',
        mapX = args.north, mapY = args.east,
        visible = true, hiddenOnPlanner = (args.hidden_on_planner == true),
        text = args.text,
        font = args.font or 'DejaVuLGCSansCondensed.ttf',
        fontSize = args.font_size or 24,
        borderThickness = args.border_thickness or 4,
        angle = angle,
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'TextBox',
             north = args.north, east = args.east, text = args.text,
             layer = args.layer or 'Common' }
end

-- drawing_create_icon — icon (NATO/Russian symbol or custom png) at a
-- map point. The icon `file` is a filename within the active icon
-- folder ('./MissionEditor/data/NewMap/images/<theme>/' where theme is
-- 'nato' or 'russian' depending on the user's options). User picks
-- which theme, we just store the bare filename.
--
-- args (required):
--   north, east   meters; anchor of the icon
--   file          icon filename (e.g. 'aaa_air_neutral.png')
--
-- args (optional):
--   name, color (tint, default white opaque), scale (default 1),
--   angle (radians, default 0), layer, hidden_on_planner
function M.drawing_create_icon(args)
    if type(args) ~= 'table' then
        return { ok = false, error = 'drawing_create_icon requires args (table)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'drawing_create_icon requires args.north and args.east (numbers, meters)' }
    end
    if type(args.file) ~= 'string' or args.file == '' then
        return { ok = false, error = 'drawing_create_icon requires args.file (icon filename)' }
    end
    local name = (type(args.name) == 'string' and args.name ~= '') and args.name
                 or unique_drawing_name('Icon')
    -- See drawing_create_rect for why angle is degrees, not radians.
    local angle = args.angle_deg or 0
    local obj = {
        primitiveType = 'Icon', name = name,
        colorString = args.color or '0xffffffff',
        mapX = args.north, mapY = args.east,
        visible = true, hiddenOnPlanner = (args.hidden_on_planner == true),
        file = args.file,
        scale = args.scale or 1,
        angle = angle,
    }
    local _, err = inject_drawing(obj, args.layer or 'Common')
    if err then return { ok = false, error = err } end
    return { ok = true, name = name, type = 'Icon',
             north = args.north, east = args.east, file = args.file,
             layer = args.layer or 'Common' }
end

-- ============================================================
-- Drawings — setters (per-field)
-- ============================================================

-- drawing_set_color — change outline / line / text color (the
-- colorString field). For polygons + textboxes this is the OUTLINE /
-- BORDER / TEXT color; the fill is set via drawing_set_fill_color.
-- For lines and icons this is the only color the shape has.
function M.drawing_set_color(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_set_color requires args.name (string)' }
    end
    if type(args.color) ~= 'string' or args.color == '' then
        return { ok = false, error = 'drawing_set_color requires args.color (hex string like 0xrrggbbaa)' }
    end
    local obj, err = mutate_drawing(args.name, function(o) o.colorString = args.color end)
    if err then return { ok = false, error = err } end
    return { ok = true, name = args.name, color = obj.colorString }
end

-- drawing_set_fill_color — change fill color (polygon shapes + textbox
-- only). Refuses on Line / Icon — those have no fill concept.
function M.drawing_set_fill_color(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_set_fill_color requires args.name (string)' }
    end
    if type(args.color) ~= 'string' or args.color == '' then
        return { ok = false, error = 'drawing_set_fill_color requires args.color (hex string like 0xrrggbbaa)' }
    end
    local target = find_drawing_by_name(args.name)
    if not target then return { ok = false, error = 'drawing not found' } end
    if target.primitiveType == 'Line' or target.primitiveType == 'Icon' then
        return { ok = false,
                 error = target.primitiveType .. ' has no fill — use drawing_set_color instead' }
    end
    local obj, err = mutate_drawing(args.name, function(o) o.fillColorString = args.color end)
    if err then return { ok = false, error = err } end
    return { ok = true, name = args.name, fill_color = obj.fillColorString }
end

-- drawing_set_pos — move the drawing's anchor (mapX / mapY). For shapes
-- with relative-to-anchor points (line, free polygon) the relative
-- offsets ride along, so the shape moves rigidly. For analytic shapes
-- (circle, rect, oval, arrow) only the center moves.
function M.drawing_set_pos(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_set_pos requires args.name (string)' }
    end
    if type(args.north) ~= 'number' or type(args.east) ~= 'number' then
        return { ok = false, error = 'drawing_set_pos requires args.north and args.east (numbers, meters)' }
    end
    local obj, err = mutate_drawing(args.name, function(o)
        o.mapX = args.north
        o.mapY = args.east
    end)
    if err then return { ok = false, error = err } end
    return { ok = true, name = args.name, north = obj.mapX, east = obj.mapY }
end

-- drawing_set_name — rename a drawing. Refuses on collision via the
-- panel's verifyName (drawing names are unique across all layers).
function M.drawing_set_name(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_set_name requires args.name (string)' }
    end
    if type(args.new_name) ~= 'string' or args.new_name == '' then
        return { ok = false, error = 'drawing_set_name requires args.new_name (non-empty string)' }
    end
    if args.new_name == args.name then
        return { ok = true, name = args.new_name, unchanged = true }
    end
    if find_drawing_by_name(args.new_name) then
        return { ok = false, error = 'name "' .. args.new_name .. '" already in use' }
    end
    local obj, err = mutate_drawing(args.name, function(o) o.name = args.new_name end)
    if err then return { ok = false, error = err } end
    return { ok = true, name = obj.name, previous_name = args.name }
end

-- drawing_set_text — change the text content of a TextBox. Refuses on
-- non-TextBox drawings.
function M.drawing_set_text(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_set_text requires args.name (string)' }
    end
    if type(args.text) ~= 'string' or args.text == '' then
        return { ok = false, error = 'drawing_set_text requires args.text (non-empty string)' }
    end
    local target = find_drawing_by_name(args.name)
    if not target then return { ok = false, error = 'drawing not found' } end
    if target.primitiveType ~= 'TextBox' then
        return { ok = false, error = 'drawing is ' .. target.primitiveType
                                     .. ', not TextBox; use drawing_remove + drawing_create_textbox' }
    end
    local obj, err = mutate_drawing(args.name, function(o) o.text = args.text end)
    if err then return { ok = false, error = err } end
    return { ok = true, name = args.name, text = obj.text }
end

-- drawing_set_thickness — change outline / line thickness in pixels.
-- Applies to Line and Polygon shapes. Refuses on TextBox (which has
-- borderThickness instead) and Icon (which has scale).
function M.drawing_set_thickness(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_set_thickness requires args.name (string)' }
    end
    if type(args.thickness) ~= 'number' or args.thickness <= 0 then
        return { ok = false, error = 'drawing_set_thickness requires args.thickness (positive number)' }
    end
    local target = find_drawing_by_name(args.name)
    if not target then return { ok = false, error = 'drawing not found' } end
    if target.primitiveType ~= 'Line' and target.primitiveType ~= 'Polygon' then
        return { ok = false, error = target.primitiveType
                                     .. ' has no thickness (TextBox has border-thickness; Icon has scale)' }
    end
    local obj, err = mutate_drawing(args.name, function(o) o.thickness = args.thickness end)
    if err then return { ok = false, error = err } end
    return { ok = true, name = args.name, thickness = obj.thickness }
end

-- drawing_set_angle — rotate a drawing around its anchor.
--
-- Supported shapes (those with an angle field in saveToMission):
--   * TextBox     — rotates the text label
--   * Icon        — rotates the icon image
--   * Polygon oval / rect / arrow — rotates the analytic shape
--
-- Refused shapes:
--   * Line        — no angle field; shape geometry is the points list
--   * Polygon circle  — rotation is meaningless (rotation-symmetric)
--   * Polygon free    — rotation would need to transform every point;
--                       remove + re-create with rotated vertices
--                       (or wait for a future drawing_rotate-points helper)
--
-- Args:
--   name       drawing name (required)
--   angle_deg  rotation in degrees (CW positive). Stored verbatim — the
--              ME's draw panel reads/writes mapData.angle as DEGREES
--              (objectUpdateSpinBoxAngle at me_draw_panel.lua:558 does
--              math.floor(angle + 0.5) clamped [0, 360]). Opposite to
--              unit/group heading which IS radians; ED inconsistency.
function M.drawing_set_angle(args)
    if type(args) ~= 'table' or type(args.name) ~= 'string' or args.name == '' then
        return { ok = false, error = 'drawing_set_angle requires args.name (string)' }
    end
    if type(args.angle_deg) ~= 'number' then
        return { ok = false, error = 'drawing_set_angle requires args.angle_deg (number, degrees)' }
    end
    local target = find_drawing_by_name(args.name)
    if not target then return { ok = false, error = 'drawing not found' } end

    -- Type / mode gate. Only the shapes that have an `angle` field in
    -- saveToMission's per-shape savers can be rotated this way.
    local pt = target.primitiveType
    local mode = target.polygonMode
    local rotatable =
        pt == 'TextBox' or pt == 'Icon'
        or (pt == 'Polygon' and (mode == 'oval' or mode == 'rect' or mode == 'arrow'))
    if not rotatable then
        local descriptor = pt
        if pt == 'Polygon' and mode then descriptor = 'Polygon ' .. mode end
        return { ok = false,
                 error = descriptor .. ' has no rotation; supported: TextBox, Icon, '
                         .. 'Polygon oval/rect/arrow' }
    end

    -- Degrees stored verbatim; no math.rad — see comment above.
    local obj, err = mutate_drawing(args.name, function(o) o.angle = args.angle_deg end)
    if err then return { ok = false, error = err } end
    return { ok = true, name = args.name, angle = obj.angle }
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

-- ============================================================
-- Trigger verbs (mission.trigrules)
-- ============================================================
--
-- mission.trigrules is the editor source-of-truth. Each entry has shape:
--   { predicate = "triggerOnce" | "triggerContinious" | "triggerStart" | "triggerFront",
--     comment   = "<user-facing name>",
--     eventlist = "" | <event id>,
--     rules     = { { predicate = "c_*", ...field args... }, ... },
--     actions   = { { predicate = "a_*", ...field args... }, ... } }
--
-- ED's me_mission.unload regenerates mission.trig.{conditions,actions,func,
-- events,funcStartup} from trigrules at save time (me_mission.lua:4592-4598),
-- so we never touch mission.trig.* directly — only trigrules.

-- _trigger_alias_cache — lazy-built map of every predicate ED knows about,
-- keyed by both canonical name AND friendly kebab-alias. Each value is
-- { canonical=..., kind="condition"|"action"|"trigger", descr=<field-schema> }.
-- Cleared on first call after init; rebuilt only if ED's descriptor tables
-- look like they've shifted (descriptor tables are session-stable in
-- practice — this cache is a perf optimization, not a correctness gate).
local _trigger_alias_cache

-- _trigger_make_alias — strip prefix + underscore→dash to get the friendly
-- form. "c_flag_is_true" → "flag-is-true", "a_set_flag" → "set-flag",
-- "triggerOnce" → "once", "triggerContinious" → "continuous" (fixes typo).
local function _trigger_make_alias(canonical)
    local s = canonical
    if s:sub(1, 2) == 'c_' or s:sub(1, 2) == 'a_' then
        s = s:sub(3)
    elseif s:sub(1, 7) == 'trigger' then
        s = s:sub(8)
        -- Special case: ED's misspelling of "Continuous"
        if s == 'Continious' then return 'continuous' end
    end
    return s:gsub('_', '-'):lower()
end

-- _trigger_build_alias_cache — populate _trigger_alias_cache from ED's
-- predicates.descrs (conditions + actions) and triggersDescr (trigger types).
local function _trigger_build_alias_cache()
    local Trigger = require('me_trigrules')
    local cache = {}
    -- predicates.descrs is a flat name → descr map; descr.kind is not stored
    -- there, so we need to classify by name prefix.
    local pred_table = Trigger.predicates and Trigger.predicates.descrs or {}
    for name, descr in pairs(pred_table) do
        local kind
        if name:sub(1, 2) == 'c_' then kind = 'condition'
        elseif name:sub(1, 2) == 'a_' then kind = 'action'
        else kind = 'unknown' end
        local entry = { canonical = name, kind = kind, descr = descr }
        cache[name] = entry
        cache[_trigger_make_alias(name)] = entry
    end
    -- Trigger types live in triggersDescr (an array of {name=..., fields=...}).
    for _, tdescr in ipairs(Trigger.triggersDescr or {}) do
        if type(tdescr) == 'table' and type(tdescr.name) == 'string' then
            local entry = { canonical = tdescr.name, kind = 'trigger', descr = tdescr }
            cache[tdescr.name] = entry
            cache[_trigger_make_alias(tdescr.name)] = entry
        end
    end
    _trigger_alias_cache = cache
end

-- _trigger_resolve_predicate — name-or-alias → canonical_name, kind, descr,
-- err. Optionally filter by kind ("condition" / "action" / "trigger") to
-- disambiguate — passing kind=nil accepts any.
local function _trigger_resolve_predicate(name_or_alias, expected_kind)
    if not _trigger_alias_cache then _trigger_build_alias_cache() end
    local entry = _trigger_alias_cache[name_or_alias]
    if not entry then
        return nil, nil, nil, 'unknown predicate "' .. tostring(name_or_alias) .. '"'
    end
    if expected_kind and entry.kind ~= expected_kind then
        return nil, nil, nil,
               'predicate "' .. name_or_alias .. '" is a ' .. entry.kind
               .. ', expected ' .. expected_kind
    end
    return entry.canonical, entry.kind, entry.descr, nil
end

-- _trigger_panel_visible — set/cleared by the monkey-patched Trigger.show
-- below. Local to this module; queried only by _trigger_panel_refresh().
local _trigger_panel_visible = false
local _trigger_show_patched = false

-- _trigger_install_show_hook — wrap Trigger.show once per session so we
-- track panel visibility. Idempotent: subsequent calls are no-ops.
local function _trigger_install_show_hook()
    if _trigger_show_patched then return end
    local Trigger = require('me_trigrules')
    if type(Trigger) ~= 'table' or type(Trigger.show) ~= 'function' then
        return  -- ME not fully loaded; try again next call
    end
    local orig = Trigger.show
    Trigger.show = function(b)
        _trigger_panel_visible = (b == true)
        return orig(b)
    end
    _trigger_show_patched = true
end

-- _trigger_panel_refresh — best-effort kick: if the panel is currently
-- visible, call show(false) + show(true) to re-bind the listbox to current
-- mission.trigrules (matches saveTriggers/setupCallbacks rebind path).
local function _trigger_panel_refresh()
    _trigger_install_show_hook()
    if not _trigger_panel_visible then return end
    local Trigger = require('me_trigrules')
    pcall(Trigger.show, false)
    pcall(Trigger.show, true)
end

-- _trigger_find_by_name — locate a trigger in mission.trigrules by its
-- comment field. Returns trigger, index_1based, total_count or nil.
local function _trigger_find_by_name(name)
    local Mission = require('me_mission')
    local mission = Mission.mission
    if type(mission) ~= 'table' or type(mission.trigrules) ~= 'table' then
        return nil, nil, 0
    end
    for i, t in ipairs(mission.trigrules) do
        if type(t) == 'table' and t.comment == name then
            return t, i, #mission.trigrules
        end
    end
    return nil, nil, #mission.trigrules
end

-- _trigger_unique_name — auto-suffix "-2", "-3", ... on collision (matches
-- the existing me group create-* collision behavior).
local function _trigger_unique_name(base)
    if not _trigger_find_by_name(base) then return base end
    local n = 2
    while _trigger_find_by_name(base .. '-' .. n) do n = n + 1 end
    return base .. '-' .. n
end

-- _trigger_default_name — ED's default when the user hits "new trigger" in
-- the panel: "Trigger " .. os.time(). We mirror it for parity.
local function _trigger_default_name()
    return 'Trigger ' .. tostring(os.time())
end

-- _trigger_field_combo_kind — classify a field's reference kind by its
-- comboFunc slot. Returns "group" / "unit" / "zone" / "coalition" /
-- "airdrome" / "event" / nil (literal field, no resolution).
local function _trigger_field_combo_kind(field_descr)
    if type(field_descr) ~= 'table' or field_descr.type ~= 'combo' then
        return nil
    end
    local fn = field_descr.comboFunc
    -- comboFunc is a function reference; we identify it by introspecting
    -- the function's environment / debug info isn't reliable in DCS Lua.
    -- Instead, ED stores friendly listers as named globals in me_trigrules
    -- — match by reference equality against the known set.
    local Trigger = require('me_trigrules')
    if fn == Trigger.groupsLister
            or fn == Trigger.groupsStaticLister
            or fn == Trigger.groupsAirLister then
        return 'group'
    end
    if fn == Trigger.unitsLister or fn == Trigger.unitsAirLister then
        return 'unit'
    end
    if fn == Trigger.zoneLister or fn == Trigger.triggerZoneLister then
        return 'zone'
    end
    if fn == Trigger.coalitionLister or fn == Trigger.coalition2Lister
            or fn == Trigger.winnerLister then
        return 'coalition'
    end
    if fn == Trigger.airdromeAndHeliportLister then return 'airdrome' end
    if fn == Trigger.eventLister then return 'event' end
    return nil
end

-- _trigger_resolve_ref — value normalization for reference fields. If kind
-- is group/unit/zone, accept either an integer id or a name (string) and
-- return the integer id. For coalition, pass through. For other kinds,
-- pass through. Returns resolved_value, err.
local function _trigger_resolve_ref(kind, value)
    if kind == 'coalition' or kind == 'event' or kind == nil then
        return value, nil
    end
    -- integer-or-numeric-string → treat as id
    local as_num = tonumber(value)
    if as_num and as_num == math.floor(as_num) then
        return as_num, nil
    end
    if type(value) ~= 'string' then
        return nil, 'expected integer or name string for ' .. kind .. ' reference'
    end
    if kind == 'group' then
        local Mission = require('me_mission')
        local g = Mission.group_by_name and Mission.group_by_name[value]
        if g then return g.groupId, nil end
        return nil, 'no group named "' .. value .. '"'
    elseif kind == 'unit' then
        local Mission = require('me_mission')
        local u = Mission.unit_by_name and Mission.unit_by_name[value]
        if u then return u.unitId, nil end
        return nil, 'no unit named "' .. value .. '"'
    elseif kind == 'zone' then
        local Mission = require('me_mission')
        local mission = Mission.mission
        if type(mission) == 'table' and type(mission.triggers) == 'table'
                and type(mission.triggers.zones) == 'table' then
            for _, z in ipairs(mission.triggers.zones) do
                if z.name == value then return z.zoneId, nil end
            end
        end
        return nil, 'no zone named "' .. value .. '"'
    elseif kind == 'airdrome' then
        return nil, 'airdrome reference by name not supported in v1; pass integer id'
    end
    return value, nil
end

-- _trigger_coerce_value — string from CLI → typed Lua value per descriptor.
-- For "edit" fields the descriptor may not say what the type should be, so
-- we infer: "true"/"false" → bool, parseable → number, else string. Array
-- values use comma-separated form (descriptor signals via field.type or
-- by the field having a known multi-int shape like typebomb/typemissile).
local function _trigger_coerce_value(field_descr, value)
    if type(field_descr) ~= 'table' then return value end
    -- known array-of-int fields per ED's trigger schema
    local id = field_descr.id
    if id == 'typebomb' or id == 'typemissile' or id == 'typemlrs' then
        local out = {}
        for piece in tostring(value):gmatch('[^,]+') do
            local n = tonumber(piece)
            if not n then return nil end
            table.insert(out, n)
        end
        return out
    end
    if value == 'true' then return true end
    if value == 'false' then return false end
    local n = tonumber(value)
    if n ~= nil then return n end
    return tostring(value)
end

-- _trigger_field_descr — find a single field descriptor by id within a
-- predicate's descr.fields list (or descr.fields under triggersDescr).
local function _trigger_field_descr(descr, field_id)
    if type(descr) ~= 'table' or type(descr.fields) ~= 'table' then return nil end
    for _, f in ipairs(descr.fields) do
        if type(f) == 'table' and f.id == field_id then return f end
    end
    return nil
end

-- _trigger_apply_fields — walk the user-supplied fields table, validate
-- each against descr, coerce types, resolve references, allocate dict
-- keys for text fields (those with a KeyDict_<id> companion). Mutates
-- entry in place. Returns ok, err.
local function _trigger_apply_fields(entry, descr, fields)
    if type(fields) ~= 'table' then return true, nil end
    local ok_dict, dictionary = pcall(require, 'dictionary')
    for k, v in pairs(fields) do
        local fd = _trigger_field_descr(descr, k)
        if not fd then
            return false, 'unknown field "' .. tostring(k) .. '" for predicate "'
                          .. tostring(descr and descr.name or '?') .. '"'
        end
        local coerced = _trigger_coerce_value(fd, v)
        if coerced == nil then
            return false, 'invalid value for field "' .. tostring(k) .. '"'
        end
        local kind = _trigger_field_combo_kind(fd)
        local resolved, ref_err = _trigger_resolve_ref(kind, coerced)
        if ref_err then return false, ref_err end
        -- Dictionary handling: descriptor flags text fields by having a
        -- companion id "KeyDict_<id>" elsewhere in descr.fields.
        local keydict_id = 'KeyDict_' .. k
        if _trigger_field_descr(descr, keydict_id) and type(resolved) == 'string'
                and resolved:sub(1, 8) ~= 'DictKey_' and ok_dict
                and type(dictionary.fixDict) == 'function' then
            -- fixDict allocates a new key, sets the value, and writes both
            -- entry[k] and entry[keydict_id] = the new key.
            pcall(dictionary.fixDict, entry, k, resolved, k)
        else
            entry[k] = resolved
        end
    end
    return true, nil
end

-- _trigger_resolve_for_get — reverse of fixDict: given an entry from a
-- trigrules trigger / rule / action, return a flat fields table with
-- DictKey_* references resolved back to literal strings, and reference
-- ids accompanied by *_name fields where resolvable. Skips the
-- KeyDict_* companions (they're internal indirection). If raw=true,
-- returns the entry verbatim instead.
local function _trigger_resolve_for_get(entry, descr, raw)
    local out = {}
    if type(entry) ~= 'table' then return out end
    if raw then
        for k, v in pairs(entry) do out[k] = v end
        return out
    end
    local ok_dict, dictionary = pcall(require, 'dictionary')
    for k, v in pairs(entry) do
        if k == 'predicate' then
            -- skip — emitted separately at the caller's level
        elseif k:sub(1, 8) == 'KeyDict_' then
            -- skip companion
        elseif type(v) == 'string' and v:sub(1, 8) == 'DictKey_'
                and ok_dict and type(dictionary.getValueDict) == 'function' then
            local literal = dictionary.getValueDict(v)
            out[k] = literal or v
        else
            out[k] = v
            -- enrichment for reference fields
            local fd = _trigger_field_descr(descr, k)
            local kind = fd and _trigger_field_combo_kind(fd)
            if kind == 'group' and type(v) == 'number' then
                local Mission = require('me_mission')
                if Mission.group_by_id and Mission.group_by_id[v] then
                    out[k .. '_name'] = Mission.group_by_id[v].name
                end
            elseif kind == 'unit' and type(v) == 'number' then
                local Mission = require('me_mission')
                if Mission.unit_by_id and Mission.unit_by_id[v] then
                    out[k .. '_name'] = Mission.unit_by_id[v].name
                end
            elseif kind == 'zone' and type(v) == 'number' then
                local Mission = require('me_mission')
                local mission = Mission.mission
                if type(mission) == 'table' and type(mission.triggers) == 'table'
                        and type(mission.triggers.zones) == 'table' then
                    for _, z in ipairs(mission.triggers.zones) do
                        if z.zoneId == v then out[k .. '_name'] = z.name; break end
                    end
                end
            end
        end
    end
    return out
end

-- _trigger_ensure_trigrules — make sure mission.trigrules exists; create
-- an empty array if not. Mirrors ED's me_trigrules.show() init guard.
local function _trigger_ensure_trigrules()
    local Mission = require('me_mission')
    local mission = Mission.mission
    if type(mission) ~= 'table' then return nil, 'no mission loaded' end
    if type(mission.trigrules) ~= 'table' then mission.trigrules = {} end
    return mission.trigrules, nil
end

-- _trigger_friendly_type — canonical "triggerOnce" / "triggerContinious" /
-- ... → friendly alias ("once" / "continuous" / ...).
local function _trigger_friendly_type(canonical)
    return _trigger_make_alias(canonical or '')
end

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
