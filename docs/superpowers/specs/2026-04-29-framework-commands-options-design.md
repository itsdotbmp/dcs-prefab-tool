# dcs-sms Framework — `sms.commands` and `sms.options` v1

**Date:** 2026-04-29
**Status:** Approved (brainstorm phase)
**Scope:** Two new framework modules wrapping DCS's controller `setCommand` and `setOption` APIs. Carbon-copy of the `sms.task` v1 pattern: ergonomic builders that return DCS-native tables, plus apply methods on `sms.group`. Includes the full FAQ surface plus MOOSE's commonly-reached-for additions. Closes the ROE gap surfaced by `docs/api/examples.md` recipe 1.

## Goal

DCS exposes two non-task APIs on a group's controller that mission scripts reach for constantly:

- **`Controller:setCommand(cmd)`** — fire-and-forget verbs (`SwitchWaypoint`, `SetFrequency`, `ActivateBeacon`, `SetImmortal`, …).
- **`Controller:setOption(id, value)`** — persistent behavioural state (ROE, alarm state, RTB on bingo, formation, …).

Both are awkward to use directly. `setOption(AI.Option.Air.id.ROE, AI.Option.Air.val.ROE.WEAPON_HOLD)` is verbose, fragile, and silently does nothing if you pass the ground enum to an air group. ROE in particular has three different DCS enums (Air / Ground / Naval) with different value sets, so wrapping it cleanly demands category-aware dispatch.

This module pair gives users the same shape they already learned for `sms.task`: a builder returns a value, the apply method dispatches it. The category enforcement, value validation, and DCS-side translation all live behind the wrapper.

## User value

After this iteration the user can write:

```lua
-- Set blue CAP weapons-free on proximity to a red flight (was the
-- "Framework gap" callout in docs/api/examples.md recipe 1):
local TRIGGER_M = sms.utils.feet_to_meters(20 * 6076)

sms.timer.every(1.0, function()
  if not (blue:is_alive() and red:is_alive()) then return false end
  local d = sms.utils.vec3_distance(blue:get_position(), red:get_position())
  if d and d <= TRIGGER_M then
    blue:set_option(sms.options.roe(sms.options.ROE.WEAPON_FREE))
    return false
  end
end)

-- Telegraph an intercept by clearing radar use:
intercept:set_option(sms.options.radar_using(sms.options.RADAR_USING.FOR_CONTINUOUS_SEARCH))

-- Ground SAM goes red on alarm trigger:
sa6:set_option(sms.options.alarm_state(sms.options.ALARM_STATE.RED))

-- Tanker activates a TACAN at mission start:
tanker:set_command(sms.commands.activate_beacon({
  type      = sms.commands.BEACON.TYPE.TACAN,
  system    = sms.commands.BEACON.SYSTEM.TACAN_TANKER_X,
  callsign  = "TEX",
  frequency = 1088000000,   -- channel 75X
}))

-- Side comm setup at mission start:
formation:set_command(sms.commands.set_frequency(251000000, sms.commands.MODULATION.AM))

-- A wrong-category call is rejected loudly, not silently:
ground_group:set_option(sms.options.rtb_on_bingo(true))
-- log: [sms.options] set_option: 'rtb_on_bingo' is air-only; group 'tank-1' is ground — not applied
```

Autocomplete works on the enum tables, so users can discover values without memorising strings.

## Module shape

Two new files in `framework/`. Loading order extends the existing chain:

```
sms → log → utils → targets → designations → group → unit → area → timer
    → group_spawn → static → events → weapon → task
    → commands → options
```

`commands.lua` and `options.lua` depend on `sms.group` (apply-method install on the metatable) and `sms.utils` (category-string normalization, `coalition_int_to_str`-style validation helpers). They do **not** depend on `sms.task` — they are peers, not children.

Files in scope:

