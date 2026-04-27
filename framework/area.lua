-- dcs-sms framework: area module (sms.area).
--
-- A unified "area on the map" abstraction — circles or polygons, sourced
-- from ME zones, ME drawings, or constructed at runtime. All sources share
-- the same handle shape and method surface.
--
-- Construction paths:
--   sms.area("ZoneName")                        -- ME zone (circle or quad)
--   sms.area.from_drawing("DrawingName")        -- ME freeform polygon drawing
--   sms.area.create_circular(vec3, radius, name?)
--   sms.area.create_polygon({vec3,...}, name?)  -- >= 3 vertices
--
-- Methods (all callable as a:method() AND as sms.area.method(handle, ...)):
--   :get_name()                                 -- string | nil (anonymous)
--   :get_kind()                                 -- "circle" | "polygon"
--   :get_position()                             -- vec3 (center / centroid)
--   :get_radius()                               -- number | nil + log on polygon
--   :get_vertices()                             -- list of vec3 | nil + log on circle
--   :is_vec3_in(vec3)                           -- bool
--   :is_unit_in(sms.unit handle)                -- bool, strict handle check
--   :is_static_in(sms.static handle)            -- bool, strict handle check
--   :is_any_of_group_in(sms.group handle)       -- bool
--   :is_all_of_group_in(sms.group handle)       -- bool
--   :get_random_point()                         -- vec3 inside the area
--
-- Failure model: log + return nil/false. Never throws.
--
-- Loading order: sms.lua -> log.lua -> group.lua -> unit.lua -> area.lua.
-- is_unit_in / is_static_in / is_*_of_group_in require sms.unit/sms.static/sms.group
-- at call time (loaded later in framework boot).
-- Polygon get_random_point uses rejection sampling within the bounding box;
-- triangulation-based replacement tracked in issue #4.
--
-- See docs/superpowers/specs/2026-04-26-framework-area-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.area")
sms.area = sms.area or {}

-- ============================================================
-- Local helpers (private)
-- ============================================================

