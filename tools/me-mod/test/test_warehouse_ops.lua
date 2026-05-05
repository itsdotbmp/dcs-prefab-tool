-- Standalone test for warehouse_ops.extract + is_default.
-- Stubs me_mission.mission.AirportsEquipment.airports.
-- Run via: lua test_warehouse_ops.lua  (cwd: tools/me-mod/test/)

local default_airport = {
    coalition          = "NEUTRAL",
    unlimitedFuel      = true,
    unlimitedAircrafts = true,
    unlimitedMunitions = true,
    OperatingLevel_Air = 10,
    OperatingLevel_Eqp = 10,
    OperatingLevel_Fuel = 10,
    aircrafts = {},
    weapons   = {},
    jet_fuel        = { InitFuel = 100 },
    methanol_mixture= { InitFuel = 100 },
    diesel          = { InitFuel = 100 },
    gasoline        = { InitFuel = 100 },
    suppliers = {},
    speed = 16.666666,
    periodicity = 30,
    size = 100,
    allowHotStart = false,
    dynamicSpawn = false,
    dynamicCargo = true,
}

local customised_airport = {
    coalition          = "BLUE",
    unlimitedFuel      = false,
    unlimitedAircrafts = false,
    unlimitedMunitions = false,
    OperatingLevel_Air = 10,
    OperatingLevel_Eqp = 0,
    OperatingLevel_Fuel = 10,
    aircrafts = {
        helicopters = {
            ["AH-64D"] = { initialAmount = 100, wsType = {1,2,6,158}, unlimited = false },
        },
        planes = {},
    },
    weapons = { foo = 1 },
    jet_fuel        = { InitFuel = 50 },
    methanol_mixture= { InitFuel = 60 },
    diesel          = { InitFuel = 60 },
    gasoline        = { InitFuel = 50 },
    suppliers = {},
    speed = 16.666666,
    periodicity = 30,
    size = 100,
    allowHotStart = false,
    dynamicSpawn = false,
    dynamicCargo = false,
}

package.preload['me_mission'] = function()
    return {
        mission = {
            AirportsEquipment = {
                airports = {
                    [1]  = default_airport,
                    [68] = customised_airport,
                }
            }
        }
    }
end

-- Stubs for AirdromeController + CoalitionController (apply tests live elsewhere
-- but warehouse_ops requires them at module load).
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
local warehouse_ops = require('dcs_sms_me.warehouse_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: extract returns a deep-copied default airport (mutating result must
-- not affect the source).
do
    local entry = warehouse_ops.extract(1)
    check('extract(1) returns table', type(entry) == 'table')
    check('extract(1).coalition == NEUTRAL', entry.coalition == 'NEUTRAL')
    check('extract(1) deep-copy of jet_fuel', entry.jet_fuel ~= default_airport.jet_fuel,
          'expected different table reference')
    entry.coalition = 'MUTATED'
    check('extract result mutation does not leak to source',
          default_airport.coalition == 'NEUTRAL', 'source coalition was: ' .. default_airport.coalition)
end

-- Case: extract on customised airport preserves nested aircrafts table.
do
    local entry = warehouse_ops.extract(68)
    check('extract(68).coalition == BLUE', entry.coalition == 'BLUE')
    check('extract(68) preserves AH-64D entry',
          entry.aircrafts and entry.aircrafts.helicopters
          and entry.aircrafts.helicopters['AH-64D']
          and entry.aircrafts.helicopters['AH-64D'].initialAmount == 100,
          'AH-64D not preserved')
    check('extract(68) deep-copies wsType array',
          entry.aircrafts.helicopters['AH-64D'].wsType
            ~= customised_airport.aircrafts.helicopters['AH-64D'].wsType,
          'expected different table reference for wsType')
end

-- Case: extract on missing index returns nil.
do
    local entry = warehouse_ops.extract(9999)
    check('extract(9999) returns nil', entry == nil)
end

-- Case: extract with non-number arguments returns nil cleanly (no error).
do
    check('extract(nil) returns nil',     warehouse_ops.extract(nil) == nil)
    check('extract("68") returns nil',    warehouse_ops.extract("68") == nil)
    check('extract(false) returns nil',   warehouse_ops.extract(false) == nil)
end

-- Case: is_default recognises a default airport.
do
    check('is_default(default) == true',
          warehouse_ops.is_default(default_airport) == true)
end

-- Case: is_default rejects a customised airport.
do
    check('is_default(customised) == false',
          warehouse_ops.is_default(customised_airport) == false)
end

-- Case: is_default rejects partial customisations one field at a time.
do
    local clone = function(t)
        local c = {}
        for k, v in pairs(t) do
            if type(v) == 'table' then
                local cc = {}
                for kk, vv in pairs(v) do cc[kk] = vv end
                c[k] = cc
            else
                c[k] = v
            end
        end
        return c
    end

    local mutations = {
        { 'coalition flipped',      function(t) t.coalition = 'BLUE' end },
        { 'unlimitedFuel false',    function(t) t.unlimitedFuel = false end },
        { 'OperatingLevel_Eqp 0',   function(t) t.OperatingLevel_Eqp = 0 end },
        { 'jet_fuel 50',            function(t) t.jet_fuel.InitFuel = 50 end },
        { 'aircrafts non-empty',    function(t) t.aircrafts = { planes = { ["F-16"] = {} } } end },
        { 'weapons non-empty',      function(t) t.weapons = { foo = 1 } end },
    }
    for _, mt in ipairs(mutations) do
        -- clone() is shallow, so the nested fuel tables would alias back to
        -- default_airport. Re-clone each nested subtable BEFORE the mutation
        -- runs to guarantee one mutation can't contaminate later iterations.
        local m = clone(default_airport)
        m.aircrafts = {}; m.weapons = {}
        m.jet_fuel = clone(default_airport.jet_fuel)
        m.methanol_mixture = clone(default_airport.methanol_mixture)
        m.diesel = clone(default_airport.diesel)
        m.gasoline = clone(default_airport.gasoline)
        mt[2](m)
        check('is_default false after: ' .. mt[1], warehouse_ops.is_default(m) == false)
    end
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All warehouse_ops extract/is_default tests passed.')
