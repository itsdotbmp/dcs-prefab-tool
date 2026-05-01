-- dcs-sms framework: waypoint module (sms.waypoint).
--
-- Hand-maintained enums for DCS waypoint type and action strings.
-- Mission code uses sms.waypoint.TYPE.<KEY> and sms.waypoint.ACTION.<KEY>
-- instead of magic strings:
--
--     local wp = {
--       x = 1234, y = 0, z = 5678,
--       type   = sms.waypoint.TYPE.TURNING_POINT,    -- "Turning Point"
--       action = sms.waypoint.ACTION.OFF_ROAD,        -- "Off Road"
--       ...
--     }
--
-- TYPE controls the kind of waypoint (turning point vs takeoff vs land).
-- ACTION controls how the unit traverses or arrives (turning point vs
-- fly-over vs from-parking-area-hot vs landing). Both have a
-- "Turning Point" entry but they live in separate enums because DCS
-- treats them as separate fields on the waypoint table.
--
-- "TakeOff" is a DCS alias for "TakeOffParkingHot"; we expose only the
-- canonical TAKEOFF_PARKING_HOT (Decision D4 in the spec).
--
-- OFF_ROAD and ON_ROAD are included on ACTION because dcs-sms emits
-- "Off Road" for ground/ship/train waypoints in framework/group.lua
-- and framework/task.lua (Decision D6).
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> countries.lua ->
-- skill.lua -> alt_type.lua -> waypoint.lua.
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

local log = sms.log.module("sms.waypoint")

---@class sms.waypoint
---@field TYPE   sms.waypoint.TYPE
---@field ACTION sms.waypoint.ACTION
sms.waypoint = sms.waypoint or {}

---@class sms.waypoint.TYPE
---@field TAKEOFF_PARKING      "TakeOffParking"
---@field TAKEOFF_PARKING_HOT  "TakeOffParkingHot"
---@field TAKEOFF_GROUND       "TakeOffGround"
---@field TAKEOFF_GROUND_HOT   "TakeOffGroundHot"
---@field TURNING_POINT        "Turning Point"
---@field LAND                 "Land"
---@field LANDING_REFUEL_REARM "LandingReFuAr"
sms.waypoint.TYPE = sms.waypoint.TYPE or {}

---@alias sms.WaypointType
---| "TakeOffParking"
---| "TakeOffParkingHot"
---| "TakeOffGround"
---| "TakeOffGroundHot"
---| "Turning Point"
---| "Land"
---| "LandingReFuAr"

sms.waypoint.TYPE.TAKEOFF_PARKING      = "TakeOffParking"
sms.waypoint.TYPE.TAKEOFF_PARKING_HOT  = "TakeOffParkingHot"
sms.waypoint.TYPE.TAKEOFF_GROUND       = "TakeOffGround"
sms.waypoint.TYPE.TAKEOFF_GROUND_HOT   = "TakeOffGroundHot"
sms.waypoint.TYPE.TURNING_POINT        = "Turning Point"
sms.waypoint.TYPE.LAND                 = "Land"
sms.waypoint.TYPE.LANDING_REFUEL_REARM = "LandingReFuAr"

---@class sms.waypoint.ACTION
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
sms.waypoint.ACTION = sms.waypoint.ACTION or {}

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

sms.waypoint.ACTION.TURNING_POINT         = "Turning Point"
sms.waypoint.ACTION.FLY_OVER_POINT        = "Fly Over Point"
sms.waypoint.ACTION.FROM_PARKING_AREA     = "From Parking Area"
sms.waypoint.ACTION.FROM_PARKING_AREA_HOT = "From Parking Area Hot"
sms.waypoint.ACTION.FROM_GROUND_AREA      = "From Ground Area"
sms.waypoint.ACTION.FROM_GROUND_AREA_HOT  = "From Ground Area Hot"
sms.waypoint.ACTION.FROM_RUNWAY           = "From Runway"
sms.waypoint.ACTION.LANDING               = "Landing"
sms.waypoint.ACTION.LANDING_REFUEL_REARM  = "LandingReFuAr"
sms.waypoint.ACTION.OFF_ROAD              = "Off Road"
sms.waypoint.ACTION.ON_ROAD               = "On Road"
