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

-- Case: is_default ignores fields that aren't user-toggle gates.
-- Coalition (varies per map), OperatingLevel_*, fuel sub-tables, and
-- aircrafts/weapons are all gated behind the unlimited* flags in the UI;
-- the only signal that matters is whether the user unchecked any of those.
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

    local stays_default = {
        { 'coalition flipped to BLUE',  function(t) t.coalition = 'BLUE' end },
        { 'coalition flipped to RED',   function(t) t.coalition = 'RED' end },
        { 'OperatingLevel_Eqp dropped', function(t) t.OperatingLevel_Eqp = 0 end },
        { 'jet_fuel adjusted',          function(t) t.jet_fuel.InitFuel = 50 end },
        { 'aircrafts non-empty',        function(t) t.aircrafts = { planes = { ["F-16"] = {} } } end },
        { 'weapons non-empty',          function(t) t.weapons = { foo = 1 } end },
    }
    for _, mt in ipairs(stays_default) do
        local m = clone(default_airport)
        m.jet_fuel = clone(default_airport.jet_fuel)
        mt[2](m)
        check('is_default still true after: ' .. mt[1], warehouse_ops.is_default(m) == true)
    end

    local breaks_default = {
        { 'unlimitedFuel false',      function(t) t.unlimitedFuel = false end },
        { 'unlimitedAircrafts false', function(t) t.unlimitedAircrafts = false end },
        { 'unlimitedMunitions false', function(t) t.unlimitedMunitions = false end },
    }
    for _, mt in ipairs(breaks_default) do
        local m = clone(default_airport)
        mt[2](m)
        check('is_default false after: ' .. mt[1], warehouse_ops.is_default(m) == false)
    end
end

-- ---------------------------------------------------------------------------
-- apply tests — re-mock AirdromeController + CoalitionController with capture.
-- ---------------------------------------------------------------------------

local set_calls = {}  -- captures AirdromeController.setAirdromeCoalition calls
package.loaded['Mission.AirdromeController'] = {
    getAirdromeId = function(n) return 'id-' .. tostring(n) end,
    setAirdromeCoalition = function(id, name) set_calls[#set_calls + 1] = { id = id, name = name } end,
}
package.loaded['Mission.CoalitionController'] = {
    redCoalitionName     = function() return 'redName' end,
    blueCoalitionName    = function() return 'blueName' end,
    neutralCoalitionName = function() return 'neutralName' end,
}
package.loaded['dcs_sms_me.warehouse_ops'] = nil
warehouse_ops = require('dcs_sms_me.warehouse_ops')

-- Use a fresh airports table for apply so we can observe writes.
local live_airports = {
    [1]  = { coalition = 'NEUTRAL' },
    [68] = { coalition = 'NEUTRAL' },
}
package.loaded['me_mission'].mission.AirportsEquipment.airports = live_airports

-- Case: apply splices the table at the right index and pushes coalition.
do
    set_calls = {}
    local saved = {
        coalition = 'BLUE',
        unlimitedFuel = false,
        jet_fuel = { InitFuel = 50 },
        aircrafts = { helicopters = { ["AH-64D"] = { initialAmount = 100 } } },
    }
    local ok, err = warehouse_ops.apply(68, saved)
    check('apply returns ok', ok == true, 'err: ' .. tostring(err))
    check('live airports[68] is replaced (table reference differs)',
          live_airports[68] ~= saved, 'expected splice to deep-copy, not alias')
    check('live airports[68].coalition == BLUE',
          live_airports[68].coalition == 'BLUE')
    check('live airports[68].jet_fuel.InitFuel == 50',
          live_airports[68].jet_fuel and live_airports[68].jet_fuel.InitFuel == 50)
    check('setAirdromeCoalition called once', #set_calls == 1, 'got ' .. #set_calls)
    check('setAirdromeCoalition id', set_calls[1] and set_calls[1].id == 'id-68',
          'got ' .. tostring(set_calls[1] and set_calls[1].id))
    check('setAirdromeCoalition name == blueName',
          set_calls[1] and set_calls[1].name == 'blueName',
          'got ' .. tostring(set_calls[1] and set_calls[1].name))
    -- Mutating saved post-apply must not leak into live data.
    saved.coalition = 'MUTATED'
    check('post-apply mutation does not leak',
          live_airports[68].coalition == 'BLUE',
          'live coalition was: ' .. live_airports[68].coalition)
end

-- Case: apply with bad inputs returns nil + reason.
do
    local ok, err = warehouse_ops.apply(nil, { coalition = 'BLUE' })
    check('apply(nil, t) returns nil', ok == nil)
    check('apply(nil, t) returns error string', type(err) == 'string')

    local ok2, err2 = warehouse_ops.apply(68, nil)
    check('apply(68, nil) returns nil', ok2 == nil)
    check('apply(68, nil) returns error string', type(err2) == 'string')
end

-- Case: apply with missing coalition still splices the table (no controller call).
do
    set_calls = {}
    local ok = warehouse_ops.apply(1, { coalition = nil, jet_fuel = { InitFuel = 80 } })
    check('apply without coalition still ok', ok == true)
    check('apply without coalition: setAirdromeCoalition not called', #set_calls == 0)
    check('live airports[1].jet_fuel.InitFuel == 80',
          live_airports[1].jet_fuel and live_airports[1].jet_fuel.InitFuel == 80)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All warehouse_ops tests passed.')
