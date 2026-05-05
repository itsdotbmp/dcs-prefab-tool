-- ship_warehouse.lua — capture + apply per-ship warehouse entries.
--
-- DCS stores ship/structure warehouses at
-- `mission.AirportsEquipment.warehouses[unitId]` (separate from the
-- airport table, which is keyed by airdromeNumber). The data is the same
-- shape as airport warehouses (coalition + unlimited* + per-fuel
-- InitFuel + aircrafts + weapons + OperatingLevel_*). Coalition strings
-- here are lowercase ("blue"/"red"/"neutral") — that's a DCS convention
-- difference from the airport table, which uses uppercase. We honour it.
--
-- Strategy: the ship is part of the prefab's groups already (it's a
-- normal selectable unit). We attach its warehouse data INLINE on the
-- unit (`unit._sms_warehouse = {...}`) so it rides through serialization
-- and place. After place, we walk the record's group_obj.units, grab the
-- freshly-allocated unitId, and splice into the destination's live
-- warehouses table.

local M = {}

local function safe_require(name)
    local ok, mod = pcall(require, name)
    if ok then return mod end
    return nil
end

local module_mission = safe_require('me_mission')
local warehouse_ops  = require('dcs_sms_me.warehouse_ops')

-- Walk every unit in the prefab's groups + statics and, for any unit
-- whose unitId points at a non-default live warehouse, deep-copy that
-- warehouse onto the unit as `_sms_warehouse`. Returns the number of
-- attachments.
function M.attach_to_prefab(prefab)
    if type(prefab) ~= 'table' then return 0 end
    if not (module_mission and module_mission.mission
            and module_mission.mission.AirportsEquipment
            and module_mission.mission.AirportsEquipment.warehouses) then
        return 0
    end
    local live = module_mission.mission.AirportsEquipment.warehouses
    local n = 0

    local function walk(groups)
        if type(groups) ~= 'table' then return end
        for _, g in ipairs(groups) do
            if type(g) == 'table' and type(g.units) == 'table' then
                for _, u in ipairs(g.units) do
                    if type(u) == 'table' and type(u.unitId) == 'number' then
                        local w = live[u.unitId]
                        if type(w) == 'table' and not warehouse_ops.is_default(w) then
                            u._sms_warehouse = warehouse_ops._deep_copy(w)
                            n = n + 1
                        end
                    end
                end
            end
        end
    end

    walk(prefab.groups)
    walk(prefab.statics)
    return n
end

-- After place, walk the record's placed groups + their units. For each
-- unit carrying _sms_warehouse, splice a deep-copied warehouse into the
-- destination's live warehouses table at the unit's NEW unitId. opts:
--   override_coalition = string?  -- if set ('RED'/'BLUE'/'NEUTRAL'),
--                                  -- written to the ship warehouse
--                                  -- coalition field as lowercase
--                                  -- (DCS uses lowercase here, unlike
--                                  -- airport warehouses).
-- Strips the marker field off the live unit so it doesn't pollute saves.
-- Returns the number of warehouse entries written.
function M.apply_from_record(record, opts)
    if type(record) ~= 'table' or type(record.groups) ~= 'table' then return 0 end
    if not (module_mission and module_mission.mission
            and module_mission.mission.AirportsEquipment) then
        return 0
    end
    local airequip = module_mission.mission.AirportsEquipment
    airequip.warehouses = airequip.warehouses or {}

    local override_lower
    if opts and type(opts.override_coalition) == 'string' then
        override_lower = opts.override_coalition:lower()
    end

    local n = 0
    for _, g in ipairs(record.groups) do
        local group_obj = g.group_obj
        if type(group_obj) == 'table' and type(group_obj.units) == 'table' then
            for _, u in ipairs(group_obj.units) do
                if type(u) == 'table'
                   and type(u._sms_warehouse) == 'table'
                   and type(u.unitId) == 'number' then
                    local w = warehouse_ops._deep_copy(u._sms_warehouse)
                    if override_lower then w.coalition = override_lower end
                    airequip.warehouses[u.unitId] = w
                    u._sms_warehouse = nil  -- don't pollute live data with our marker
                    n = n + 1
                end
            end
        end
    end
    return n
end

return M
