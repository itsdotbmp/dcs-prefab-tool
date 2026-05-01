# Examples — cross-module recipes

Copy-and-paste recipes that combine multiple `sms.*` modules. Each one is realistic mission-script Lua, not a toy snippet.

Every recipe below assumes [`sms` is loaded](../../README.md#quick-start-mission-framework) and that anything mentioned by name (groups, drawings, zones) exists in your `.miz`. When a recipe needs an entity that does **not** exist in the ME, it spawns it inline.

For per-module reference see the [API index](README.md). For the dense surface map see [`AGENTS.md`](../../AGENTS.md).

---

## 1. ROE flip on proximity

**Scenario** — A blue CAP and a red CAP are airborne with rules of engagement set to *Weapons Hold*. As soon as the two flights close to within 20 nautical miles, blue is cleared to *Weapons Free*. Used a lot for training scenarios where you want a known engagement geometry.

**Modules used** — [`sms.group`](group.md), [`sms.task`](task.md), [`sms.options`](options.md), [`sms.timer`](timer.md), [`sms.utils`](utils.md).

```lua
-- Spawn the two CAPs.
local blue_cap = sms.group.create({
  name     = "blue-cap",
  position = {x = 0,      y = 0, z = 0},
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units    = { {type = sms.K.units.planes.FA_18C_hornet, alt = 7500, heading = 90, speed = 220} },
})

local red_cap = sms.group.create({
  name     = "red-cap",
  position = {x = 80000, y = 0, z = 0},   -- ~43 nm east
  country  = sms.K.countries.RUSSIA,
  category = sms.K.category.AIRPLANE,
  units    = { {type = sms.K.units.planes.Su_27, alt = 7500, heading = 270, speed = 220} },
})

-- Send each side to orbit a point 30 km in front of itself.
local blue_orbit = sms.task.orbit({x = 30000, y = 0, z = 0}, {
  altitude = 7500, speed = 220, pattern = "Circle",
})
blue_cap:set_task(blue_orbit)

local red_orbit = sms.task.orbit({x = 50000, y = 0, z = 0}, {
  altitude = 7500, speed = 220, pattern = "Circle",
})
red_cap:set_task(red_orbit)

-- Both sides start with weapons hold.
blue_cap:set_option(sms.options.roe(sms.K.roe.WEAPON_HOLD))
red_cap:set_option(sms.options.roe(sms.K.roe.WEAPON_HOLD))

-- Poll once per second; convert 20 NM to meters once.
local TRIGGER_RANGE_M = sms.utils.feet_to_meters(20 * 6076)   -- 20 NM ≈ 37 040 m
local triggered       = false

sms.timer.every(1.0, function()
  if triggered then return false end                          -- self-cancel after flip
  if not (blue_cap:is_alive() and red_cap:is_alive()) then return false end

  local distance = sms.utils.vec3_distance(blue_cap:get_position(), red_cap:get_position())
  if distance and distance <= TRIGGER_RANGE_M then
    blue_cap:set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))
    sms.log.info(string.format("blue cleared hot at %.0f m", distance))
    triggered = true
  end
end)
```

---

## 2. Range tracker with bomb-impact reports

**Scenario** — A practice range. Whenever a bomb is dropped from within the range polygon, track it and log the miss distance from a fixed target marker when it impacts.

**Modules used** — [`sms.area`](area.md), [`sms.events`](events.md), [`sms.weapon`](weapon.md), [`sms.log`](log.md).

```lua
local range  = sms.area.from_drawing("PracticeRange")
local target = sms.static("Range-Target-Bullseye")

-- Defining the handler as a named local function (rather than inline
-- inside `connect`) keeps the connect call readable and lets the
-- handler be re-used or unit-tested independently. `range` and
-- `target` are captured as upvalues.
--
-- The `---@param evt sms.events.event` annotation gives `evt` full
-- autocomplete in editors with LuaLS. Inline lambdas passed straight
-- to `connect` get this for free; named handlers need the explicit
-- annotation since the language server can't trace it back from the
-- connect call site.
---@param evt sms.events.event
local function on_shot(evt)
  local weapon = evt.weapon
  if not weapon or not weapon:is_bomb() then return end

  -- Only score weapons released inside the range polygon.
  local release_pos = weapon:get_release_position()
  if not release_pos or not range:is_vec3_in(release_pos) then return end

  -- Tail the weapon and score on impact.
  weapon:on_impact(function(weapon)
    local distance = weapon:get_impact_distance_from(target:get_position())
    if distance then
      sms.log.info(string.format(
        "[range] %s scored %.1f m from bullseye (released by %s at %.0f m AGL)",
        weapon:get_type(),
        distance,
        evt.initiator and evt.initiator:get_name() or "unknown",
        weapon:get_release_altitude_agl() or 0
      ))
    end
  end)

  weapon:start_tracking({rate = 30})
end

sms.events.connect(sms.events.SHOT, on_shot)
```

`sms.events` upgrades `evt.weapon` to a tracking-capable handle automatically. `start_tracking` is idempotent, so this is safe even if the same weapon is somehow re-emitted.

---

## 3. Random respawn until depleted

**Scenario** — A red SAM patrol is part of an ME-placed template. Whenever the live patrol is wiped out, respawn it at a random point inside a "patrol box" drawing. Cap at 5 respawns total — after that the area is clear.

**Modules used** — [`sms.group`](group.md), [`sms.area`](area.md), [`sms.events`](events.md), [`sms.timer`](timer.md).

```lua
local box      = sms.area.from_drawing("PatrolBox")
local current  = sms.group("red-patrol-1")           -- the ME-placed instance
local lives    = 5

local function arm_respawn(group_handle)
  group_handle:connect(sms.events.DEAD, function(evt)
    if lives <= 0 then
      sms.log.info("[patrol] depleted at " .. evt.time)
      return
    end
    lives = lives - 1

    -- Small delay so the dead event fully settles before re-spawn.
    sms.timer.after(5, function()
      local next_pos = box:get_random_point()
      local fresh    = sms.group.clone("RED_PATROL_TEMPLATE", {
        name     = "red-patrol-1",
        position = next_pos,
      })
      if fresh then
        sms.log.info(string.format("[patrol] respawn %d at (%.0f, %.0f); %d lives left",
          5 - lives, next_pos.x, next_pos.z, lives))
        arm_respawn(fresh)
      end
    end)
  end)
end

arm_respawn(current)
```

`group:connect(sms.events.DEAD, ...)` fires *once* — when the last unit of the group dies — so each respawn re-arms a new connection on the freshly-spawned group handle.

---

## 4. Strike package with CAP escort and on-demand retasking

**Scenario** — Blue strike (two F-16s with bombs) is briefed to hit a target. A pair of F-15 CAP escorts the strike at offset. If anyone in the strike is hit, the CAP immediately breaks off escort and engages whatever fired the missile.

**Modules used** — [`sms.group`](group.md), [`sms.task`](task.md), [`sms.events`](events.md).

```lua
local strike = sms.group.create({
  name     = "blue-strike",
  position = {x = 0, y = 0, z = 0},
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units    = {
    {type = sms.K.units.planes.F_16C_50, alt = 6000, heading = 90, speed = 220},
    {type = sms.K.units.planes.F_16C_50, alt = 6000, heading = 90, speed = 220, offset = {x = -50, y = 0, z = 50}},
  },
})

local cap = sms.group.create({
  name     = "blue-cap",
  position = {x = -2000, y = 0, z = 1000},
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units    = {
    {type = sms.K.units.planes.F_15C, alt = 7000, heading = 90, speed = 240},
    {type = sms.K.units.planes.F_15C, alt = 7000, heading = 90, speed = 240, offset = {x = -50, y = 0, z = 50}},
  },
})

local target_pt = {x = 60000, y = 0, z = 0}

-- Strike: bomb the target.
local bomb_task = sms.task.bomb(target_pt, {
  altitude    = 5000,
  weapon_type = "Bombs",
  expend      = "All",
  group_attack = true,
})
strike:set_task(bomb_task)

-- CAP: escort the strike with a generous engagement bubble.
local escort_task = sms.task.escort(strike, {
  offset             = {x = -1500, y = 500, z = 1500},
  engagement_dist_max = 12000,
})
cap:set_task(escort_task)

-- Re-task the CAP to engage the shooter the moment the strike takes a hit.
-- Pulling the handler out as a named function (with `cap` as an upvalue)
-- reads more naturally than nesting it inside the `connect` call. The
-- `---@param` annotation gives `evt` full autocomplete in LuaLS-aware
-- editors — see the `on_shot` example above for the rationale.
---@param evt sms.events.event
local function on_strike_hit(evt)
  local shooter = evt.initiator
  if not shooter then return end
  local shooter_group = shooter:get_group()
  if not shooter_group or shooter_group:get_coalition() == sms.K.coalition.BLUE then return end

  sms.log.warn("[cap] strike hit by " .. shooter:get_name() .. " — engaging")
  cap:set_task(sms.task.attack(shooter_group, {weapon_type = "Auto"}))
end

strike:connect(sms.events.HIT, on_strike_hit)
```

Note that `:set_task` *replaces* the active task — the CAP drops its escort the instant the new attack task is dispatched. Use [`:push_task`](task.md#grouppush_tasktask--bool) instead if you want the CAP to resume the escort after the engagement, but be aware of the LIFO caveats documented on `task.md`.

---

## 5. AWACS + Tanker support track with auto-restart

**Scenario** — Two support tracks for a blue mission: an E-3 AWACS holding overhead the FOB, and a KC-135 tanker on a north-south anchor. When either lands or runs out of fuel and despawns, spawn a fresh replacement after 30 minutes.

**Modules used** — [`sms.group`](group.md), [`sms.task`](task.md), [`sms.events`](events.md), [`sms.timer`](timer.md), [`sms.utils`](utils.md).

```lua
local FOB   = {x = 0,     y = 0, z = 0}
local TRACK = {x = 50000, y = 0, z = 30000}

local function spawn_awacs()
  local awacs = sms.group.create({
    name     = "blue-awacs",
    position = {x = FOB.x - 5000, y = 0, z = FOB.z},
    country  = sms.K.countries.USA,
    category = sms.K.category.AIRPLANE,
    units    = { {type = sms.K.units.planes.E_3A, alt = sms.utils.feet_to_meters(30000), heading = 90, speed = 200} },
  })
  if not awacs then return end

  local plan = sms.task.combo({
    sms.task.orbit(FOB, {
      altitude = sms.utils.feet_to_meters(30000),
      speed    = 200,
      pattern  = "Circle",
    }),
    sms.task.awacs({priority = 1}),
  })
  awacs:set_task(plan)
  return awacs
end

local function spawn_tanker()
  local tanker = sms.group.create({
    name     = "blue-tanker",
    position = {x = TRACK.x, y = 0, z = TRACK.z - 5000},
    country  = sms.K.countries.USA,
    category = sms.K.category.AIRPLANE,
    units    = { {type = sms.K.units.planes.KC_135, alt = sms.utils.feet_to_meters(22000), heading = 0, speed = 180} },
  })
  if not tanker then return end

  local plan = sms.task.combo({
    sms.task.orbit(TRACK, {
      altitude        = sms.utils.feet_to_meters(22000),
      speed           = 180,
      pattern         = "Anchored",
      hot_leg_bearing = 0,
      leg_length      = 60000,    -- ~32 nm legs
      width           = 8000,
      clockwise       = true,
    }),
    sms.task.tanker({priority = 1}),
  })
  tanker:set_task(plan)
  return tanker
end

local function rearm(spawn_fn)
  local group = spawn_fn()
  if not group then return end
  group:connect(sms.events.DEAD, function()
    sms.log.info("[support] " .. group:get_name() .. " gone — replacement in 30 min")
    sms.timer.after(30 * 60, function() rearm(spawn_fn) end)
  end)
end

rearm(spawn_awacs)
rearm(spawn_tanker)
```

`sms.task.combo` runs both sub-tasks in parallel; the AWACS / Tanker enroute verbs need an `Orbit` mission underneath them or DCS has nothing to fly the aircraft through.

---

## 6. Convoy ambush — `ONCE` rule with a dev-flag escape hatch

**Scenario** — A red supply convoy is rolling toward an FOB. A blue ambush force is sitting on overwatch with `weapon_hold` and `green` alarm. As soon as any vehicle in the convoy crosses into the kill-zone drawing, the ambush flips to `weapon_free` + `red` alarm — once. A `MIZ.ambush_now` flag short-circuits the condition so the mission designer can verify the action without driving the convoy across the map.

**Modules used** — [`sms.area`](area.md), [`sms.group`](group.md), [`sms.options`](options.md), [`sms.rule`](rule.md), [`sms.log`](log.md).

```lua
MIZ = MIZ or {}

local kill_zone = sms.area.from_drawing("convoy_kill_box")
local convoy    = sms.group("red_supply_convoy")
local ambush    = {
  sms.group("ambush_armor"),
  sms.group("ambush_atgm"),
  sms.group("ambush_infantry"),
}

sms.rule("convoy_ambush", {
  type          = sms.rule.TYPE.ONCE,
  interval      = 2,
  dev_condition = function() return MIZ.ambush_now end,
  condition = function()
    return convoy:is_alive() and kill_zone:is_any_of_group_in(convoy)
  end,
  action = function()
    sms.log.info("[ambush] convoy in kill box — going hot")
    local roe       = sms.options.roe(sms.K.roe.WEAPON_FREE)
    local alarm_red = sms.options.alarm_state(sms.K.alarm_state.RED)
    for _, grp in ipairs(ambush) do
      grp:set_option(roe)
      grp:set_option(alarm_red)
    end
  end,
})
```

To validate the action without the convoy ever moving, set `MIZ.ambush_now = true` from a chat command, F10 menu, or the live-exec bridge. The next `dev_condition` poll (within `interval` seconds) fires the action — and because `ONCE` rules unregister on first fire, you can flip the flag back to `false` immediately afterwards without worrying about a re-fire. See [`sms.rule`](rule.md) for the full dev-vs-natural-fire semantics.

---

## 7. No-fly-zone nag — `CONTINUOUS` rule with `cooldown`

**Scenario** — The mission has a clearly-marked no-fly polygon over a friendly civilian zone. While the player is inside it, a chat warning appears every 20 sim-seconds reminding them to leave; the moment they exit the zone, the warnings stop. No fixed timer — the warning cadence is gated by the rule's cooldown.

**Modules used** — [`sms.area`](area.md), [`sms.unit`](unit.md), [`sms.rule`](rule.md).

```lua
local nfz    = sms.area.from_drawing("civilian_no_fly_zone")
local player = sms.unit("Player")

sms.rule("nfz_warning", {
  type     = sms.rule.TYPE.CONTINUOUS,
  interval = 2,
  cooldown = 20,
  condition = function()
    return player:is_alive() and nfz:is_unit_in(player)
  end,
  action = function()
    trigger.action.outText("LEAVE THE NO-FLY ZONE", 8)
  end,
})
```

`CONTINUOUS` would otherwise fire on every poll while the condition is true; `cooldown = 20` collapses that into one warning per 20 sim-seconds. As soon as the player crosses back out, the condition goes false and the cooldown is moot — the next warning only happens if they re-enter and the cooldown has elapsed.

**Framework gap** — `trigger.action.outText` is the vanilla DCS message API; the framework doesn't yet wrap it. If chat-message recipes start showing up in 2-3 places, that's the signal to add `sms.message.to_all(...)` / `sms.message.to_group(...)` and update [`AGENTS.md`](../../AGENTS.md) §7.

---

## 8. QRF on sustained capture — `TOGGLE` rule with `sustain`

**Scenario** — Red infantry has to *hold* a capture zone, not just dip in. If any red unit is inside the capture polygon for **30 continuous sim-seconds**, a blue QRF spawns from a template and is tasked to retake the zone. If red leaves before 30s elapse, the sustain timer resets and nothing happens. After the QRF launches, the rule re-arms only when the zone clears, so a second sustained push later in the mission triggers a second QRF.

**Modules used** — [`sms.area`](area.md), [`sms.group`](group.md), [`sms.task`](task.md), [`sms.rule`](rule.md), [`sms.log`](log.md).

```lua
local capture_zone = sms.area.from_drawing("capture_zone_alpha")
local red_assault  = {
  sms.group("red_inf_01"),
  sms.group("red_inf_02"),
  sms.group("red_btr_01"),
}
local qrf_count = 0

sms.rule("qrf_dispatch", {
  type     = sms.rule.TYPE.TOGGLE,
  interval = 2,
  sustain  = 30,
  condition = function()
    for _, grp in ipairs(red_assault) do
      if grp:is_alive() and capture_zone:is_any_of_group_in(grp) then
        return true
      end
    end
  end,
  action = function()
    qrf_count = qrf_count + 1
    local spawn_pt = capture_zone:get_position()
    local qrf = sms.group.clone("BLUE_QRF_TEMPLATE", {
      name     = "blue_qrf_" .. qrf_count,
      position = {x = spawn_pt.x - 4000, y = 0, z = spawn_pt.z - 4000},
    })
    if not qrf then return end

    sms.log.info(string.format("[qrf] dispatch %d — red holding capture zone", qrf_count))
    qrf:set_task(sms.task.attack(red_assault[1], {weapon_type = "Auto"}))
  end,
})
```

`TOGGLE` only fires on the rising edge — the moment the condition is sustained-true after being false. Once it fires, the rule sits in its `active` state and *will not fire again* until the condition flips back to false (red has fully left the zone or been killed). That falling edge re-arms the rule for the next sustained push. `sustain = 30` is measured between condition evaluations, so with `interval = 2` red has to be in the zone across at least ~15 polls before the action runs.

---

## Adding to this page

New recipes are welcome. The same correctness bar as the per-module pages applies — every symbol referenced must exist in the framework source, and any vanilla DCS fallback must be flagged with a "Framework gap" note like the one in recipe 1.

When you write a recipe, also consider whether it surfaces a pattern that should grow into the framework. Recipe 1's ROE fallback is a candidate — if it gets reached for in 3+ recipes, that is the signal to add `sms.group:set_roe(...)`.
