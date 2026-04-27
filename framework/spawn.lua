-- dcs-sms framework: spawn module.
--
-- Adds two factory functions to sms.group:
--   sms.group.create(config)             -> sms.group handle | nil + log
--   sms.group.clone(template, overrides) -> sms.group handle | nil + log
--
-- Stateless. Plain config tables. Auto-suffixes on name collision (so
-- create({name = "tank"}) called repeatedly yields tank, tank-1, tank-2,
-- ...). The returned handle's :get_name() is authoritative for the resolved
-- name — always use the handle, not the input string, for follow-up ops.
--
-- Public field names: position (group anchor, vec3), offset (per-unit
-- relative, vec3). Heading is in DEGREES; altitude is in METERS.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> group.lua -> unit.lua
-- -> area.lua -> spawn.lua. spawn.lua does not depend on area.lua but is
-- loaded after for consistency.
--
-- See docs/superpowers/specs/2026-04-26-framework-spawn-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.group) == "table", "framework/group.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
local log = sms.log.module("sms.spawn")

-- ============================================================
-- Module-private state and lookup tables
-- ============================================================

-- base_name -> next-index hint for auto-suffix. Lost on reload (probe
-- recovers).
local _name_counters = {}

-- "ground" -> Group.Category.GROUND etc.
local _category_map = {
  ground     = Group.Category.GROUND,
  airplane   = Group.Category.AIRPLANE,
  helicopter = Group.Category.HELICOPTER,
  ship       = Group.Category.SHIP,
  train      = Group.Category.TRAIN,
}

-- Default group-level task per category.
local _default_task = {
  ground     = "Ground Nothing",
  airplane   = "Nothing",
  helicopter = "Nothing",
  ship       = "Nothing",
  train      = "Nothing",
}

-- Mission-descriptor category keys (env.mission.coalition.<side>.country[i].<cat>)
-- mapped to our category strings.
local _mission_cat_to_string = {
  plane      = "airplane",
  helicopter = "helicopter",
  vehicle    = "ground",
  ship       = "ship",
  train      = "train",
}

-- ============================================================
-- Validation helpers
-- ============================================================