- **new** `framework/commands.lua` — verb-style builders + `group:set_command` apply method.
- **new** `framework/options.lua` — option-state builders + `group:set_option` apply method.
- **new** `framework/test/smoke_commands.sh` — synthetic + live-DCS smoke coverage.
- **new** `framework/test/smoke_options.sh` — synthetic + live-DCS smoke coverage.
- **modify** `framework/load_all.lua` — append `commands.lua` and `options.lua` to the loader list.
- **modify** `framework/group.lua` — extend the existing `_validate_apply` helper (used by `set_task` / `push_task`) to also handle `_sms_naval_only` and `_sms_roe`. The new methods install themselves from the new modules; `group.lua` only needs the helper extension.
- **modify** `AGENTS.md` — two new sub-sections under §7 (`sms.commands`, `sms.options`); brief mentions in §3 of `_sms_naval_only` and `_sms_roe`.
- **new** `docs/api/commands.md`, `docs/api/options.md` — full per-builder reference pages matching the existing API doc style.
- **modify** `docs/api/README.md` — index gets two new rows.
- **modify** `docs/api/examples.md` — rewrite recipe 1 to use `sms.options.roe(...)`; drop the "Framework gap" callout.
- **modify** `README.md` — module list under "Repo layout" gains `sms.commands` and `sms.options`.
- **new spec** this file.

## Builders

### `sms.commands` (19 builders)

Every builder returns a plain DCS command table:

```lua
{
  id              = "<DCS command id>",
  params          = {...},
  _sms_verb       = "<verb name>",       -- private, log msgs
  _sms_air_only   = true|nil,            -- private, apply-layer gate
}
```

Air-only commands set `_sms_air_only = true`; everything else is unflagged ("works on every category").

| Builder | Args | Categories |
|---|---|---|
| `sms.commands.no_action()` | — | all |
| `sms.commands.set_frequency(hz, modulation?, power?)` | Hz number; modulation = `MODULATION.AM` (default) / `MODULATION.FM`; optional power (W). | all |
| `sms.commands.set_frequency_for_unit(hz, modulation?, power?, unit_id)` | Same plus unit ID. | all |
| `sms.commands.switch_waypoint(from_idx, to_idx)` | Two ints. | all |
| `sms.commands.stop_route(value)` | bool — true halts route, false resumes. | all |
| `sms.commands.switch_action(action_idx)` | int. | all |
| `sms.commands.set_invisible(value)` | bool. | all |
| `sms.commands.set_immortal(value)` | bool. | all |
| `sms.commands.set_unlimited_fuel(value)` | bool. | air |
| `sms.commands.set_callsign(callname, number?)` | numeric DCS callname enum + flight number (default 1). | air |
| `sms.commands.activate_beacon(opts)` | `{type, system, callsign?, frequency, name?, unit_id?, channel?, mode_channel?, aa?, bearing?}`. Mirrors MOOSE's full surface. | air |
| `sms.commands.deactivate_beacon()` | — | air |
| `sms.commands.activate_acls(unit_id?, name?)` | optional unit ID, name. | air |
| `sms.commands.deactivate_acls()` | — | air |
| `sms.commands.activate_icls(channel, unit_id?, callsign?)` | int channel + optional unit ID, callsign. | air |
| `sms.commands.deactivate_icls()` | — | air |
| `sms.commands.activate_link4(frequency, unit_id?, callsign?)` | Hz number + optional unit ID, callsign. | air |
| `sms.commands.deactivate_link4()` | — | air |
| `sms.commands.eplrs(value, group_id?)` | bool + optional explicit group ID (defaults to the group the command is applied to). | all |

`sms.commands.script` is intentionally **not** included — using `dostring`/`dofile` to inject Lua is redundant when the user is already writing mission script Lua.

### `sms.options` (20 builders)

Same return shape as `sms.commands`, plus optional `_sms_ground_only`, `_sms_naval_only`, and `_sms_roe` markers:

```lua
{
  id               = "<AI.Option.{Air,Ground,Naval}.id.X>" | nil,    -- nil for _sms_roe; resolved at apply
  params           = <value>,
  _sms_verb        = "<verb name>",
  _sms_air_only    = true|nil,
  _sms_ground_only = true|nil,
  _sms_naval_only  = true|nil,
  _sms_roe         = true|nil,    -- triggers category-dispatched id+value lookup at apply time
}
```

