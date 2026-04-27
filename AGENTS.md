# AGENTS.md — dcs-sms framework reference for AI agents

This is the single-source orientation document for AI agents working in this repo. It exists so an agent dropped in cold can write idiomatic dcs-sms code without grepping through every module first.

If you are a human and you want to hand-write framework code, this also works as a dense reference — but read [`MISSION.md`](MISSION.md) first for project rationale and [`docs/superpowers/specs/`](docs/superpowers/specs/) for design rationale per module.

> **Companion documents:**
> - [`MISSION.md`](MISSION.md) — vision and rationale.
> - [`docs/superpowers/specs/`](docs/superpowers/specs/) — per-module design docs (canonical source for "why is it shaped this way").
> - [`docs/superpowers/plans/`](docs/superpowers/plans/) — implementation plans, often with helpful context.
> - This file is a *summary*. When the spec disagrees with this file, the spec wins.

---

## 1. The prime directive

**Always prefer `sms.*` over vanilla DCS API when the framework provides it.**

The framework exists precisely because vanilla DCS scripting is awkward, undocumented, and full of footguns. If a vanilla call would replace a single line of `sms.*` code, use the `sms.*` version every time.

**When the framework does not yet cover what you need:**

1. Use the vanilla DCS API (`Group.getByName`, `coalition.addGroup`, `world.addEventHandler`, `trigger.action.*`, etc.) to get the job done.
2. **Surface this to the user.** Say something like:
   > "I needed to call vanilla DCS `<api>` here because `sms.<module>` doesn't expose this yet. Want me to file a GitHub issue so we can fold this into the framework later?"
3. If the user agrees, invoke the `make-issue` skill (or use `gh issue create`) with a description of the gap, the use case, the vanilla API used, and a sketch of what the `sms.*` shape might look like.

This is non-negotiable. The framework only grows by noticing where it falls short. **If you silently fall back to vanilla without flagging the gap, you have failed the assignment.**

### What counts as "the framework doesn't cover it"

- The function does not exist on any `sms.*` module.
- The function exists but its current contract doesn't expose the data you need (e.g. `sms.unit.get_position` returns vec3 but you need the full Position3 with orientation axes).
- The function exists but a known issue (`docs/superpowers/specs/`, GitHub issues) limits it.

### What does NOT count

- "There's a vanilla one-liner that's slightly shorter." Use `sms.*` anyway — the framework's value is the *consistency* and the failure model, not the syntactic sugar.
- "The framework version returns nil on bad input but I want it to throw." This is the framework's [failure model](#3-failure-model-log--nil-never-throw) by design. Never bypass it.

---

## 2. Repo layout at a glance

```
dcs-sms/
├── framework/              In-DCS Lua framework — runs inside the mission environment.
│   ├── sms.lua             Root namespace + shared metatable factories.
│   ├── log.lua             sms.log — structured logging.
│   ├── utils.lua           sms.utils — small numeric helpers (deg/rad, ft/m, etc.).
│   ├── group.lua           sms.group — group entity wrapper.
│   ├── unit.lua            sms.unit — unit entity wrapper.
│   ├── area.lua            sms.area — zones, drawings, runtime areas.
│   ├── timer.lua           sms.timer — after / every / now.
│   ├── spawn.lua           sms.group.create / .clone — runtime group spawning.
│   ├── static.lua          sms.static — static-object wrapper + create/clone.
│   ├── events.lua          sms.events — DCS world-event bus + entity sugar.
│   └── test/               Bash smoke tests driven by tools/dcs-sms.exe.
│
├── tools/                  Host-side Go tooling (NOT in DCS).
│   ├── cmd/dcs-sms/        CLI: exec / status / tail-log / install-hook.
│   └── lua/                The Scripts/Hooks Lua hook embedded in the binary.
│
├── docs/superpowers/
│   ├── specs/              Design docs (one per sub-project / module).
│   └── plans/              Implementation plans.
│
├── MISSION.md              Project vision and rationale.
├── README.md               Quick start (mostly host-side bridge usage).
└── AGENTS.md               This file.
```

**Two distinct Lua environments:**

- **Mission environment** (`framework/*.lua`): sandboxed by `Scripts/MissionScripting.lua`. `os`, `io`, `lfs` are nilled. Lua 5.1. `print` is silent — use `env.info` / `env.error` (or `sms.log.*`).
- **Hook environment** (`tools/lua/dcs-sms-hook.lua`): NOT sandboxed. Has LuaSocket, `lfs`, full file I/O. Used by the host-side bridge.

The framework runs in the mission environment. The bridge runs in the hook environment. They communicate through the filesystem mailbox the bridge installs.

---

## 3. Failure model: log + nil, never throw

