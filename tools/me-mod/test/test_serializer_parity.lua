-- Parity test: framework/utils_serialize.lua vs tools/me-mod/lua/dcs_sms_me/serializer.lua.
-- Both must produce byte-identical output for the same input.
-- Run via: lua test_serializer_parity.lua  (cwd: tools/me-mod/test/)

-- 1) Load me-mod copy (module-style).
package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local memod_serializer = require('serializer')

-- 2) Load framework copy. It's framework-style: expects sms + sms.log,
-- writes sms.utils.serialize. Stub the contract.
sms = {}
sms.log = { module = function() return { warn=function() end, error=function() end, info=function() end, debug=function() end } end }
sms.utils = sms.utils or {}
dofile('../../../framework/utils_serialize.lua')
local fw_serialize = sms.utils.serialize

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function assert_parity(name, value)
    local a = memod_serializer.serialize(value)
    local b = fw_serialize(value)
    check(name, a == b, 'me-mod=' .. tostring(#a) .. 'B fw=' .. tostring(#b) .. 'B; diff at ' .. tostring((function()
        for i = 1, math.max(#a, #b) do
            if a:sub(i,i) ~= b:sub(i,i) then return i end
        end
        return -1
    end)()))
end

-- Cases — same inputs as framework/test/test_utils_serialize.lua.
assert_parity('empty table', {})
assert_parity('flat array', {1, 2, 3})
assert_parity('callsign mixed-key', {[1]=3, [2]=1, [3]=1, name='Uzi11'})
assert_parity('nested', {a=1, b={c=2, d={e=3}}})
assert_parity('numbers: int, float, negative', {1, -1, 0.5, -3.14})
assert_parity('strings with quotes and newlines', {s='hello "world"\nline2'})
assert_parity('booleans', {t=true, f=false})

-- Cycle (visited-set; same marker text in both).
local cyc = {x=1}; cyc.self = cyc
assert_parity('cycle', cyc)

-- NaN / inf normalization (both should emit 0/0 / 1/0 / -1/0).
assert_parity('inf and nan', {math.huge, -math.huge, 0/0})

-- Boolean keys (both should emit [true] / [false]).
assert_parity('boolean keys', {[true]=1, [false]=2})

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All parity tests passed.')