| Builder | Args | Categories |
|---|---|---|
| `sms.options.roe(value)` | One of the 5 `sms.options.ROE.*` strings. Apply layer dispatches to the right `AI.Option.*.id.ROE`; values not allowed for the resolved category log + return false. | all (special) |
| `sms.options.reaction_on_threat(value)` | One of the 5 `sms.options.REACTION_ON_THREAT.*` strings. | air |
| `sms.options.radar_using(value)` | One of 4 `sms.options.RADAR_USING.*` strings. | air |
| `sms.options.flare_using(value)` | One of 4 `sms.options.FLARE_USING.*` strings. | air |
| `sms.options.formation(value)` | A `sms.options.FORMATION.*` string preset OR a raw DCS packed integer (escape hatch for unknown formations — same pattern as `weapon_type` in `sms.task`). | air |
| `sms.options.formation_interval(meters)` | Positive number (formation spacing). | air |
| `sms.options.rtb_on_bingo(value)` | bool. | air |
| `sms.options.rtb_on_bingo_ammo(value)` | bool. | air |
| `sms.options.silence(value)` | bool. | air |
| `sms.options.jettison_empty_tanks(value)` | bool. | air |
| `sms.options.landing_straight_in(value)` | bool. | air |
| `sms.options.landing_force_pair(value)` | bool. | air |
| `sms.options.landing_restrict_pair(value)` | bool. | air |
| `sms.options.landing_overhead_break(value)` | bool. | air |
| `sms.options.waypoint_pass_report(value)` | bool. **Wrapper inverts the bool** before passing — DCS exposes this as `PROHIBIT_WP_PASS_REPORT` (inverted). User-facing semantics: `true` = report, `false` = silent. | air |
| `sms.options.radio_contact(attrs?)` | List of DCS attribute strings (e.g. `{"Air", "Ground Units"}`). Defaults to `{"Air"}`. | air |
| `sms.options.radio_engage(attrs?)` | Same shape. | air |
| `sms.options.radio_kill(attrs?)` | Same shape. | air |
| `sms.options.alarm_state(value)` | One of `sms.options.ALARM_STATE.AUTO` / `GREEN` / `RED`. | ground |
| `sms.options.disperse_on_attack(seconds)` | Non-negative integer. `0` disables. (DCS takes seconds; the FAQ wrongly documents this as a bool — MOOSE confirms the integer-seconds shape.) | ground |

### Enum tables

Live alongside the builders in the same module file. Convention: **uppercase table name** distinguishes constants from the lowercase builder functions. Builders accept either the constant value or the equivalent raw string — exact same forward-compat escape hatch as `sms.targets.AIR` (string `"Air"`).

`sms.options`:

```lua
sms.options.ROE = {
  WEAPON_FREE           = "weapon_free",
  OPEN_FIRE_WEAPON_FREE = "open_fire_weapon_free",
  OPEN_FIRE             = "open_fire",
  RETURN_FIRE           = "return_fire",
  WEAPON_HOLD           = "weapon_hold",
}

sms.options.REACTION_ON_THREAT = {
  NO_REACTION          = "no_reaction",
  PASSIVE_DEFENCE      = "passive_defence",
  EVADE_FIRE           = "evade_fire",
  BYPASS_AND_ESCAPE    = "bypass_and_escape",
  ALLOW_ABORT_MISSION  = "allow_abort_mission",
}

sms.options.RADAR_USING = {
  NEVER                  = "never",
  FOR_ATTACK_ONLY        = "for_attack_only",
  FOR_SEARCH_IF_REQUIRED = "for_search_if_required",
  FOR_CONTINUOUS_SEARCH  = "for_continuous_search",
}

sms.options.FLARE_USING = {
  NEVER                     = "never",
  AGAINST_FIRED_MISSILE     = "against_fired_missile",
  WHEN_FLYING_IN_SAM_WEZ    = "when_flying_in_sam_wez",
  WHEN_FLYING_NEAR_ENEMIES  = "when_flying_near_enemies",
}

sms.options.ALARM_STATE = { AUTO = "auto", GREEN = "green", RED = "red" }

sms.options.FORMATION = {
  -- Air formations exposed as preset names. Implementation looks up packed
  -- DCS integer at builder time. Builder also accepts a raw integer for
  -- unknown formations (forward-compat).
  LINE_ABREAST = "line_abreast",
  TRAIL        = "trail",
  WEDGE        = "wedge",
  ECHELON_RIGHT = "echelon_right",
  ECHELON_LEFT  = "echelon_left",
  FINGER_FOUR  = "finger_four",
  SPREAD       = "spread",
  -- Full preset list landed in implementation per AI.Formation table.
}
```