**Every public framework call follows this contract:**

- On bad input or missing entity → log via `sms.log.error` (or the module's tagged logger) and return `nil` or `false`.
- **Never `error()` out of an `sms.*` call.** Throwing aborts the entire mission script — that is the failure mode dcs-sms exists to avoid.
- Methods accept either a handle (`{name=...}` table) or a raw name string interchangeably. They also tolerate garbage (nil, numbers, booleans) — those normalize to "not alive" and produce a logged nil.

```lua
-- All four of these behave the same way: log + return nil if the unit isn't there.
sms.unit("ghost"):get_position()
sms.unit.get_position("ghost")
sms.unit.get_position({name = "ghost"})
sms.unit.get_position(nil)
```

When you write new framework code, mimic this contract. Do not `error()`. Do not `assert()` on user input. Use `pcall` around any vanilla DCS call that could throw.

---

## 4. Conventions and units

| Concept | Convention |
|---|---|
| **Coordinates** | `vec3 = {x = east, y = altitude, z = north}`. DCS-2D uses `{x = east, y = north}` (no altitude). Conversion: 2D `y` ↔ 3D `z`. |
| **Headings** | **Public API: degrees**, 0=north, 90=east, clockwise. Internal: radians (DCS native). Use `sms.utils.deg_to_rad` / `rad_to_deg` to cross the boundary. |
| **Altitudes** | **Public API: meters** (DCS native). Pilot-facing helpers: `sms.utils.feet_to_meters` / `meters_to_feet`. |
| **Coalition strings** | Lowercase: `"red"`, `"blue"`, `"neutral"`. (DCS internally uses `0/1/2` — never expose these.) |
| **Categories** | Lowercase: `"ground"`, `"airplane"`, `"helicopter"`, `"ship"`, `"train"`. |
| **Naming** | snake_case for everything public (`get_position`, `is_alive`, `from_drawing`). Internal helpers: `_leading_underscore`. |
| **Auto-suffix on collision** | Spawning with a name already taken yields `name-1`, `name-2`, ... Always trust the returned handle's `:get_name()` over the input string. |
| **Log tags** | Each module logs as `[sms.<module>]` via `sms.log.module("sms.<module>")`. Top-level untagged calls log as `[sms]`. |

---

## 5. Entity handles — the universal pattern

Every entity wrapper (`sms.group`, `sms.unit`, `sms.static`, `sms.area`) follows the same shape:

```lua
local handle = sms.unit("Bandit-1")    -- callable lookup; returns handle | nil + log

-- Method-style and module-style both work:
handle:get_position()
sms.unit.get_position(handle)
sms.unit.get_position("Bandit-1")      -- bare name string also works
```

A handle is a small `{name = "..."}` table with a metatable whose `__index` points at the module. They are cheap; build and discard them freely. They do not cache — every method call re-resolves through DCS, so handles stay correct after the underlying entity dies.

`sms.area` handles also carry a `kind` field (`"circle"` or `"polygon"`) and an internal `_data` table. `sms.timer` handles and `sms.events` connection handles use a different pattern (private metatables, identity-checked) but expose the same `handle:method()` ergonomics.

---

## 6. Loading order

The bridge currently loads framework files via `net.dostring_in` in this order:

```
sms.lua → log.lua → utils.lua → group.lua → unit.lua → area.lua → timer.lua → spawn.lua → static.lua → events.lua → weapon.lua
```

Each module asserts the dependencies it actually uses. When adding a new module, decide where it slots in based on what it needs and append the assert.

`sms.events` requires `sms.timer` (the `g:connect(DEAD)` deferred check) — adding behavior that uses both is safe.

---

## 7. Module reference

> Notation: `:method` = takes a handle (also accepts a name string); `module.fn` = static module function.
> Every method follows the [failure model](#3-failure-model-log--nil-never-throw) — "returns X" implicitly means "returns X | nil + log on failure" unless the row notes otherwise.

### `sms` (root) — `framework/sms.lua`

The single global namespace. Idempotent on reload.

| Symbol | Purpose |
|---|---|
| `sms.version` | String (`"0.1.0"`). |
| `sms._make_handle(module, name)` | **Internal.** Build a `{name=name}` handle without verifying existence. Used by entity sugar that needs to wrap dead units (e.g. event normalization). |
| `sms._make_callable_handle(module, dcs_getter, log)` | **Internal.** Wires `module("name") → handle | nil + log` using `dcs_getter` for existence check. Used by group/unit/static. |
| `sms._is_handle_of(value, module)` | **Internal.** Strict handle-type check. Used in cross-module APIs that must reject raw strings. |

### `sms.log` — `framework/log.lua`

| Symbol | Purpose |
|---|---|
| `sms.log.info(msg)` | Untagged; logs `[sms] msg` via `env.info`. |
| `sms.log.error(msg)` | Untagged; logs `[sms] msg` via `env.error`. |
| `sms.log.module(name?)` | Returns `{tag, info, error}` tagged logger. With `name`, prefixes lines `[name]`. Without, auto-derives from caller's file basename → `sms.<basename>` (only works for `dofile`-loaded modules; bridge-loaded modules must pass an explicit tag). |

### `sms.utils` — `framework/utils.lua`

Cross-cutting helpers shared across the framework. Scope is deliberately narrow — unit conversions, vec3 maths, and validation/lookup helpers that 2+ entity modules already needed. Failure mode: log + return nil (vec3 helpers log a contextual error; lookup helpers return nil silently so callers can wrap their own context).

| Symbol | Purpose |
|---|---|
| `sms.utils.add_numbers(a, b)` | Smoke-test exerciser. Real, but trivial. |
| `sms.utils.deg_to_rad(deg)` | Public-API degrees → DCS-internal radians. |
| `sms.utils.rad_to_deg(rad)` | Inverse. |
| `sms.utils.feet_to_meters(ft)` | Pilot-facing conversion (framework I/O is meters). |
| `sms.utils.meters_to_feet(m)` | Inverse. |
| `sms.utils.is_vec3(v)` | `bool` — structural check: table with numeric `x`, `y`, `z`. Silent (callers craft the contextual error). |
| `sms.utils.vec3_length(v)` | `number` — 3D Euclidean length `sqrt(x² + y² + z²)`. Logs + returns nil on bad input. |
| `sms.utils.vec3_distance(a, b)` | `number` — 3D Euclidean distance between two vec3s. Logs + returns nil on bad input. Pure maths; does not duck-type handles. |
| `sms.utils.normalize_heading(deg)` | `number` — wrap any heading to `[0, 360)`. Handles negatives via Lua's mathematical modulo. Logs + returns nil on bad input. |
| `sms.utils.bearing_to(from, to)` | `number` — compass bearing in **degrees** from one vec3 to another (0=north, 90=east, clockwise). Computed on the horizontal plane (xz); altitude is ignored. Logs + returns nil on bad input. |
| `sms.utils.resolve_country(s)` | `int \| nil` — `country.id` lookup. Case-insensitive; spaces become underscores (`"United Kingdom"` → `country.id.UNITED_KINGDOM`). Silent on unknown / non-string. |
| `sms.utils.coalition_int_to_str(c)` | `"red" \| "blue" \| "neutral" \| nil` — DCS coalition int → lowercase string. Silent on unknown int. |
| `sms.utils.deep_copy(t)` | `t` — recursive copy of plain-table values. Non-tables pass through. Does not preserve metatables; does not handle cycles. |

### `sms.group` — `framework/group.lua` (+ `spawn.lua`, `events.lua`)

Constructor: `sms.group("name") → handle | nil + log`.

| Method | Returns |
|---|---|
| `:is_alive()` | `bool` (silent — false on missing). |
| `:get_name()` | `string` (the name field, no validation). |
| `:get_coalition()` | `"red" \| "blue" \| "neutral"`. |
| `:get_category()` | `"ground" \| "airplane" \| "helicopter" \| "ship" \| "train"`. |
| `:get_position()` | `vec3` (leader unit's position). |
| `:get_units()` | List of `sms.unit` handles. |
| `:destroy()` | `true` on success. |
| `:connect(event_name, fn)` | `Connection` handle. **From `events.lua`.** Filter by `evt.initiator_group_name`. For `sms.events.DEAD` specifically, fires once when last unit dies. |

Static factories (from `spawn.lua`):

| Function | Returns |
|---|---|
| `sms.group.create(cfg)` | New group from config. **See [Spawning groups](#spawning-groups) below.** |
| `sms.group.clone(template_name, overrides)` | Clones an ME-placed group at a new position with a new name. |

### `sms.unit` — `framework/unit.lua` (+ `events.lua`)

Constructor: `sms.unit("name") → handle | nil + log`.

| Method | Returns |
|---|---|
| `:is_alive()` | `bool` (silent). |
| `:get_name()` | `string`. |
| `:get_coalition()` | `"red" \| "blue" \| "neutral"`. |
| `:get_position()` | `vec3`. |
| `:get_type()` | DCS type name string (e.g. `"M-2000C"`, `"T-72B"`). |
| `:get_group()` | `sms.group` handle. |
| `:get_heading()` | Heading in **degrees**, 0–360 (0=north, 90=east). |
| `:get_pitch()` | Pitch in **degrees**, positive = nose up. |
| `:get_altitude(agl?)` | Altitude in **meters**. ASL by default; pass `true` for AGL (subtracts terrain height). |
| `:destroy(opts?)` | `true`. With `{emit_event = true}`, also synthesizes a DEAD event onto `sms.events` so reactive code treats programmatic destroy like a combat death. |
| `:connect(event_name, fn)` | `Connection`. **From `events.lua`.** Filter by `evt.initiator.name == self.name`. |

### `sms.area` — `framework/area.lua`

Unified area abstraction over circles and polygons, sourced from ME zones, ME drawings, or constructed at runtime. **All four sources produce handles with the same method surface.**

Constructors:

| Function | Returns |
|---|---|
| `sms.area("ZoneName")` | ME trigger zone (circle or quad). |
| `sms.area.from_drawing("DrawingName")` | ME freeform polygon drawing. |
| `sms.area.create_circular(center_vec3, radius, name?)` | Runtime circle. |
| `sms.area.create_polygon({vec3, ...}, name?)` | Runtime polygon (≥3 vertices). |

Methods:

| Method | Returns |
|---|---|
| `:get_name()` | `string \| nil` (anonymous areas allowed). |
| `:get_kind()` | `"circle" \| "polygon"`. |
| `:get_position()` | `vec3` — center for circles, centroid for polygons. |
| `:get_radius()` | `number` for circles; nil + log for polygons. |
| `:get_vertices()` | List of `vec3` (deep copy) for polygons; nil + log for circles. |
| `:is_vec3_in(vec3)` | `bool`. |
| `:is_unit_in(sms.unit handle)` | `bool` — strict handle check. |
| `:is_static_in(sms.static handle)` | `bool` — strict handle check. |
| `:is_any_of_group_in(sms.group handle)` | `bool` — at least one unit inside. |
| `:is_all_of_group_in(sms.group handle)` | `bool` — every unit inside. |
| `:get_random_point()` | Uniform-random `vec3` inside. Polygons use rejection sampling. |

### `sms.static` — `framework/static.lua`

Constructor: `sms.static("name") → handle | nil + log`.

**`is_alive` semantics differ from `sms.unit`:** statics spawned with `dead = true` are reachable via `getByName` but `:isExist()` returns false. The framework gates on `getByName` only so dead-spawned wreckage statics remain usable.

Methods:

| Method | Returns |
|---|---|
| `:is_alive()` | `bool` (presence-based, see note above). |
| `:get_name()` | `string`. |
| `:get_coalition()` | `"red" \| "blue" \| "neutral"`. |
| `:get_country()` | Lowercase country name string. |
| `:get_position()` | `vec3`. |
| `:get_type()` | DCS type name. |
| `:destroy()` | `true`. |

Static factories:

| Function | Returns |
|---|---|
| `sms.static.create(cfg)` | New static. **See [Spawning statics](#spawning-statics) below.** |
| `sms.static.clone(template_name, overrides)` | Clone an ME-placed static at a new position. |

### `sms.timer` — `framework/timer.lua`

Sim-time-based scheduling. Pauses with DCS.

| Function | Returns |
|---|---|
| `sms.timer.after(seconds, fn)` | One-shot. Returns timer handle. |
| `sms.timer.every(seconds, fn, max?)` | Repeating. Returns timer handle. `fn` returning `false` self-cancels. `max` caps total iterations. |
| `sms.timer.now()` | Current sim time (seconds since mission start). |

Handle methods:

| Method | Returns |
|---|---|
| `:stop()` | `true` if newly stopped, `false` if already inactive. |
| `:is_active()` | `bool` (silent probe). |
| `:get_remaining()` | Seconds until next fire (or nil + log if inactive). |

User errors in `fn` are caught via `pcall` and logged — they do not break the framework.

### `sms.events` — `framework/events.lua`

Pub/sub bus over DCS world events plus user-emittable signals. Wraps DCS's single-handler `world.addEventHandler` so multiple subscribers can listen to specific event types.

**Event constants:** every `world.event.S_EVENT_FOO` is mirrored as `sms.events.FOO = "foo"`. Examples: `sms.events.SHOT`, `sms.events.HIT`, `sms.events.KILL`, `sms.events.DEAD`, `sms.events.BIRTH`, `sms.events.TAKEOFF`, `sms.events.LAND`, `sms.events.CRASH`, `sms.events.EJECTION`, `sms.events.PILOT_DEAD`, `sms.events.ENGINE_STARTUP`, `sms.events.ENGINE_SHUTDOWN`. The full list comes from DCS — iterate `world.event` if you need to confirm.

One **fabricated** constant added by `sms.weapon`: `sms.events.WEAPON_IMPACT = "weapon_impact"`. Fired by the weapon tracker when a tracked weapon's DCS object stops existing. Payload: `{weapon, impact_position, time}`.

| Function | Returns |
|---|---|
| `sms.events.connect(name, fn)` | `Connection` handle. `fn` receives a normalized event payload (see below). |
| `sms.events.emit(name, ...)` | nil. Args pass verbatim to subscribers — used for custom user signals. |
| `sms.events.disconnect(conn)` | `bool`. Idempotent. |
| `sms.events.is_active(conn)` | `bool` (silent probe). |

**Normalized event payload:**

```lua
{
  id = <int>,                       -- DCS S_EVENT id
  name = "<lowercase>",             -- "shot", "hit", "dead", ...
  time = <sim seconds>,
  initiator = <sms.unit handle | nil>,        -- always a wrapped handle, even if dead
  initiator_group_name = <string | nil>,      -- captured live for dead-init events
  target = <sms.unit handle | nil>,
  weapon_type = <string | nil>,               -- DCS type name (back-compat string)
  weapon = <sms.weapon handle | nil>,         -- present on SHOT/HIT when sms.weapon is loaded
  place_name = <string | nil>,                -- airbase name for takeoff/land
}
```

`initiator` and `target` are always `sms.unit` handles when present, even when the unit is already dead. `:is_alive()` returns false on those, but `:get_name()` etc. work.

**Snapshot semantics:** when an event fires, the subscriber list is snapshotted before dispatch. Disconnecting during dispatch does not skip already-pending fires; subscribing during dispatch takes effect on the next emit.

**Entity sugar** (auto-attached to existing modules):

```lua
unit_handle:connect(sms.events.HIT, fn)        -- fires only when evt.initiator is this unit
group_handle:connect(sms.events.DEAD, fn)      -- fires once when group fully dies (last-unit latch)
group_handle:connect(sms.events.HIT, fn)       -- fires per-unit-hit for any unit in this group
```

Entity sugar only accepts events with a meaningful `initiator` field (BIRTH, DEAD, HIT, KILL, TAKEOFF, LAND, CRASH, EJECTION, PILOT_DEAD, SHOT, ENGINE_STARTUP, ENGINE_SHUTDOWN, REFUELING, REFUELING_STOP, PLAYER_ENTER_UNIT, PLAYER_LEAVE_UNIT, HUMAN_FAILURE, UNIT_LOST, SHOOTING_START, SHOOTING_END, LANDING_QUALITY_MARK, LANDING_AFTER_EJECTION, EMERGENCY_LANDING). Other events return nil + log if you try entity-scoping them.

### `sms.weapon` — `framework/weapon.lua`

Wraps DCS weapon objects from SHOT/HIT events. **Not name-addressable** — `Weapon.getByName` does not exist in DCS. The only constructor is `sms.weapon.wrap(raw)`, called automatically by `sms.events` to populate `evt.weapon`.

State machine (forward-only): `created → tracking → impacted` (or `created/tracking → destroyed`).

**Constructor:**

| Function | Returns |
|---|---|
| `sms.weapon.wrap(raw_dcs_weapon)` | Handle. Snapshots release-time state; usable after the DCS object is gone. |

**Always-available getters** (snapshotted at wrap; valid in any state):

| Method | Returns |
|---|---|
| `:get_name()` | DCS-assigned name (usually numeric string). |
| `:get_type()` | DCS type name. |
| `:get_category()` | `"bomb" \| "missile" \| "rocket" \| "shell" \| "torpedo"`. |
| `:get_coalition()` | `"red" \| "blue" \| "neutral"`. |
| `:get_country()` | Lowercase country name. |
| `:get_launcher()` | `sms.unit` handle, or nil if launcher absent. |
| `:get_state()` | `"created" \| "tracking" \| "impacted" \| "destroyed"`. |
| `:get_release_position()` | `vec3` at launcher's release time (nil if no launcher). |
| `:get_release_heading()` | Heading in **degrees** at release. |
| `:get_release_pitch()` | Pitch in **degrees** at release. |
| `:get_release_altitude_asl()` | Meters ASL at release. |
| `:get_release_altitude_agl()` | Meters AGL at release. |
| `:is_bomb()` / `:is_missile()` / `:is_rocket()` / `:is_shell()` / `:is_torpedo()` | `bool` (silent — false on bad input). |

**Tracking lifecycle:**

| Method | Returns |
|---|---|
| `:start_tracking(opts?)` | `bool`. `opts = {rate = 60, ip_distance = 50}`. Idempotent (false on second call). |
| `:stop_tracking()` | `bool`. Returns to `"created"`. Does NOT fire `on_impact` — explicit abort. |
| `:is_tracking()` | `bool` (silent). |
| `:on_tick(fn)` | Sets per-tick callback. Single-slot, last-write-wins. `fn(weapon)`. |
| `:on_impact(fn)` | Sets impact callback. Single-slot. Fires once on natural impact (not on `stop_tracking()` or `destroy()`). `fn(weapon)`. |

**Live getters** (state must be `"tracking"`; otherwise log + nil — except `:get_target()`, which is silent-nil):

| Method | Returns |
|---|---|
| `:is_alive()` | `bool` (silent). |
| `:get_position()` | `vec3` from last poll (up to `1/rate` seconds stale). |
| `:get_velocity()` | `vec3`. |
| `:get_speed()` | `number`. |
| `:get_target()` | `sms.unit` or `sms.static` handle, re-resolved each call. **Silent-nil** when no target / target disappeared / wrong state — these are normal mid-flight outcomes, not API misuse. |

**Impact getters** (state must be `"impacted"`; otherwise log + nil):

| Method | Returns |
|---|---|
| `:get_impact_position()` | `vec3` — extrapolated via `land.getIP` along last-known forward axis, falls back to last-known `pos.p`. |
| `:get_last_known_position()` | `vec3` — raw last-polled position (unmassaged). |
| `:get_impact_distance_from(target)` | `number` — Euclidean distance to a vec3 OR to any handle exposing `:get_position()` (duck-typed; works for `sms.unit`, `sms.static`, `sms.weapon`). |

**Destroy:**

| Method | Returns |
|---|---|
| `:destroy()` | `bool`. Stops tracking silently (no impact event), removes weapon from world. Only valid from `"created"`/`"tracking"`; returns `false` from `"impacted"` or `"destroyed"`. |

**Bus integration:** `sms.events.WEAPON_IMPACT = "weapon_impact"` is fired when a tracked weapon impacts. Payload: `{weapon = handle, impact_position = vec3, time = sim_seconds}`.

**Typical use:**

```lua
sms.events.connect(sms.events.SHOT, function(evt)
  local w = evt.weapon
  if not w or not w:is_bomb() then return end
  if not range:is_vec3_in(w:get_release_position()) then return end
  w:on_impact(function(weapon)
    sms.log.info("impact " .. weapon:get_impact_distance_from(target_pos) .. "m from target")
  end)
  w:start_tracking()
end)
```

### `sms.task` — `framework/task.lua`

Ergonomic builders for DCS task tables, plus runtime apply methods (`group:set_task`, `group:push_task`) installed on `sms.group`'s metatable. The split between *build* and *apply* keeps tasks as first-class values: a task can be stored, passed around, composed via `combo`, or built once and applied to multiple groups.

Each builder returns a plain DCS task table with two private fields:

- `_sms_verb` — string, used in apply-layer log messages
- `_sms_air_only` — `true` for verbs DCS only honors on air groups; consumed by the apply-layer category check

The fields are otherwise transparent to DCS. Manually-built task tables (no `_sms_*` tags) skip the air-only check at apply time — user's responsibility.

**Builders:**

| Function | Targets | DCS task | Categories |
|---|---|---|---|
| `sms.task.move_to(target)` | vec3 / sms.unit / sms.group / sms.static / sms.area | `Mission` (single waypoint at snapshot pos) | all |
| `sms.task.hold()` | — | `Nothing` (DCS interprets per category: air loiters; ground stops) | all |
| `sms.task.follow(target, opts?)` | sms.unit / sms.group; opts: `{offset = {x,y,z}}` | `Follow` | air (v1) |
| `sms.task.orbit(pos, opts?)` | vec3; opts: `{altitude=5000, speed=200, pattern="Circle"\|"RaceTrack"}` | `Orbit` | air |
| `sms.task.attack(target, opts?)` | sms.group / sms.unit; opts: `{weapon_type="Auto", expend="Auto", attack_qty}` | `AttackGroup` (group) / `AttackUnit` (unit) | air (v1) |
| `sms.task.attack_in_area(area, opts?)` | circular sms.area; opts: `{altitude_min, altitude_max, weapon_type}` | `EngageTargetsInZone` | air (v1) |
| `sms.task.bomb(target, opts?)` | vec3 / sms.area / sms.unit / sms.static; opts: `{altitude, weapon_type, expend, group_attack, direction}` | `Bombing` | air |
| `sms.task.land(target, opts?)` | vec3 / sms.static / sms.unit / DCS Airbase; opts: `{duration=300}` | `Land` | air (incl. helo) |
| `sms.task.combo({t1, t2, ...})` | array of task tables | `ComboTask` (parallel; propagates `_sms_air_only` if any constituent has it) | inherits |

**Snapshot vs follow.** `move_to(unit)` reads `unit:get_position()` once at build time; if the unit moves before the task ends, the task still drives to the original location. For continuous tracking, use `follow(unit)`.

**Air-only enforcement.** Six builders set `_sms_air_only = true`: `follow`, `orbit`, `attack`, `attack_in_area`, `bomb`, `land`. At apply time, `set_task`/`push_task` reads the flag and rejects-with-log if the group's category is not `airplane` or `helicopter`:

```
[sms.task] set_task: 'orbit' is air-only; group 'tank-1' is ground — not applied
```

**Weapon type strings** (accepted by builders that take `opts.weapon_type`): `"Auto"` (default), `"Guns"`, `"Rockets"`, `"Missiles"`, `"Bombs"`. Numeric DCS bitmasks are also accepted.

**Apply API (on `sms.group`):**

| Method | Returns |
|---|---|
| `:set_task(task)` | `true` on dispatch; `false` + log on bad input or air-only mismatch. Wraps `Group:getController():setTask`. |
| `:push_task(task)` | `true` on dispatch; same failure modes. Wraps `Group:getController():pushTask`. LIFO — new task interrupts current; current resumes when new task ends. |

**Out of v1:** `sequence` verb (use `push_task` LIFO ordering or event-driven retasking), ground-specific engage verbs (DCS ground engagement is ROE-driven, separate design problem), polygon-area `attack_in_area`, `pop_task`, current-task introspection (DCS doesn't expose it cleanly), per-waypoint task mutation.

---

## 8. Spawning groups

`sms.group.create(cfg)` builds and adds a group at runtime. Returns an `sms.group` handle (with auto-suffixed name on collision) or nil + log.

```lua
-- Minimal ground spawn
local g = sms.group.create({
  name = "tank-section",
  position = {x = 0, y = 0, z = 0},
  country = "USA",
  units = {
    {type = "M-1 Abrams"},
    {type = "M-1 Abrams", offset = {x = 20, y = 0, z = 0}},
  },
})

-- Aircraft (alt is required per unit)
sms.group.create({
  name = "f18-cap",
  position = airfield_pos,
  country = "USA",
  category = "airplane",
  units = {
    {type = "FA-18C_hornet", alt = 6000, heading = 90},
  },
  -- route omitted → default 50km north waypoint at first unit's alt
})

-- Clone an ME-placed template at a new position
sms.group.clone("MY_TEMPLATE_GROUP", {
  name = "spawned-instance",
  position = some_vec3,
})
```

Public field names (the framework normalizes these to DCS's quirky underlying keys):

- `position` (group anchor, vec3) — replaces DCS-2D `x`/`y`.
- `offset` (per-unit relative, vec3) — applied to anchor.
- `heading` is **degrees**.
- `alt` is **meters**.
- `category`: `"ground" | "airplane" | "helicopter" | "ship" | "train"` (default `"ground"`).
- `country`: any value from `country.id` as a string (case-insensitive, spaces → underscores).

**Aircraft cap.** DCS silently truncates `airplane` and `helicopter` groups above 4 units (units 5+ vanish without any error from `coalition.addGroup`). `sms.group.create` rejects such configs up-front with `log.error + return nil` rather than auto-truncating — fix the config (split into multiple groups). The cap does **not** apply to `ground` / `ship` / `train`.

Always trust the returned handle's `:get_name()` for follow-up operations — auto-suffix can change it.

---

## 9. Spawning statics

`sms.static.create(cfg)` and `sms.static.clone(template_name, overrides)` mirror the group flow but for single-object statics.

```lua
sms.static.create({
  name = "fuel-tank",
  type = "FARP Fuel Depot",
  position = {x = 0, y = 0, z = 0},
  country = "USA",
  heading = 45,                  -- degrees
  -- dead = true,                -- spawns as wreckage
  -- canCargo = true, mass = 500
})
```

Required fields: `name` (non-empty string), `type` (non-empty string), `position` (vec3), `country` (string).

Optional fields and their expected types — bad types are rejected at the framework boundary (`log.error` + `nil`, no DCS call):

| Field | Type | Notes |
|---|---|---|
| `heading` | number | degrees |
| `category` | string | e.g. `"Cargos"` |
| `dead` | boolean | spawn as wreckage |
| `mass` | number | kg, only meaningful with `canCargo = true` |
| `canCargo` | boolean | makes the static slingable |
| `shape_name` | string | DCS shape override |
| `livery_id` | string | DCS livery override |

DCS silently ignores `pitch` and `bank` on `coalition.addStaticObject`. The framework warns and drops them. Only `heading` is applied.

---

## 10. Common patterns (cookbook)

### Polling something every second, capping at 10 iterations

```lua
sms.timer.every(1.0, function()
  local g = sms.group("convoy-1")
  if not g:is_alive() then return false end       -- self-cancel when group dies
  sms.log.info("convoy at " .. g:get_position().x)
end, 10)
```

### Fire once when a group is fully dead

```lua
local g = sms.group("red-armor")
g:connect(sms.events.DEAD, function(evt)
  sms.log.info("red armor wiped at " .. evt.time)
end)
```

### Filter SHOT events to a specific area

```lua
local range = sms.area("RangeBox")
sms.events.connect(sms.events.SHOT, function(evt)
  if not evt.initiator then return end
  if not range:is_unit_in(evt.initiator) then return end
  sms.log.info(evt.initiator:get_name() .. " fired " .. (evt.weapon_type or "?"))
end)
```

### Random respawn within an ME zone

```lua
local box = sms.area("SpawnBox")
sms.timer.every(60, function()
  if sms.group("patrol-1"):is_alive() then return end   -- skip if alive
  sms.group.clone("PATROL_TEMPLATE", {
    name = "patrol-1",
    position = box:get_random_point(),
  })
end)
```

### Custom signal between mission scripts

```lua
-- Module A
sms.events.emit("phase_two_start", {time = sms.timer.now(), reason = "trigger"})

-- Module B
sms.events.connect("phase_two_start", function(payload)
  -- payload is whatever Module A passed; verbatim semantics
end)
```

---

## 11. Flagging gaps in the framework

When you need behavior the framework doesn't cover, this is the workflow:

1. **Get the user's task done first.** Use vanilla DCS API. The user wants their feature; they don't want to wait for framework work.

2. **In your reply, name the gap explicitly.** Use this phrasing pattern:

   > "I used vanilla DCS `<api>` for `<purpose>` because `sms.<module>` doesn't currently expose this. The shape it would need is something like `sms.<module>.<proposed_name>(<args>) → <return>`. Want me to file a GitHub issue so we can fold this into the framework?"

3. **If the user agrees, file the issue.** Prefer the `make-issue` skill — it'll rewrite the description for clarity and link to the relevant code. If unavailable, use `gh issue create` directly.

   The issue should include:
   - **Use case:** what the user was trying to do (one or two sentences).
   - **Vanilla API used:** the actual DCS calls you fell back to.
   - **Proposed `sms.*` shape:** function signature, return value, failure mode.
   - **Notes:** anything tricky about the underlying DCS behavior (silent drops, namespace quirks, mid-frame deconstruction risk, etc.).

4. **Do not silently work around the framework.** A vanilla call without a flagged gap is a bug-shaped omission — it deprives the project of the signal that the framework is missing something.

### What does NOT need a gap-flag

- Reading `env.mission.*` for one-off mission-descriptor introspection (used in spawn.clone / static.clone). The mission descriptor is read-only metadata; wrapping it module-by-module would balloon scope.
- Calling `world.event.S_EVENT_*` numeric constants directly. The framework already mirrors them as `sms.events.*` — use the mirrored form, but the underlying `world.event` table is fine to inspect for completeness.
- Using `pcall` defensively around any vanilla call inside framework code itself. That is the framework code; it's expected to touch vanilla.

---

## 12. When you write new framework code

- Read the relevant spec in [`docs/superpowers/specs/`](docs/superpowers/specs/) before changing a module. That document explains *why* the shape is what it is.
- Mirror the existing patterns: callable handles, `_name_of` normalization, `is_alive` gates on every method that touches DCS state, log + nil + never throw.
- Add a tagged logger at the top of the file: `local log = sms.log.module("sms.<name>")`.
- If you depend on another `sms.*` module, `assert(type(sms.<dep>) == "table", ...)` at the top of the file. State the load order in the file's top comment.
- Update [`AGENTS.md`](AGENTS.md) (this file) as part of the same PR. Adding a method without updating this doc is a regression — agents and humans both lose visibility.
- Add or extend a smoke test under `framework/test/` (`smoke_<module>.sh` driven by `tools/dcs-sms.exe`).

---

## 13. Out-of-DCS tooling (`tools/`)

The `tools/` directory is host-side Go. It produces `dcs-sms` / `dcs-sms.exe`, a CLI that:

- `install-hook` — drops `dcs-sms-hook.lua` into `<Saved Games>/DCS*/Scripts/Hooks/`.
- `status` — confirms the hook is alive and reports current mission name.
- `exec --code "<lua>"` — runs Lua in the running mission and returns structured JSON `{ok, return_value, output, error}`.
- `tail-log -n <N>` — last N lines of `dcs.log`.

Agents writing or testing framework code typically use `dcs-sms exec` to run snippets against a running mission. See [`tools/lua/README.md`](tools/lua/README.md) for the full smoke checklist and the one required edit to `Scripts/MissionScripting.lua`.

This is separate from in-DCS framework work. Don't conflate the two environments.
