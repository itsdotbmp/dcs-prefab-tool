-- dcs-sms framework: serialize module (sms.utils.serialize).
--
-- Lua value → Lua chunk string. Round-trips losslessly through loadstring
-- for tables with mixed numeric/string keys, cycles (replaced with marker),
-- inf/NaN numbers, and unsupported value types (function/userdata/thread →
-- nil with comment).
--
-- The algorithm mirrors tools/me-mod/lua/dcs_sms_me/serializer.lua. Keep
-- the two in lock-step (both have identical test suites for parity).
-- Eventually one becomes the canonical source; for now duplication is the
-- simplest path because the framework runs in DCS mission env while the
-- ME mod runs in the GUI env, and they have no shared load path.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> utils_serialize.lua.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")
sms.utils = sms.utils or {}

local function number_literal(n)
    if n ~= n then return '0/0' end
    if n == math.huge then return '1/0' end
    if n == -math.huge then return '-1/0' end
    return tostring(n)
end

local function key_repr(k)
    if type(k) == 'string' then
        return '[' .. string.format('%q', k) .. ']'
    elseif type(k) == 'number' then
        return '[' .. number_literal(k) .. ']'
    elseif type(k) == 'boolean' then
        return '[' .. tostring(k) .. ']'
    end
    return nil
end

local function value_repr(v)
    local t = type(v)
    if t == 'nil' then return 'nil' end
    if t == 'string' then return string.format('%q', v) end
    if t == 'number' then return number_literal(v) end
    if t == 'boolean' then return tostring(v) end
    return nil
end

local function key_summary(k)
    local t = type(k)
    if t == 'string' then return string.format('%q', k) end
    if t == 'number' or t == 'boolean' then return tostring(k) end
    return tostring(k)
end

local function sorted_keys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
            if ta == 'number' or ta == 'string' then return a < b end
            return tostring(a) < tostring(b)
        end
        return ta < tb
    end)
    return keys
end

local emit_value

local function emit_table(tbl, indent_unit, depth, visited)
    if visited[tbl] then return 'nil --[[ cycle ]]' end
    visited[tbl] = true

    local keys = sorted_keys(tbl)
    if #keys == 0 then visited[tbl] = nil; return '{}' end

    local pad     = indent_unit:rep(depth + 1)
    local pad_end = indent_unit:rep(depth)
    local parts   = {'{'}
    for _, k in ipairs(keys) do
        local kr = key_repr(k)
        if kr then
            local v_str = emit_value(tbl[k], indent_unit, depth + 1, visited)
            parts[#parts + 1] = pad .. kr .. ' = ' .. v_str .. ','
        else
            parts[#parts + 1] = pad .. '-- key dropped: ' .. type(k) .. ' = ' .. key_summary(k)
        end
    end
    parts[#parts + 1] = pad_end .. '}'
    visited[tbl] = nil
    return table.concat(parts, '\n')
end

emit_value = function(v, indent_unit, depth, visited)
    if type(v) == 'table' then
        return emit_table(v, indent_unit, depth, visited)
    end
    local simple = value_repr(v)
    if simple then return simple end
    return 'nil --[[ ' .. type(v) .. ' ]]'
end

function sms.utils.serialize(value, opts)
    opts = opts or {}
    local indent_unit = opts.indent or '  '
    local body = emit_value(value, indent_unit, 0, {})
    return 'return ' .. body .. '\n'
end
