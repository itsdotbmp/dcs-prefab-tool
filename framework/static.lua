-- dcs-sms framework: static module (sms.static).
--
-- Entity wrapper + factories for DCS static objects (single-object scenery,
-- cargo, FARPs, hangars, wreckage). Sibling of sms.unit, with create/clone
-- factories on the same module (no separate sms.spawn_static).
--
-- sms.static("name") returns a lightweight handle, or nil + log if the
-- static doesn't exist in DCS. Handles are {name=name} tables with
-- __index = sms.static, so handle:method() dispatches to sms.static.method(handle).
--
-- sms.static.create(cfg) -> handle | nil + log. coalition.addStaticObject under the hood.
-- sms.static.clone(template_name, overrides) -> handle | nil + log. ME-template-derived.
--
-- All methods accept either a handle or a raw name string, normalized at entry.
-- Methods that touch DCS state internally check is_alive first; if the static is
-- not alive, they log and return nil — they never throw. _name_of also accepts
-- garbage input (nil, numbers, ...) and returns nil, which then makes is_alive
-- return false and the standard log+nil path triggers.
--
-- Static-specific is_alive semantics: unlike sms.unit (which checks isExist()),
-- sms.static.is_alive uses only StaticObject.getByName(). Statics spawned with
-- dead = true are addressable via getByName but return false from isExist();
-- gating methods on isExist() would make dead-spawned statics unusable through
-- the framework even though they're in the scene as wreckage. See is_alive
-- definition for the empirical rationale.
--
-- Auto-suffix probes ONLY StaticObject.getByName (statics live in their own
-- name namespace, separate from groups and units — verified empirically).
--
-- DCS silently ignores pitch/bank on coalition.addStaticObject; cfg.pitch and
-- cfg.bank (if present) are warned (via log.info with explicit "warning:" text,
-- since v1 logger has no warning level) and dropped — only heading is applied.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua -> unit.lua
--                -> area.lua -> timer.lua -> spawn.lua -> static.lua.
-- area.lua's is_static_in resolves sms.static lazily at call time.
--
-- See docs/superpowers/specs/2026-04-26-framework-static-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.static")
sms.static = sms.static or {}