`sms.commands`:

```lua
sms.commands.MODULATION = { AM = 0, FM = 1 }   -- numeric per DCS

sms.commands.BEACON = {
  TYPE = {
    NULL                     = 0,
    VOR                      = 2,
    DME                      = 3,
    TACAN                    = 4,
    VORTAC                   = 5,
    HOMER                    = 8,
    AIRPORT_HOMER            = 9,
    AIRPORT_HOMER_WITH_MARKER = 10,
    ILS_FAR_HOMER            = 16,
    ILS_NEAR_HOMER           = 17,
    ILS_LOCALIZER            = 18,
    ILS_GLIDESLOPE           = 19,
    NAUTICAL_HOMER           = 65,
  },
  SYSTEM = {
    PAR_10                   = 1,
    RSBN_5                   = 2,
    TACAN                    = 3,
    TACAN_TANKER_X           = 4,
    TACAN_TANKER_Y           = 5,
    VOR                      = 6,
    ILS_LOCALIZER            = 7,
    ILS_GLIDESLOPE           = 8,
    -- additional values per DCS Beacon.System; full list in implementation.
  },
}

sms.commands.CALLSIGN = {
  -- Numeric per-aircraft callsign enum. Provided as a documented passthrough;
  -- the most common values are exposed by name in implementation but most
  -- users will pass a numeric DCS enum value directly.
}
```

## Apply API

Two new methods installed on `sms.group`'s metatable, exactly mirroring `set_task` / `push_task`:

```lua
group:set_command(cmd) → bool      -- wraps Group:getController():setCommand(cmd)
group:set_option(opt)  → bool      -- wraps Group:getController():setOption(id, value)
```

No `push_*` variants — DCS does not stack commands or options.

**Returns `true`** on dispatch.

**Returns `false` + log on:**

- non-handle argument
- dead group
- non-table argument, or table without `_sms_verb` (rejects manually-built tables that don't carry the marker — different from `set_task`, which tolerates raw DCS task tables; rationale: command/option tables don't have the same `id`/`params` ubiquity that DCS tasks do, and accepting raw tables would defeat the category gate)
- `_sms_air_only` applied to non-air group (category not `"airplane"` or `"helicopter"`)
- `_sms_ground_only` applied to non-ground group (category not `"ground"`)
- `_sms_naval_only` applied to non-naval group (category not `"ship"`)
- `_sms_roe` with a value not in the resolved category's allowed set (e.g. `"weapon_free"` against a ground group)
- DCS-side `pcall` failure

**Category mismatch log:**

```
[sms.options] set_option: 'rtb_on_bingo' is air-only; group 'tank-1' is ground — not applied
[sms.options] set_option: 'roe' value 'weapon_free' not allowed for ground groups; group 'tank-1' — not applied
```

## ROE category dispatch (the one deviation from sms.task's pattern)

The `roe(value)` builder cannot resolve to a single DCS option `id` at build time — `AI.Option.Air.id.ROE`, `AI.Option.Ground.id.ROE`, and `AI.Option.Naval.id.ROE` are three different ints, and the value sets differ.

Builder returns:

