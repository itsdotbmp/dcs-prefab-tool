-- dcs-sms framework: options module (sms.options).
--
-- Builders for DCS persistent controller options
-- (Group:getController():setOption). Each builder returns a table
-- {id (int|nil), params|value, _sms_verb, _sms_air_only|_sms_ground_only|_sms_naval_only|_sms_roe}.
-- Application via sms.group:set_option(opt) — installed in group.lua.
--
-- ROE is special: the builder returns an id-less table tagged with
-- _sms_roe = true; set_option resolves the right AI.Option.{Air,Ground,Naval}.id.ROE
-- and validates the value at apply time using the helpers below.
--
-- Loading order: ... -> task.lua -> commands.lua -> options.lua.
-- Depends on: sms.group, sms.utils.

assert(type(sms)         == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log)     == "table", "framework/log.lua must be loaded first")
assert(type(sms.group)   == "table", "framework/group.lua must be loaded first")
assert(type(sms.utils)   == "table", "framework/utils.lua must be loaded first")

---@class sms.options
sms.options = sms.options or {}

local log = sms.log.module("sms.options")

-- An option table built by an sms.options.* builder. Returned by all
-- builders; consumed by sms.group.set_option. The id is nil for the ROE
-- builder (resolved at apply time via _sms_roe + group category).
---@class sms.options.option
---@field id integer?
---@field params any?
---@field value string?
---@field _sms_verb string?
---@field _sms_air_only boolean?
---@field _sms_ground_only boolean?
---@field _sms_naval_only boolean?
---@field _sms_roe boolean?

local function _stamp(t, verb, air_only, ground_only, naval_only)
  t._sms_verb = verb
  if air_only    then t._sms_air_only    = true end
  if ground_only then t._sms_ground_only = true end
  if naval_only  then t._sms_naval_only  = true end
  return t
end

-- ============================================================
-- Enum tables (lowercase strings; builders accept either constant or string)
-- ============================================================

sms.options.ROE = {
  WEAPON_FREE           = "weapon_free",
  OPEN_FIRE_WEAPON_FREE = "open_fire_weapon_free",
  OPEN_FIRE             = "open_fire",
  RETURN_FIRE           = "return_fire",
  WEAPON_HOLD           = "weapon_hold",
}

sms.options.REACTION_ON_THREAT = {
  NO_REACTION         = "no_reaction",
  PASSIVE_DEFENCE     = "passive_defence",
  EVADE_FIRE          = "evade_fire",
  BYPASS_AND_ESCAPE   = "bypass_and_escape",
  ALLOW_ABORT_MISSION = "allow_abort_mission",
}

sms.options.RADAR_USING = {
  NEVER                  = "never",
  FOR_ATTACK_ONLY        = "for_attack_only",
  FOR_SEARCH_IF_REQUIRED = "for_search_if_required",
  FOR_CONTINUOUS_SEARCH  = "for_continuous_search",
}

sms.options.FLARE_USING = {
  NEVER                    = "never",
  AGAINST_FIRED_MISSILE    = "against_fired_missile",
  WHEN_FLYING_IN_SAM_WEZ   = "when_flying_in_sam_wez",
  WHEN_FLYING_NEAR_ENEMIES = "when_flying_near_enemies",
}

sms.options.ALARM_STATE = { AUTO = "auto", GREEN = "green", RED = "red" }

-- Air formation presets — strings here; builder maps to DCS packed integers.
-- Builder also accepts a raw integer for unknown formations.
sms.options.FORMATION = {
  LINE_ABREAST  = "line_abreast",
  TRAIL         = "trail",
  WEDGE         = "wedge",
  ECHELON_RIGHT = "echelon_right",
  ECHELON_LEFT  = "echelon_left",
  FINGER_FOUR   = "finger_four",
  SPREAD        = "spread",
}

-- ============================================================
-- Internal lookup tables
-- ============================================================

-- DCS air formation -> packed integer (per AI.Formation enum).
-- Verified against MOOSE Wrapper/Controllable.lua and DCS docs.
local _formation_dcs = {
  line_abreast  = 65537,    -- LINE_ABREAST
  trail         = 131073,   -- TRAIL
  wedge         = 196609,   -- WEDGE
  echelon_right = 262145,   -- ECHELON_RIGHT
  echelon_left  = 327681,   -- ECHELON_LEFT
  finger_four   = 393217,   -- FINGER_FOUR
  spread        = 458753,   -- SPREAD
}

-- Air ROE: lowercase string -> AI.Option.Air.val.ROE numeric.
local _roe_air = {
  weapon_free           = 0,
  open_fire_weapon_free = 1,
  open_fire             = 2,
  return_fire           = 3,
  weapon_hold           = 4,
}

-- Ground ROE.
local _roe_ground = {
  open_fire   = 0,
  return_fire = 1,
  weapon_hold = 2,
}

