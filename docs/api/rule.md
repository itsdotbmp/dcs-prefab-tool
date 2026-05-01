# `sms.rule` — declarative trigger rules

`sms.rule` is the dcs-sms answer to the Mission Editor trigger panel. Every rule is a named, polled, condition-action pair with a small lifecycle: `ONCE` (fire then die), `CONTINUOUS` (fire every tick condition is true), or `TOGGLE` (fire on the false→true edge). Two orthogonal knobs — `cooldown` (minimum sim-seconds between fires) and `sustain` (condition must hold for this long before counting as true) — compose with all three types. A `dev_condition` escape hatch fires the action immediately, bypassing both gates, so authors can verify the action without setting up real game state.

Each rule owns its own `sms.timer.every` handle — there is **no shared scheduler**. The "manager" is a passive registry indexed by name. Construction auto-registers the rule and starts its timer; `:stop()` cancels and unregisters. Constructing a new rule with a name already in the registry replaces the old one (same-name semantics that match DCS's own behavior).

All public functions follow the framework's [failure model: log + nil, never throw](../../AGENTS.md#3-failure-model-log--nil-never-throw). Throws inside `condition` / `dev_condition` / `action` are caught with `pcall` and logged at `error`; the state machine treats a throw as "no fire this tick" and never aborts the framework.

## Loading

Requires `sms.lua`, `log.lua`, and `timer.lua`. The simplest path is `framework/load_all.lua` — see the [API index](README.md).

## `sms.rule(name, opts) → handle | nil`

**Synopsis** — construct a rule, register it under `name`, and start its timer. Returns the handle on success, `nil` + log on bad input.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `name` | `string` | Non-empty registry key. If a rule with this name is already registered it is `:stop()`-ed and replaced (logged at `info`). |
| `opts` | `table` | Options table — see below. |

**Options table**

| Key | Type | Default | Description |
|---|---|---|---|
| `type` | enum | (required) | One of `sms.rule.TYPE.ONCE` / `CONTINUOUS` / `TOGGLE`. |
| `condition` | `fun(): any` | (required) | Zero-arg. Truthy return value means "the rule wants to fire this tick". |
| `action` | `fun()` | (required) | Zero-arg. Return value ignored. Throws are caught and logged. |
| `interval` | `number` (sim-sec) | `1` | How often the condition is evaluated. Must be `> 0`. |
| `cooldown` | `number` (sim-sec) | `0` | Minimum sim-seconds between fires. `0` disables. **Rejected if `> 0` and `type == ONCE`** (a one-shot rule has no second fire to gate). |
| `sustain` | `number` (sim-sec) | `0` | Condition must be continuously true for at least this many sim-seconds before counting as true. `0` disables. Note: sustain is measured between *evaluations*; for tight windows set `interval` proportionally lower. |
| `dev_condition` | `fun(): any` | no-op (`function() end`) | Testing escape hatch. When truthy, fires the action immediately and (for `CONTINUOUS`) repeatedly, **bypassing both `cooldown` and `sustain`**. Pure-dev fires do **not** update `last_fire_time` — dev mode is invisible to the production state machine, so a natural fire that happens after `dev_condition` flips back to false is gated by cooldown the same as if dev had never fired. (Manual `r:fire()` *does* update `last_fire_time` — see below.) |

**Returns** — rule handle. `nil` + `log.warn` on any invalid opts.

**Example — three lifecycle types side by side**

```lua
-- ONCE: fire when the convoy enters the kill zone, then unregister.
sms.rule("convoy_in_kz", {
  type      = sms.rule.TYPE.ONCE,
  interval  = 2,
  condition = function()
    return sms.area("kill_zone"):is_any_of_group_in(sms.group("convoy"))
  end,
  action = function()
    sms.group("ambush_armor"):set_option(sms.options.alarm_state(sms.K.alarm_state.RED))
  end,
})

-- CONTINUOUS with cooldown: warn the player every 30 sim-seconds while
-- they're loitering low over hostile terrain.
sms.rule("low_altitude_warning", {
  type      = sms.rule.TYPE.CONTINUOUS,
  interval  = 5,
  cooldown  = 30,
  condition = function()
    local agl = sms.unit("Player"):get_altitude(true)
    return agl ~= nil and agl < 100
  end,
  action = function()
    trigger.action.outText("ALTITUDE — pull up", 10)
  end,
})

-- TOGGLE with sustain: fire when the helicopter has been above 200ft
-- for 10 continuous seconds; rearm only after it descends.
sms.rule("apache_unmasked", {
  type      = sms.rule.TYPE.TOGGLE,
  interval  = 1,
  sustain   = 10,
  condition = function()
    local agl = sms.unit("apache_lead"):get_altitude(true)
    return agl ~= nil and agl > sms.utils.feet_to_meters(200)
  end,
  action = function()
    sms.group("manpads_team"):set_option(sms.options.alarm_state(sms.K.alarm_state.RED))
  end,
})
```

## `sms.rule.TYPE` — enum table

```lua
sms.rule.TYPE = {
  ONCE       = "once",
  CONTINUOUS = "continuous",
  TOGGLE     = "toggle",
}
```

The opts `type` field accepts any of these three constants. Unknown values are rejected at construction. Internally stored as the lowercase strings (visible in log lines).

## Handle methods

Method-style and module-style calls are equivalent: `r:get_name()` is the same as `sms.rule.get_name(r)`. Methods accept either a handle or a registered name string.

### `r:get_name() → string | nil`

Name passed to the constructor.

### `r:get_type() → string | nil`

The lifecycle type as a lowercase string (`"once" / "continuous" / "toggle"`).

### `r:is_active() → boolean`

For `TOGGLE` rules: `true` while the rule is in the fired state (between rising-edge fire and the falling edge that re-arms). For `ONCE` and `CONTINUOUS`: returns whether the rule is still registered (i.e. not `:stop()`-ed and, for `ONCE`, not yet fired). Silent — never logs.

### `r:fire() → boolean`

Manually run the action right now, **bypassing condition, cooldown, and sustain**. Logged at `info` (`[sms.rule] <name>: manual fire`). For `ONCE` rules, a successful manual fire still unregisters the rule (just like a natural fire). A throw inside `action` is caught, logged at `error`, and does NOT unregister the rule even if `type == ONCE`. Manual fire **does** update `last_fire_time`, so a subsequent natural fire still respects `cooldown`. Returns `true` on success, `false` on throw or bad handle.

### `r:stop() → boolean`

Cancel the timer and remove from the registry. Idempotent — `true` if newly stopped, `false` if already stopped.

### `r:reset() → boolean`

Clear the TOGGLE `active` flag, the in-flight `sustain_start`, and the `last_fire_time`. Useful for "the player restarted the level — re-arm every rule" or for tests. Does NOT touch the timer or the registry.

### `r:set_interval(sec) → boolean`

Reschedule the underlying timer at a new interval. Stops the old timer and starts a fresh one. `sec` must be `> 0`.

### `r:set_cooldown(sec) → boolean`

Mutate cooldown at runtime. `sec` must be `>= 0`. Rejected with `log.warn` if `sec > 0` and the rule is `ONCE`.

### `r:set_sustain(sec) → boolean`

Mutate sustain at runtime. `sec` must be `>= 0`. Also clears any in-flight `sustain_start` so the next true tick restarts accumulation cleanly.

## Registry functions

### `sms.rule.get(name) → handle | nil`

Look up a rule by name. Logs a `warn` and returns `nil` if no rule is registered under that name.

### `sms.rule.all() → handle[]`

Snapshot of every registered rule, in registration order.

### `sms.rule.remove(name) → boolean`

Convenience for `sms.rule.get(name):stop()`. Returns `false` (with a log line) if no rule by that name is registered.

### `sms.rule.test_all()`

Diagnostic. `pcall`s every `condition`, `dev_condition`, and `action` across the entire registry; logs PASS/FAIL per call. **Does not change rule state** — `last_fire_time` is not updated, the TOGGLE `active` flag is not flipped, and `ONCE` rules are not unregistered. Use this to verify your callbacks compile and run without crashing — not to exercise firing logic.

## Worked example — the helicopter_height rule

This is the rule the `sms.rule` design was originally motivated by: red SAMs unmask only when blue helicopters fly high enough to be detectable in a specific zone. It uses `sms.area`, `sms.group`, `sms.unit`, `sms.utils`, and `sms.options` — all already in the framework — plus `sms.rule` itself.

```lua
local kz       = sms.area("zone_apache_height_check")
local choppers = {
  sms.group("apache_grp_01"),
  sms.group("apache_grp_02"),
  sms.group("kiowa_grp_01"),
  sms.group("kiowa_grp_02"),
}

sms.rule("helicopter_height", {
  type          = sms.rule.TYPE.ONCE,
  interval      = 2,
  dev_condition = function() return MIZ.helicopter_height end,
  condition = function()
    for _, grp in ipairs(choppers) do
      if grp:is_alive() and kz:is_any_of_group_in(grp) then
        for _, unit in ipairs(grp:get_units()) do
          if unit:get_altitude(true) > sms.utils.feet_to_meters(200) then
            return true
          end
        end
      end
    end
  end,
  action = function()
    sms.log.info("Apaches detected — unmasking SAM ring")
    for _, name in ipairs({"radar_AAA", "radar_AAA_02", "sa8_02_grp", "sa3", "sa6"}) do
      local roe_opt = sms.options.roe(sms.K.roe.WEAPON_FREE)
      sms.group(name):set_option(roe_opt)
    end
    local alarm_red = sms.options.alarm_state(sms.K.alarm_state.RED)
    sms.group("sa5"):set_option(alarm_red)
    sms.group("manpads"):set_option(alarm_red)
  end,
})
```

To verify the action without flying the mission:

```lua
MIZ = MIZ or {}
MIZ.helicopter_height = true   -- dev_condition fires the action immediately
```

To wire that into an F10 menu or chat command, set `MIZ.helicopter_height` from any DCS callback you like — the rule polls `dev_condition` on its normal `interval`, so the fire happens within `interval` seconds of the flag flip (regardless of `cooldown`, `sustain`, or the real `condition`).

**See also** — [`sms.timer`](timer.md) for the underlying scheduling primitive (rules are layered on `sms.timer.every`); [`sms.events`](events.md) for event-driven hooks (use these instead when the trigger is fundamentally an event, not a state).
