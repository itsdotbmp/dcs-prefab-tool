# `sms.options` — persistent controller options (ROE, alarm state, formation, …)

`sms.options` wraps DCS's `Controller:setOption(id, value)` API. Each public function is a *builder* that returns an option table; the apply method [`group:set_option`](#groupset_optionopt--bool) hands that table to the group's controller. Options are *persistent* — once applied they stay in effect until you change them, unlike one-shot tasks or commands.

The module is a near carbon-copy of [`sms.task`](task.md)'s build/apply split, with **one deviation**: ROE cannot resolve to a single DCS option `id` at build time, because `AI.Option.Air.id.ROE`, `AI.Option.Ground.id.ROE`, and `AI.Option.Naval.id.ROE` are three different ints with three different value sets. [`sms.options.roe`](#smsoptionsroevalue--option) returns an `id`-less table tagged with `_sms_roe = true`; the apply layer reads the group's category and dispatches to the right DCS enum + value table. This is documented in detail under [ROE category dispatch](#roe-category-dispatch).

The framework failure model — log + return `nil` (builders) or `false` (apply), never throw — is described in [`AGENTS.md` §3](../../AGENTS.md#3-failure-model-log--nil-never-throw); it is **not** restated per-function below.

## Loading

`sms.options` depends on [`sms.group`](group.md) and [`sms.utils`](utils.md). Loaded by [`framework/load_all.lua`](../../framework/load_all.lua) — nothing extra needed.

## Conventions used on this page

These apply to **every** builder; they are not repeated in each row.

- **String values are lowercase + underscores.** `"weapon_free"`, `"open_fire_weapon_free"`, `"for_continuous_search"`, etc. Match the framework-wide convention in [`AGENTS.md` §4](../../AGENTS.md#4-conventions-and-units).
- **Constant tables are UPPERCASE.** `sms.options.ROE.WEAPON_FREE` resolves to the string `"weapon_free"`. Both forms are accepted by every builder; pick whichever reads better at the call site.
- **Category gates** are enforced at apply time. An air-only option (e.g. `rtb_on_bingo`) applied to a ground group logs a warning and returns `false`. Same for ground-only options (`alarm_state`, `disperse_on_attack`) on aircraft.
- **Distances** are meters; **durations** are seconds. (Both are passed through to DCS unchanged.)

---

## Apply API

### `group:set_option(opt) → bool`

**Synopsis** — apply a `sms.options.*` option table to a group's controller. Wraps `Group:getController():setOption(id, value)`. Handles ROE category dispatch internally.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `opt` | `table` | Option table built by an `sms.options.*` function. Must carry the framework's `_sms_verb` tag — manually-built tables are rejected with a logged warning. |

**Returns** — `true` on success. `false` + log on:
- non-table or untagged input (no `_sms_verb`)
- dead group / invalid handle
- category mismatch (air-only option on ground, etc.)
- ROE value disallowed for the resolved category (e.g. `weapon_free` on a ground group)
- DCS-side rejection (caught via `pcall`)

#### ROE category dispatch

When the supplied option carries `_sms_roe = true`, `set_option` does **not** read `opt.id` / `opt.params`. It instead asks `sms.options._roe_resolve_for_category(g:get_category())` for the right `(id, value_table)`, validates the user's string against the value table, and dispatches the resolved numeric DCS value:

| Category (`group:get_category()`) | DCS option id | Allowed values |
|---|---|---|
| `airplane`, `helicopter` | `AI.Option.Air.id.ROE` | `weapon_free`, `open_fire_weapon_free`, `open_fire`, `return_fire`, `weapon_hold` |
| `ground`, `train` | `AI.Option.Ground.id.ROE` | `open_fire`, `return_fire`, `weapon_hold` |
| `ship` | `AI.Option.Naval.id.ROE` | `open_fire`, `return_fire`, `weapon_hold` |

`weapon_free` and `open_fire_weapon_free` are air-only — applying them to a ground / ship group logs and returns `false`.

**Example**

```lua
-- A blue CAP set to "weapons free" once they push.
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))
cap:set_option(sms.options.reaction_on_threat(sms.options.REACTION_ON_THREAT.EVADE_FIRE))
cap:set_option(sms.options.rtb_on_bingo(true))

-- A SAM site sleeping until called for.
local sam = sms.group("red-sa6-1")
sam:set_option(sms.options.alarm_state(sms.options.ALARM_STATE.GREEN))
sam:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))
```

---

## ROE — `sms.options.roe(value) → option`

**Synopsis** — set the rules of engagement for any group (air, ground, naval). Validation and DCS-side translation happen at apply time, based on the group's category.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `string` | One of the lowercase ROE strings, or the matching `sms.options.ROE.*` constant. See the [enum reference](#smsoptionsroe) below. |

**Returns** — option table tagged `_sms_roe = true`. Builder validates only that `value` is *some* known ROE string; per-category validity is checked by [`group:set_option`](#groupset_optionopt--bool).

**Example — CAP cleared hot**

```lua
-- Two CAP flights start with weapons hold; flip blue to weapons free
-- when the merge is imminent.
local blue_cap = sms.group("blue-cap-1")
local red_cap  = sms.group("red-cap-1")

blue_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))
red_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))

-- Later, on trigger:
blue_cap:set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))
```

**Example — SAM ambush**

```lua
-- Strela holding fire until the strike package is overhead.
local strela = sms.group("red-strela-ambush")
strela:set_option(sms.options.roe(sms.options.ROE.WEAPON_HOLD))
strela:set_option(sms.options.alarm_state(sms.options.ALARM_STATE.GREEN))

-- When triggered, raise alarm and clear ground-allowed ROE.
sms.timer.after(300, function()
  strela:set_option(sms.options.alarm_state(sms.options.ALARM_STATE.RED))
  strela:set_option(sms.options.roe(sms.options.ROE.OPEN_FIRE))
end)
```

**Example — air-only `weapon_free` rejected on ground**

```lua
local tank = sms.group("red-t72-platoon")

-- This succeeds: open_fire is allowed for ground.
tank:set_option(sms.options.roe(sms.options.ROE.OPEN_FIRE))   -- → true

-- This is rejected at apply time: weapon_free is air-only.
tank:set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE)) -- → false
-- log.warn: roe: value 'weapon_free' not allowed for ground groups
```

**Notes** — the builder itself accepts any value present in *any* of the air / ground / naval value tables. A truly bogus string (`"shoot_em"`) is rejected at build time with `nil` + log. Category-specific allowed-set checking is the apply layer's job — that is the only place that knows the group's category.

**See also** — [`group:set_option`](#groupset_optionopt--bool), [`sms.options.alarm_state`](#smsoptionsalarm_statevalue--option).

---

## Air-only enum builders

Each builder below stamps the option with `_sms_air_only = true`; applying any of them to a ground / ship / train group is rejected at apply time.

### `sms.options.reaction_on_threat(value) → option`

**Synopsis** — how the AI flight reacts when a threat is detected (no reaction, evade, abort, …).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `string` | One of `sms.options.REACTION_ON_THREAT.*`. See the [enum reference](#smsoptionsreaction_on_threat). |

**Returns** — option table for `AI.Option.Air.id.REACTION_ON_THREAT`. Air-only.

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.reaction_on_threat(
  sms.options.REACTION_ON_THREAT.EVADE_FIRE
))
```

---

### `sms.options.radar_using(value) → option`

**Synopsis** — controls when the AI uses its radar (never, attack-only, search-if-required, continuous).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `string` | One of `sms.options.RADAR_USING.*`. See the [enum reference](#smsoptionsradar_using). |

**Returns** — option table for `AI.Option.Air.id.RADAR_USING`. Air-only.

**Example**

```lua
-- Silent CAP — only emit when committing to a kill.
local cap = sms.group("blue-cap-stealth")
cap:set_option(sms.options.radar_using(
  sms.options.RADAR_USING.FOR_ATTACK_ONLY
))
```

---

### `sms.options.flare_using(value) → option`

**Synopsis** — when the AI deploys flares.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `string` | One of `sms.options.FLARE_USING.*`. See the [enum reference](#smsoptionsflare_using). |

**Returns** — option table for `AI.Option.Air.id.FLARE_USING`. Air-only.

**Example**

```lua
local strike = sms.group("blue-strike-1")
strike:set_option(sms.options.flare_using(
  sms.options.FLARE_USING.AGAINST_FIRED_MISSILE
))
```

---

### `sms.options.formation(value) → option`

**Synopsis** — set the air formation. Accepts either an `sms.options.FORMATION.*` preset string or a raw DCS packed-integer formation code (escape hatch for formations not in the preset list).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `string \| number` | Preset string (e.g. `"finger_four"`) or a raw DCS packed integer. See the [enum reference](#smsoptionsformation) for the seven presets and their DCS integer mappings. |

**Returns** — option table for `AI.Option.Air.id.FORMATION`. Air-only.

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.formation(sms.options.FORMATION.FINGER_FOUR))

-- Or pass a raw DCS integer for a formation not in the preset list:
cap:set_option(sms.options.formation(786433))   -- e.g. a custom DCS code
```

---

### `sms.options.formation_interval(meters) → option`

**Synopsis** — spacing in meters between formation members.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `meters` | `number` | Non-negative spacing in meters. |

**Returns** — option table for `AI.Option.Air.id.FORMATION_INTERVAL`. Air-only.

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.formation(sms.options.FORMATION.SPREAD))
cap:set_option(sms.options.formation_interval(450))   -- 450 m between wingmen
```

---

## Air-only boolean builders

Each builder below takes a strict `boolean` (numbers and `nil` are rejected) and stamps the option as air-only.

### `sms.options.rtb_on_bingo(value) → option`

**Synopsis** — RTB automatically when fuel reaches bingo.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` enables; `false` disables. |

**Returns** — option table for `AI.Option.Air.id.RTB_ON_BINGO`. Air-only.

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.rtb_on_bingo(true))
```

---

### `sms.options.rtb_on_bingo_ammo(value) → option`

**Synopsis** — RTB automatically when out of weapons (DCS calls this `RTB_ON_OUT_OF_AMMO`).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` enables; `false` disables. |

**Returns** — option table for `AI.Option.Air.id.RTB_ON_OUT_OF_AMMO`. Air-only.

**Example**

```lua
local strike = sms.group("blue-strike-1")
strike:set_option(sms.options.rtb_on_bingo_ammo(true))
```

---

### `sms.options.silence(value) → option`

**Synopsis** — global radio silence. When `true`, the AI suppresses all radio chatter.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` to go silent; `false` to allow chatter. |

**Returns** — option table for `AI.Option.Air.id.SILENCE`. Air-only.

**Example**

```lua
local infil = sms.group("blue-helo-infil")
infil:set_option(sms.options.silence(true))
```

---

### `sms.options.jettison_empty_tanks(value) → option`

**Synopsis** — automatically jettison external fuel tanks once empty.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` to jettison; `false` to retain. |

**Returns** — option table for `AI.Option.Air.id.JETT_TANKS_IF_EMPTY`. Air-only.

**Example**

```lua
local cap = sms.group("blue-cap-1")
cap:set_option(sms.options.jettison_empty_tanks(true))
```

---

### `sms.options.landing_straight_in(value) → option`

**Synopsis** — force the flight to land straight-in (no overhead pattern).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` enables straight-in landing. |

**Returns** — option table for `AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_STRAIGHT_IN`. Air-only.

**Example**

```lua
sms.group("blue-strike-1"):set_option(sms.options.landing_straight_in(true))
```

---

### `sms.options.landing_force_pair(value) → option`

**Synopsis** — force flights to land in pairs.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` to force pair landing. |

**Returns** — option table for `AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_FORCE_PAIR`. Air-only.

**Example**

```lua
sms.group("blue-cap-1"):set_option(sms.options.landing_force_pair(true))
```

---

### `sms.options.landing_restrict_pair(value) → option`

**Synopsis** — restrict flights from landing in pairs (one at a time).

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` to restrict pair landing. |

**Returns** — option table for `AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_RESTRICT_PAIR`. Air-only.

**Example**

```lua
sms.group("blue-cap-1"):set_option(sms.options.landing_restrict_pair(true))
```

---

### `sms.options.landing_overhead_break(value) → option`

**Synopsis** — force the flight to land via an overhead break.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` enables overhead break landing. |

**Returns** — option table for `AI.Option.Air.id.OPTION_FORCED_ATTACK_LANDING_OVERHEAD_BREAK`. Air-only.

**Example**

```lua
sms.group("blue-cap-1"):set_option(sms.options.landing_overhead_break(true))
```

---

### `sms.options.waypoint_pass_report(value) → option`

**Synopsis** — control whether the flight reports waypoint passages on the radio. **The framework inverts the DCS-side semantics so the builder reads the way users think:** `true` = report waypoints, `false` = stay quiet.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `boolean` | `true` to report waypoint passages; `false` to suppress. |

**Returns** — option table for `AI.Option.Air.id.PROHIBIT_WP_PASS_REPORT` with `params = not value`. Air-only.

**Notes** — DCS exposes this as `PROHIBIT_WP_PASS_REPORT`, where `true` means "do *not* report". The framework flips the boolean internally so callers don't have to think backwards. If you happen to read the raw `opt.params` for debugging, expect to see the inverted value.

**Example**

```lua
-- Verbose CAP that calls every waypoint:
sms.group("blue-cap-1"):set_option(sms.options.waypoint_pass_report(true))

-- Quiet ingress:
sms.group("blue-strike-1"):set_option(sms.options.waypoint_pass_report(false))
```

---

## Radio reporting builders (air-only)

Each of the three radio builders below accepts:

- `nil` (or no argument) — defaults to the single attribute `{"Air"}` (matches MOOSE).
- a single string — wrapped into a one-element table.
- a list of strings — passed through verbatim.

Every entry must be a string; non-string entries log + return `nil`. Attributes are DCS unit-attribute strings — common values include `"Air"`, `"Ground Units"`, `"Air Defense"`, `"Helicopters"`, `"Ships"`, `"Tanks"`. Consult DCS `Scripting Wiki` / unit DBs for the full list.

### `sms.options.radio_contact(attrs?) → option`

**Synopsis** — controls which target attributes trigger a "contact" radio call.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `attrs` | `string \| string[] \| nil` | Optional list of DCS attribute strings. Defaults to `{"Air"}`. |

**Returns** — option table for `AI.Option.Air.id.OPTION_RADIO_USAGE_CONTACT`. Air-only.

**Example**

```lua
sms.group("blue-cap-1"):set_option(sms.options.radio_contact({"Air", "Helicopters"}))
```

---

### `sms.options.radio_engage(attrs?) → option`

**Synopsis** — controls which target attributes trigger an "engaging" radio call.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `attrs` | `string \| string[] \| nil` | Optional list of DCS attribute strings. Defaults to `{"Air"}`. |

**Returns** — option table for `AI.Option.Air.id.OPTION_RADIO_USAGE_ENGAGE`. Air-only.

**Example**

```lua
sms.group("blue-cap-1"):set_option(sms.options.radio_engage({"Air"}))
```

---

### `sms.options.radio_kill(attrs?) → option`

**Synopsis** — controls which target attributes trigger a "splash"/kill radio call.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `attrs` | `string \| string[] \| nil` | Optional list of DCS attribute strings. Defaults to `{"Air"}`. |

**Returns** — option table for `AI.Option.Air.id.OPTION_RADIO_USAGE_KILL`. Air-only.

**Example**

```lua
-- Single string is auto-wrapped into a one-element table.
sms.group("blue-cap-1"):set_option(sms.options.radio_kill("Air"))
```

---

## Ground-only builders

Each builder below stamps `_sms_ground_only = true`; applying to an air / ship group is rejected at apply time.

### `sms.options.alarm_state(value) → option`

**Synopsis** — ground-unit alarm state (`auto` / `green` / `red`). `green` = relaxed, radars off; `red` = active, radars on; `auto` = DCS decides.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `value` | `string` | One of `sms.options.ALARM_STATE.*`. See the [enum reference](#smsoptionsalarm_state). |

**Returns** — option table for `AI.Option.Ground.id.ALARM_STATE`. Ground-only.

**Example**

```lua
local sam = sms.group("red-sa10-bn")
sam:set_option(sms.options.alarm_state(sms.options.ALARM_STATE.GREEN))

-- Wake up on trigger.
sms.timer.after(180, function()
  sam:set_option(sms.options.alarm_state(sms.options.ALARM_STATE.RED))
end)
```

---

### `sms.options.disperse_on_attack(seconds) → option`

**Synopsis** — when under attack, ground units scatter from their formation for the given duration before regrouping. **Note: this is integer seconds, not a boolean.** Pass `0` to disable.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `seconds` | `number` | Non-negative number of seconds to disperse. `0` disables. |

**Returns** — option table for `AI.Option.Ground.id.DISPERSE_ON_ATTACK`. Ground-only.

**Notes** — DCS treats this as a duration, not a flag. Calling `disperse_on_attack(true)` is invalid (the builder logs and returns `nil`); use `disperse_on_attack(120)` for a two-minute scatter.

**Example**

```lua
local convoy = sms.group("red-convoy")
convoy:set_option(sms.options.disperse_on_attack(120))   -- 2 min scatter

-- To disable:
convoy:set_option(sms.options.disperse_on_attack(0))
```

---

## Enum reference

Every value listed below is also accepted as the lowercase string on the right (both forms work in every builder).

### `sms.options.ROE`

| Constant | String | Allowed for |
|---|---|---|
| `sms.options.ROE.WEAPON_FREE` | `"weapon_free"` | air only |
| `sms.options.ROE.OPEN_FIRE_WEAPON_FREE` | `"open_fire_weapon_free"` | air only |
| `sms.options.ROE.OPEN_FIRE` | `"open_fire"` | air, ground, naval |
| `sms.options.ROE.RETURN_FIRE` | `"return_fire"` | air, ground, naval |
| `sms.options.ROE.WEAPON_HOLD` | `"weapon_hold"` | air, ground, naval |

### `sms.options.REACTION_ON_THREAT`

| Constant | String |
|---|---|
| `sms.options.REACTION_ON_THREAT.NO_REACTION` | `"no_reaction"` |
| `sms.options.REACTION_ON_THREAT.PASSIVE_DEFENCE` | `"passive_defence"` |
| `sms.options.REACTION_ON_THREAT.EVADE_FIRE` | `"evade_fire"` |
| `sms.options.REACTION_ON_THREAT.BYPASS_AND_ESCAPE` | `"bypass_and_escape"` |
| `sms.options.REACTION_ON_THREAT.ALLOW_ABORT_MISSION` | `"allow_abort_mission"` |

### `sms.options.RADAR_USING`

| Constant | String |
|---|---|
| `sms.options.RADAR_USING.NEVER` | `"never"` |
| `sms.options.RADAR_USING.FOR_ATTACK_ONLY` | `"for_attack_only"` |
| `sms.options.RADAR_USING.FOR_SEARCH_IF_REQUIRED` | `"for_search_if_required"` |
| `sms.options.RADAR_USING.FOR_CONTINUOUS_SEARCH` | `"for_continuous_search"` |

### `sms.options.FLARE_USING`

| Constant | String |
|---|---|
| `sms.options.FLARE_USING.NEVER` | `"never"` |
| `sms.options.FLARE_USING.AGAINST_FIRED_MISSILE` | `"against_fired_missile"` |
| `sms.options.FLARE_USING.WHEN_FLYING_IN_SAM_WEZ` | `"when_flying_in_sam_wez"` |
| `sms.options.FLARE_USING.WHEN_FLYING_NEAR_ENEMIES` | `"when_flying_near_enemies"` |

### `sms.options.ALARM_STATE`

| Constant | String |
|---|---|
| `sms.options.ALARM_STATE.AUTO` | `"auto"` |
| `sms.options.ALARM_STATE.GREEN` | `"green"` |
| `sms.options.ALARM_STATE.RED` | `"red"` |

### `sms.options.FORMATION`

| Constant | String | DCS packed integer |
|---|---|---|
| `sms.options.FORMATION.LINE_ABREAST` | `"line_abreast"` | `65537` |
| `sms.options.FORMATION.TRAIL` | `"trail"` | `131073` |
| `sms.options.FORMATION.WEDGE` | `"wedge"` | `196609` |
| `sms.options.FORMATION.ECHELON_RIGHT` | `"echelon_right"` | `262145` |
| `sms.options.FORMATION.ECHELON_LEFT` | `"echelon_left"` | `327681` |
| `sms.options.FORMATION.FINGER_FOUR` | `"finger_four"` | `393217` |
| `sms.options.FORMATION.SPREAD` | `"spread"` | `458753` |

For formations not in this preset list, pass the raw packed integer directly to [`sms.options.formation`](#smsoptionsformationvalue--option).
