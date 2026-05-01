-- dcs-sms framework: waypoint module (sms.constants.waypoint / sms.K.waypoint).
--
-- Hand-maintained enums for DCS waypoint type and action strings.
-- Mission code uses sms.K.waypoint.type.<KEY> and sms.K.waypoint.action.<KEY>
-- instead of magic strings:
--
--     local wp = {
--       x = 1234, y = 0, z = 5678,
--       type   = sms.K.waypoint.type.TURNING_POINT,    -- "Turning Point"
--       action = sms.K.waypoint.action.OFF_ROAD,        -- "Off Road"
--       ...
--     }
--
-- type controls the kind of waypoint (turning point vs takeoff vs land).
-- action controls how the unit traverses or arrives (turning point vs
-- fly-over vs from-parking-area-hot vs landing). Both have a
-- "Turning Point" entry but they live in separate enums because DCS
-- treats them as separate fields on the waypoint table.
--
-- "TakeOff" is a DCS alias for "TakeOffParkingHot"; we expose only the
-- canonical TAKEOFF_PARKING_HOT (Decision D4 in the spec).
--
-- OFF_ROAD and ON_ROAD are included on action because dcs-sms emits
-- "Off Road" for ground/ship/train waypoints in framework/group.lua
-- and framework/task.lua (Decision D6).
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- framework/constants/waypoint.lua.
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",          "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table",      "framework/log.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

local log = sms.log.module("sms.constants.waypoint")

---@class sms.constants.waypoint
---@field type   sms.constants.waypoint.type
---@field action sms.constants.waypoint.action
sms.constants.waypoint = sms.constants.waypoint or {}

---@class sms.constants.waypoint.type
---@field TAKEOFF_PARKING      "TakeOffParking"
---@field TAKEOFF_PARKING_HOT  "TakeOffParkingHot"
---@field TAKEOFF_GROUND       "TakeOffGround"
---@field TAKEOFF_GROUND_HOT   "TakeOffGroundHot"
---@field TURNING_POINT        "Turning Point"
---@field LAND                 "Land"
---@field LANDING_REFUEL_REARM "LandingReFuAr"
sms.constants.waypoint.type = sms.constants.waypoint.type or {}

---@alias sms.WaypointType
---| "TakeOffParking"
---| "TakeOffParkingHot"
---| "TakeOffGround"
---| "TakeOffGroundHot"
---| "Turning Point"
---| "Land"
---| "LandingReFuAr"

sms.constants.waypoint.type.TAKEOFF_PARKING      = "TakeOffParking"
sms.constants.waypoint.type.TAKEOFF_PARKING_HOT  = "TakeOffParkingHot"
sms.constants.waypoint.type.TAKEOFF_GROUND       = "TakeOffGround"
sms.constants.waypoint.type.TAKEOFF_GROUND_HOT   = "TakeOffGroundHot"
sms.constants.waypoint.type.TURNING_POINT        = "Turning Point"
sms.constants.waypoint.type.LAND                 = "Land"
sms.constants.waypoint.type.LANDING_REFUEL_REARM = "LandingReFuAr"

---@class sms.constants.waypoint.action
---@field TURNING_POINT         "Turning Point"
---@field FLY_OVER_POINT        "Fly Over Point"
---@field FROM_PARKING_AREA     "From Parking Area"
---@field FROM_PARKING_AREA_HOT "From Parking Area Hot"
---@field FROM_GROUND_AREA      "From Ground Area"
---@field FROM_GROUND_AREA_HOT  "From Ground Area Hot"
---@field FROM_RUNWAY           "From Runway"
---@field LANDING               "Landing"
---@field LANDING_REFUEL_REARM  "LandingReFuAr"
---@field OFF_ROAD              "Off Road"
---@field ON_ROAD               "On Road"
sms.constants.waypoint.action = sms.constants.waypoint.action or {}

---@alias sms.WaypointAction
---| "Turning Point"
---| "Fly Over Point"
---| "From Parking Area"
---| "From Parking Area Hot"
---| "From Ground Area"
---| "From Ground Area Hot"
---| "From Runway"
---| "Landing"
---| "LandingReFuAr"
---| "Off Road"
---| "On Road"

sms.constants.waypoint.action.TURNING_POINT         = "Turning Point"
sms.constants.waypoint.action.FLY_OVER_POINT        = "Fly Over Point"
sms.constants.waypoint.action.FROM_PARKING_AREA     = "From Parking Area"
sms.constants.waypoint.action.FROM_PARKING_AREA_HOT = "From Parking Area Hot"
sms.constants.waypoint.action.FROM_GROUND_AREA      = "From Ground Area"
sms.constants.waypoint.action.FROM_GROUND_AREA_HOT  = "From Ground Area Hot"
sms.constants.waypoint.action.FROM_RUNWAY           = "From Runway"
sms.constants.waypoint.action.LANDING               = "Landing"
sms.constants.waypoint.action.LANDING_REFUEL_REARM  = "LandingReFuAr"
sms.constants.waypoint.action.OFF_ROAD              = "Off Road"
sms.constants.waypoint.action.ON_ROAD               = "On Road"