-- DCS coalition int -> normalized lowercase string. Lookup now lives in
-- sms.utils.coalition_int_to_str (issue #14).

-- base_name -> next-index hint for auto-suffix. Lost on reload (probe recovers).
local _name_counters = {}

-- int country id -> string country name. Built lazily.
local _country_reverse = nil

local function _build_country_reverse()
  if _country_reverse then return end
  _country_reverse = {}
  for k, v in pairs(country.id) do
    _country_reverse[v] = k
  end
end

-- ============================================================
-- Helpers (private)
-- ============================================================

-- Accept either a handle ({name=...}) or a raw name string; return the name.
-- Returns nil for any other input (nil, numbers, booleans, table-without-name).
-- Callers handle nil names as "not alive" rather than throwing.
local function _name_of(s)
  if type(s) == "string" then return s end
  if type(s) == "table" and type(s.name) == "string" then return s.name end
  return nil
end

-- _is_vec3 / _resolve_country lifted to sms.utils (issue #14).
local _is_vec3 = sms.utils.is_vec3
local _resolve_country = sms.utils.resolve_country

local function _name_taken(name)
  return StaticObject.getByName(name) ~= nil
end

-- Resolve a unique name using base + numeric suffix. Probes ONLY
-- StaticObject.getByName — statics share name namespace with neither
-- groups nor units (verified empirically). Counter is a hint; probe is
-- the source of truth.
local function _resolve_unique_name(base)
  if not _name_taken(base) then return base end
  local n = _name_counters[base] or 1
  while _name_taken(base .. "-" .. n) do
    n = n + 1
  end
  _name_counters[base] = n + 1
  return base .. "-" .. n
end

-- _deep_copy lifted to sms.utils.deep_copy (issue #14).
local _deep_copy = sms.utils.deep_copy

-- ============================================================
-- Entity wrapper methods
-- ============================================================

sms.static.is_alive = function(s)
  local name = _name_of(s)
  if not name then return false end
  -- Use getByName-presence as the addressable gate, NOT isExist().
  -- Empirically, statics spawned with dead = true are findable via getByName
  -- (they're in the scene as wreckage) but isExist() returns false. If we
  -- gated on isExist(), every method on the resulting handle (get_position,
  -- destroy, ...) would log+nil even though the static is in the world. Using
  -- getByName lets dead-spawned statics remain usable through the framework.
  -- DCS clears getByName lookups across frames after destroy, so the gate
  -- still correctly fires for actually-destroyed statics in subsequent frames.
  return StaticObject.getByName(name) ~= nil
end

sms.static.get_name = function(s)
  return _name_of(s)
end

sms.static.get_position = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_position: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local p = StaticObject.getByName(name):getPoint()
  -- DCS world coords: x = east, y = altitude, z = north.
  return {x = p.x, y = p.y, z = p.z}
end

sms.static.get_coalition = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_coalition: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local c = StaticObject.getByName(name):getCoalition()
  local s_str = sms.utils.coalition_int_to_str(c)
  if not s_str then
    log.error("get_coalition: '" .. tostring(name) .. "' returned unknown coalition " .. tostring(c))
    return nil
  end
  return s_str
end

sms.static.get_country = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_country: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  local int = StaticObject.getByName(name):getCountry()
  _build_country_reverse()
  local c_str = _country_reverse[int]
  if not c_str then
    log.error("get_country: '" .. tostring(name) .. "' returned unknown country " .. tostring(int))
    return nil
  end
  return c_str
end

sms.static.get_type = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("get_type: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  return StaticObject.getByName(name):getTypeName()
end

sms.static.destroy = function(s)
  local name = _name_of(s)
  if not sms.static.is_alive(name) then
    log.error("destroy: '" .. tostring(name) .. "' no longer exists in mission")
    return nil
  end
  StaticObject.getByName(name):destroy()
  return true
end

-- ============================================================
-- DCS def builder (factories)
-- ============================================================

local function _build_def(cfg, resolved_name)
  local heading_deg = cfg.heading or 0
  local heading_rad = sms.utils.deg_to_rad(heading_deg) or 0

  local def = {
    name    = resolved_name,
    type    = cfg.type,
    -- DCS-2D: x = vec3.x (east), y = vec3.z (north)
    x       = cfg.position.x,
    y       = cfg.position.z,
    heading = heading_rad,
  }

  -- Blessed optional fields
  if cfg.category   ~= nil then def.category   = cfg.category   end
  if cfg.dead       ~= nil then def.dead       = cfg.dead       end
  if cfg.mass       ~= nil then def.mass       = cfg.mass       end
  if cfg.canCargo   ~= nil then def.canCargo   = cfg.canCargo   end
  if cfg.shape_name ~= nil then def.shape_name = cfg.shape_name end
  if cfg.livery_id  ~= nil then def.livery_id  = cfg.livery_id  end

  -- Pitch/bank: warn-and-drop. DCS silently ignores these on
  -- coalition.addStaticObject (verified empirically across hangars, cargo,
  -- planes, and dead-state planes). v1 logger has no warning level; using
  -- log.info with explicit "warning:" text so it's both searchable and
  -- the call still succeeds.
  if cfg.pitch ~= nil or cfg.bank ~= nil then
    log.info("create: warning: pitch/bank are ignored by DCS on statics; dropping (only heading is applied)")
  end

  -- Pass-through unknown fields verbatim (forward-compat). pitch/bank are
  -- explicitly excluded since DCS silently drops them anyway.
  local known = {
    name = true, type = true, position = true, country = true, heading = true,
    category = true, dead = true, mass = true, canCargo = true,
    shape_name = true, livery_id = true,
    pitch = true, bank = true,  -- explicitly filtered (warned above)
  }
  for k, v in pairs(cfg) do
    if not known[k] and def[k] == nil then
      def[k] = v
    end
  end

  return def
end

local function _spawn(def, country_int, resolved_name)
  -- coalition.addStaticObject may error on bad input. Wrap in pcall.
  local ok, err = pcall(coalition.addStaticObject, country_int, def)
  if not ok then
    log.error("DCS rejected the spawn: " .. tostring(err))
    return nil
  end
  if not StaticObject.getByName(resolved_name) then
    log.error("DCS accepted addStaticObject but static '" .. resolved_name ..
              "' not found post-call (check type/category validity)")
    return nil
  end
  return sms.static(resolved_name)
end

-- ============================================================
-- create
-- ============================================================

local function _validate_create_config(cfg)
  if type(cfg) ~= "table" then
    log.error("create: config must be a table")
    return false
  end
  if type(cfg.name) ~= "string" or cfg.name == "" then
    log.error("create: name is required (non-empty string)")
    return false
  end
  if type(cfg.type) ~= "string" or cfg.type == "" then
    log.error("create: type is required (non-empty string)")
    return false
  end
  if not _is_vec3(cfg.position) then
    log.error("create: position is required (vec3 with x/y/z numbers)")
    return false
  end
  if type(cfg.country) ~= "string" then
    log.error("create: country is required (string)")
    return false
  end
  if cfg.heading ~= nil and type(cfg.heading) ~= "number" then
    log.error("create: heading must be a number (degrees) if provided")
    return false
  end
  if cfg.category ~= nil and type(cfg.category) ~= "string" then
    log.error("create: category must be a string if provided")
    return false
  end
  return true
end

sms.static.create = function(cfg)
  if not _validate_create_config(cfg) then return nil end

  local country_int = _resolve_country(cfg.country)
  if not country_int then
    log.error("create: unknown country '" .. tostring(cfg.country) .. "'")
    return nil
  end

  local resolved_name = _resolve_unique_name(cfg.name)
  local def = _build_def(cfg, resolved_name)
  return _spawn(def, country_int, resolved_name)
end

-- ============================================================
-- clone
-- ============================================================

-- Walk env.mission.coalition[red/blue/neutrals].country[*].static.group[]
-- for a "group" with matching name. In the ME mission descriptor each
-- static is wrapped in a single-unit "group" with units[1] holding the
-- actual static def.
local function _find_template_in_mission(template_name)
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country_entry in ipairs(side.country) do
        if country_entry.static and country_entry.static.group then
          for _, sg in ipairs(country_entry.static.group) do
            if sg.name == template_name and sg.units and sg.units[1] then
              return {
                def_unit    = sg.units[1],
                country_int = country_entry.id,
                group_name  = sg.name,
              }
            end
          end
        end
      end
    end
  end
  return nil
end

sms.static.clone = function(template_name, overrides)
  if type(template_name) ~= "string" or template_name == "" then
    log.error("clone: template_name must be a non-empty string")
    return nil
  end
  if type(overrides) ~= "table" then
    log.error("clone: overrides must be a table")
    return nil
  end
  if type(overrides.name) ~= "string" or overrides.name == "" then
    log.error("clone: overrides.name is required (non-empty string)")
    return nil
  end
  if not _is_vec3(overrides.position) then
    log.error("clone: overrides.position is required (vec3)")
    return nil
  end

  local found = _find_template_in_mission(template_name)
  if not found then
    log.error("clone: template '" .. template_name .. "' not in mission")
    return nil
  end

  local def = _deep_copy(found.def_unit)

  -- Strip ME-assigned ids so DCS gets fresh ones for the clone.
  def.unitId = nil
  def.groupId = nil

  -- Re-anchor: replace x/y with new world position (DCS-2D translation).
  def.x = overrides.position.x
  def.y = overrides.position.z

  -- New unique name.
  local resolved_name = _resolve_unique_name(overrides.name)
  def.name = resolved_name

  return _spawn(def, found.country_int, resolved_name)
end

-- ============================================================
-- Sugar constructor
-- ============================================================

-- sms.static("name") -> handle | nil + log.
sms._make_callable_handle(sms.static, StaticObject.getByName, log)