-- Naval ROE (same shape as ground in DCS).
local _roe_naval = {
  open_fire   = 0,
  return_fire = 1,
  weapon_hold = 2,
}

local _reaction_on_threat = {
  no_reaction         = 0,
  passive_defence     = 1,
  evade_fire          = 2,
  bypass_and_escape   = 3,
  allow_abort_mission = 4,
}

local _radar_using = {
  never                  = 0,
  for_attack_only        = 1,
  for_search_if_required = 2,
  for_continuous_search  = 3,
}

local _flare_using = {
  never                    = 0,
  against_fired_missile    = 1,
  when_flying_in_sam_wez   = 2,
  when_flying_near_enemies = 3,
}

local _alarm_state = { auto = 0, green = 1, red = 2 }

-- ============================================================
-- ROE category dispatch helpers (used by group.lua's set_option)
-- ============================================================

-- Resolve which DCS option id and value table to use for a given group
-- category. Returns id, value_table, category_name (for log messages).
sms.options._roe_resolve_for_category = function(category)
  if category == "airplane" or category == "helicopter" then
    return AI.Option.Air.id.ROE, _roe_air, "air"
  elseif category == "ground" or category == "train" then
    return AI.Option.Ground.id.ROE, _roe_ground, "ground"
  elseif category == "ship" then
    return AI.Option.Naval.id.ROE, _roe_naval, "naval"
  end
  return nil, nil, tostring(category)
end

-- Validate an ROE value against a category. Returns true on success;
-- false + reason string otherwise. Called by group.lua's _validate_apply
-- when payload._sms_roe is set.
sms.options._validate_roe = function(value, category)
  if type(value) ~= "string" then
    return false, "roe value must be a string, got " .. type(value)
  end
  local _, value_table, cat_name = sms.options._roe_resolve_for_category(category)
  if not value_table then
    return false, "roe: unsupported category '" .. cat_name .. "'"
  end
  if value_table[value] == nil then
    return false, "roe: value '" .. value .. "' not allowed for " .. cat_name .. " groups"
  end
  return true
end

-- Look up the DCS-side numeric value for a validated (category, value) pair.
-- Caller must have already passed _validate_roe.
sms.options._roe_value_to_dcs = function(value, category)
  local _, value_table = sms.options._roe_resolve_for_category(category)
  return value_table and value_table[value] or nil
end

-- ============================================================
-- ROE builder (special: id resolved at apply time via _sms_roe marker)
-- ============================================================

---@param value string  # sms.options.ROE.* enum string
---@return sms.options.option|nil
sms.options.roe = function(value)
  if type(value) ~= "string" then
    log.warn("roe: value must be a string, got " .. type(value))
    return nil
  end
  -- Validate the string is at least known to one of the three category sets.
  -- Apply layer enforces category-specific allowed values; this is just a
  -- "did you mistype it entirely" guard.
  if not (_roe_air[value] or _roe_ground[value] or _roe_naval[value]) then
    log.warn("roe: unknown value '" .. value .. "'")
    return nil
  end
  local t = { _sms_roe = true, value = value }
  return _stamp(t, "roe", false)
end

-- ============================================================
-- Air-only enum builders
-- ============================================================

---@param value string  # sms.options.REACTION_ON_THREAT.* enum string
---@return sms.options.option|nil
sms.options.reaction_on_threat = function(value)
  if type(value) ~= "string" or _reaction_on_threat[value] == nil then
    log.warn("reaction_on_threat: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.REACTION_ON_THREAT,
    params = _reaction_on_threat[value],
  }, "reaction_on_threat", true)
end

---@param value string  # sms.options.RADAR_USING.* enum string
---@return sms.options.option|nil
sms.options.radar_using = function(value)
  if type(value) ~= "string" or _radar_using[value] == nil then
    log.warn("radar_using: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.RADAR_USING,
    params = _radar_using[value],
  }, "radar_using", true)
end

---@param value string  # sms.options.FLARE_USING.* enum string
---@return sms.options.option|nil
sms.options.flare_using = function(value)
  if type(value) ~= "string" or _flare_using[value] == nil then
    log.warn("flare_using: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.FLARE_USING,
    params = _flare_using[value],
  }, "flare_using", true)
end

-- ============================================================
-- Formation builders (air-only)
-- ============================================================

-- formation accepts either a sms.options.FORMATION string preset or a raw
-- DCS packed integer (escape hatch for formations not in the preset list).
---@param value string|integer  # sms.options.FORMATION.* preset or DCS packed integer
---@return sms.options.option|nil
sms.options.formation = function(value)
  local packed
  if type(value) == "number" then
    packed = value
  elseif type(value) == "string" then
    packed = _formation_dcs[value]
    if packed == nil then
      log.warn("formation: unknown preset '" .. value .. "'")
      return nil
    end
  else
    log.warn("formation: value must be a string preset or DCS integer, got " .. type(value))
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.FORMATION,
    params = packed,
  }, "formation", true)
end