-- _validate_vec3 lifted to sms.utils.is_vec3 (issue #14).
local _validate_vec3 = sms.utils.is_vec3

local function _point_in_circle(data, x, z)
  local dx = x - data.center.x
  local dz = z - data.center.z
  return (dx * dx + dz * dz) <= (data.radius * data.radius)
end

-- Standard ray-casting point-in-polygon on the xz-plane. Handles concave
-- polygons. Edge-on-vertex cases are nondeterministic (acceptable for v1).
local function _point_in_polygon(verts, x, z)
  local inside = false
  local n = #verts
  local j = n
  for i = 1, n do
    local vi, vj = verts[i], verts[j]
    if ((vi.z > z) ~= (vj.z > z)) and
       (x < (vj.x - vi.x) * (z - vi.z) / (vj.z - vi.z) + vi.x) then
      inside = not inside
    end
    j = i
  end
  return inside
end

local function _bbox_of_polygon(verts)
  local min_x, max_x = verts[1].x, verts[1].x
  local min_z, max_z = verts[1].z, verts[1].z
  for i = 2, #verts do
    local v = verts[i]
    if v.x < min_x then min_x = v.x end
    if v.x > max_x then max_x = v.x end
    if v.z < min_z then min_z = v.z end
    if v.z > max_z then max_z = v.z end
  end
  return {min_x = min_x, max_x = max_x, min_z = min_z, max_z = max_z}
end

local function _centroid_of_polygon(verts)
  local sx, sy, sz = 0, 0, 0
  local n = #verts
  for _, v in ipairs(verts) do
    sx = sx + v.x
    sy = sy + v.y
    sz = sz + v.z
  end
  return {x = sx / n, y = sy / n, z = sz / n}
end

-- Uniform random point inside a circle. r = sqrt(random()) * radius gives
-- uniform distribution; naive r = random() * radius clusters near center.
local function _random_in_circle(data)
  local theta = math.random() * 2 * math.pi
  local r = math.sqrt(math.random()) * data.radius
  return {
    x = data.center.x + r * math.cos(theta),
    y = data.center.y,
    z = data.center.z + r * math.sin(theta),
  }
end

-- Rejection sampling within bounding box. Capped at 100 attempts; falls
-- back to centroid + log on degenerate input. See issue #4 for the
-- triangulation-based replacement plan.
local function _random_in_polygon(data, name)
  local bbox = data.bbox
  for attempt = 1, 100 do
    local x = bbox.min_x + math.random() * (bbox.max_x - bbox.min_x)
    local z = bbox.min_z + math.random() * (bbox.max_z - bbox.min_z)
    if _point_in_polygon(data.vertices, x, z) then
      return {x = x, y = data.centroid.y, z = z}
    end
  end
  log.error("get_random_point: 100 attempts failed for polygon '" .. tostring(name) .. "', returning centroid")
  return {x = data.centroid.x, y = data.centroid.y, z = data.centroid.z}
end

-- ============================================================
-- Internal handle factories
-- ============================================================

local function _make_circle_handle(name, center, radius)
  return setmetatable({
    name = name,
    kind = "circle",
    _data = {
      center = {x = center.x, y = center.y, z = center.z},
      radius = radius,
    },
  }, {__index = sms.area})
end

local function _make_polygon_handle(name, vertices)
  -- Copy vertices to prevent external mutation.
  local verts = {}
  for i, v in ipairs(vertices) do
    verts[i] = {x = v.x, y = v.y, z = v.z}
  end
  return setmetatable({
    name = name,
    kind = "polygon",
    _data = {
      vertices = verts,
      centroid = _centroid_of_polygon(verts),
      bbox = _bbox_of_polygon(verts),
    },
  }, {__index = sms.area})
end

-- ============================================================
-- Methods
-- ============================================================

sms.area.get_name = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_name: argument must be an sms.area handle")
    return nil
  end
  return a.name
end

sms.area.get_kind = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_kind: argument must be an sms.area handle")
    return nil
  end
  return a.kind
end

sms.area.get_position = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_position: argument must be an sms.area handle")
    return nil
  end
  if a.kind == "circle" then
    local c = a._data.center
    return {x = c.x, y = c.y, z = c.z}
  end
  local c = a._data.centroid
  return {x = c.x, y = c.y, z = c.z}
end

sms.area.get_radius = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_radius: argument must be an sms.area handle")
    return nil
  end
  if a.kind ~= "circle" then
    log.error("get_radius: area '" .. tostring(a.name) .. "' is a " .. a.kind .. ", no radius")
    return nil
  end
  return a._data.radius
end

sms.area.get_vertices = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_vertices: argument must be an sms.area handle")
    return nil
  end
  if a.kind ~= "polygon" then
    log.error("get_vertices: area '" .. tostring(a.name) .. "' is a " .. a.kind .. ", no vertices")
    return nil
  end
  -- Return a copy so the user can't mutate internal state.
  local copy = {}
  for i, v in ipairs(a._data.vertices) do
    copy[i] = {x = v.x, y = v.y, z = v.z}
  end
  return copy
end

sms.area.is_vec3_in = function(a, target)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_vec3_in: argument must be an sms.area handle")
    return false
  end
  if not _validate_vec3(target) then
    log.error("is_vec3_in: target must be a vec3 with x/y/z numbers")
    return false
  end
  if a.kind == "circle" then
    return _point_in_circle(a._data, target.x, target.z)
  end
  return _point_in_polygon(a._data.vertices, target.x, target.z)
end

sms.area.is_unit_in = function(a, u)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_unit_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(u, sms.unit) then
    log.error("is_unit_in: target must be an sms.unit handle")
    return false
  end
  local p = sms.unit.get_position(u)
  if not p then return false end
  if a.kind == "circle" then
    return _point_in_circle(a._data, p.x, p.z)
  end
  return _point_in_polygon(a._data.vertices, p.x, p.z)
end

sms.area.is_static_in = function(a, s)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_static_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(s, sms.static) then
    log.error("is_static_in: target must be an sms.static handle")
    return false
  end
  local p = sms.static.get_position(s)
  if not p then return false end
  if a.kind == "circle" then
    return _point_in_circle(a._data, p.x, p.z)
  end
  return _point_in_polygon(a._data.vertices, p.x, p.z)
end

sms.area.is_any_of_group_in = function(a, g)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_any_of_group_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(g, sms.group) then
    log.error("is_any_of_group_in: target must be an sms.group handle")
    return false
  end
  local units = sms.group.get_units(g)
  if not units then return false end
  for _, u in ipairs(units) do
    if u then
      local p = sms.unit.get_position(u)
      if p then
        local inside
        if a.kind == "circle" then
          inside = _point_in_circle(a._data, p.x, p.z)
        else
          inside = _point_in_polygon(a._data.vertices, p.x, p.z)
        end
        if inside then return true end
      end
    end
  end
  return false
end

sms.area.is_all_of_group_in = function(a, g)
  if not sms._is_handle_of(a, sms.area) then
    log.error("is_all_of_group_in: argument must be an sms.area handle")
    return false
  end
  if not sms._is_handle_of(g, sms.group) then
    log.error("is_all_of_group_in: target must be an sms.group handle")
    return false
  end
  local units = sms.group.get_units(g)
  if not units or #units == 0 then return false end
  for _, u in ipairs(units) do
    if not u then return false end
    local p = sms.unit.get_position(u)
    if not p then return false end
    local inside
    if a.kind == "circle" then
      inside = _point_in_circle(a._data, p.x, p.z)
    else
      inside = _point_in_polygon(a._data.vertices, p.x, p.z)
    end
    if not inside then return false end
  end
  return true
end

sms.area.get_random_point = function(a)
  if not sms._is_handle_of(a, sms.area) then
    log.error("get_random_point: argument must be an sms.area handle")
    return nil
  end
  if a.kind == "circle" then
    return _random_in_circle(a._data)
  end
  return _random_in_polygon(a._data, a.name)
end

-- ============================================================
-- Constructors
-- ============================================================

sms.area.create_circular = function(center, radius, name)
  if not _validate_vec3(center) then
    log.error("create_circular: center must be a vec3 with x/y/z numbers")
    return nil
  end
  if type(radius) ~= "number" or radius <= 0 then
    log.error("create_circular: radius must be a positive number, got " .. tostring(radius))
    return nil
  end
  if name ~= nil and type(name) ~= "string" then
    log.error("create_circular: name must be a string or nil, got " .. type(name))
    return nil
  end
  return _make_circle_handle(name, center, radius)
end

sms.area.create_polygon = function(vertices, name)
  if type(vertices) ~= "table" then
    log.error("create_polygon: vertices must be a table (list) of vec3 entries")
    return nil
  end
  if #vertices < 3 then
    log.error("create_polygon: need at least 3 vertices, got " .. #vertices)
    return nil
  end
  for i, v in ipairs(vertices) do
    if not _validate_vec3(v) then
      log.error("create_polygon: vertex " .. i .. " is not a vec3 with x/y/z numbers")
      return nil
    end
  end
  if name ~= nil and type(name) ~= "string" then
    log.error("create_polygon: name must be a string or nil, got " .. type(name))
    return nil
  end
  return _make_polygon_handle(name, vertices)
end

sms.area.from_drawing = function(name)
  if type(name) ~= "string" then
    log.error("from_drawing: name must be a string")
    return nil
  end
  local drawings = env.mission and env.mission.drawings
  if not drawings or not drawings.layers then
    log.error("from_drawing: env.mission.drawings.layers not available")
    return nil
  end
  for _, layer in ipairs(drawings.layers) do
    if layer.objects then
      for _, obj in ipairs(layer.objects) do
        if obj.name == name then
          if obj.primitiveType ~= "Polygon" then
            log.error("from_drawing: '" .. name .. "' is not a polygon drawing (type: " .. tostring(obj.primitiveType) .. ")")
            return nil
          end
          local pts = obj.points
          if type(pts) ~= "table" or #pts < 3 then
            log.error("from_drawing: '" .. name .. "' has insufficient points")
            return nil
          end
          -- Drawing points are 2D {x, y} where DCS-y is north-south.
          -- Anchor at the drawing's mapX/mapY origin and convert to vec3
          -- with our z = DCS-y.
          local origin_x = obj.mapX or 0
          local origin_z = obj.mapY or 0
          local verts = {}
          for i, p in ipairs(pts) do
            verts[i] = {x = origin_x + p.x, y = 0, z = origin_z + p.y}
          end
          return _make_polygon_handle(name, verts)
        end
      end
    end
  end
  log.error("from_drawing: drawing '" .. name .. "' not found")
  return nil
end

-- Callable: sms.area("name") -> handle | nil + log.
-- Looks up via trigger.misc.getZone, dispatches to circle or polygon.
-- Quad zones use DCS's "verticies" key (note the spelling, that's how DCS
-- has it).
setmetatable(sms.area, {
  __call = function(_, name)
    local zone = trigger.misc.getZone(name)
    if not zone then
      log.error("couldn't find area '" .. tostring(name) .. "'")
      return nil
    end
    if zone.radius then
      return _make_circle_handle(name, zone.point, zone.radius)
    end
    if zone.verticies then
      -- Quad-zone vertices are {x, y} 2D (y = north-south). Convert to vec3.
      local verts = {}
      for i, v in ipairs(zone.verticies) do
        verts[i] = {x = v.x, y = 0, z = v.y}
      end
      return _make_polygon_handle(name, verts)
    end
    log.error("area '" .. tostring(name) .. "' has neither radius nor vertices")
    return nil
  end,
})
