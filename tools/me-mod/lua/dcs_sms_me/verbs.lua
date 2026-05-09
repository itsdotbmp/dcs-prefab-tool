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

return M
