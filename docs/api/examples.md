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
  country  = "USA",
  category = "airplane",
  units    = { {type = "FA-18C_hornet", alt = 7500, heading = 90, speed = 220} },
})

local red_cap = sms.group.create({
  name     = "red-cap",
  position = {x = 80000, y = 0, z = 0},   -- ~43 nm east
  country  = "RUSSIA",
  category = "airplane",
  units    = { {type = "Su-27", alt = 7500, heading = 270, speed = 220} },
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
blue_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))
red_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))

-- Poll once per second; convert 20 NM to meters once.
local TRIGGER_RANGE_M = sms.utils.feet_to_meters(20 * 6076)   -- 20 NM ≈ 37 040 m
local triggered       = false

sms.timer.every(1.0, function()
  if triggered then return false end                          -- self-cancel after flip
  if not (blue_cap:is_alive() and red_cap:is_alive()) then return false end

  local distance = sms.utils.vec3_distance(blue_cap:get_position(), red_cap:get_position())
  if distance and distance <= TRIGGER_RANGE_M then
    blue_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))
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
  country  = "USA",
  category = "airplane",
  units    = {
    {type = "F-16C_50", alt = 6000, heading = 90, speed = 220},
    {type = "F-16C_50", alt = 6000, heading = 90, speed = 220, offset = {x = -50, y = 0, z = 50}},
  },
})

local cap = sms.group.create({
  name     = "blue-cap",
  position = {x = -2000, y = 0, z = 1000},
  country  = "USA",
  category = "airplane",
  units    = {
    {type = "F-15C", alt = 7000, heading = 90, speed = 240},
    {type = "F-15C", alt = 7000, heading = 90, speed = 240, offset = {x = -50, y = 0, z = 50}},
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
  if not shooter_group or shooter_group:get_coalition() == "blue" then return end

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
    country  = "USA",
    category = "airplane",
    units    = { {type = "E-3A", alt = sms.utils.feet_to_meters(30000), heading = 90, speed = 200} },
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
    country  = "USA",
    category = "airplane",
    units    = { {type = "KC-135", alt = sms.utils.feet_to_meters(22000), heading = 0, speed = 180} },
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

## Adding to this page

New recipes are welcome. The same correctness bar as the per-module pages applies — every symbol referenced must exist in the framework source, and any vanilla DCS fallback must be flagged with a "Framework gap" note like the one in recipe 1.

When you write a recipe, also consider whether it surfaces a pattern that should grow into the framework. Recipe 1's ROE fallback is a candidate — if it gets reached for in 3+ recipes, that is the signal to add `sms.group:set_roe(...)`.
