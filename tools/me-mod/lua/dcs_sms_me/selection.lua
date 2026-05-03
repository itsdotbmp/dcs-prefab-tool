-- selection.lua — ME selection-state lookup.
--
-- This is the only file that touches ME-internal globals. Every external
-- call is wrapped in pcall so a DCS patch breaking these APIs degrades to
-- {ok=false, error=...} instead of crashing the user's editor session.
--
-- Public:
--   M.snapshot() → {
--     ok            = boolean,
--     error         = string?,
--     timestamp_utc = string,
--     selection_mode = "multi"|"single",
--     groups        = table[],
--     zones         = table[],
--     drawings      = table[],
--     nav_points    = table[],
--     raw           = table,                -- everything ME handed us, verbatim
--   }

local M = {}

-- Lazy requires inside helpers so a missing module fails gracefully via the
-- outer pcall rather than at module-load time.

local function utc_now()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local function empty_snap()
    return {
        groups        = {},
        zones         = {},
        drawings      = {},
        nav_points    = {},
        raw           = {},
    }
end

local function collect_multi()
    local snap = empty_snap()
    snap.selection_mode = 'multi'

    local multiSelection = require('me_multiSelection')
    local Mission        = require('me_mission')

    local objects, err = safe_call(multiSelection.getSelectedObjects)
    if not objects then
        snap.raw.multi_get_objects_error = tostring(err)
        return snap
    end
    snap.raw.multi_get_objects = objects

    -- objects.selectGroups: table keyed by group id → group descriptor (already
    -- a DCS-shaped or ME-shaped table; we pass it through as-is, then also
    -- attempt Mission.getGroup(id) for the canonical raw form).
    if type(objects.selectGroups) == 'table' then
        for id, desc in pairs(objects.selectGroups) do
            local raw_group = safe_call(Mission.getGroup, id)
            snap.groups[#snap.groups + 1] = raw_group or desc
        end
    end
    if type(objects.selectTriggerZones) == 'table' then
        for _, zone in pairs(objects.selectTriggerZones) do
            snap.zones[#snap.zones + 1] = zone
        end
    end
    if type(objects.selectDrawObjects) == 'table' then
        for _, drw in pairs(objects.selectDrawObjects) do
            snap.drawings[#snap.drawings + 1] = drw
        end
    end
    return snap
end

local function collect_single()
    local snap = empty_snap()
    snap.selection_mode = 'single'

    local MapWindow                = require('me_map_window')
    local Mission                  = require('me_mission')
    local MapController            = require('Mission.MapController')
    local MissionData              = require('Mission.Data')
    local TriggerZoneController    = require('Mission.TriggerZoneController')
    local NavigationPointController = require('Mission.NavigationPointController')

    -- Groups (and statics, which the ME models as single-unit groups).
    local groups = safe_call(MapWindow.getSelectedGroups)
    snap.raw.single_get_groups = groups
    if type(groups) == 'table' then
        for id, _ in pairs(groups) do
            local raw_group = safe_call(Mission.getGroup, id)
            if raw_group then snap.groups[#snap.groups + 1] = raw_group end
        end
    end

    -- Single non-group selection (zone, nav point) via MapController.
    local objectId = safe_call(MapController.getSelectedObjectId)
    snap.raw.single_object_id = objectId
    if objectId then
        local kind = safe_call(MissionData.getObjectType, objectId)
        if kind == safe_call(MissionData.triggerZoneType) then
            local zone = safe_call(TriggerZoneController.getTriggerZone, objectId)
            if zone then snap.zones[#snap.zones + 1] = zone end
        elseif kind == safe_call(MissionData.navigationPointType) then
            local np = safe_call(NavigationPointController.getNavigationPoint, objectId)
            if np then snap.nav_points[#snap.nav_points + 1] = np end
        end
    end

    -- Current draw object (panel_draw module).
    local panel_draw = safe_call(require, 'me_draw_panel')
    if panel_draw and panel_draw.getCurrObject then
        local drawObj = safe_call(panel_draw.getCurrObject)
        snap.raw.single_draw_object = drawObj
        if drawObj then snap.drawings[#snap.drawings + 1] = drawObj end
    end

    return snap
end

function M.snapshot()
    local ok, result = pcall(function()
        local multiSelection = require('me_multiSelection')
        if multiSelection.isVisible and multiSelection.isVisible() then
            return collect_multi()
        end
        return collect_single()
    end)
    if not ok then
        local snap = empty_snap()
        snap.ok = false
        snap.error = tostring(result)
        snap.timestamp_utc = utc_now()
        snap.selection_mode = 'unknown'
        return snap
    end
    result.ok = true
    result.timestamp_utc = utc_now()
    return result
end

return M
