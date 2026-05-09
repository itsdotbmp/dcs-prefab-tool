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

return M