```lua
{
  _sms_verb = "roe",
  _sms_roe  = true,
  value     = "weapon_hold",   -- normalized lowercase string
}
```

Apply layer:

1. Reads the group's category via the existing `g:get_category()`.
2. Maps category to `(option_id, allowed_values)`:
   - `airplane` / `helicopter` → `AI.Option.Air.id.ROE`, full 5 values
   - `ground` / `train` → `AI.Option.Ground.id.ROE`, 3 values (`open_fire`, `return_fire`, `weapon_hold`)
   - `ship` → `AI.Option.Naval.id.ROE`, 3 values (same as ground)
3. Validates the value against the allowed set; logs + `false` on mismatch.
4. Translates the lowercase string to the matching numeric `AI.Option.*.val.ROE.*` constant and dispatches `setOption(id, num_value)`.

The `_sms_roe` flag and validation table live entirely in `options.lua`. `group.lua` only sees the existing apply helper, generalized.

## Extending `_validate_apply` in `group.lua`

`group.lua` currently has a private helper `_validate_apply(verb, g, task)` used by `set_task` and `push_task`. The check covers handle/alive/table-shape and the air-only flag. We extend it to:

- accept any of `_sms_air_only` / `_sms_ground_only` / `_sms_naval_only`
- delegate ROE-specific validation to a callback the new modules pass in (keeping `group.lua` ignorant of the ROE value tables)

The helper signature changes from `_validate_apply(verb, g, task)` to `_validate_apply(verb, g, payload, opts?)` where `opts.roe_validator(payload, category) -> bool, err_msg?` is called when `payload._sms_roe` is set. Default opts gives the historical behaviour.

This is a small refactor (one helper, two existing callers stay one-line). No public surface changes in `sms.group`.

## Failure model

| Layer | Bad input | Behavior |
|---|---|---|
| Builders | Wrong arg type, nil required arg, unknown enum string, malformed opts | `log.warn` with builder name + reason; return `nil` |
| Apply (`set_command` / `set_option`) | Non-handle, dead group, non-table payload, missing `_sms_verb`, category mismatch, ROE value disallowed for category | `log.warn`; return `false` |
| DCS pcall failure | Controller gone, malformed payload reaches DCS | `log.error`; return `false` |

Invariant: never throws. Builders return `nil` on bad input so the user sees the failure at apply time (`set_*` will reject `nil`).

## Testing

### `framework/test/smoke_commands.sh`

**Synthetic** — for each builder:

- valid args → returns table with expected `_sms_verb`, `id`, `params`, and category flag
- bad args → returns `nil` (per-verb matrix: nil required arg, wrong type)

**Live DCS** (EXIT-trap fixture cleanup):

- ground group: `set_command(switch_waypoint(0, 1))` → `true`
- air F-16: `set_command(set_frequency(251000000, sms.commands.MODULATION.AM))` → `true`
- air F-16: `set_command(activate_beacon({type = ..., system = ..., frequency = ...}))` → `true`
- ground group: `set_command(set_callsign(1))` → `false` + log (air-only)
- bad-arg matrix on apply

### `framework/test/smoke_options.sh`

**Synthetic** — for each builder:

- valid args (constant + raw string) → returns table; ROE returns table with `_sms_roe = true`
- bad args (unknown string, wrong type) → `nil`
- ROE table: every category-disallowed value across air/ground/naval

**Live DCS:**

- air F-16: `set_option(roe(ROE.WEAPON_HOLD))` → `true`
- ground tank: `set_option(roe(ROE.WEAPON_HOLD))` → `true`
- ground tank: `set_option(roe(ROE.WEAPON_FREE))` → `false` + log (value not allowed for ground)
- air F-16: `set_option(rtb_on_bingo(true))` → `true`
- ground tank: `set_option(rtb_on_bingo(true))` → `false` + log (air-only)
- ground tank: `set_option(alarm_state(ALARM_STATE.RED))` → `true`
- air F-16: `set_option(alarm_state(ALARM_STATE.RED))` → `false` + log (ground-only)
- ground tank: `set_option(disperse_on_attack(30))` → `true`
- bad-arg matrix on apply

