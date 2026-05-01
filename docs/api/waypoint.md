# `sms.waypoint` — DCS waypoint type and action enums

Two hand-maintained enum sub-tables for hand-built route waypoints:

- `sms.waypoint.TYPE.<KEY>` — the `type` field (turning point vs takeoff vs land).
- `sms.waypoint.ACTION.<KEY>` — the `action` field (turning point vs fly-over vs from-parking-area-hot vs landing vs off-road, etc.).

Both have a `TURNING_POINT` entry (DCS uses `"Turning Point"` for both fields with different meanings); they live in separate sub-namespaces because the DCS waypoint table treats `type` and `action` as separate keys.

```lua
local wp = {
  x = 1234, y = 0, z = 5678,
  alt = 4500, alt_type = sms.alt_type.BARO,
  type   = sms.waypoint.TYPE.TURNING_POINT,    -- "Turning Point"
  action = sms.waypoint.ACTION.OFF_ROAD,        -- "Off Road" (ground unit)
  speed  = 22,
}
```

## Loading

Requires `sms.lua` and `log.lua`. Loaded automatically by `framework/load_all.lua` after `alt_type.lua`.

## `sms.waypoint.TYPE` values

| Constant | DCS string | Use |
|---|---|---|
| `sms.waypoint.TYPE.TAKEOFF_PARKING` | `"TakeOffParking"` | Cold takeoff from a parking spot (engines off). |
| `sms.waypoint.TYPE.TAKEOFF_PARKING_HOT` | `"TakeOffParkingHot"` | Hot takeoff from a parking spot (engines running). DCS's default takeoff form. |
| `sms.waypoint.TYPE.TAKEOFF_GROUND` | `"TakeOffGround"` | Cold takeoff on the ground (e.g. carrier deck cold start). |
| `sms.waypoint.TYPE.TAKEOFF_GROUND_HOT` | `"TakeOffGroundHot"` | Hot takeoff on the ground. |
| `sms.waypoint.TYPE.TURNING_POINT` | `"Turning Point"` | Standard en-route waypoint. |
| `sms.waypoint.TYPE.LAND` | `"Land"` | Land at this point. |
| `sms.waypoint.TYPE.LANDING_REFUEL_REARM` | `"LandingReFuAr"` | Land, refuel, rearm, then continue. |

DCS exposes a `"TakeOff"` alias that resolves to `"TakeOffParkingHot"` — the framework intentionally exposes only the canonical `TAKEOFF_PARKING_HOT` (Decision D4 in the spec).

## `sms.waypoint.ACTION` values

| Constant | DCS string | Use |
|---|---|---|
| `sms.waypoint.ACTION.TURNING_POINT` | `"Turning Point"` | Standard turn-at-point traversal (air units). |
| `sms.waypoint.ACTION.FLY_OVER_POINT` | `"Fly Over Point"` | Pass directly over the point without turning. |
| `sms.waypoint.ACTION.FROM_PARKING_AREA` | `"From Parking Area"` | Cold start from parking, then proceed. |
| `sms.waypoint.ACTION.FROM_PARKING_AREA_HOT` | `"From Parking Area Hot"` | Hot start from parking, then proceed. |
| `sms.waypoint.ACTION.FROM_GROUND_AREA` | `"From Ground Area"` | Cold start on the ground. |
| `sms.waypoint.ACTION.FROM_GROUND_AREA_HOT` | `"From Ground Area Hot"` | Hot start on the ground. |
| `sms.waypoint.ACTION.FROM_RUNWAY` | `"From Runway"` | Start at the runway threshold, takeoff. |
| `sms.waypoint.ACTION.LANDING` | `"Landing"` | Land at the airfield. |
| `sms.waypoint.ACTION.LANDING_REFUEL_REARM` | `"LandingReFuAr"` | Land, refuel, rearm. |
| `sms.waypoint.ACTION.OFF_ROAD` | `"Off Road"` | Ground / ship / train unit traverses cross-country. Default for ground-unit waypoints in dcs-sms. |
| `sms.waypoint.ACTION.ON_ROAD` | `"On Road"` | Ground unit follows the road network. |

`OFF_ROAD` and `ON_ROAD` are ground-unit-specific actions; `FLY_OVER_POINT` / `FROM_*` / `LANDING*` are air-unit actions; `TURNING_POINT` works for both categories.

## The `sms.WaypointType` and `sms.WaypointAction` aliases

Two LuaCATS string-literal aliases enumerate every value of each sub-table. They drive autocomplete on raw-string usage in any user code that consumes a hand-built waypoint table. The framework doesn't currently annotate any specific field with these aliases (waypoint tables are passthrough to DCS, not first-class types in the framework yet) — that's a future opportunity.

## See also

- [`sms.alt_type`](alt_type.md) — companion enum for the `alt_type` field on the same waypoint tables.
- [`sms.task`](task.md) — task builders that produce waypoints internally; the framework emits `"Turning Point"` and `"Off Road"` literals from those builders today.
- [`sms.group`](group.md) — `group:set_task` consumes routes whose waypoints can be built using these enums.
