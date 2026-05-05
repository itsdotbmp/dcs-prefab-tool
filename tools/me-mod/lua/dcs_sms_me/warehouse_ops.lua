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
M._deep_copy = deep_copy  -- exposed for tests

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

-- Predicate: returns true iff the entry matches the pristine "untouched
-- airbase" shape the ME emits for never-edited airports. See the design's
-- Default-detection decision for the exact rules.
function M.is_default(entry)
    if type(entry) ~= 'table' then return false end
    if entry.coalition ~= 'NEUTRAL' then return false end
    if entry.unlimitedFuel ~= true or entry.unlimitedAircrafts ~= true or entry.unlimitedMunitions ~= true then
        return false
    end
    if entry.OperatingLevel_Air ~= 10 or entry.OperatingLevel_Eqp ~= 10 or entry.OperatingLevel_Fuel ~= 10 then
        return false
    end
    if type(entry.aircrafts) == 'table' and next(entry.aircrafts) ~= nil then
        -- Default emits aircrafts = {}; some saves emit
        -- aircrafts = { helicopters = {}, planes = {} } — accept either by
        -- treating empty subtables as absent.
        for k, v in pairs(entry.aircrafts) do
            if type(v) == 'table' and next(v) ~= nil then return false end
            if type(v) ~= 'table' then return false end
            if k ~= 'helicopters' and k ~= 'planes' then return false end
        end
    end
    if type(entry.weapons) == 'table' and next(entry.weapons) ~= nil then return false end
    local function fuel_default(name)
        local f = entry[name]
        return type(f) == 'table' and f.InitFuel == 100
    end
    if not (fuel_default('jet_fuel') and fuel_default('methanol_mixture')
            and fuel_default('diesel') and fuel_default('gasoline')) then
        return false
    end
    return true
end

return M