-- _is_vec3 / _resolve_country lifted to sms.utils (issue #14). Local
-- aliases below keep the rest of this file's call-sites compact.
local _is_vec3 = sms.utils.is_vec3
local _resolve_country = sms.utils.resolve_country

local function _resolve_category(s)
  if type(s) ~= "string" then return nil end
  return _category_map[s:lower()]
end

-- ============================================================
-- Auto-suffix name resolution
-- ============================================================

-- Check whether `name` is taken by any group OR unit — DCS shares the
-- name namespace across both, so a unit named "tank-1" makes
-- Group.getByName("tank-1") return truthy too. We check both to ensure
-- the resolved name is genuinely free in DCS.
local function _name_taken(name)
  return Group.getByName(name) ~= nil or Unit.getByName(name) ~= nil
end

-- Resolve a unique name using base + numeric suffix. Probes both group
-- and unit namespaces; counter is a hint, probing is source of truth.
local function _resolve_unique_name(base)
  if not _name_taken(base) then return base end
  local n = _name_counters[base] or 1
  while _name_taken(base .. "-" .. n) do
    n = n + 1
  end
  _name_counters[base] = n + 1
  return base .. "-" .. n
end

-- ============================================================
-- DCS group_def builder
-- ============================================================

-- Build a single DCS unit table from a unit spec, anchor, and category.
-- Mutates u_spec is forbidden — we read fields and copy what we need.
local function _build_dcs_unit(u_spec, anchor, category, base_unit_name, idx)
  local offset = u_spec.offset or {x = 0, y = 0, z = 0}
  local heading_deg = u_spec.heading or 0
  local heading_rad = sms.utils.deg_to_rad(heading_deg) or 0

  -- Auto-suffix the unit name. If user provided one, suffix it. Otherwise
  -- auto-generate from the resolved group name + index.
  -- Note: unit auto-gen uses "_" separator (not "-") to avoid colliding
  -- with auto-suffixed group names which use "-<n>".
  local desired_name
  if type(u_spec.name) == "string" then
    desired_name = u_spec.name
  else
    desired_name = base_unit_name .. "_" .. idx
  end
  local resolved_unit_name = _resolve_unique_name(desired_name)

  local dcs_unit = {
    name    = resolved_unit_name,
    type    = u_spec.type,
    -- DCS-2D: x = vec3.x (east), y = vec3.z (north)
    x       = anchor.x + offset.x,
    y       = anchor.z + offset.z,
    heading = heading_rad,
    psi     = -heading_rad,  -- DCS internal yaw, computed from heading
    skill   = u_spec.skill or "Average",
  }

  -- Optional universal fields
  if u_spec.livery_id   ~= nil then dcs_unit.livery_id   = u_spec.livery_id end
  if u_spec.onboard_num ~= nil then dcs_unit.onboard_num = u_spec.onboard_num end

  -- Air-specific fields
  if category == "airplane" or category == "helicopter" then
    if u_spec.alt        ~= nil then dcs_unit.alt        = u_spec.alt end
    if u_spec.alt_type   ~= nil then dcs_unit.alt_type   = u_spec.alt_type else dcs_unit.alt_type = "BARO" end
    if u_spec.speed      ~= nil then
      dcs_unit.speed = u_spec.speed
    elseif category == "airplane" then
      dcs_unit.speed = 200  -- airplanes need forward speed or they stall; helicopters default to 0 (hover)
    end
    if u_spec.payload    ~= nil then dcs_unit.payload    = u_spec.payload end
    if u_spec.callsign   ~= nil then dcs_unit.callsign   = u_spec.callsign end
    if u_spec.frequency  ~= nil then dcs_unit.frequency  = u_spec.frequency end
    if u_spec.modulation ~= nil then dcs_unit.modulation = u_spec.modulation end
    if u_spec.parking_id ~= nil then dcs_unit.parking_id = u_spec.parking_id end
  end

  -- Pass-through any unknown fields verbatim
  local known = {
    name = true, type = true, offset = true, heading = true, skill = true,
    livery_id = true, onboard_num = true, alt = true, alt_type = true,
    speed = true, payload = true, callsign = true, frequency = true,
    modulation = true, parking_id = true,
  }
  for k, v in pairs(u_spec) do
    if not known[k] and dcs_unit[k] == nil then
      dcs_unit[k] = v
    end
  end

  return dcs_unit
end

-- Default route for aircraft: single waypoint 50km north of anchor.
local function _default_route_for_aircraft(anchor, first_unit_alt)
  local alt = first_unit_alt or 5000
  return {
    points = {
      [1] = {
        type     = "Turning Point",
        action   = "Turning Point",
        x        = anchor.x,
        y        = anchor.z + 50000,  -- DCS-2D north
        alt      = alt,
        alt_type = "BARO",
        speed    = 200,
        task     = { id = "ComboTask", params = { tasks = {} } },
      },
    },
  }
end

-- Build the full DCS group_def from a validated cfg + resolved group name.
local function _build_dcs_group_def(cfg, resolved_group_name, category)
  local anchor = cfg.position
  local task = cfg.task or _default_task[category] or "Nothing"

  local dcs_units = {}
  for i, u_spec in ipairs(cfg.units) do
    dcs_units[i] = _build_dcs_unit(u_spec, anchor, category, resolved_group_name, i)
  end

  local def = {
    name  = resolved_group_name,
    task  = task,
    units = dcs_units,
  }

  -- Route handling
  if cfg.route ~= nil then
    def.route = cfg.route
  elseif category == "airplane" or category == "helicopter" then
    def.route = _default_route_for_aircraft(anchor, cfg.units[1].alt)
  end

  -- Pass-through unknown group-level fields
  local known = {
    name = true, position = true, country = true, category = true,
    task = true, route = true, units = true,
  }
  for k, v in pairs(cfg) do
    if not known[k] and def[k] == nil then
      def[k] = v
    end
  end

  return def
end

-- ============================================================
-- Spawn execution
-- ============================================================

local function _spawn(group_def, country_int, category_int, resolved_group_name)
  -- coalition.addGroup may error on bad input. Wrap in pcall.
  local ok, err = pcall(coalition.addGroup, country_int, category_int, group_def)
  if not ok then
    log.error("DCS rejected the spawn: " .. tostring(err))
    return nil
  end
  -- Verify by name
  if not Group.getByName(resolved_group_name) then
    log.error("DCS accepted addGroup but group '" .. resolved_group_name .. "' not found post-call (check type/payload validity)")
    return nil
  end
  return sms.group(resolved_group_name)
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
  if not _is_vec3(cfg.position) then
    log.error("create: position is required (vec3 with x/y/z numbers)")
    return false
  end
  if type(cfg.country) ~= "string" then
    log.error("create: country is required (string)")
    return false
  end
  if type(cfg.units) ~= "table" or #cfg.units == 0 then
    log.error("create: units is required (non-empty table)")
    return false
  end
  for i, u in ipairs(cfg.units) do
    if type(u) ~= "table" then
      log.error("create: unit " .. i .. " must be a table")
      return false
    end
    if type(u.type) ~= "string" or u.type == "" then
      log.error("create: unit " .. i .. " missing type")
      return false
    end
    if u.offset ~= nil and not _is_vec3(u.offset) then
      log.error("create: unit " .. i .. " offset must be a vec3")
      return false
    end
    if u.heading ~= nil and type(u.heading) ~= "number" then
      log.error("create: unit " .. i .. " heading must be a number (degrees)")
      return false
    end
  end
  return true
end

sms.group.create = function(cfg)
  if not _validate_create_config(cfg) then return nil end

  local country_int = _resolve_country(cfg.country)
  if not country_int then
    log.error("create: unknown country '" .. tostring(cfg.country) .. "'")
    return nil
  end

  local category_str = (cfg.category or "ground"):lower()
  local category_int = _resolve_category(category_str)
  if not category_int then
    log.error("create: unknown category '" .. tostring(cfg.category) .. "'")
    return nil
  end

  -- Air-specific validation: every unit must have alt
  if category_str == "airplane" or category_str == "helicopter" then
    for i, u in ipairs(cfg.units) do
      if type(u.alt) ~= "number" then
        log.error("create: air unit " .. i .. " missing alt (meters)")
        return nil
      end
    end
  end

  local resolved_group_name = _resolve_unique_name(cfg.name)
  local group_def = _build_dcs_group_def(cfg, resolved_group_name, category_str)
  return _spawn(group_def, country_int, category_int, resolved_group_name)
end

-- ============================================================
-- clone
-- ============================================================

-- Walk env.mission.coalition[*].country[*].<category>.group[] for the named group.
-- Returns {def, country_int, category_string} or nil.
local function _find_template_in_mission(template_name)
  if not env.mission or not env.mission.coalition then return nil end
  local side_keys = {"red", "blue", "neutrals"}
  for _, sk in ipairs(side_keys) do
    local side = env.mission.coalition[sk]
    if side and side.country then
      for _, country_entry in ipairs(side.country) do
        for cat_key, cat_string in pairs(_mission_cat_to_string) do
          local cat = country_entry[cat_key]
          if cat and cat.group then
            for _, g in ipairs(cat.group) do
              if g.name == template_name then
                return {
                  def = g,
                  country_int = country_entry.id,
                  category_string = cat_string,
                }
              end
            end
          end
        end
      end
    end
  end
  return nil
end

-- _deep_copy lifted to sms.utils.deep_copy (issue #14).
local _deep_copy = sms.utils.deep_copy

sms.group.clone = function(template_name, overrides)
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

  local cat_int = _resolve_category(found.category_string)
  if not cat_int then
    log.error("clone: internal error — unknown category '" .. tostring(found.category_string) .. "'")
    return nil
  end

  local def = _deep_copy(found.def)
  if not def.units or #def.units == 0 then
    log.error("clone: template '" .. template_name .. "' has no units")
    return nil
  end

  -- Strip the template's groupId / unitId so DCS assigns fresh IDs to
  -- the clone. Empirically DCS forgives duplicate IDs, but relying on
  -- undocumented forgiveness is fragile.
  def.groupId = nil
  for _, u in ipairs(def.units) do
    u.unitId = nil
  end

  -- Compute original anchor (leader unit's DCS-2D position).
  local orig_x = def.units[1].x
  local orig_y = def.units[1].y  -- DCS-2D y == our z

  -- New anchor from overrides.
  local new_anchor = overrides.position

  -- Re-anchor every unit: original (x, y) -> new (anchor.x + dx, anchor.z + dy)
  for _, u in ipairs(def.units) do
    local dx = u.x - orig_x
    local dz = u.y - orig_y
    u.x = new_anchor.x + dx
    u.y = new_anchor.z + dz
  end

  -- Resolve unique group name from overrides.
  local resolved_group_name = _resolve_unique_name(overrides.name)
  def.name = resolved_group_name

  -- Resolve unique unit names per unit. Unit auto-gen uses "_" to avoid
  -- collision with auto-suffixed group names ("-<n>").
  for i, u in ipairs(def.units) do
    local desired_unit_name = u.name or (resolved_group_name .. "_" .. i)
    u.name = _resolve_unique_name(desired_unit_name)
  end

  -- Update route waypoint 1 if present (keep relative shape; just shift first point to new anchor).
  -- For v1 we don't try to be clever with subsequent waypoints; users override route via create() for that.
  if def.route and def.route.points and def.route.points[1] then
    def.route.points[1].x = new_anchor.x
    def.route.points[1].y = new_anchor.z
  end

  return _spawn(def, found.country_int, cat_int, resolved_group_name)
end
