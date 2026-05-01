# dcs-sms API reference

Per-module reference with worked code examples. Inspired by Autodesk Maya's MEL / Python command docs: every public function gets a signature, a description, an arguments table, a return value, and at least one runnable example.

For the framework's cross-cutting rules (failure model, conventions, handle pattern, loading order), see [`AGENTS.md`](../../AGENTS.md). For copy-and-paste recipes that combine multiple modules, see [`examples.md`](examples.md).

## Loading the framework

Every snippet in this directory assumes `sms` is loaded as a global. Load it once per mission:

```lua
dofile("D:/git/dcs-sms/framework/load_all.lua")
```

(Or via the bridge: `./dcs-sms exec --file framework/load_all.lua`. See the top-level [`README.md`](../../README.md) for bridge setup.)

After this, every `sms.*` symbol below is available.

## Module index

| Page | Module(s) | Summary |
|---|---|---|
| [`task.md`](task.md) | `sms.task` | Task-table builders (move, attack, bomb, orbit, FAC, escort, …) and the apply API on `sms.group`. |
| [`commands.md`](commands.md) | `sms.commands` | One-shot controller commands (frequency, beacons, callsign, waypoint switch, etc.) and `group:set_command`. |
| [`options.md`](options.md) | `sms.options` | Persistent controller options (ROE, alarm state, RTB on bingo, formation, …) and `group:set_option`. ROE dispatched per category. |
| [`group.md`](group.md) | `sms.group` | Group entity wrapper, spawn factories (`create` / `clone`), event sugar, `set_task` / `push_task`. |
| [`unit.md`](unit.md) | `sms.unit` | Unit entity wrapper. Position, heading, altitude, group lookup, event sugar, programmatic destroy. |
| [`static.md`](static.md) | `sms.static` | Static-object wrapper plus `create` / `clone` factories. |
| [`countries.md`](countries.md) | `sms.countries` | Hand-maintained enum of DCS `country.id` keys; provides autocomplete on `country = sms.countries.<KEY>` spawn configs. |
| [`area.md`](area.md) | `sms.area` | Unified zone / drawing / runtime-circle / runtime-polygon abstraction with containment tests. |
| [`weapon.md`](weapon.md) | `sms.weapon` | Weapon-from-event wrapper with tracking lifecycle and impact extrapolation. |
| [`events.md`](events.md) | `sms.events` | DCS world-event bus, normalized payloads, entity-scoped `:connect`. |
| [`timer.md`](timer.md) | `sms.timer` | `after` / `every` / `now`, with handle methods for stop / inspect. |
| [`rule.md`](rule.md) | `sms.rule` | Declarative trigger rules: once / continuous / toggle with cooldown + sustain knobs and a dev_condition escape hatch. |
| [`utils.md`](utils.md) | `sms.utils` | Numeric helpers (deg/rad, ft/m), vec3 maths, country / coalition lookup. |
| [`log.md`](log.md) | `sms.log` | Structured logging with four levels and per-module tagged loggers. |
| [`constants.md`](constants.md) | `sms`, `sms.targets`, `sms.designations`, `load_all` | Root namespace, target-attribute constants, FAC designation constants, framework loader. |
| [`examples.md`](examples.md) | (all) | Copy-and-paste recipes that combine multiple modules. |

## Page template

Every module page is structured the same way. Authors must follow this template — drift makes the docs hard to scan and harder to keep correct.

```markdown
# `sms.<module>` — short tagline

One- or two-paragraph overview: what the module is for, the model behind it,
the most important conventions or gotchas a reader needs to know up front.
Cross-link to the relevant AGENTS.md section.

## Loading

Note any load-order dependencies (e.g. "requires sms.events"). Most modules
just need `load_all.lua`; mention only what's non-obvious.

## `sms.<module>(<args>)` — constructor (if any)

(For modules with a callable constructor: `sms.unit("Bandit-1")`, etc.)

## Functions

### `sms.<module>.<fn>(<args>) → <return>`

**Synopsis** — one sentence on what it does.

**Arguments**

| Name | Type | Description |
|---|---|---|
| `<arg>` | `<type>` | Detail. Mark optional args with `(optional)` and state the default. |

For builders that take an `opts` table, document the **full** options table:

| Key | Type | Default | Description |
|---|---|---|---|
| `speed` | `number` (m/s) | DCS cruise | Locks group speed. |
| ... | ... | ... | ... |

**Returns** — `<return type>`, plus `nil` + log on failure (per the
[framework failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw)).
Mention silent-nil paths explicitly when they exist.

**Example**

\`\`\`lua
-- Realistic, runnable snippet. Multi-line is fine — for sms.task in
-- particular, prefer larger examples that show the call in context.
local group = sms.group("red-cas-1")
sms.task.bomb(group, {x = 1234, y = 0, z = 5678}, {
  altitude    = 4000,
  weapon_type = "Bombs",
  expend      = "All",
  direction   = 270,            -- degrees, framework convention
})
\`\`\`

**Notes** — optional. Use only for non-obvious behavior: hidden constraints,
DCS quirks the framework doesn't smooth over, version history that affects
callers (e.g. "DCS renamed RaceTrack → Anchored").

**See also** — `sms.task.attack_map_object`, `sms.task.bomb_runway`.
```

## Style conventions for authors

These rules apply to everyone (humans and agents) writing or updating these pages.

1. **Examples must be correct.** Every snippet must reference only symbols that actually exist in the module's source file. Do not invent options-table keys. If the source is ambiguous, write a TODO note in the page rather than guessing.
2. **Examples assume `sms` is loaded** — never include the `dofile(...)` line in per-function snippets. The top of this README handles that once.
3. **Prefer realistic call sites.** A snippet for `sms.task.bomb` should show the full builder + a `set_task` call on a real-looking group, not `sms.task.bomb(...)` in isolation.
4. **Larger is fine for `sms.task`.** Task builders accept rich `opts` tables; show the full table with sensible defaults, then add a second snippet that shows the task being applied.
5. **Document the full options table.** Every `opts` key the module reads must be listed with type, default, and meaning. If a key is "passthrough to DCS" (the framework doesn't introspect it), say so.
6. **Units are framework-public.** Degrees for headings, meters for altitudes, m/s for speeds, lowercase strings for coalitions / categories. Match what `AGENTS.md` §4 promises.
7. **Failure model is implicit.** Don't restate "returns nil + log on bad input" for every function — link once to [§3](../../AGENTS.md#3-failure-model-log--nil-never-throw) at the top of the page. Do call out silent-nil paths (e.g. `sms.weapon:get_target()`).
8. **Cross-link with relative paths.** `[sms.group](group.md)`, `[failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw)`. Don't hardcode absolute paths or GitHub URLs.
9. **Keep it correct over keeping it short.** Longer pages with right examples beat tight pages with wrong ones.

## Examples page

[`examples.md`](examples.md) is the cross-module cookbook — recipes like *"spawn red and blue aircraft, set ROE to green, flip blue's ROE to red within 20 miles of red"*. It's curated by hand, not auto-generated; new recipes are welcome but every snippet is held to the same correctness bar as the per-module pages.
