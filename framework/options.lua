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

sms.options = sms.options or {}

local log = sms.log.module("sms.options")

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
