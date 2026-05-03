-- dcs-sms framework: prefab module (sms.prefab).
--
-- Public namespace for prefab management at runtime: load/save prefab
-- files, register them in an in-memory map, spawn instances at any anchor +
-- rotation + (optional) country override, and clean up via per-instance
-- handles or bulk destroy_all.
--
-- A prefab is a portable bundle of groups + statics + zones + drawings
-- distilled from an ME selection dump. See sms.prefab.distill (in
-- prefab_distill.lua) for the input side. See spec for the file format.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- group.lua -> unit.lua -> area.lua -> timer.lua -> rule.lua ->
-- group_spawn.lua -> static.lua -> events.lua -> weapon.lua -> task.lua ->
-- commands.lua -> options.lua -> utils_serialize.lua -> prefab_distill.lua ->
-- prefab.lua.
--
-- See docs/superpowers/specs/2026-05-03-sms-prefab-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
assert(type(sms.utils.serialize) == "function", "framework/utils_serialize.lua must be loaded first")
assert(type(sms.constants) == "table" or type(sms.K) == "table", "framework/constants.lua must be loaded first")
assert(type(sms.prefab) == "table" and type(sms.prefab.distill) == "function", "framework/prefab_distill.lua must be loaded first")

local log = sms.log.module("sms.prefab")

-- ---------------------------------------------------------------------------
-- Module-private state
-- ---------------------------------------------------------------------------

local _registry = {}    -- name -> template_table
local _instances = {}   -- id -> handle
local _next_instance_id = 1

-- ---------------------------------------------------------------------------
-- Math helpers (pure; unit-testable separately if desired).
-- Exposed under sms.prefab._<name> so the smoke tests can poke them.
-- ---------------------------------------------------------------------------

-- Rotate a point (x, y) around origin (0, 0) by rotation_deg degrees,
-- clockwise from north (DCS convention).
function sms.prefab._rotate_xy(x, y, rotation_deg)
    if not rotation_deg or rotation_deg == 0 then return x, y end
    local r = rotation_deg * (math.pi / 180)
    local c, s = math.cos(r), math.sin(r)
    return x * c - y * s, x * s + y * c
end

-- Resolve a vec2/vec3-shaped anchor into (x, z). Spec: caller passes
-- {x = world_x, z = world_y} (DCS world coords; framework convention 2D-y =
-- 3D-z). Also accepts {x, y} for 2D callers.
function sms.prefab._anchor_xy(anchor)
    if type(anchor) ~= 'table' then return nil end
    local ax = anchor.x
    local az = anchor.z or anchor.y
    if type(ax) ~= 'number' or type(az) ~= 'number' then return nil end
    return ax, az
end

-- ---------------------------------------------------------------------------
-- Registry: load / load_dir / save / unload / list / get / register
-- ---------------------------------------------------------------------------

function sms.prefab.load(path)
    if type(path) ~= 'string' or path == '' then
        log.warn('load: path required')
        return nil
    end
    local ok, result = pcall(dofile, path)
    if not ok then
        log.error('load: dofile failed for ' .. path .. ': ' .. tostring(result))
        return nil
    end
    if type(result) ~= 'table' or type(result.meta) ~= 'table' or type(result.meta.name) ~= 'string' then
        log.warn('load: file at ' .. path .. ' has no meta.name')
        return nil
    end
    if _registry[result.meta.name] then
        log.warn("load: overwriting prefab '" .. result.meta.name .. "'")
    end
    _registry[result.meta.name] = result
    return result
end

function sms.prefab.load_dir(dir)
    if type(dir) ~= 'string' or dir == '' then
        log.warn('load_dir: dir required')
        return 0
    end
    if not lfs then
        log.warn('load_dir: lfs not available — call sms.prefab.load(path) per file instead')
        return 0
    end
    local count = 0
    local function recurse(d)
        for entry in lfs.dir(d) do
            if entry ~= '.' and entry ~= '..' then
                local full = d .. '/' .. entry
                local attr = lfs.attributes(full)
                if attr and attr.mode == 'directory' then
                    recurse(full)
                elseif attr and entry:match('%.lua$') then
                    if sms.prefab.load(full) then count = count + 1 end
                end
            end
        end
    end
    local ok = pcall(recurse, dir)
    if not ok then
        log.warn('load_dir: directory not accessible: ' .. dir)
    end
    return count
end

function sms.prefab.save(prefab_table, path)
    if type(prefab_table) ~= 'table' or type(prefab_table.meta) ~= 'table' then
        log.warn('save: prefab_table missing meta')
        return false
    end
    if type(path) ~= 'string' or path == '' then
        log.warn('save: path required')
        return false
    end
    if type(io) ~= 'table' or not io.open then
        log.warn('save: io.open not available in this environment')
        return false
    end
    local f, err = io.open(path, 'w')
    if not f then
        log.error('save: open failed: ' .. tostring(err))
        return false
    end
    f:write(sms.utils.serialize(prefab_table))
    f:close()
    return true
end

-- Register a template directly (without going through dofile). Useful for
-- programmatically constructed prefabs and for tests. The 'load' path is
-- the production happy path; this is the in-memory equivalent.
function sms.prefab.register(name, template)
    if type(name) ~= 'string' or name == '' then
        log.warn('register: name required')
        return nil
    end
    if type(template) ~= 'table' or type(template.meta) ~= 'table' then
        log.warn("register: template missing meta")
        return nil
    end
    if _registry[name] then
        log.warn("register: overwriting prefab '" .. name .. "'")
    end
    template.meta.name = name
    _registry[name] = template
    return template
end

function sms.prefab.unload(name)
    if _registry[name] then
        _registry[name] = nil
        return true
    end
    return false
end

function sms.prefab.list()
    local out = {}
    for name in pairs(_registry) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function sms.prefab.get(name)
    return _registry[name]
end

-- ---------------------------------------------------------------------------
-- Spawn (skeleton — implementation in next task)
-- ---------------------------------------------------------------------------

function sms.prefab.spawn(name, opts)
    log.error('spawn: not implemented yet')
    return nil
end

function sms.prefab.list_instances(name)
    local out = {}
    for _, h in pairs(_instances) do
        if not name or h:get_name() == name then
            out[#out + 1] = h
        end
    end
    return out
end

function sms.prefab.destroy_all(name)
    local count = 0
    for id, h in pairs(_instances) do
        if not name or h:get_name() == name then
            h:destroy()
            count = count + 1
        end
    end
    return count
end
