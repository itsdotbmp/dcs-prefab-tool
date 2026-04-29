-- dcs-sms framework: commands module (sms.commands).
--
-- Builders for DCS one-shot controller commands (Group:getController():setCommand).
-- Each builder returns a plain DCS command table {id, params, ...} with a
-- private _sms_verb tag (and optionally _sms_air_only) used by the apply
-- layer for log messages and category enforcement.
--
-- Application via sms.group:set_command(cmd) — installed in group.lua.
--
-- Loading order: ... -> task.lua -> commands.lua -> options.lua.
-- Depends on: sms.group (for the apply method install path), sms.utils.

assert(type(sms)         == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log)     == "table", "framework/log.lua must be loaded first")
assert(type(sms.group)   == "table", "framework/group.lua must be loaded first")
assert(type(sms.utils)   == "table", "framework/utils.lua must be loaded first")

sms.commands = sms.commands or {}

local log = sms.log.module("sms.commands")

-- Stamp a command table with the framework's private markers.
-- Returns the same table for fluent use.
local function _stamp(t, verb, air_only)
  t._sms_verb = verb
  if air_only then t._sms_air_only = true end
  return t
end

-- ============================================================
-- Enum tables
-- ============================================================

-- Radio modulation (used by set_frequency / set_frequency_for_unit).
sms.commands.MODULATION = {
  AM = 0,
  FM = 1,
}

-- Beacon constants used by activate_beacon. Numeric DCS-native ids; the
-- framework passes them through verbatim.
sms.commands.BEACON = {
  TYPE = {
    NULL                       = 0,
    VOR                        = 2,
    DME                        = 3,
    TACAN                      = 4,
    VORTAC                     = 5,
    HOMER                      = 8,
    AIRPORT_HOMER              = 9,
    AIRPORT_HOMER_WITH_MARKER  = 10,
    ILS_FAR_HOMER              = 16,
    ILS_NEAR_HOMER             = 17,
    ILS_LOCALIZER              = 18,
    ILS_GLIDESLOPE             = 19,
    NAUTICAL_HOMER             = 65,
  },
  SYSTEM = {
    PAR_10            = 1,
    RSBN_5            = 2,
    TACAN             = 3,
    TACAN_TANKER_X    = 4,
    TACAN_TANKER_Y    = 5,
    VOR               = 6,
    ILS_LOCALIZER     = 7,
    ILS_GLIDESLOPE    = 8,
    BROADCAST_STATION = 9,
    VORTAC            = 10,
    TACAN_AA_MODE_X   = 11,
    TACAN_AA_MODE_Y   = 12,
    ICLS              = 13,
    ICLS_LOCALIZER    = 14,
    ICLS_GLIDESLOPE   = 15,
  },
}

-- DCS callsign numeric enum is huge and per-aircraft. Most users will pass
-- raw integers from DCS docs; the most common air-side namesakes are exposed
-- here as a starting set. Builders accept any positive integer (passthrough).
sms.commands.CALLSIGN = {
  -- Common AWACS / tanker / FAC numeric callnames (Aircraft.id range).
  -- Add more here as users encounter them.
  ENFIELD  = 1,
  SPRINGFIELD = 2,
  UZI      = 3,
  COLT     = 4,
  DODGE    = 5,
  FORD     = 6,
  CHEVY    = 7,
  PONTIAC  = 8,
  TEXACO   = 1,
  ARCO     = 2,
  SHELL    = 3,
  OVERLORD = 1,
  MAGIC    = 2,
  WIZARD   = 3,
  FOCUS    = 4,
  DARKSTAR = 5,
}

-- ============================================================
-- Simple builders (no special arg shapes, all-categories unless noted)
-- ============================================================

-- No-op command. Useful for clearing a queued command.
sms.commands.no_action = function()
  return _stamp({ id = "NoAction", params = {} }, "no_action", false)
end

-- Toggle visibility to AI sensors.
sms.commands.set_invisible = function(value)
  if type(value) ~= "boolean" then
    log.warn("set_invisible: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({ id = "SetInvisible", params = { value = value } }, "set_invisible", false)
end

-- Toggle damage immunity.
sms.commands.set_immortal = function(value)
  if type(value) ~= "boolean" then
    log.warn("set_immortal: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({ id = "SetImmortal", params = { value = value } }, "set_immortal", false)
end

-- Halt or resume the group's route.
sms.commands.stop_route = function(value)
  if type(value) ~= "boolean" then
    log.warn("stop_route: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({ id = "StopRoute", params = { value = value } }, "stop_route", false)
end

-- Switch to a triggered action by index.
sms.commands.switch_action = function(action_index)
  if type(action_index) ~= "number" then
    log.warn("switch_action: action_index must be a number, got " .. type(action_index))
    return nil
  end
  return _stamp({
    id = "SwitchAction",
    params = { actionIndex = action_index },
  }, "switch_action", false)
end

-- Toggle unlimited fuel on aircraft.
sms.commands.set_unlimited_fuel = function(value)
  if type(value) ~= "boolean" then
    log.warn("set_unlimited_fuel: value must be a boolean, got " .. type(value))
    return nil
  end
  return _stamp({
    id = "SetUnlimitedFuel",
    params = { value = value },
  }, "set_unlimited_fuel", true)
end

-- Toggle EPLRS datalink. group_id is optional; when omitted, DCS uses the
-- group the command is applied to.
sms.commands.eplrs = function(value, group_id)
  if type(value) ~= "boolean" then
    log.warn("eplrs: value must be a boolean, got " .. type(value))
    return nil
  end
  if group_id ~= nil and type(group_id) ~= "number" then
    log.warn("eplrs: group_id must be a number when given, got " .. type(group_id))
    return nil
  end
  local params = { value = value }
  if group_id then params.groupId = group_id end
  return _stamp({ id = "EPLRS", params = params }, "eplrs", false)
end
