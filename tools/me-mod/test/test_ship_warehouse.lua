-- Standalone test for ship_warehouse.attach_to_prefab + apply_from_record.
-- Stubs me_mission.mission.AirportsEquipment.warehouses and Mission.Airdrome*.
-- Run via: lua test_ship_warehouse.lua  (cwd: tools/me-mod/test/)

-- Live mission state we can read + mutate.
local live_warehouses = {}

package.preload['me_mission'] = function()
    return { mission = { AirportsEquipment = { warehouses = live_warehouses } } }
end

package.preload['Mission.AirdromeController'] = function()
    return { getAirdromeId = function(n) return n end, setAirdromeCoalition = function() end }
end
package.preload['Mission.CoalitionController'] = function()
    return {
        redCoalitionName     = function() return 'red' end,
        blueCoalitionName    = function() return 'blue' end,
        neutralCoalitionName = function() return 'neutral' end,
    }
end

package.preload['log'] = function()
    return { write = function() end, INFO = 1, WARNING = 2, ERROR = 3 }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local ship_warehouse = require('dcs_sms_me.ship_warehouse')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- A non-default ship warehouse — what attach should pick up.
local ship_warehouse_blue = {
    coalition          = 'blue',
    unlimitedFuel      = false,
    unlimitedAircrafts = false,
    unlimitedMunitions = false,
    OperatingLevel_Air = 10,
    OperatingLevel_Eqp = 0,
    OperatingLevel_Fuel = 10,
    aircrafts = { helicopters = { ["AH-64D"] = { initialAmount = 100 } } },
    weapons   = {},
    jet_fuel  = { InitFuel = 123 },
}

-- A pristine ship warehouse — attach should ignore it.
local ship_warehouse_default = {
    coalition          = 'blue',
    unlimitedFuel      = true,
    unlimitedAircrafts = true,
    unlimitedMunitions = true,
}

-- Case: attach copies the warehouse onto the unit when it's non-default.
do
    live_warehouses[1] = ship_warehouse_blue
    live_warehouses[2] = ship_warehouse_default

    local prefab = {
        groups = {
            { name = 'CVN', units = { { name = 'Naval-1-1', unitId = 1, type = 'CVN_71' } } },
            { name = 'PT',  units = { { name = 'Patrol-1',  unitId = 2, type = 'speedboat' } } },
        },
    }
    local attached = ship_warehouse.attach_to_prefab(prefab)
    check('attach returns count of non-default ships', attached == 1, 'got ' .. tostring(attached))

    local cvn = prefab.groups[1].units[1]
    check('CVN unit has _sms_warehouse', type(cvn._sms_warehouse) == 'table')
    check('CVN warehouse coalition preserved (lowercase)',
          cvn._sms_warehouse.coalition == 'blue')
    check('CVN warehouse jet_fuel preserved',
          cvn._sms_warehouse.jet_fuel and cvn._sms_warehouse.jet_fuel.InitFuel == 123)
    check('CVN warehouse is a deep copy (table refs differ)',
          cvn._sms_warehouse ~= ship_warehouse_blue)
    check('CVN warehouse aircrafts deep-copied',
          cvn._sms_warehouse.aircrafts ~= ship_warehouse_blue.aircrafts)

    local pt = prefab.groups[2].units[1]
    check('Patrol unit (default warehouse) does NOT have _sms_warehouse',
          pt._sms_warehouse == nil)
end

-- Case: attach skips units with no warehouse entry.
do
    live_warehouses = {}
    package.loaded['me_mission'] = { mission = { AirportsEquipment = { warehouses = live_warehouses } } }
    package.loaded['dcs_sms_me.ship_warehouse'] = nil
    ship_warehouse = require('dcs_sms_me.ship_warehouse')

    local prefab = {
        groups = {
            { name = 'JET', units = { { name = 'F-16', unitId = 99, type = 'F-16C_50' } } },
        },
    }
    local attached = ship_warehouse.attach_to_prefab(prefab)
    check('attach returns 0 when no warehouses match', attached == 0)
    check('unit untouched',
          prefab.groups[1].units[1]._sms_warehouse == nil)
end

-- Case: apply_from_record splices warehouses at the new unitId.
do
    live_warehouses = {}
    package.loaded['me_mission'] = { mission = { AirportsEquipment = { warehouses = live_warehouses } } }
    package.loaded['dcs_sms_me.ship_warehouse'] = nil
    ship_warehouse = require('dcs_sms_me.ship_warehouse')

    -- Simulate a record post-place: unit got a fresh unitId (500) and still
    -- carries the _sms_warehouse marker we attached at save time.
    local placed_unit = {
        name    = 'Naval-1-1',
        unitId  = 500,
        type    = 'CVN_71',
        _sms_warehouse = {
            coalition = 'blue',
            unlimitedFuel = false,
            jet_fuel = { InitFuel = 123 },
        },
    }
    local record = {
        groups = {
            { orig_name = 'CVN', runtime_id = 7, group_obj = { units = { placed_unit } } },
        },
    }
    local applied = ship_warehouse.apply_from_record(record)
    check('apply returns 1', applied == 1, 'got ' .. tostring(applied))
    check('live warehouses[500] is set',
          type(live_warehouses[500]) == 'table',
          'got ' .. tostring(live_warehouses[500]))
    check('live warehouses[500].coalition == blue',
          live_warehouses[500].coalition == 'blue')
    check('live warehouses[500].jet_fuel preserved',
          live_warehouses[500].jet_fuel and live_warehouses[500].jet_fuel.InitFuel == 123)
    check('marker stripped from live unit',
          placed_unit._sms_warehouse == nil)
    check('splice deep-copies (mutating live entry does not affect a future apply)',
          live_warehouses[500] ~= placed_unit._sms_warehouse)
end

-- Case: apply_from_record honours opts.override_coalition (lowercased).
do
    live_warehouses = {}
    package.loaded['me_mission'] = { mission = { AirportsEquipment = { warehouses = live_warehouses } } }
    package.loaded['dcs_sms_me.ship_warehouse'] = nil
    ship_warehouse = require('dcs_sms_me.ship_warehouse')

    local saved = { coalition = 'blue', jet_fuel = { InitFuel = 50 } }
    local placed_unit = { name = 'X', unitId = 42, _sms_warehouse = saved }
    local record = {
        groups = { { group_obj = { units = { placed_unit } } } },
    }
    local applied = ship_warehouse.apply_from_record(record, { override_coalition = 'RED' })
    check('apply with override returns 1', applied == 1)
    check('live warehouse coalition lowercased to "red"',
          live_warehouses[42].coalition == 'red',
          'got ' .. tostring(live_warehouses[42] and live_warehouses[42].coalition))
    check('saved table not mutated by override',
          saved.coalition == 'blue',
          'saved coalition was: ' .. tostring(saved.coalition))
end

-- Case: apply skips units with no _sms_warehouse marker.
do
    live_warehouses = {}
    package.loaded['me_mission'] = { mission = { AirportsEquipment = { warehouses = live_warehouses } } }
    package.loaded['dcs_sms_me.ship_warehouse'] = nil
    ship_warehouse = require('dcs_sms_me.ship_warehouse')

    local record = {
        groups = {
            { group_obj = { units = { { name = 'no-marker', unitId = 1 } } } },
        },
    }
    local applied = ship_warehouse.apply_from_record(record)
    check('apply with no markers returns 0', applied == 0)
    check('live warehouses untouched', next(live_warehouses) == nil)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All ship_warehouse tests passed.')