-- Spacing in meters between formation members.
---@param meters number  # non-negative
---@return sms.options.option|nil
sms.options.formation_interval = function(meters)
  if type(meters) ~= "number" or meters < 0 then
    log.warn("formation_interval: meters must be a non-negative number")
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.FORMATION_INTERVAL,
    params = meters,
  }, "formation_interval", true)
end

-- ============================================================
-- Air-only boolean builders
-- ============================================================

---@param verb string
---@param dcs_id integer
---@return fun(value: boolean): sms.options.option|nil
local function _make_bool_air_option(verb, dcs_id)
  return function(value)
    if type(value) ~= "boolean" then
      log.warn(verb .. ": value must be a boolean, got " .. type(value))
      return nil
    end
    return _stamp({ id = dcs_id, params = value }, verb, true)
  end
end

sms.options.rtb_on_bingo       = _make_bool_air_option("rtb_on_bingo",       AI.Option.Air.id.RTB_ON_BINGO)
sms.options.rtb_on_bingo_ammo  = _make_bool_air_option("rtb_on_bingo_ammo",  AI.Option.Air.id.RTB_ON_OUT_OF_AMMO)
sms.options.silence            = _make_bool_air_option("silence",            AI.Option.Air.id.SILENCE)
sms.options.jettison_empty_tanks = _make_bool_air_option("jettison_empty_tanks", AI.Option.Air.id.JETT_TANKS_IF_EMPTY)
sms.options.landing_straight_in     = _make_bool_air_option("landing_straight_in",     AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_STRAIGHT_IN)
sms.options.landing_force_pair      = _make_bool_air_option("landing_force_pair",      AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_FORCE_PAIR)
sms.options.landing_restrict_pair   = _make_bool_air_option("landing_restrict_pair",   AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_RESTRICT_PAIR)
sms.options.landing_overhead_break  = _make_bool_air_option("landing_overhead_break",  AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_OVERHEAD_BREAK)

-- waypoint_pass_report flips the user-facing semantics: DCS exposes this
-- as PROHIBIT_WP_PASS_REPORT (inverted). We expose `true = report` and
-- invert internally so users don't think backwards.
---@param value boolean
---@return sms.options.option|nil
sms.options.waypoint_pass_report = function(value)
  if type(value) ~= "boolean" then
    log.warn("waypoint_pass_report: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({
    id     = AI.Option.Air.id.PROHIBIT_WP_PASS_REPORT,
    params = not value,                  -- inverted: false = "do report"
  }, "waypoint_pass_report", true)
end

-- ============================================================
-- Radio reporting (air-only). Accepts a list of DCS attribute strings.
-- Defaults to {"Air"} when nil/empty (matches MOOSE).
-- ============================================================

---@param verb string
---@param dcs_id integer
---@return fun(attrs: string[]|string|nil): sms.options.option|nil
local function _make_radio_option(verb, dcs_id)
  return function(attrs)
    if attrs == nil then attrs = { "Air" } end
    if type(attrs) == "string" then attrs = { attrs } end
    if type(attrs) ~= "table" then
      log.warn(verb .. ": attrs must be a table or string, got " .. type(attrs))
      return nil
    end
    for i, a in ipairs(attrs) do
      if type(a) ~= "string" then
        log.warn(verb .. ": attrs[" .. i .. "] must be a string, got " .. type(a))
        return nil
      end
    end
    return _stamp({ id = dcs_id, params = attrs }, verb, true)
  end
end

sms.options.radio_contact = _make_radio_option("radio_contact", AI.Option.Air.id.OPTION_RADIO_USAGE_CONTACT)
sms.options.radio_engage  = _make_radio_option("radio_engage",  AI.Option.Air.id.OPTION_RADIO_USAGE_ENGAGE)
sms.options.radio_kill    = _make_radio_option("radio_kill",    AI.Option.Air.id.OPTION_RADIO_USAGE_KILL)

-- ============================================================
-- Ground-only builders
-- ============================================================

---@param value string  # sms.options.ALARM_STATE.* enum string
---@return sms.options.option|nil
sms.options.alarm_state = function(value)
  if type(value) ~= "string" or _alarm_state[value] == nil then
    log.warn("alarm_state: unknown or invalid value '" .. tostring(value) .. "'")
    return nil
  end
  return _stamp({
    id     = AI.Option.Ground.id.ALARM_STATE,
    params = _alarm_state[value],
  }, "alarm_state", false, true)
end

-- DCS takes seconds (integer). 0 disables; positive value sets duration.
---@param seconds number  # non-negative; 0 disables
---@return sms.options.option|nil
sms.options.disperse_on_attack = function(seconds)
  if type(seconds) ~= "number" or seconds < 0 then
    log.warn("disperse_on_attack: seconds must be a non-negative number")
    return nil
  end
  return _stamp({
    id     = AI.Option.Ground.id.DISPERSE_ON_ATTACK,
    params = seconds,
  }, "disperse_on_attack", false, true)
end
