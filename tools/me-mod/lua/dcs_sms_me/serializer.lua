-- serializer.lua — Lua value → Lua chunk string.
--
-- Returns a chunk that, when loadstring'd / dofile'd, reconstructs the input.
-- Handles mixed-key tables (the DCS callsign problem), cycles (marker), and
-- unsupported value types (function/userdata/thread → nil with comment).
--
-- Public:
--   M.serialize(value, opts) → string
--     opts.indent     = "  "    (default; one indent unit)
--
-- Keys are always sorted (deterministic output for diffs).

local M = {}

-- Produce a load-safe Lua literal for a number, normalizing NaN and +/-inf
-- to expressions (avoids "1.#INF" / "-1.#IND" platform-specific tostring).
local function number_literal(n)
    if n ~= n then return '0/0' end           -- NaN
    if n == math.huge then return '1/0' end    -- +inf
    if n == -math.huge then return '-1/0' end  -- -inf
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
    return nil  -- caller emits a comment marker for dropped keys
end

local function value_repr(v)
    local t = type(v)
    if t == 'nil' then return 'nil' end
    if t == 'string' then return string.format('%q', v) end
    if t == 'number' then return number_literal(v) end
    if t == 'boolean' then return tostring(v) end
    return nil  -- table/function/userdata/thread handled by caller
end

-- One-line summary of a key value for the "key dropped" comment marker.
local function key_summary(k)
    local t = type(k)
    if t == 'string' then
        return string.format('%q', k)
    elseif t == 'number' or t == 'boolean' then
        return tostring(k)
    end
    return tostring(k)  -- table/function/userdata/thread → "table: 0x..."
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

-- Forward declarations so the recursion can chain.
local emit_value

local function emit_table(tbl, indent_unit, depth, visited)
    if visited[tbl] then
        return 'nil --[[ cycle ]]'
    end
    visited[tbl] = true

    local keys = sorted_keys(tbl)
    if #keys == 0 then
        visited[tbl] = nil
        return '{}'
    end

    local pad     = indent_unit:rep(depth + 1)
    local pad_end = indent_unit:rep(depth)
    local parts   = {'{'}
    for _, k in ipairs(keys) do
        local k_repr = key_repr(k)
        if k_repr then
            local v_str = emit_value(tbl[k], indent_unit, depth + 1, visited)
            parts[#parts + 1] = pad .. k_repr .. ' = ' .. v_str .. ','
        else
            -- Key type can't be represented as a Lua literal. Leave a
            -- visible marker so the dump's lossiness is auditable.
            parts[#parts + 1] = pad .. '-- key dropped: ' .. type(k)
                .. ' = ' .. key_summary(k)
        end
    end
    parts[#parts + 1] = pad_end .. '}'
    visited[tbl] = nil
    return table.concat(parts, '\n')
end

emit_value = function(v, indent_unit, depth, visited)
    local t = type(v)
    if t == 'table' then
        return emit_table(v, indent_unit, depth, visited)
    end
    local simple = value_repr(v)
    if simple then return simple end
    -- Unsupported value type.
    return 'nil --[[ ' .. t .. ' ]]'
end

function M.serialize(value, opts)
    opts = opts or {}
    local indent_unit = opts.indent or '  '
    local body = emit_value(value, indent_unit, 0, {})
    return 'return ' .. body .. '\n'
end

return M
