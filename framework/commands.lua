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

-- ============================================================
-- Frequency builders
-- ============================================================

-- Set the group's radio frequency. modulation is sms.commands.MODULATION.AM
-- (default) or .FM. power is optional (W); DCS picks a reasonable default
-- when nil.
sms.commands.set_frequency = function(hz, modulation, power)
  if type(hz) ~= "number" then
    log.warn("set_frequency: hz must be a number, got " .. type(hz))
    return nil
  end
  if modulation == nil then modulation = sms.commands.MODULATION.AM end
  if type(modulation) ~= "number" then
    log.warn("set_frequency: modulation must be a number, got " .. type(modulation))
    return nil
  end
  if power ~= nil and type(power) ~= "number" then
    log.warn("set_frequency: power must be a number when given, got " .. type(power))
    return nil
  end
  local params = { frequency = hz, modulation = modulation }
  if power then params.power = power end
  return _stamp({ id = "SetFrequency", params = params }, "set_frequency", false)
end

-- Per-unit variant; unit_id is the integer DCS unit id.
sms.commands.set_frequency_for_unit = function(hz, modulation, power, unit_id)
  if type(hz) ~= "number" then
    log.warn("set_frequency_for_unit: hz must be a number, got " .. type(hz))
    return nil
  end
  if type(unit_id) ~= "number" then
    log.warn("set_frequency_for_unit: unit_id must be a number, got " .. type(unit_id))
    return nil
  end
  if modulation == nil then modulation = sms.commands.MODULATION.AM end
  if type(modulation) ~= "number" then
    log.warn("set_frequency_for_unit: modulation must be a number, got " .. type(modulation))
    return nil
  end
  if power ~= nil and type(power) ~= "number" then
    log.warn("set_frequency_for_unit: power must be a number when given, got " .. type(power))
    return nil
  end
  local params = { frequency = hz, modulation = modulation, unitId = unit_id }
  if power then params.power = power end
  return _stamp({ id = "SetFrequencyForUnit", params = params }, "set_frequency_for_unit", false)
end

-- ============================================================
-- Waypoint
-- ============================================================

-- Jump from waypoint index `from_idx` to `to_idx` (DCS uses 0-based).
sms.commands.switch_waypoint = function(from_idx, to_idx)
  if type(from_idx) ~= "number" or type(to_idx) ~= "number" then
    log.warn("switch_waypoint: both indices must be numbers")
    return nil
  end
  return _stamp({
    id = "SwitchWaypoint",
    params = { fromWaypointIndex = from_idx, goToWaypointIndex = to_idx },
  }, "switch_waypoint", false)
end

-- ============================================================
-- Callsign (air-only)
-- ============================================================

-- Set the AI radio callsign. callname is a numeric DCS callname enum
-- (sms.commands.CALLSIGN.* or any DCS Aircraft.id integer). number is the
-- flight number (default 1).
sms.commands.set_callsign = function(callname, number)
  if type(callname) ~= "number" then
    log.warn("set_callsign: callname must be a number, got " .. type(callname))
    return nil
  end
  if number == nil then number = 1 end
  if type(number) ~= "number" then
    log.warn("set_callsign: number must be a number when given, got " .. type(number))
    return nil
  end
  return _stamp({
    id = "SetCallsign",
    params = { callname = callname, number = number },
  }, "set_callsign", true)
end

-- ============================================================
-- Beacon (TACAN, ILS, VOR, etc.) — air-only
-- ============================================================

