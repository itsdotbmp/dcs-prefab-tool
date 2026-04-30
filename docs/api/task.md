# `sms.task` — task-table builders for DCS group controllers

`sms.task` is the framework's largest module: a family of *builders* that produce DCS task tables, plus the *apply* methods on [`sms.group`](group.md) that hand them to a group's controller. The split between build and apply is deliberate — a task is a first-class value you can store, pass around, compose with [`combo`](#smstaskcombotasks--task), and apply to one group or many.

Every builder returns a plain DCS task table (so manually-built tasks remain valid) plus two private fields the framework reads at apply time:

- `_sms_verb` — string used in apply-layer log messages.
- `_sms_air_only` / `_sms_ground_only` — category gates. [`set_task`](#groupset_tasktask--bool) and [`push_task`](#grouppush_tasktask--bool) reject category mismatches with a logged `false`. Manually-built tables (no `_sms_*` tags) skip the check — that is the user's responsibility.

The framework failure model — log + return `nil` (builders) or `false` (apply), never throw — is described in [`AGENTS.md` §3](../../AGENTS.md#3-failure-model-log--nil-never-throw); it is **not** restated per-function below.

## Loading

`sms.task` requires `sms.unit`, `sms.group`, `sms.static`, `sms.area`, and `sms.utils`. Use [`framework/load_all.lua`](../../framework/load_all.lua) and everything below is available.

## Conventions used on this page

These apply to **every** builder; they are not repeated in each row.

- **Headings**: degrees (0=north, 90=east, clockwise). Internally converted to radians where DCS needs them.
- **Altitudes**: meters (DCS-native). Use [`sms.utils.feet_to_meters`](utils.md) at the boundary if you think in feet.
- **Speed**: meters per second.
- **Coordinates**: vec3 `{x = north, y = altitude, z = east}`. Builders that take a 2D point on the ground (`bomb`, `orbit`, `fire_at_point`, ...) read `pos.x` and `pos.z`; the `y` is altitude where the builder accepts one and ignored otherwise.
- **`opts.weapon_type`** — accepts the strings `"Auto"` (default), `"Guns"`, `"Rockets"`, `"Missiles"`, `"Bombs"`, OR a raw DCS weapon-flag bitmask number for advanced cases. Unknown strings log a warning and fall back to `"Auto"`.
- **Categories**: lowercase `"airplane"`, `"helicopter"`, `"ground"`, `"ship"`, `"train"` — as returned by [`sms.group:get_category`](group.md).
- **Air-only flag** is set by `follow`, `orbit`, `attack`, `attack_in_area`, `bomb`, `land`, `no_task`, `refuel`, `attack_map_object`, `bomb_runway`, `awacs`, `tanker`, `escort`, and the three `engage_en_route_*` builders.
- **Ground-only flag** is set by `fire_at_point` and `ewr`.
- **Snapshot vs. live tracking.** Builders that take a `target` handle (e.g. `move_to`, `bomb`) snapshot the target's position at *build* time. The task does not track a moving target — for that, use [`follow`](#smstaskfollowtarget-opts--task) or [`escort`](#smstaskescorttarget-opts--task).

---

## Builders

### `sms.task.move_to(target, opts?) → task`

**Synopsis** — single-waypoint Mission to drive to `target`'s position. Works for all categories; the apply layer rewrites the waypoint shape (action, alt_type, prepended start waypoint, default ground speed) per the destination group's category.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | `vec3` \| [`sms.unit`](unit.md) \| [`sms.group`](group.md) \| [`sms.static`](static.md) \| [`sms.area`](area.md) | Where to go. Handle positions are read once at build time. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `speed` | `number` (m/s) | unset → DCS default cruise (air); category default for ground/ship/train injected at apply time | When set, the waypoint is built with `speed` and `speed_locked = true`. |

**Returns** — DCS `Mission` task. Not air-only. Apply-layer hook prepends a starting waypoint at the group's current position (mirrors MOOSE's `RouteAirTo` / `RouteGroundTo` pattern).

**Example**

```lua
-- Move a CAS flight to a vec3 reference point at 350 kt (~180 m/s).
local cas = sms.group("blue-cas-1")
cas:set_task(sms.task.move_to({x = 12000, y = 4500, z = -3500}, {
  speed = 180,
}))

-- Drive a convoy to a named ME drawing. The drawing's centroid is the destination.
local convoy = sms.group("red-convoy")
local rally  = sms.area.from_drawing("RallyPolygon")
convoy:set_task(sms.task.move_to(rally))
```

**See also** — [`sms.task.follow`](#smstaskfollowtarget-opts--task), [`sms.task.combo`](#smstaskcombotasks--task).

---

### `sms.task.hold() → task`

**Synopsis** — stop and hold position. Returns a DCS `Nothing` task. The apply layer transparently rewrites this to a zero-speed `Mission` for ground/ship/train groups (DCS rejects `Nothing` as a runtime task on those categories). For air groups DCS interprets `Nothing` as loiter.

**Arguments** — none.

**Returns** — `Nothing` task. No category flag — works on every category.

**Example**

```lua
-- Tell a SAM site to hold fire/movement until you re-task it.
local sam = sms.group("red-sa6-1")
sam:set_task(sms.task.hold())

-- Same call works on air; here we give a CAP some idle time before its real task.
local cap = sms.group("blue-cap-1")
cap:set_task(sms.task.hold())
sms.timer.after(120, function()
  cap:set_task(sms.task.orbit(cap:get_position(), {altitude = 6000, pattern = "Circle"}))
end)
```

---

### `sms.task.follow(target, opts?) → task`

**Synopsis** — air-only formation-follow on another aircraft group. The follower locks to a fixed offset from the target's leader.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | [`sms.unit`](unit.md) \| [`sms.group`](group.md) | Group to follow. A unit handle resolves to its parent group. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `offset` | `vec3` (meters, target-relative) | `{x=-50, y=0, z=-50}` | Position relative to the target leader. `x` = forward/back, `y` = altitude offset, `z` = right/left. |

**Returns** — DCS `Follow` task with `_sms_air_only = true`.

**Example**

```lua
-- Wingman holds 100m astern, 30m below, 50m right of the lead F-15.
local lead = sms.group("blue-f15-lead")
local wing = sms.group("blue-f15-wing")
wing:set_task(sms.task.follow(lead, {
  offset = {x = -100, y = -30, z = 50},
}))
```

**See also** — [`sms.task.escort`](#smstaskescorttarget-opts--task) (follow + permission to engage).

---

### `sms.task.orbit(pos, opts?) → task`

**Synopsis** — air-only orbit at a fixed point. Two patterns: `"Circle"` (default) and `"Anchored"` (the racetrack-style hold; DCS renamed this from `"RaceTrack"` in a recent update — only `"Anchored"` is accepted).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `pos` | `vec3` | Center of the orbit. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `altitude` | `number` (meters) | `5000` | Orbit altitude. |
| `speed` | `number` (m/s) | `200` | Orbit speed. |
| `pattern` | `string` | `"Circle"` | `"Circle"` or `"Anchored"`. Anything else logs and returns `nil`. |

Anchored-only keys (silently ignored when `pattern == "Circle"`):

| Key | Type | Default | Description |
|---|---|---|---|
| `hot_leg_bearing` | `number` (degrees) | `0` | Bearing of the inbound (hot) leg. Internally converted to radians. |
| `leg_length` | `number` (meters) | `30000` (~16 nm) | Length of each straight leg. |
| `width` | `number` (meters) | `10000` (~5 nm) | Width between the two legs. |
| `clockwise` | `boolean` | `false` | Turn direction. Bad type rejected with log + nil. |

**Returns** — DCS `Orbit` task with `_sms_air_only = true`.

**Example**

```lua
-- Simple CAP wheel over a forward area.
local cap = sms.group("blue-f18-cap")
cap:set_task(sms.task.orbit({x = 25000, y = 0, z = -8000}, {
  altitude = 7500,         -- 25k ft
  speed    = 220,
  pattern  = "Circle",
}))

-- Tanker racetrack on a 270° hot leg, clockwise.
local tex = sms.group("blue-tanker-1")
tex:set_task(sms.task.combo({
  sms.task.orbit({x = 50000, y = 0, z = 30000}, {
    altitude        = 6700,
    speed           = 180,
    pattern         = "Anchored",
    hot_leg_bearing = 270,
    leg_length      = 92500,    -- ~50 nm
    width           = 18500,    -- ~10 nm
    clockwise       = true,
  }),
  sms.task.tanker(),
}))
```

**See also** — [`sms.task.tanker`](#smstasktankeropts--task), [`sms.task.awacs`](#smstaskawacsopts--task), [`sms.task.combo`](#smstaskcombotasks--task).

---

### `sms.task.attack(target, opts?) → task`

**Synopsis** — air-only direct-attack on a specific group, unit, or static. Routes to DCS `AttackGroup` for groups and `AttackUnit` for units / statics (DCS shares the unit/static ID space for targeting).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | [`sms.group`](group.md) \| [`sms.unit`](unit.md) \| [`sms.static`](static.md) | What to attack. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `expend` | `string` | `"Auto"` | DCS expend enum (`"All"`, `"Auto"`, `"One"`, `"Two"`, `"Four"`, ...). Passthrough — the framework does not validate. |
| `attack_qty` | `number?` | unset | Max number of attack passes. When set, `attackQtyLimit = true` is also set. |

**Returns** — DCS `AttackGroup` (group target) or `AttackUnit` (unit / static) with `_sms_air_only = true`.

**Example**

```lua
-- Hornet bombs a SAM site group, max two passes, all bombs each pass.
local strike  = sms.group("blue-strike-1")
local sa6     = sms.group("red-sa6-2")
strike:set_task(sms.task.attack(sa6, {
  weapon_type = "Bombs",
  expend      = "All",
  attack_qty  = 2,
}))

-- Strafe a single hostile unit with guns.
local hog = sms.group("blue-a10-1")
local apc = sms.unit("red-bmp-3")
hog:set_task(sms.task.attack(apc, {
  weapon_type = "Guns",
  expend      = "Auto",
}))
```

**See also** — [`sms.task.bomb`](#smstaskbombtarget-opts--task), [`sms.task.engage_en_route_group`](#smstaskengage_en_route_grouptarget-opts--task), [`sms.task.attack_in_area`](#smstaskattack_in_areaarea-opts--task).

---

### `sms.task.attack_in_area(area, opts?) → task`

**Synopsis** — air-only "engage anything in this circle." Wraps DCS `EngageTargetsInZone`. Polygon areas are rejected (v1 limitation, log + nil).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `area` | [`sms.area`](area.md) | Must be circular (`area:get_kind() == "circle"`). |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `altitude_min` | `number?` (meters) | unset | Minimum engagement altitude. Passthrough to DCS `minAlt`. |
| `altitude_max` | `number?` (meters) | unset | Maximum engagement altitude. Passthrough to DCS `maxAlt`. |
| `priority` | `number` | `1` | Priority for enroute scheduling. Bad type rejected with log + nil. |

`targetTypes` is fixed to `{"All"}` in v1. Use [`engage_en_route_targets`](#smstaskengage_en_route_targetsopts--task) when you need the categorical filter.

**Returns** — DCS `EngageTargetsInZone` with `_sms_air_only = true`.

**Example**

```lua
-- Strike package sweeps a kill box. ME zone "KillBox-Alpha" is a circle.
local strike = sms.group("blue-mud-mover-1")
local box    = sms.area("KillBox-Alpha")

strike:set_task(sms.task.combo({
  sms.task.move_to(box),
  sms.task.attack_in_area(box, {
    weapon_type   = "Bombs",
    altitude_min  = 3000,
    altitude_max  = 7500,
    priority      = 1,
  }),
}))
```

**See also** — [`sms.task.engage_en_route_targets`](#smstaskengage_en_route_targetsopts--task).

---

### `sms.task.bomb(target, opts?) → task`

**Synopsis** — air-only level-bombing pass against a position (or any handle's snapshotted position).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | `vec3` \| [`sms.unit`](unit.md) \| [`sms.group`](group.md) \| [`sms.static`](static.md) \| [`sms.area`](area.md) | Where to bomb. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `altitude` | `number` (meters) | `6000` | Release altitude. |
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `expend` | `string` | `"Auto"` | DCS expend enum. Passthrough. |
| `direction` | `number?` (degrees) | unset → free axis | Run-in heading. Internally converted to radians; `directionEnabled` is set to true when this is provided. |
| `group_attack` | `boolean` | `false` | If `true`, every aircraft in the group attacks. |

**Returns** — DCS `Bombing` task with `_sms_air_only = true`.

**Example**

```lua
-- Two-ship of B-1Bs hit a fuel depot from the north at 8 km altitude,
-- both jets release.
local bones = sms.group("blue-bone-flight")
local depot = sms.static("red-fuel-depot-1")

bones:set_task(sms.task.bomb(depot, {
  altitude     = 8000,
  weapon_type  = "Bombs",
  expend       = "All",
  direction    = 180,        -- run in heading south (target lies south)
  group_attack = true,
}))
```

**See also** — [`sms.task.attack`](#smstaskattacktarget-opts--task), [`sms.task.attack_map_object`](#smstaskattack_map_objectpoint-opts--task), [`sms.task.bomb_runway`](#smstaskbomb_runwayairdrome_id-opts--task).

---

### `sms.task.land(target, opts?) → task`

**Synopsis** — air-only land-and-wait at a position. Most useful for helicopters; the apply target is a vec3 or any position-bearing handle.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | `vec3` \| [`sms.unit`](unit.md) \| [`sms.group`](group.md) \| [`sms.static`](static.md) \| [`sms.area`](area.md) | Landing spot. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `duration` | `number` (seconds) | `300` | How long to remain landed before continuing. |

**Returns** — DCS `Land` task with `_sms_air_only = true`. `durationFlag` is always set to `true`.

**Example**

```lua
-- Helo CSAR run: fly to LZ, land for 90 seconds, return home.
local heli   = sms.group("blue-uh60-csar")
local lz     = sms.area("CSAR-LZ")
local home   = sms.area("FOB-Bravo")

heli:set_task(sms.task.combo({
  sms.task.move_to(lz),
  sms.task.land(lz, {duration = 90}),
  sms.task.move_to(home),
}))
```

---

### `sms.task.combo(tasks) → task`

**Synopsis** — runs the listed tasks in parallel via DCS `ComboTask`. Propagates `_sms_air_only` if any constituent has it; same for `_sms_ground_only`. Empty lists or non-table constituents are rejected.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `tasks` | `{task, ...}` | Array of task tables, each typically built by another `sms.task.*` call. |

**Returns** — DCS `ComboTask`. Inherits the strictest category flag of its constituents.

**Example**

```lua
-- AWACS station: orbit + AWACS role.
local awacs = sms.group("blue-e3-1")
awacs:set_task(sms.task.combo({
  sms.task.orbit({x = 60000, y = 0, z = 0}, {
    altitude = 9000,
    speed    = 200,
    pattern  = "Anchored",
    hot_leg_bearing = 90,
    leg_length      = 110000,
    width           = 18500,
  }),
  sms.task.awacs({priority = 1}),
}))
```

**Notes** — Combos do not introduce sequencing; for "do A, then B" use [`push_task`](#grouppush_tasktask--bool) on a short-lived task or chain via [`sms.timer.after`](timer.md) / events.

---

### `sms.task.no_task() → task`

**Synopsis** — air-only empty noop. Useful for clearing the active task without resetting the controller queue.

**Arguments** — none.

**Returns** — DCS `NoTask` with `_sms_air_only = true`.

**Example**

```lua
-- Stop a CAP from chasing the wrong contact, but keep its queue intact.
sms.group("blue-cap-1"):set_task(sms.task.no_task())
```

---

### `sms.task.refuel() → task`

**Synopsis** — air-only "go refuel from the nearest tanker."

**Arguments** — none.

**Returns** — DCS `Refueling` with `_sms_air_only = true`.

**Example**

```lua
-- A bingo-fuel CAP queues a refuel after its current task.
local cap = sms.group("blue-cap-1")
cap:push_task(sms.task.refuel())
```

---

### `sms.task.attack_map_object(point, opts?) → task`

**Synopsis** — air-only attack on a static map object (building / structure that exists in the terrain, not a script-spawned static). DCS does not let scripts pass a map-object id; the AI scans for a structure within ~2 km of `point`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `point` | `vec3` | Position on / near the structure. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `expend` | `string` | `"Auto"` | DCS expend enum. Passthrough. |
| `attack_qty` | `number?` | unset | Number of attack passes. |
| `direction` | `number?` (degrees) | unset | Run-in heading. Converted to radians internally. |
| `group_attack` | `boolean` | `false` | Whole group attacks if `true`. |

**Returns** — DCS `AttackMapObject` with `_sms_air_only = true`.

**Example**

```lua
-- Hit a bridge from the south. Bridge is at the given vec3.
local bombers = sms.group("blue-strike-2")
bombers:set_task(sms.task.attack_map_object({x = 18500, y = 0, z = -22300}, {
  weapon_type  = "Bombs",
  attack_qty   = 1,
  direction    = 180,
  group_attack = true,
}))
```

**See also** — [`sms.task.bomb`](#smstaskbombtarget-opts--task), [`sms.task.bomb_runway`](#smstaskbomb_runwayairdrome_id-opts--task).

---

### `sms.task.bomb_runway(airdrome_id, opts?) → task`

**Synopsis** — air-only "bomb this runway." Takes a numeric DCS airdrome ID. Wraps DCS `BombingRunway`.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `airdrome_id` | `number` (integer DCS airdrome ID) | The id is what `Airbase:getID()` returns; an `sms.airdrome` handle is tracked in [#23](https://github.com/nielsvaes/dcs-sms/issues/23). |
| `opts` | `table?` | Same options as [`attack_map_object`](#smstaskattack_map_objectpoint-opts--task). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `expend` | `string` | `"Auto"` | DCS expend enum. Passthrough. |
| `attack_qty` | `number?` | unset | Number of attack passes. |
| `direction` | `number?` (degrees) | unset | Run-in heading. Converted to radians internally. |
| `group_attack` | `boolean` | `false` | Whole group attacks if `true`. |

**Returns** — DCS `BombingRunway` with `_sms_air_only = true`.

**Example**

```lua
-- Crater the runway at airdrome ID 12 (Krymsk on Caucasus, for example).
local strike = sms.group("blue-strike-3")
strike:set_task(sms.task.bomb_runway(12, {
  weapon_type = "Bombs",
  expend      = "All",
  attack_qty  = 1,
  direction   = 90,         -- run east-bound along the runway axis
  group_attack = true,
}))
```

---

### `sms.task.fire_at_point(point, opts?) → task`

**Synopsis** — ground-only artillery / direct-fire at a vec3. Without `radius`, DCS targets the exact point; with `radius`, fire is spread over a disc.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `point` | `vec3` | Aimpoint. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `radius` | `number?` (meters) | unset → exact point | Radius around the aimpoint to spread fire over. |

**Returns** — DCS `FireAtPoint` with `_sms_ground_only = true`.

**Example**

```lua
-- MLRS battery saturates a 200m circle around an FLOT reference.
local mlrs = sms.group("red-mlrs-bty-1")
mlrs:set_task(sms.task.fire_at_point({x = -8500, y = 0, z = 14500}, {
  radius = 200,
}))
```

---

### `sms.task.escort(target, opts?) → task`

**Synopsis** — air-only escort: follow a target group at offset, engage threats matching `target_types`. Uses the same shape as [`follow`](#smstaskfollowtarget-opts--task) plus engagement parameters.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | [`sms.unit`](unit.md) \| [`sms.group`](group.md) | Group being escorted (a unit handle resolves to its parent group). |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `offset` | `vec3` | `{x=-50, y=0, z=-50}` | Target-relative offset. |
| `engagement_dist_max` | `number` (meters) | `5000` | Max distance from the formation at which the escort will engage. |
| `target_types` | `{string, ...}?` | unset | Array of attribute strings (use [`sms.targets.*`](constants.md) constants). When omitted, DCS applies its default. |
| `last_waypoint_index` | `number?` | unset | Detach when target reaches this waypoint. When set, DCS `lastWptIndexFlag` is also set. |

**Returns** — DCS `Escort` with `_sms_air_only = true`.

**Example**

```lua
-- Two F-15s escort a strike package. Engage anything airborne up to 15 km.
local lead   = sms.group("blue-strike-lead")
local escort = sms.group("blue-f15-escort")

escort:set_task(sms.task.escort(lead, {
  offset              = {x = -200, y = 100, z = 200},   -- aft, above, right
  engagement_dist_max = 15000,
  target_types        = {sms.targets.AIR},
  last_waypoint_index = 5,
}))
```

**See also** — [`sms.task.follow`](#smstaskfollowtarget-opts--task), [`sms.targets`](constants.md).

---

### `sms.task.fac_attack_group(target, opts?) → task`

**Synopsis** — immediate FAC: tag a specific group for friendlies. No category gate (works on air or ground FACs).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | [`sms.group`](group.md) | The group to designate. Strict — units / statics not accepted. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | Recommended weapon class for engagers. |
| `designation` | `string` | `"Auto"` | Marker style. Use [`sms.designations.*`](constants.md): `NO`, `AUTO`, `WP`, `IR_POINTER`, `LASER`. Raw strings also accepted (DCS validates). |
| `datalink` | `boolean` | `true` | Whether to share via datalink. |

**Returns** — DCS `FAC_AttackGroup`. No category flag.

**Example**

```lua
-- A-10 FAC marks an enemy column with WP for incoming CAS.
local fac     = sms.group("blue-fac-a10")
local hostile = sms.group("red-armor-1")

fac:set_task(sms.task.fac_attack_group(hostile, {
  weapon_type = "Auto",
  designation = sms.designations.WP,
  datalink    = true,
}))
```

**See also** — [`sms.task.fac`](#smstaskfacopts--task), [`sms.task.fac_engage_group`](#smstaskfac_engage_grouptarget-opts--task), [`sms.designations`](constants.md).

---

### `sms.task.fac(opts) → task`

**Synopsis** — area FAC (enroute role): patrol an area and call out hostiles for friendlies. No category gate.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `opts` | `table` | **Required.** `radius` is mandatory. |

| Key | Type | Default | Description |
|---|---|---|---|
| `radius` | `number` (meters) | **required** | Area radius around the FAC. |
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `FAC`. No category flag.

**Example**

```lua
-- An OH-58D scout runs an area FAC over a 10 km radius.
local scout = sms.group("blue-oh58-1")
scout:set_task(sms.task.combo({
  sms.task.orbit(scout:get_position(), {altitude = 600, speed = 50, pattern = "Circle"}),
  sms.task.fac({radius = 10000, priority = 1}),
}))
```

---

### `sms.task.fac_engage_group(target, opts?) → task`

**Synopsis** — enroute FAC for a specific target group. Same option surface as [`fac_attack_group`](#smstaskfac_attack_grouptarget-opts--task) plus a priority.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | [`sms.group`](group.md) | The group to engage. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `designation` | `string` | `"Auto"` | See [`fac_attack_group`](#smstaskfac_attack_grouptarget-opts--task). |
| `datalink` | `boolean` | `true` | Share via datalink. |
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `FAC_EngageGroup`. No category flag.

**Example**

```lua
local fac     = sms.group("blue-fac-flight")
local hostile = sms.group("red-mech-coy-1")
fac:push_task(sms.task.fac_engage_group(hostile, {
  designation = sms.designations.LASER,
  priority    = 1,
}))
```

---

### `sms.task.engage_en_route_targets(opts) → task`

**Synopsis** — air-only enroute "permission to engage anything matching these target types." Distinct from [`attack`](#smstaskattacktarget-opts--task) and [`attack_in_area`](#smstaskattack_in_areaarea-opts--task) — those are immediate, this is a standing rule that persists alongside the route.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `opts` | `table` | **Required.** `target_types` is mandatory. |

| Key | Type | Default | Description |
|---|---|---|---|
| `target_types` | `{string, ...}` | **required** | Attribute strings (use [`sms.targets.*`](constants.md)). |
| `max_dist` | `number?` (meters) | unset | Max engagement distance from the route. |
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `EngageTargets` with `_sms_air_only = true`.

**Example**

```lua
-- F-16 sweep: fly the route AND engage any planes within 50 km.
local sweep = sms.group("blue-f16-sweep")
sweep:set_task(sms.task.combo({
  sms.task.move_to({x = 80000, y = 7500, z = 0}),
  sms.task.engage_en_route_targets({
    target_types = {sms.targets.PLANES, sms.targets.HELICOPTERS},
    max_dist     = 50000,
    priority     = 1,
  }),
}))
```

**See also** — [`sms.targets`](constants.md), [`sms.task.engage_en_route_group`](#smstaskengage_en_route_grouptarget-opts--task).

---

### `sms.task.engage_en_route_group(target, opts?) → task`

**Synopsis** — air-only enroute permission to engage a specific group.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | [`sms.group`](group.md) | Group to engage. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `expend` | `string` | `"Auto"` | DCS expend enum. Passthrough. |
| `attack_qty` | `number?` | unset | Max attack passes. Sets `attackQtyLimit = true` when present. |
| `direction` | `number?` (degrees) | unset | Run-in heading; converted to radians. |
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `EngageGroup` with `_sms_air_only = true`.

**Example**

```lua
-- A flight on a transit gets standing permission to engage a known SAM
-- group if it bumps into them, but only with anti-radiation missiles.
local strike = sms.group("blue-wild-weasel-1")
local sa10   = sms.group("red-sa10-1")
strike:push_task(sms.task.engage_en_route_group(sa10, {
  weapon_type = "Missiles",
  attack_qty  = 1,
  priority    = 1,
}))
```

---

### `sms.task.engage_en_route_unit(target, opts?) → task`

**Synopsis** — air-only enroute permission to engage a specific unit.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `target` | [`sms.unit`](unit.md) | Unit to engage. |
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `weapon_type` | `string` \| `number` | `"Auto"` | See [conventions](#conventions-used-on-this-page). |
| `expend` | `string` | `"Auto"` | DCS expend enum. Passthrough. |
| `attack_qty` | `number?` | unset | Max attack passes. Sets `attackQtyLimit = true` when present. |
| `direction` | `number?` (degrees) | unset | Run-in heading; converted to radians. |
| `group_attack` | `boolean` | `false` | If true, every aircraft in the group engages. |
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `EngageUnit` with `_sms_air_only = true`.

**Example**

```lua
-- Hunt one specific high-value target (HVT named in the ME).
local hunters = sms.group("blue-f15e-1")
local hvt     = sms.unit("red-command-truck")
hunters:set_task(sms.task.combo({
  sms.task.move_to({x = 30000, y = 5000, z = -10000}),
  sms.task.engage_en_route_unit(hvt, {
    weapon_type  = "Missiles",
    attack_qty   = 1,
    group_attack = true,
    priority     = 1,
  }),
}))
```

---

### `sms.task.awacs(opts?) → task`

**Synopsis** — air-only enroute "act as AWACS for friendlies."

**Arguments**

| Name | Type | Description |
|---|---|---|
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `AWACS` with `_sms_air_only = true`.

**Example**

```lua
-- E-3 on station: orbit + AWACS role.
local awacs = sms.group("blue-awacs-1")
awacs:set_task(sms.task.combo({
  sms.task.orbit({x = 100000, y = 0, z = 50000}, {
    altitude        = 9000,
    speed           = 200,
    pattern         = "Anchored",
    hot_leg_bearing = 90,
    leg_length      = 110000,
    width           = 18500,
  }),
  sms.task.awacs({priority = 1}),
}))
```

---

### `sms.task.tanker(opts?) → task`

**Synopsis** — air-only enroute "act as tanker for friendlies."

**Arguments**

| Name | Type | Description |
|---|---|---|
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `Tanker` with `_sms_air_only = true`.

**Example**

```lua
-- KC-135 racetrack with tanker role at priority 2 (a higher-priority
-- AWACS task is on the same group).
local boom = sms.group("blue-tanker-1")
boom:set_task(sms.task.combo({
  sms.task.orbit({x = 50000, y = 0, z = 30000}, {
    altitude        = 6700,
    speed           = 180,
    pattern         = "Anchored",
    hot_leg_bearing = 270,
    leg_length      = 92500,
    width           = 18500,
    clockwise       = true,
  }),
  sms.task.awacs({priority = 1}),
  sms.task.tanker({priority = 2}),
}))
```

---

### `sms.task.ewr(opts?) → task`

**Synopsis** — ground-only enroute "act as early-warning radar."

**Arguments**

| Name | Type | Description |
|---|---|---|
| `opts` | `table?` | Options (below). |

| Key | Type | Default | Description |
|---|---|---|---|
| `priority` | `number` | `1` | Enroute-task priority. |

**Returns** — DCS `EWR` with `_sms_ground_only = true`.

**Example**

```lua
-- A 55G6 stationed near the FLOT acts as EWR for the IADS.
local ewr = sms.group("red-55g6-1")
ewr:set_task(sms.task.ewr({priority = 1}))
```

---

## Apply API — installed on `sms.group`

These two methods live in `framework/group.lua` (they extend `sms.group`'s namespace) but they are the runtime counterpart to every builder above, so they are documented here. See also [`sms.group`](group.md).

Both call into the deferred-dispatch machinery: validation runs synchronously, the actual `Controller:setTask` / `Controller:pushTask` call is scheduled ~10 ms in the future via [`sms.timer.after`](timer.md). This avoids a DCS race where assigning a task on the same frame the group spawned silently despawns aircraft / no-ops ground.

### `group:set_task(task) → bool`

**Synopsis** — replace the group's current task. Returns `true` on dispatch, `false` after logging on bad input or category mismatch.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `self` | [`sms.group`](group.md) | Receiver. Must be alive. |
| `task` | `table` | A task built by `sms.task.*` (preferred) or any DCS-shaped table with `id` (string) and `params` (table). |

**Failure surface (logged):**

- `task` not a table or missing `id` / `params` → `false`.
- Group not alive at apply time → `false`.
- Task is `_sms_air_only` and group is not airplane / helicopter → `false`. Log line: `set_task: '<verb>' is air-only; group '<name>' is <category> — not applied`.
- Task is `_sms_ground_only` and group is not ground → `false`. Symmetric log line.
- DCS rejects the task at deferred dispatch → `error`-level log; the synchronous `set_task` call has already returned `true`.

**Returns** — `bool`.

**Example**

```lua
local cap = sms.group("blue-cap-1")
local ok  = cap:set_task(sms.task.orbit({x = 0, y = 0, z = 0}, {altitude = 7000}))
if not ok then
  sms.log.warn("CAP could not start orbit; check category / aliveness")
end
```

---

### `group:push_task(task) → bool`

**Synopsis** — push a task onto the group's task stack. Same validation surface as [`set_task`](#groupset_tasktask--bool).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `self` | [`sms.group`](group.md) | Receiver. Must be alive. |
| `task` | `table` | Same shape as for `set_task`. |

**Returns** — `bool`.

**Notes — partial LIFO.**
- Short-lived tasks (`attack`, `bomb`, `land`) interrupt the current task; the previous task resumes when they finish.
- Mission-style tasks (`move_to`, `orbit`) **do not stack** — pushing one over another *replaces* the previous route. Wrapping in `combo` does not change this.
- For "via B then to A" semantics use a multi-waypoint route (planned), or chain via [`sms.timer.after`](timer.md) / events.

**Example**

```lua
-- A CAP gets tasked to land at a divert base after its current orbit.
local cap = sms.group("blue-cap-1")
cap:push_task(sms.task.land({x = 14000, y = 0, z = -2000}, {duration = 600}))
```

**See also** — [`sms.timer.after`](timer.md), [`sms.events`](events.md), [`sms.group`](group.md).
