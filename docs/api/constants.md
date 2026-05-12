# `sms.constants` (alias `sms.K`) — every wire-format constant

`sms.constants` is the single namespace for every DCS enum-shaped value the framework knows about: coalitions, group categories, countries, skill levels, altitude reference types, waypoint types and actions, ROE / alarm state / reaction-on-threat / radar-using / flare-using / formation strings, target attribute strings, FAC designations, plus the auto-generated unit and static catalogs.

`sms.K` is an alias for `sms.constants` — the long form works too, but every example below uses `sms.K` because it is what the framework's own internals use. Both forms point at the same table.

Mission code uses `sms.K.<topic>.<KEY>` instead of magic strings:

```lua
local cap = sms.group.create({
  name     = "blue-cap-1",
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  position = {x = 0, y = 0, z = 0},
  units    = {
    {type = sms.K.units.planes.F_16C_50, skill = sms.K.skill.AVERAGE},
  },
})

cap:set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))
```

Autocomplete in any LuaCATS-aware editor lists every member; a typo (`sms.K.skill.AVERAGEX`) is a static type error rather than a silent runtime failure when DCS receives a bogus string.

## Loading

`framework/constants.lua` is loaded by `framework/load_all.lua` after `utils.lua`. It in turn `dofile`s every topic file in `framework/constants/*.lua` in the fixed alphabetical order shown in its source. After loading, both `sms.constants` and `sms.K` point at the same fully-populated table.

---

## `sms.K.coalition`

DCS coalition strings on the wire are lowercase: `"red"`, `"blue"`, `"neutral"`. Use `sms.K.coalition.*` instead of magic strings; `sms.utils.coalition_int_to_str` returns one of these same strings.

**LuaCATS alias:** `sms.Coalition`

| Constant | Wire string |
|---|---|
| `sms.K.coalition.RED` | `"red"` |
| `sms.K.coalition.BLUE` | `"blue"` |
| `sms.K.coalition.NEUTRAL` | `"neutral"` |

**Example**

```lua
-- Filter an event handler to blue-coalition units only.
sms.events.on_unit_dead(function(evt)
  if evt.coalition == sms.K.coalition.BLUE then
    sms.log.info("blue unit lost: " .. tostring(evt.unit_name))
  end
end)
```

---

## `sms.K.category`

DCS group categories on the wire are lowercase strings. The framework uses these for category dispatch (ROE validation, `_sms_air_only` guard, etc.); mission code uses them in spawn configs.

**LuaCATS alias:** `sms.Category`

| Constant | Wire string |
|---|---|
| `sms.K.category.AIRPLANE` | `"airplane"` |
| `sms.K.category.HELICOPTER` | `"helicopter"` |
| `sms.K.category.GROUND` | `"ground"` |
| `sms.K.category.SHIP` | `"ship"` |
| `sms.K.category.TRAIN` | `"train"` |

**Example**

```lua
local cap = sms.group.create({
  name     = "blue-cap-1",
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  position = {x = 0, y = 0, z = 0},
  units    = { {type = sms.K.units.planes.F_16C_50, alt = 6000, heading = 90} },
})
```

---

## `sms.K.countries`

Hand-maintained table of every well-known DCS `country.id` key. Mission code uses `sms.K.countries.<KEY>` instead of magic-string `country = "USA"` literals. Autocomplete lists every supported country, and a typo (`sms.K.countries.USAa`) is a static type error instead of a runtime resolve failure.

All entries follow the invariant `sms.K.countries.X == "X"` — values are the upper-snake form that `country.id` itself uses.

`sms.utils.resolve_country` is case-insensitive and folds spaces to underscores, so `country = sms.K.countries.UNITED_KINGDOM`, `country = "United Kingdom"`, and `country = "united kingdom"` all resolve to the same DCS country integer.

**LuaCATS alias:** `sms.Country`

