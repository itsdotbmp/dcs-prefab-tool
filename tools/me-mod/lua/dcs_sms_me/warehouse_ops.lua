-- warehouse_ops.lua — read/write per-airbase warehouse entries.
--
-- The live data lives at `me_mission.mission.AirportsEquipment.airports[N]`
-- where N is the airdromeNumber. We deep-copy on read (so callers can mutate
-- freely) and splice on write (so callbacks attached to the live table fire).
-- Coalition is pushed through AirdromeController.setAirdromeCoalition so the
-- map display refreshes.
--
-- Failure mode: log + return nil. Module loads cleanly even if the DCS
-- modules can't be required (test VM, broken install).

local M = {}

local function safe_require(name)
    local ok, mod = pcall(require, name)
    if ok then return mod end
    return nil
end

local module_mission        = safe_require('me_mission')
-- AirdromeController + CoalitionController are loaded here so M.apply (added in
-- Task 5) can use them without re-requiring per-call. Unused by M.extract /
-- M.is_default — those only need module_mission.
local AirdromeController    = safe_require('Mission.AirdromeController')
local CoalitionController   = safe_require('Mission.CoalitionController')

-- Shallow-copies are tempting but the warehouse table contains nested
-- aircrafts / weapons subtables that the caller will own. Use a real deep
-- copy so subsequent mutations on the result don't leak into live data.
local function deep_copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deep_copy(v) end
    return out
end
M._deep_copy = deep_copy  -- exposed for unit testing

-- Read the airport entry at `airdrome_number` from the live mission data and
-- return a deep copy. nil when the index is out of range or me_mission is
-- unavailable.
function M.extract(airdrome_number)
    if type(airdrome_number) ~= 'number' then return nil end
    if not (module_mission and module_mission.mission
            and module_mission.mission.AirportsEquipment
            and module_mission.mission.AirportsEquipment.airports) then
        return nil
    end
    local entry = module_mission.mission.AirportsEquipment.airports[airdrome_number]
    if type(entry) ~= 'table' then return nil end
    return deep_copy(entry)
end

-- Predicate: returns true iff the user has NOT meaningfully customised this
-- airbase's warehouse. We rely on the three "unlimited" flags as the proxy:
-- the Resource Manager UI requires unchecking these before any of the
-- specific stock controls (per-aircraft initialAmount, per-weapon counts,
-- fuel InitFuel sliders) become editable. So `unlimited*=true` across all
-- three categories is a tight signal that the user hasn't dialed in any
-- specific values worth bundling.
--
-- This deliberately ignores: coalition (varies by map — many maps ship
-- airbases pre-coloured RED/BLUE), OperatingLevel_* (replenishment rate;
-- moot when stock is unlimited), and the fuel/aircrafts/weapons sub-tables
-- (their values can't diverge from default while the unlimited flag is
-- still set — the UI gates them). Earlier versions of this check were
-- stricter and produced false negatives for pre-coloured airbases.
function M.is_default(entry)
    if type(entry) ~= 'table' then return false end
    return entry.unlimitedFuel      == true
       and entry.unlimitedAircrafts == true
       and entry.unlimitedMunitions == true
end

-- Splice a saved warehouse entry into the live mission data and push the
-- coalition through AirdromeController so the map display + Resource Manager
-- dialog refresh. Always deep-copies so the caller can safely keep their
-- table around.
function M.apply(airdrome_number, warehouse_entry)
    if type(airdrome_number) ~= 'number' then
        return nil, 'airdrome_number must be a number'
    end
    if type(warehouse_entry) ~= 'table' then
        return nil, 'warehouse_entry must be a table'
    end
    if not (module_mission and module_mission.mission
            and module_mission.mission.AirportsEquipment
            and module_mission.mission.AirportsEquipment.airports) then
        return nil, 'mission.AirportsEquipment.airports unavailable'
    end

    local copy = deep_copy(warehouse_entry)
    module_mission.mission.AirportsEquipment.airports[airdrome_number] = copy

    if AirdromeController and CoalitionController and copy.coalition then
        -- ED's coalition strings are lowercase ("blue"/"red"/"neutrals"), as
        -- returned by CoalitionController.{blue,red,neutral}CoalitionName().
        -- Earlier versions of this map keyed on uppercase singular
        -- ("BLUE"/"RED"/"NEUTRAL"), so the lookup always returned nil and the
        -- AirdromeController push silently no-op'd — the warehouse table got
        -- the new coalition but the live map display didn't refresh until the
        -- mission was saved + reopened. Keying on the lowercase strings ED
        -- actually emits fixes that.
        local controller_name = ({
            blue     = CoalitionController.blueCoalitionName    and CoalitionController.blueCoalitionName(),
            red      = CoalitionController.redCoalitionName     and CoalitionController.redCoalitionName(),
            neutrals = CoalitionController.neutralCoalitionName and CoalitionController.neutralCoalitionName(),
        })[copy.coalition]
        if controller_name and AirdromeController.setAirdromeCoalition and AirdromeController.getAirdromeId then
            local id = AirdromeController.getAirdromeId(airdrome_number)
            if id then
                pcall(AirdromeController.setAirdromeCoalition, id, controller_name)
            end
        end
    end

    return true
end

return M