`SMOKE_FIXTURES` lists every group name created. EXIT trap matches the convention from `smoke_task.sh`.

## Out of scope (v1)

- **`sms.commands.script`** — running raw Lua via `setCommand` is redundant when the user is already writing mission Lua. Skip.
- **Convenience zero-arg ROE wrappers** — MOOSE has `OptionROEWeaponHold()` etc. The enum-plus-builder pattern makes these unnecessary (`sms.options.roe(sms.options.ROE.WEAPON_HOLD)` is barely longer and more uniform).
- **Per-unit option setters** — DCS's `setOption` is on the controller, which is on the group. Some MOOSE wrappers expose unit-level variants by indexing the group's leader; not yet a documented pattern.
- **Delay parameter on every builder** — MOOSE has `Delay` everywhere. We rely on `sms.timer.after` instead — already a first-class framework primitive.
- **Push variants** (`push_command`, `push_option`) — DCS does not stack these.
- **`get_option` / introspection** — DCS does not expose a getter for the current option state. Out of scope.
- **Naval-specific option surface beyond ROE** — the FAQ documents only ROE for ships; MOOSE doesn't expand it. If naval groups gain more option surface in DCS, add in a v1.1.

## Decisions / rationale

1. **Two separate modules, not a single `controller.lua`.** Commands and options are different concepts (one-shot vs persistent), use different DCS APIs (`setCommand` vs `setOption`), and have different namespaces (`sms.commands.*` vs `sms.options.*`). Keeping them in separate files mirrors the user's `sms.commands` / `sms.options` mental model directly.

2. **Enums as uppercase tables alongside lowercase builders.** Discoverable via autocomplete, idiomatic in many languages, and matches the existing `sms.targets.AIR = "Air"` pattern. Both the constant and the raw string work — same forward-compat escape hatch as `sms.targets`.

3. **Drop `sms.commands.script`.** Redundant with mission scripting; including it would only encourage callers to inject Lua via DCS's command stream when they could write it directly. YAGNI.

4. **ROE category dispatch via `_sms_roe` marker.** The only deviation from `sms.task`'s pattern. Necessary because ROE is one user-facing concept that maps to three DCS enums with different value sets. Marker keeps `group.lua` ignorant of the validation tables (they live in `options.lua`).

5. **`_sms_naval_only` extends the existing flag system.** Symmetric with air-only and ground-only. Trivial to add to the apply-time check.

6. **Apply-time category validation, not build-time.** Same rationale as `sms.task` v1: a builder result is a value that may be applied to multiple groups. Failing at apply gives a precise per-group error instead of pre-emptively rejecting valid values.

7. **`waypoint_pass_report` flips the DCS-internal name semantics.** DCS exposes `PROHIBIT_WP_PASS_REPORT` (inverted). User-facing API is the non-inverted shape `waypoint_pass_report(true)` = "do report". Wrapper inverts inside the builder. Matches the framework's "smooth over DCS quirks" philosophy.

8. **`disperse_on_attack` is integer-seconds, not bool.** DCS FAQ wrongly documents this as a bool; MOOSE source confirms it's the integer-seconds shape. Trust source over FAQ.

9. **`set_command` and `set_option` reject manually-built tables without `_sms_verb`.** Rationale: command/option tables don't have the `id`/`params` ubiquity DCS tasks do. Accepting raw tables would defeat the category-gate guarantee. If a user genuinely needs to dispatch an unwrapped table, they can call vanilla `Group:getController():setOption(...)` and flag the gap per AGENTS.md §1.

10. **Spec mandates AGENTS.md and `docs/api/` updates.** Per project rule (CLAUDE.md): every spec adding public surface must explicitly include both updates in scope. New `sms.commands` and `sms.options` sections in AGENTS.md §7 + new `docs/api/commands.md` and `docs/api/options.md` pages land in the same change-set.

## Open questions

None.
