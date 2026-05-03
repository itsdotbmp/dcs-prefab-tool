-- dcs-sms framework: prefab distill module (sms.prefab.distill).
--
-- Pure-data transform: walk an ME selection dump, drop back-references,
-- partition statics out of the groups array, capture country before strip,
-- convert headings rad → deg, and anchor every coordinate relative to the
-- centroid of the selection. No DCS dependencies — runnable in standalone
-- Lua 5.1 for unit tests.
--
-- Public:
--   sms.prefab.distill(dump_or_path, opts) → prefab_table | nil
--     opts = {
--       name    = string,           -- required; meta.name
--       theatre = string?,          -- optional; meta.theatre
--     }
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- ... -> prefab_distill.lua. Asserts sms and sms.log only.
--
-- See docs/superpowers/specs/2026-05-03-sms-prefab-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")
sms.prefab = sms.prefab or {}

local log = sms.log.module("sms.prefab.distill")

local PREFAB_VERSION = "0.1.0"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function rad_to_deg(r)
    return r * (180 / math.pi)
end

local function utc_now()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function is_static_entity(entry)
    -- Catalog lookup first.
    if sms.K and sms.K.statics and entry.units and entry.units[1]
       and sms.K.statics[entry.units[1].type] then
        return true
    end
    -- Field-shape inference: static-only fields, no route/tasks.
    if entry.category and entry.dead ~= nil and not entry.route then
        return true
    end
    return false
end

-- Walk a table, drop "boss" + back-references (cycles). Returns a fresh deep
-- copy with the offending references removed. Captures country (numeric id)
-- via boss.country.id and returns it as the second return value when found.
local function strip_back_refs(value, visited)
    if type(value) ~= 'table' then return value end
    if visited[value] then return nil end
    visited[value] = true

    local out = {}
    local captured_country
    for k, v in pairs(value) do
        if k == 'boss' then
            -- Capture country before dropping.
            if type(v) == 'table' and type(v.country) == 'table' and type(v.country.id) == 'number' then
                captured_country = v.country.id
            end
            -- Drop the boss field entirely.
        else
            local cv, sub_country = strip_back_refs(v, visited)
            out[k] = cv
            if sub_country and not captured_country then
                captured_country = sub_country
            end
        end
    end

    visited[value] = nil
    return out, captured_country
end

local function convert_headings(t)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'heading' and type(v) == 'number' then
            t[k] = rad_to_deg(v)
        elseif type(v) == 'table' then
            convert_headings(v)
        end
    end
end

local function rebase_xy(t, ax, ay)
    if type(t) ~= 'table' then return end
    if type(t.x) == 'number' and type(t.y) == 'number' then
        t.x = t.x - ax
        t.y = t.y - ay
    end
    for _, v in pairs(t) do
        if type(v) == 'table' then
            rebase_xy(v, ax, ay)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function sms.prefab.distill(dump_or_path, opts)
    opts = opts or {}
    if not opts.name or opts.name == '' then
        log.warn('distill: opts.name is required')
        return nil
    end

    -- Resolve dump.
    local dump
    local source_dump_name
    if type(dump_or_path) == 'string' then
        local ok, result = pcall(dofile, dump_or_path)
        if not ok then
            log.error('distill: dofile failed for ' .. dump_or_path .. ': ' .. tostring(result))
            return nil
        end
        dump = result
        -- Extract just the filename for source_dump.
        source_dump_name = dump_or_path:match('([^/\\]+)$') or dump_or_path
    elseif type(dump_or_path) == 'table' then
        dump = dump_or_path
    else
        log.warn('distill: dump must be a path string or table')
        return nil
    end

    if type(dump) ~= 'table' then
        log.warn('distill: dump did not load to a table')
        return nil
    end

    local raw_groups   = dump.groups   or {}
    local raw_statics  = dump.statics  or {}
    local raw_zones    = dump.zones    or {}
    local raw_drawings = dump.drawings or {}

    if #raw_groups == 0 and #raw_statics == 0 and #raw_zones == 0 and #raw_drawings == 0 then
        log.warn('distill: dump has no entities — nothing to distill')
        return nil
    end

    -- Phase 1: strip back-refs + capture country per entity.
    -- Process groups (which may include statics in disguise).
    local clean_groups   = {}
    local clean_statics  = {}
    for _, entry in ipairs(raw_groups) do
        local cleaned, country = strip_back_refs(entry, {})
        if cleaned then
            if country and not cleaned.country then
                cleaned.country = country
            end
            -- Propagate country down to units that don't have one.
            if cleaned.units then
                for _, u in pairs(cleaned.units) do
                    if u and not u.country then u.country = country end
                end
            end
            if is_static_entity(cleaned) then
                clean_statics[#clean_statics + 1] = cleaned
            else
                clean_groups[#clean_groups + 1] = cleaned
            end
        end
    end
    -- Statics that came in via dump.statics (not yet seen).
    for _, entry in ipairs(raw_statics) do
        local cleaned, country = strip_back_refs(entry, {})
        if cleaned then
            if country and not cleaned.country then
                cleaned.country = country
            end
            clean_statics[#clean_statics + 1] = cleaned
        end
    end
    local clean_zones = {}
    for _, z in ipairs(raw_zones) do
        local cleaned = strip_back_refs(z, {})
        if cleaned then clean_zones[#clean_zones + 1] = cleaned end
    end
    local clean_drawings = {}
    for _, d in ipairs(raw_drawings) do
        local cleaned = strip_back_refs(d, {})
        if cleaned then clean_drawings[#clean_drawings + 1] = cleaned end
    end

    -- Phase 2: compute centroid.
    local sum_x, sum_y, n = 0, 0, 0
    local function add_point(p)
        if type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' then
            sum_x = sum_x + p.x; sum_y = sum_y + p.y; n = n + 1
        end
    end
    for _, g in ipairs(clean_groups)   do add_point(g) end
    for _, s in ipairs(clean_statics)  do add_point(s) end
    for _, z in ipairs(clean_zones)    do add_point(z) end
    for _, d in ipairs(clean_drawings) do
        if d.mapData then add_point(d.mapData) else add_point(d) end
    end
    if n == 0 then
        log.warn('distill: no positionable entities — cannot anchor')
        return nil
    end
    local cx, cy = sum_x / n, sum_y / n

    -- Phase 3: rebase all coords relative to centroid.
    for _, g in ipairs(clean_groups)   do rebase_xy(g, cx, cy) end
    for _, s in ipairs(clean_statics)  do rebase_xy(s, cx, cy) end
    for _, z in ipairs(clean_zones)    do rebase_xy(z, cx, cy) end
    for _, d in ipairs(clean_drawings) do rebase_xy(d, cx, cy) end

    -- Phase 4: convert all headings rad → deg.
    for _, g in ipairs(clean_groups)   do convert_headings(g) end
    for _, s in ipairs(clean_statics)  do convert_headings(s) end

    return {
        meta = {
            sms_prefab_version = PREFAB_VERSION,
            name               = opts.name,
            created_utc        = utc_now(),
            source_dump        = source_dump_name,
            world_anchor       = { x = cx, y = cy },
            theatre            = opts.theatre,
        },
        groups   = clean_groups,
        statics  = clean_statics,
        zones    = clean_zones,
        drawings = clean_drawings,
    }
end
