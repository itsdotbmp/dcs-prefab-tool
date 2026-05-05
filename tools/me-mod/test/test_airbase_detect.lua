-- Standalone test for airbase_detect.airbases_in_rect.
-- Stubs Mission.AirdromeController with a fixed list of airdromes.
-- Run via: lua test_airbase_detect.lua  (cwd: tools/me-mod/test/)

-- Make-believe airdromes with x/y reference points + getName + getAirdromeNumber.
local function make_airdrome(name, n, x, y)
    return {
        x = x, y = y,
        getName             = function(self) return name end,
        getAirdromeNumber   = function(self) return n end,
    }
end

local airdromes = {
    make_airdrome('Khalde',          12, -250000,  610000),
    make_airdrome('Muwaffaq Salti',  68, -260000,  605000),
    make_airdrome('Beirut',          15, -270000,  615000),
    make_airdrome('H4',              80, -340000,  590000),
}

package.preload['Mission.AirdromeController'] = function()
    return {
        getAirdromes = function() return airdromes end,
    }
end

-- Stub log.
package.preload['log'] = function()
    return { write = function() end, INFO = 1, WARNING = 2, ERROR = 3 }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local airbase_detect = require('dcs_sms_me.airbase_detect')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: rect contains a single airdrome.
do
    local hits = airbase_detect.airbases_in_rect({x=-262000, y=603000}, {x=-258000, y=607000})
    check('single airdrome in rect: count == 1', #hits == 1, 'got ' .. #hits)
    check('single airdrome name', hits[1] and hits[1].name == 'Muwaffaq Salti',
          'got ' .. tostring(hits[1] and hits[1].name))
    check('single airdrome number', hits[1] and hits[1].airdrome_number_at_save == 68,
          'got ' .. tostring(hits[1] and hits[1].airdrome_number_at_save))
end

-- Case: rect contains multiple airdromes.
do
    local hits = airbase_detect.airbases_in_rect({x=-280000, y=600000}, {x=-240000, y=620000})
    check('multi-airdrome rect: count == 3', #hits == 3, 'got ' .. #hits)
    local by_name = {}
    for _, h in ipairs(hits) do by_name[h.name] = true end
    check('Khalde in rect',          by_name['Khalde'] == true)
    check('Muwaffaq Salti in rect',  by_name['Muwaffaq Salti'] == true)
    check('Beirut in rect',          by_name['Beirut'] == true)
    check('H4 NOT in rect',          by_name['H4'] == nil)
end

-- Case: rect with start/end reversed (drawn upper-right to lower-left) still works.
do
    local hits = airbase_detect.airbases_in_rect({x=-258000, y=607000}, {x=-262000, y=603000})
    check('reversed rect: count == 1', #hits == 1, 'got ' .. #hits)
    check('reversed rect: Muwaffaq Salti', hits[1] and hits[1].name == 'Muwaffaq Salti')
end

-- Case: empty rect (no airdromes inside) returns empty.
do
    local hits = airbase_detect.airbases_in_rect({x=0, y=0}, {x=100, y=100})
    check('empty rect returns empty array', type(hits) == 'table' and #hits == 0, 'got ' .. #hits)
end

-- Case: airdrome exactly on rect boundary is included (inclusive bounds).
do
    local hits = airbase_detect.airbases_in_rect({x=-260000, y=605000}, {x=-260000, y=605000})
    check('point-rect at airdrome reference picks it up', #hits == 1, 'got ' .. #hits)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All airbase_detect tests passed.')