The `country` field on `sms.group.create` and `sms.static.create` configs is annotated `sms.Country|string`:
- `country = sms.K.countries.USA` — autocompleted, type-safe.
- `country = "USA"` — accepted, autocompleted from the alias.
- `country = "United Kingdom"` — accepted as `string`; resolves at runtime via `resolve_country`.
- `country = "USAa"` — passes the type checker as `string`, but `resolve_country` returns `nil` and the spawn fails with a `log.warn` per the [framework failure model](../../framework/AGENTS.md#3-failure-model-log--nil-never-throw).

| Constant | Wire string |
|---|---|
| `sms.K.countries.RUSSIA` | `"RUSSIA"` |
| `sms.K.countries.UKRAINE` | `"UKRAINE"` |
| `sms.K.countries.USA` | `"USA"` |
| `sms.K.countries.TURKEY` | `"TURKEY"` |
| `sms.K.countries.UK` | `"UK"` |
| `sms.K.countries.FRANCE` | `"FRANCE"` |
| `sms.K.countries.GERMANY` | `"GERMANY"` |
| `sms.K.countries.USAF_AGGRESSORS` | `"USAF_AGGRESSORS"` |
| `sms.K.countries.CANADA` | `"CANADA"` |
| `sms.K.countries.SPAIN` | `"SPAIN"` |
| `sms.K.countries.THE_NETHERLANDS` | `"THE_NETHERLANDS"` |
| `sms.K.countries.BELGIUM` | `"BELGIUM"` |
| `sms.K.countries.NORWAY` | `"NORWAY"` |
| `sms.K.countries.DENMARK` | `"DENMARK"` |
| `sms.K.countries.ISRAEL` | `"ISRAEL"` |
| `sms.K.countries.GEORGIA` | `"GEORGIA"` |
| `sms.K.countries.INSURGENTS` | `"INSURGENTS"` |
| `sms.K.countries.ABKHAZIA` | `"ABKHAZIA"` |
| `sms.K.countries.SOUTH_OSETIA` | `"SOUTH_OSETIA"` |
| `sms.K.countries.ITALY` | `"ITALY"` |
| `sms.K.countries.AUSTRALIA` | `"AUSTRALIA"` |
| `sms.K.countries.SWITZERLAND` | `"SWITZERLAND"` |
| `sms.K.countries.AUSTRIA` | `"AUSTRIA"` |
| `sms.K.countries.BELARUS` | `"BELARUS"` |
| `sms.K.countries.BULGARIA` | `"BULGARIA"` |
| `sms.K.countries.CHEZH_REPUBLIC` | `"CHEZH_REPUBLIC"` |
| `sms.K.countries.CHINA` | `"CHINA"` |
| `sms.K.countries.CROATIA` | `"CROATIA"` |
| `sms.K.countries.EGYPT` | `"EGYPT"` |
| `sms.K.countries.FINLAND` | `"FINLAND"` |
| `sms.K.countries.GREECE` | `"GREECE"` |
| `sms.K.countries.HUNGARY` | `"HUNGARY"` |
| `sms.K.countries.INDIA` | `"INDIA"` |
| `sms.K.countries.IRAN` | `"IRAN"` |
| `sms.K.countries.IRAQ` | `"IRAQ"` |
| `sms.K.countries.JAPAN` | `"JAPAN"` |
| `sms.K.countries.KAZAKHSTAN` | `"KAZAKHSTAN"` |
| `sms.K.countries.NORTH_KOREA` | `"NORTH_KOREA"` |
| `sms.K.countries.PAKISTAN` | `"PAKISTAN"` |
| `sms.K.countries.POLAND` | `"POLAND"` |
| `sms.K.countries.ROMANIA` | `"ROMANIA"` |
| `sms.K.countries.SAUDI_ARABIA` | `"SAUDI_ARABIA"` |
| `sms.K.countries.SERBIA` | `"SERBIA"` |
| `sms.K.countries.SLOVAKIA` | `"SLOVAKIA"` |
| `sms.K.countries.SOUTH_KOREA` | `"SOUTH_KOREA"` |
| `sms.K.countries.SWEDEN` | `"SWEDEN"` |
| `sms.K.countries.SYRIA` | `"SYRIA"` |
| `sms.K.countries.YEMEN` | `"YEMEN"` |
| `sms.K.countries.VIETNAM` | `"VIETNAM"` |
| `sms.K.countries.VENEZUELA` | `"VENEZUELA"` |
| `sms.K.countries.TUNISIA` | `"TUNISIA"` |
| `sms.K.countries.THAILAND` | `"THAILAND"` |
| `sms.K.countries.SUDAN` | `"SUDAN"` |
| `sms.K.countries.PHILIPPINES` | `"PHILIPPINES"` |
| `sms.K.countries.MOROCCO` | `"MOROCCO"` |
| `sms.K.countries.MEXICO` | `"MEXICO"` |
| `sms.K.countries.MALAYSIA` | `"MALAYSIA"` |
| `sms.K.countries.LIBYA` | `"LIBYA"` |
| `sms.K.countries.JORDAN` | `"JORDAN"` |
| `sms.K.countries.INDONESIA` | `"INDONESIA"` |
| `sms.K.countries.HONDURAS` | `"HONDURAS"` |
| `sms.K.countries.ETHIOPIA` | `"ETHIOPIA"` |
| `sms.K.countries.CHILE` | `"CHILE"` |
| `sms.K.countries.BRAZIL` | `"BRAZIL"` |
| `sms.K.countries.BAHRAIN` | `"BAHRAIN"` |
| `sms.K.countries.THIRDREICH` | `"THIRDREICH"` |
| `sms.K.countries.YUGOSLAVIA` | `"YUGOSLAVIA"` |
| `sms.K.countries.USSR` | `"USSR"` |
| `sms.K.countries.ITALIAN_SOCIAL_REPUBLIC` | `"ITALIAN_SOCIAL_REPUBLIC"` |
| `sms.K.countries.ALGERIA` | `"ALGERIA"` |
| `sms.K.countries.KUWAIT` | `"KUWAIT"` |
| `sms.K.countries.QATAR` | `"QATAR"` |
| `sms.K.countries.OMAN` | `"OMAN"` |
| `sms.K.countries.UAE` | `"UAE"` |
| `sms.K.countries.SOUTH_AFRICA` | `"SOUTH_AFRICA"` |
| `sms.K.countries.CUBA` | `"CUBA"` |
| `sms.K.countries.PORTUGAL` | `"PORTUGAL"` |
| `sms.K.countries.GDR` | `"GDR"` |
| `sms.K.countries.LEBANON` | `"LEBANON"` |
| `sms.K.countries.CJTF_BLUE` | `"CJTF_BLUE"` |
| `sms.K.countries.CJTF_RED` | `"CJTF_RED"` |
| `sms.K.countries.UN_PEACEKEEPERS` | `"UN_PEACEKEEPERS"` |
| `sms.K.countries.ARGENTINA` | `"ARGENTINA"` |
| `sms.K.countries.CYPRUS` | `"CYPRUS"` |
| `sms.K.countries.SLOVENIA` | `"SLOVENIA"` |
| `sms.K.countries.BOLIVIA` | `"BOLIVIA"` |
| `sms.K.countries.GHANA` | `"GHANA"` |
| `sms.K.countries.NIGERIA` | `"NIGERIA"` |
| `sms.K.countries.PERU` | `"PERU"` |
| `sms.K.countries.ECUADOR` | `"ECUADOR"` |
| `sms.K.countries.ESTONIA` | `"ESTONIA"` |
| `sms.K.countries.LATVIA` | `"LATVIA"` |
| `sms.K.countries.LITHUANIA` | `"LITHUANIA"` |
| `sms.K.countries.URUGUAY` | `"URUGUAY"` |

**Example**

```lua
local cap = sms.group.create({
  name     = "blue-cap",
  position = {x = 0, y = 0, z = 0},
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units    = { {type = sms.K.units.planes.FA_18C_hornet, alt = 6000, heading = 90} },
})

local convoy = sms.group.create({
  name     = "red-convoy",
  position = {x = 50000, y = 0, z = 0},
  country  = sms.K.countries.RUSSIA,
  category = sms.K.category.GROUND,
  units    = { {type = sms.K.units.unarmed.Ural_4320T, heading = 270} },
})
```

### Why upper-snake?

`country.id` itself is a hash keyed by upper-snake names (`country.id.USA`, `country.id.UNITED_KINGDOM`). Mirroring those keys gives the `sms.K.countries.X == "X"` invariant, making round-trips with `country.id` trivial.

### Runtime drift check

DCS occasionally adds new countries between releases. `framework/constants/countries.lua` runs a one-time check at load time: walk `country.id` keys; for each key not in the static table, add it at runtime AND log a single `warn` line:

```
[sms.constants.countries] country.id key 'NEW_COUNTRY' not in static list — added at runtime; update framework/constants/countries.lua to keep autocomplete in sync
```

Spawn calls keep working forever, but the missing key is visible in `dcs.log` so the static list (and editor autocomplete) can be updated when someone notices.

### Handling unknown countries

There is no `sms.K.countries.from_int(n)` reverse lookup. If a unit handle gives you a country int and you need a human-readable name, walk `country.id` directly:

```lua
local function name_from_int(n)
  for k, v in pairs(country.id) do
    if v == n then return k end
  end
end
```

This is intentionally not framework code — the use case is rare, the helper is three lines, and inlining keeps the framework surface small.

---

## `sms.K.skill`

Hand-maintained enum of the seven DCS strings accepted on the `skill` field of unit specs. Values are the verbatim DCS strings (`"Average"` etc., case-sensitive) — DCS skill strings are case-sensitive and will silently fall back to a default if the wrong case is passed.

**LuaCATS alias:** `sms.Skill`

The `skill` field on `sms.group.unit_spec` is annotated `sms.Skill|string`:
- `skill = sms.K.skill.AVERAGE` — autocompleted, type-safe.
- `skill = "Average"` — accepted, autocompleted from the alias.
- `skill = "average"` — passes the type checker as `string`, but **DCS skill strings are case-sensitive**, so DCS receives `"average"` and falls back to its own default.

| Constant | DCS string | Notes |
|---|---|---|
| `sms.K.skill.AVERAGE` | `"Average"` | Default for AI units. |
| `sms.K.skill.GOOD` | `"Good"` | Slightly above average. |
| `sms.K.skill.HIGH` | `"High"` | Skilled AI. |
| `sms.K.skill.EXCELLENT` | `"Excellent"` | Top tier. |
| `sms.K.skill.RANDOM` | `"Random"` | DCS picks a level at spawn time. |
| `sms.K.skill.PLAYER` | `"Player"` | **Special** — marks a unit slot as a player aircraft (single-player). Do not use on AI units. |
| `sms.K.skill.CLIENT` | `"Client"` | **Special** — marks a unit slot as a multiplayer client (joinable). Do not use on AI units. |

`PLAYER` and `CLIENT` are not skill levels in the AI-difficulty sense — they are placeholder values DCS recognizes on the same `skill` field to mark a unit as human-controllable.

**Example**

```lua
sms.group.create({
  name     = "blue-cap",
  position = {x = 0, y = 0, z = 0},
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units    = {
    {type = sms.K.units.planes.F_16C_50, alt = 6000, heading = 90,
     skill = sms.K.skill.AVERAGE},
  },
})
```

---

## `sms.K.alt_type`

Hand-maintained enum for the `alt_type` field on unit specs and waypoint tables. Values are upper-case; DCS rejects lower-case forms.

**LuaCATS alias:** `sms.AltType`

The `alt_type` field on `sms.group.unit_spec` is annotated `sms.AltType|string`:
- `alt_type = sms.K.alt_type.BARO` — autocompleted, type-safe.
- `alt_type = "BARO"` — accepted, autocompleted from the alias.
- `alt_type = "baro"` — passes the type checker as `string`, but **fails at runtime**; DCS expects upper-case.

| Constant | DCS string | Notes |
|---|---|---|
| `sms.K.alt_type.BARO` | `"BARO"` | Altitude above mean sea level. Default for fixed-wing aircraft. |
| `sms.K.alt_type.RADIO` | `"RADIO"` | Altitude above ground level (radar altimeter). Used for terrain-following routes and helicopter low-level. |

**Example**

```lua
local wp = {
  x = 1234, y = 0, z = 5678,
  alt      = 4500,
  alt_type = sms.K.alt_type.BARO,
  type     = sms.K.waypoint.type.TURNING_POINT,
  action   = sms.K.waypoint.action.TURNING_POINT,
  speed    = 220,
}
```

---

## `sms.K.waypoint.type`

Seven entries for the `type` field of a DCS waypoint table. Controls the kind of waypoint (turning point vs takeoff vs land).

**LuaCATS alias:** `sms.WaypointType`

| Constant | DCS string | Notes |
|---|---|---|
| `sms.K.waypoint.type.TAKEOFF_PARKING` | `"TakeOffParking"` | Cold takeoff from a parking spot (engines off). |
| `sms.K.waypoint.type.TAKEOFF_PARKING_HOT` | `"TakeOffParkingHot"` | Hot takeoff from a parking spot (engines running). DCS's default takeoff form. |
| `sms.K.waypoint.type.TAKEOFF_GROUND` | `"TakeOffGround"` | Cold takeoff on the ground (e.g. carrier deck cold start). |
| `sms.K.waypoint.type.TAKEOFF_GROUND_HOT` | `"TakeOffGroundHot"` | Hot takeoff on the ground. |
| `sms.K.waypoint.type.TURNING_POINT` | `"Turning Point"` | Standard en-route waypoint. |
| `sms.K.waypoint.type.LAND` | `"Land"` | Land at this point. |
| `sms.K.waypoint.type.LANDING_REFUEL_REARM` | `"LandingReFuAr"` | Land, refuel, rearm, then continue. |

DCS exposes a `"TakeOff"` alias that resolves to `"TakeOffParkingHot"` — the framework intentionally exposes only the canonical `TAKEOFF_PARKING_HOT` (Decision D4 in the spec).

**Example**

```lua
local departure_wp = {
  x      = airbase_x, y = 0, z = airbase_z,
  alt    = 0,
  type   = sms.K.waypoint.type.TAKEOFF_PARKING_HOT,
  action = sms.K.waypoint.action.FROM_PARKING_AREA_HOT,
  speed  = 0,
}
local en_route_wp = {
  x        = 12000, y = 0, z = 4500,
  alt      = 6000,
  alt_type = sms.K.alt_type.BARO,
  type     = sms.K.waypoint.type.TURNING_POINT,
  action   = sms.K.waypoint.action.TURNING_POINT,
  speed    = 220,
}
```

---

## `sms.K.waypoint.action`

Eleven entries for the `action` field of a DCS waypoint table. Controls how the unit traverses or arrives at the point.

**LuaCATS alias:** `sms.WaypointAction`

`OFF_ROAD` and `ON_ROAD` are ground-unit-specific actions. `FLY_OVER_POINT`, `FROM_*`, and `LANDING*` are air-unit actions. `TURNING_POINT` works for both categories. The framework emits `"Off Road"` by default for ground/ship/train waypoints.

| Constant | DCS string | Notes |
|---|---|---|
| `sms.K.waypoint.action.TURNING_POINT` | `"Turning Point"` | Standard turn-at-point traversal (air units). |
| `sms.K.waypoint.action.FLY_OVER_POINT` | `"Fly Over Point"` | Pass directly over the point without turning. |
| `sms.K.waypoint.action.FROM_PARKING_AREA` | `"From Parking Area"` | Cold start from parking, then proceed. |
| `sms.K.waypoint.action.FROM_PARKING_AREA_HOT` | `"From Parking Area Hot"` | Hot start from parking, then proceed. |
| `sms.K.waypoint.action.FROM_GROUND_AREA` | `"From Ground Area"` | Cold start on the ground. |
| `sms.K.waypoint.action.FROM_GROUND_AREA_HOT` | `"From Ground Area Hot"` | Hot start on the ground. |
| `sms.K.waypoint.action.FROM_RUNWAY` | `"From Runway"` | Start at the runway threshold, takeoff. |
| `sms.K.waypoint.action.LANDING` | `"Landing"` | Land at the airfield. |
| `sms.K.waypoint.action.LANDING_REFUEL_REARM` | `"LandingReFuAr"` | Land, refuel, rearm. |
| `sms.K.waypoint.action.OFF_ROAD` | `"Off Road"` | Ground / ship / train unit traverses cross-country. Default for ground-unit waypoints in dcs-sms. |
| `sms.K.waypoint.action.ON_ROAD` | `"On Road"` | Ground unit follows the road network. |

**Example**

```lua
local ground_wp = {
  x        = 50000, y = 0, z = 20000,
  alt      = 0,
  alt_type = sms.K.alt_type.BARO,
  type     = sms.K.waypoint.type.TURNING_POINT,
  action   = sms.K.waypoint.action.OFF_ROAD,
  speed    = 22,
}
```

---

## `sms.K.targets`

Named constants for the DCS target-attribute strings consumed by enroute engagement task builders (`sms.task.engage_en_route_*`, `sms.task.escort`, and any other builder that filters targets by attribute).

Builders accept either these constants (recommended — typo-checked at edit time) or raw strings (forward-compat for new DCS attributes the framework hasn't catalogued yet).

DCS treats these as exact-match strings; the spelling and casing in the table below is what the engine expects.

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.targets.AIR` | `"Air"` | All air targets. |
| `sms.K.targets.PLANES` | `"Planes"` | Fixed-wing aircraft only. |
| `sms.K.targets.HELICOPTERS` | `"Helicopters"` | Rotary-wing aircraft only. |
| `sms.K.targets.GROUND_UNITS` | `"Ground Units"` | All ground units. |
| `sms.K.targets.GROUND_VEHICLES` | `"Ground vehicles"` | Ground vehicles specifically. |
| `sms.K.targets.SHIPS` | `"Ships"` | Naval units. |
| `sms.K.targets.AIR_DEFENCE` | `"Air Defence"` | SAM + AAA combined. |
| `sms.K.targets.SAM` | `"SAM"` | Surface-to-air missile systems. |
| `sms.K.targets.AAA` | `"AAA"` | Anti-aircraft artillery. |
| `sms.K.targets.STATICS` | `"Static"` | Static objects. |
| `sms.K.targets.BUILDINGS` | `"Buildings"` | Building statics. |
| `sms.K.targets.ALL` | `"All"` | No filter — engage everything. |

**Example**

```lua
-- Tell a CAP flight to engage any air target it sees enroute.
local cap = sms.group("blue-cap-1")
sms.task.engage_en_route_targets(cap, {
  target_types = {sms.K.targets.AIR},
  max_distance = 80000,   -- meters
})

-- Escort with selective targeting.
sms.task.escort(cap, sms.group("blue-striker-1"), {
  target_types    = {sms.K.targets.PLANES, sms.K.targets.HELICOPTERS},
  engagement_dist = 60000,
})
```

---

## `sms.K.designations`

Named constants for the DCS FAC designation enum strings consumed by `sms.task.fac_attack_group` and `sms.task.fac_engage_group`.

As with `sms.K.targets`, builders accept either these constants (recommended) or raw strings.

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.designations.NO` | `"No"` | No designation method. |
| `sms.K.designations.AUTO` | `"Auto"` | DCS auto-selects a designation. |
| `sms.K.designations.WP` | `"WP"` | White phosphorus marker. |
| `sms.K.designations.IR_POINTER` | `"IR-Pointer"` | IR pointer designation. |
| `sms.K.designations.LASER` | `"Laser"` | Laser designation. |

**Example**

```lua
-- A JTAC marks an enemy convoy with a laser for a CAS flight to attack.
local jtac   = sms.group("blue-jtac-1")
local target = sms.group("red-convoy-1")

sms.task.fac_attack_group(jtac, target, {
  designation = sms.K.designations.LASER,
  frequency   = 30,     -- MHz
  modulation  = "AM",
})
```

---

## `sms.K.roe`

ROE strings consumed by `sms.options.roe(value)`. The option builder handles category-specific validation — some values are air-only (ground and naval groups only accept `OPEN_FIRE`, `RETURN_FIRE`, and `WEAPON_HOLD`).

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.roe.WEAPON_FREE` | `"weapon_free"` | Engage any target. Air-only. |
| `sms.K.roe.OPEN_FIRE_WEAPON_FREE` | `"open_fire_weapon_free"` | Engage designated + opportunistic. Air-only. |
| `sms.K.roe.OPEN_FIRE` | `"open_fire"` | Engage designated targets only. All categories. |
| `sms.K.roe.RETURN_FIRE` | `"return_fire"` | Fire only when fired upon. All categories. |
| `sms.K.roe.WEAPON_HOLD` | `"weapon_hold"` | Do not fire under any circumstances. All categories. |

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))

local convoy = sms.group("red-convoy-1")
convoy:set_option(sms.options.roe(sms.K.roe.RETURN_FIRE))
```

---

## `sms.K.alarm_state`

Alarm state strings consumed by `sms.options.alarm_state(value)`. Ground-only — the builder rejects air groups.

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.alarm_state.AUTO` | `"auto"` | DCS manages readiness automatically. |
| `sms.K.alarm_state.GREEN` | `"green"` | Relaxed; radars off, weapons cold. |
| `sms.K.alarm_state.RED` | `"red"` | Full readiness; radars active, weapons hot. |

**Example**

```lua
local sa6 = sms.group("red-sa6-battery-1")
sa6:set_option(sms.options.alarm_state(sms.K.alarm_state.RED))
```

---

## `sms.K.reaction_on_threat`

Reaction-on-threat strings consumed by `sms.options.reaction_on_threat(value)`. Air-only — the builder rejects ground and naval groups.

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.reaction_on_threat.NO_REACTION` | `"no_reaction"` | Ignore threats. |
| `sms.K.reaction_on_threat.PASSIVE_DEFENCE` | `"passive_defence"` | Manoeuvre defensively but do not break off. |
| `sms.K.reaction_on_threat.EVADE_FIRE` | `"evade_fire"` | Actively evade incoming fire. |
| `sms.K.reaction_on_threat.BYPASS_AND_ESCAPE` | `"bypass_and_escape"` | Leave the threat envelope and disengage. |
| `sms.K.reaction_on_threat.ALLOW_ABORT_MISSION` | `"allow_abort_mission"` | Permit AI to abort and RTB when threatened. |

**Example**

```lua
local strike = sms.group("blue-strike-1")
strike:set_option(sms.options.reaction_on_threat(sms.K.reaction_on_threat.EVADE_FIRE))
```

---

## `sms.K.radar_using`

Radar-using strings consumed by `sms.options.radar_using(value)`. Air-only — the builder rejects ground and naval groups.

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.radar_using.NEVER` | `"never"` | Radar never active. |
| `sms.K.radar_using.FOR_ATTACK_ONLY` | `"for_attack_only"` | Radar on only when locked onto a target. |
| `sms.K.radar_using.FOR_SEARCH_IF_REQUIRED` | `"for_search_if_required"` | Radar on when needed to find targets. |
| `sms.K.radar_using.FOR_CONTINUOUS_SEARCH` | `"for_continuous_search"` | Radar always on. |

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.radar_using(sms.K.radar_using.FOR_ATTACK_ONLY))
```

---

## `sms.K.flare_using`

Flare-using strings consumed by `sms.options.flare_using(value)`. Air-only — the builder rejects ground and naval groups.

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.flare_using.NEVER` | `"never"` | Never deploy flares. |
| `sms.K.flare_using.AGAINST_FIRED_MISSILE` | `"against_fired_missile"` | Deploy only when a missile is detected in flight. |
| `sms.K.flare_using.WHEN_FLYING_IN_SAM_WEZ` | `"when_flying_in_sam_wez"` | Deploy while inside a SAM weapon engagement zone. |
| `sms.K.flare_using.WHEN_FLYING_NEAR_ENEMIES` | `"when_flying_near_enemies"` | Deploy when near any enemy. |

**Example**

```lua
local strike = sms.group("blue-strike-1")
strike:set_option(sms.options.flare_using(sms.K.flare_using.AGAINST_FIRED_MISSILE))
```

---

## `sms.K.formation`

Formation preset strings consumed by `sms.options.formation(value)`. Air-only — the builder rejects ground and naval groups.

The builder also accepts a raw integer (the DCS packed formation integer) as an escape hatch for formation presets not listed here.

| Constant | Wire string | Notes |
|---|---|---|
| `sms.K.formation.LINE_ABREAST` | `"line_abreast"` | Side-by-side line. |
| `sms.K.formation.TRAIL` | `"trail"` | Follow-the-leader column. |
| `sms.K.formation.WEDGE` | `"wedge"` | Arrowhead formation. |
| `sms.K.formation.ECHELON_RIGHT` | `"echelon_right"` | Step formation angled right. |
| `sms.K.formation.ECHELON_LEFT` | `"echelon_left"` | Step formation angled left. |
| `sms.K.formation.FINGER_FOUR` | `"finger_four"` | Four-ship finger-four. |
| `sms.K.formation.SPREAD` | `"spread"` | Wide spread formation. |

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.formation(sms.K.formation.WEDGE))

-- Escape hatch: raw DCS integer for an unlisted preset.
cap:set_option(sms.options.formation(131073))
```

---

## `sms.K.units`

Auto-generated catalog of every group-spawnable DCS type, organized by nested category sub-tables. This section is a navigation pointer — the catalog is not exhaustively listed here; use editor autocomplete.

**LuaCATS alias:** `sms.GroupSpawnType` (top-level literal-union of every spawnable group type-string).

**Categories:**

| Namespace | Contains |
|---|---|
| `sms.K.units.planes` | All fixed-wing aircraft |
| `sms.K.units.helicopters` | All rotary-wing aircraft |
| `sms.K.units.armor.tanks` | Main battle tanks |
| `sms.K.units.armor.ifv` | Infantry fighting vehicles |
| `sms.K.units.armor.apc` | Armored personnel carriers |
| `sms.K.units.armor.misc` | Other armored vehicles |
| `sms.K.units.air_defence.sam` | SAM launchers and radars |
| `sms.K.units.air_defence.aaa` | Anti-aircraft artillery |
| `sms.K.units.air_defence.radar` | Standalone EWR radars |
| `sms.K.units.air_defence.manpads` | Shoulder-launched SAMs |
| `sms.K.units.air_defence.misc` | Command vehicles, generators |
| `sms.K.units.artillery` | Howitzers, MLRS, mortars |
| `sms.K.units.infantry` | Soldiers |
| `sms.K.units.unarmed` | Trucks, jeeps, fuel, supply |
| `sms.K.units.fortifications` | Group-spawnable obstacles (bunkers, emplacements) |
| `sms.K.units.missiles` | Surface-to-surface missile launchers |
| `sms.K.units.ships.warships` | Frigates, destroyers, cruisers, missile boats |
| `sms.K.units.ships.carriers` | Aircraft carriers |
| `sms.K.units.ships.civilian` | Cargo vessels, tugs, fishing boats |
| `sms.K.units.ships.submarines` | Submarines |
| `sms.K.units.trains` | Locomotives and cars |

`sms.K.units.origin_of(type_string)` returns the asset-pack name if the type belongs to a non-base-game pack, or `nil` for base-game / unknown strings.

See [`units.md`](units.md) for navigation patterns, identifier sanitization rules, and the `origin_of` API.

---

## `sms.K.statics`

Auto-generated catalog of every static-spawnable DCS type. Same shape as `sms.K.units` — navigation pointer only.

**LuaCATS alias:** `sms.StaticSpawnType` (top-level literal-union of every spawnable static type-string).

**Categories:**

| Namespace | Contains |
|---|---|
| `sms.K.statics.fortifications` | Statics-only fortifications (bunkers, walls, towers, sandbags) |
| `sms.K.statics.cargos` | Slingable crates and containers |
| `sms.K.statics.personnel` | Deck crew, statue-soldiers |
| `sms.K.statics.heliports` | FARPs, helipads, oil rigs |
| `sms.K.statics.warehouses` | Warehouse buildings |
| `sms.K.statics.airfields` | Grass strips |
| `sms.K.statics.equipment` | Aircraft deck equipment, jet starters, generators |
| `sms.K.statics.effects` | Smoke, fire, markers |
| `sms.K.statics.animals` | Cows, etc. |
| `sms.K.statics.airships` | LTA vehicles (balloons) |
| `sms.K.statics.ground_objects` | Miscellaneous |

`sms.K.statics.origin_of(type_string)` works the same as the units variant.

See [`statics.md`](statics.md) for navigation patterns and the `origin_of` API.

---

**See also** — [`AGENTS.md`](../../framework/AGENTS.md) §4 for wire-format conventions; [`docs/api/options.md`](options.md) for the builder functions that consume the option-related constants; [`docs/api/group.md`](group.md) for spawn config examples that thread `sms.K.countries.*` and `sms.K.category.*`.
