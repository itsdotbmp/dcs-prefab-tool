-- mock_me_mission.lua — synthetic stand-in for the ME's `me_mission` module.
-- Used by test_verbs_route.lua (and future verb test files per issue #55).
--
-- Usage in a test file:
--   package.preload['me_mission'] = function() return require('mock_me_mission') end
--   local mock = require('mock_me_mission')
--   mock.new_mission()
--   local g = mock.add_plane({ name = 'strike-1', country = 'USA' })
--
-- The module mutates its own `mission` field; verbs.lua's calls to
-- require('me_mission') will return THIS module, so `Mission.mission` is
-- our synthetic table.

local M = {}

-- Counters for recording verb-induced refresh calls. Tests reset these
-- via M.reset_refresh_counters().
M.refresh_calls = { create = 0, update = 0 }

function M.reset_refresh_counters()
    M.refresh_calls.create = 0
    M.refresh_calls.update = 0
end

function M.create_group_map_objects(g)
    M.refresh_calls.create = M.refresh_calls.create + 1
end

function M.update_group_map_objects(g)
    M.refresh_calls.update = M.refresh_calls.update + 1
end

-- new_mission — reset the synthetic mission table and the refresh counters.
-- Returns the freshly-built mission table for direct inspection.
function M.new_mission()
    M.reset_refresh_counters()
    M.mission = {
        coalition = {
            blue = {
                country = {
                    { id = 2, name = 'USA',
                      plane = { group = {} },
                      helicopter = { group = {} },
                      vehicle = { group = {} },
                      ship = { group = {} },
                      static = { group = {} } },
                },
            },
            red = {
                country = {
                    { id = 0, name = 'Russia',
                      plane = { group = {} },
                      helicopter = { group = {} },
                      vehicle = { group = {} },
                      ship = { group = {} },
                      static = { group = {} } },
                },
            },
        },
    }
    M._next_group_id = 1
    return M.mission
end

local function next_group_id()
    local id = M._next_group_id
    M._next_group_id = (M._next_group_id or 1) + 1
    return id
end

-- Build the default waypoint for a category. Mirrors the
-- CATEGORY_DEFAULTS that verbs.lua uses, kept in sync by design.
local function default_wp(category, x, y)
    local profiles = {
        plane =      { alt = 8000, alt_type = 'BARO', speed = 220, action = 'Turning Point' },
        helicopter = { alt = 500,  alt_type = 'BARO', speed = 50,  action = 'Turning Point' },
        vehicle =    { alt = 0,    alt_type = 'BARO', speed = 8,   action = 'Off Road' },
        ship =       { alt = 0,    alt_type = 'BARO', speed = 5,   action = 'Turning Point' },
        static =     { alt = 0,    alt_type = 'BARO', speed = 0,   action = 'Off Road' },
    }
    local p = profiles[category] or profiles.vehicle
    return {
        x = x, y = y,
        alt = p.alt, alt_type = p.alt_type,
        speed = p.speed,
        action = p.action, type = 'Turning Point',
        ETA = 0, ETA_locked = true, speed_locked = true,
        formation_template = '', name = '',
        task = { id = 'ComboTask', params = { tasks = {} } },
    }
end

local function add_group(category, side, country_name, opts)
    opts = opts or {}
    local country
    for _, c in ipairs(M.mission.coalition[side].country) do
        if c.name == country_name then country = c; break end
    end
    assert(country, 'mock: country not found: ' .. tostring(country_name))
    local g = {
        name = opts.name or (category .. '-' .. next_group_id()),
        groupId = opts.groupId or next_group_id(),
        x = opts.x or 0, y = opts.y or 0,
        units = opts.units or {
            { unitId = next_group_id(), name = (opts.name or category) .. '-1',
              type = opts.unit_type or category, x = opts.x or 0, y = opts.y or 0 },
        },
        route = opts.route or {
            points = { default_wp(category, opts.x or 0, opts.y or 0) },
            routeRelativeTOT = false,
        },
        mapObjects = nil,
    }
    table.insert(country[category].group, g)
    return g
end

function M.add_plane(opts)      return add_group('plane',      opts and opts.side or 'blue', opts and opts.country or 'USA', opts) end
function M.add_helicopter(opts) return add_group('helicopter', opts and opts.side or 'blue', opts and opts.country or 'USA', opts) end
function M.add_vehicle(opts)    return add_group('vehicle',    opts and opts.side or 'blue', opts and opts.country or 'USA', opts) end
function M.add_ship(opts)       return add_group('ship',       opts and opts.side or 'blue', opts and opts.country or 'USA', opts) end
function M.add_static(opts)     return add_group('static',     opts and opts.side or 'blue', opts and opts.country or 'USA', opts) end

-- Build a single waypoint table suitable for splicing into a route's
-- points array. Used by tests that need multi-WP routes.
function M.make_waypoint(category, opts)
    opts = opts or {}
    local wp = default_wp(category, opts.x or 0, opts.y or 0)
    for k, v in pairs(opts) do
        if k ~= 'category' then wp[k] = v end
    end
    return wp
end

-- insert_waypoint — mock stand-in for me_mission.insert_waypoint. Mirrors the
-- data-side behavior of the real function (alt_type inherited from previous
-- WP, default locks per index, wpt.index assigned, route renumbered) without
-- the mapObjects manipulation the real ME does. Tests don't need symbol
-- creation; they assert against route.points directly.
function M.insert_waypoint(group, index, type, x, y, alt, speed, name, formation_template)
    local alt_type = 'BARO'
    if group.route.points[index - 1] then
        alt_type = group.route.points[index - 1].alt_type or 'BARO'
    end
    local speed_locked = true
    local ETA_locked = (index == 1) and true or false
    local ETA = (index == 1) and 0.0 or 0
    local wpt = {
        boss = group,
        index = index,
        type = type,
        x = x, y = y,
        alt = alt or 0,
        alt_type = alt_type,
        speed = speed or 0,
        speed_locked = speed_locked,
        ETA = ETA,
        ETA_locked = ETA_locked,
        targets = {},
        formation_template = formation_template or '',
        name = name or '',
    }
    table.insert(group.route.points, index, wpt)
    for i = index + 1, #group.route.points do
        group.route.points[i].index = i
    end
    return wpt
end

-- remove_waypoint — mock stand-in for me_mission.remove_waypoint. Removes
-- from route.points and renumbers. Skips the symbol/task-back-reference
-- cleanup the real ME does.
function M.remove_waypoint(group, index)
    table.remove(group.route.points, index)
    for i = 1, #group.route.points do
        group.route.points[i].index = i
    end
end

-- move_waypoint — mock stand-in for MapWindow.move_waypoint. Updates the
-- data side: wpt.x/wpt.y and vehicle route.spans. Real ME also moves map
-- symbols, number labels, child units, etc. — tests only care about data.
-- Same module is registered as both 'me_mission' and 'me_map_window' via
-- package.preload in test_verbs_route.lua, so require('me_map_window')
-- inside verbs.lua resolves to this table.
function M.move_waypoint(group, index, x, y, dontMoveLinked, doNotUpdateRoute, dontMoveChild, dontRelativePos, noCheckSurface)
    local wpt = group.route.points[index]
    if not wpt then return end
    wpt.x = x
    wpt.y = y
    if group.route.spans and #group.route.spans > 0 then
        local spans = group.route.spans
        if index > 1 then
            local p = group.route.points[index - 1]
            spans[index - 1] = { { x = p.x, y = p.y }, { x = x, y = y } }
        end
        if index < #group.route.points then
            local p = group.route.points[index + 1]
            spans[index] = { { x = x, y = y }, { x = p.x, y = p.y } }
        end
        if index == #group.route.points then
            spans[index] = { { x = x, y = y }, { x = x, y = y } }
        end
    end
end

return M