-- Activate a beacon on the group. opts table:
--   type      (number, required) — sms.commands.BEACON.TYPE.* (or DCS int)
--   system    (number, required) — sms.commands.BEACON.SYSTEM.* (or DCS int)
--   frequency (number, required) — Hz
--   callsign  (string, optional) — TACAN voice callsign, e.g. "TEX"
--   name      (string, optional) — beacon name (defaults to "")
--   unit_id   (number, optional) — host unit id
--   channel   (number, optional) — TACAN channel number
--   mode_channel (string, optional) — "X" or "Y"
--   aa        (boolean, optional) — air-to-air mode
--   bearing   (boolean, optional) — bearing info enable
sms.commands.activate_beacon = function(opts)
  if type(opts) ~= "table" then
    log.warn("activate_beacon: opts must be a table")
    return nil
  end
  if type(opts.type) ~= "number" then
    log.warn("activate_beacon: opts.type must be a number")
    return nil
  end
  if type(opts.system) ~= "number" then
    log.warn("activate_beacon: opts.system must be a number")
    return nil
  end
  if type(opts.frequency) ~= "number" then
    log.warn("activate_beacon: opts.frequency must be a number")
    return nil
  end
  local params = {
    type      = opts.type,
    system    = opts.system,
    frequency = opts.frequency,
    callsign  = opts.callsign or "",
    name      = opts.name     or "",
  }
  if opts.unit_id      then params.unitId      = opts.unit_id end
  if opts.channel      then params.channel     = opts.channel end
  if opts.mode_channel then params.modeChannel = opts.mode_channel end
  if opts.aa ~= nil    then params.AA          = opts.aa end
  if opts.bearing ~= nil then params.bearing   = opts.bearing end
  return _stamp({ id = "ActivateBeacon", params = params }, "activate_beacon", true)
end

-- Deactivate any active beacon.
sms.commands.deactivate_beacon = function()
  return _stamp({ id = "DeactivateBeacon", params = {} }, "deactivate_beacon", true)
end

-- ============================================================
-- ACLS / ICLS / Link4 (carrier ops, all air-only)
-- ============================================================

-- Aircraft Carrier Landing System.
sms.commands.activate_acls = function(unit_id, name)
  if unit_id ~= nil and type(unit_id) ~= "number" then
    log.warn("activate_acls: unit_id must be a number when given, got " .. type(unit_id))
    return nil
  end
  if name ~= nil and type(name) ~= "string" then
    log.warn("activate_acls: name must be a string when given, got " .. type(name))
    return nil
  end
  local params = {}
  if unit_id then params.UnitID = unit_id end
  if name    then params.Name   = name    end
  return _stamp({ id = "ActivateACLS", params = params }, "activate_acls", true)
end

sms.commands.deactivate_acls = function()
  return _stamp({ id = "DeactivateACLS", params = {} }, "deactivate_acls", true)
end

-- Instrument Carrier Landing System.
sms.commands.activate_icls = function(channel, unit_id, callsign)
  if type(channel) ~= "number" then
    log.warn("activate_icls: channel must be a number, got " .. type(channel))
    return nil
  end
  if unit_id  ~= nil and type(unit_id)  ~= "number" then
    log.warn("activate_icls: unit_id must be a number when given, got " .. type(unit_id))
    return nil
  end
  if callsign ~= nil and type(callsign) ~= "string" then
    log.warn("activate_icls: callsign must be a string when given, got " .. type(callsign))
    return nil
  end
  local params = { channel = channel }
  if unit_id  then params.unitId   = unit_id  end
  if callsign then params.callsign = callsign end
  return _stamp({ id = "ActivateICLS", params = params }, "activate_icls", true)
end

sms.commands.deactivate_icls = function()
  return _stamp({ id = "DeactivateICLS", params = {} }, "deactivate_icls", true)
end

-- Link 4 datalink.
sms.commands.activate_link4 = function(frequency, unit_id, callsign)
  if type(frequency) ~= "number" then
    log.warn("activate_link4: frequency must be a number, got " .. type(frequency))
    return nil
  end
  if unit_id  ~= nil and type(unit_id)  ~= "number" then
    log.warn("activate_link4: unit_id must be a number when given, got " .. type(unit_id))
    return nil
  end
  if callsign ~= nil and type(callsign) ~= "string" then
    log.warn("activate_link4: callsign must be a string when given, got " .. type(callsign))
    return nil
  end
  local params = { frequency = frequency }
  if unit_id  then params.unitId   = unit_id  end
  if callsign then params.callsign = callsign end
  return _stamp({ id = "ActivateLink4", params = params }, "activate_link4", true)
end

sms.commands.deactivate_link4 = function()
  return _stamp({ id = "DeactivateLink4", params = {} }, "deactivate_link4", true)
end
