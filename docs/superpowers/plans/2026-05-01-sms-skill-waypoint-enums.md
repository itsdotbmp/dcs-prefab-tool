# `sms.skill`, `sms.alt_type`, `sms.waypoint` enums implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three enum modules — `sms.skill` (flat, 7 entries), `sms.alt_type` (flat, 2), `sms.waypoint.TYPE` + `sms.waypoint.ACTION` (nested, 7 + 11) — covering the unit-skill, altitude-reference, and waypoint magic strings users hit when writing spawn configs and routes.

**Architecture:** Three hand-maintained files (`framework/skill.lua`, `framework/alt_type.lua`, `framework/waypoint.lua`) following the established `sms.targets` / `sms.designations` / `sms.countries` shape: `---@class` field block + `---@alias` literal-union + idempotent `or {}` init + explicit assignments. No drift check (no DCS-global to introspect).

**Tech Stack:** Lua 5.1 (DCS mission environment), `sms.log` (tagged logger). Smoke-tested via bash + `tools/dcs-sms.exe exec` against a live DCS mission.

**Spec:** `docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md`

---

## Conventions used in this plan

- **Working directory:** `D:/git/dcs-sms/.worktrees/sms-skill-waypoint/`. All shell commands run from there unless otherwise noted.
- **Lua syntax check:** the framework has no LSP / linter wired in; trust the smoke test as the contract. Some agents have `luac` available on Windows — try `luac -p <file>` after each new file as a sanity check.
- **Commit style:** conventional commits, scopes follow the repo (`feat(framework)`, `docs(framework)`, etc.). One commit per task.
- **Smoke tests need DCS:** any new check added to `framework/test/smoke.sh` requires DCS running with a mission loaded. CI does NOT run it. The plan still requires the smoke check be written and committed; the user runs it as part of `/bring-it-home`.
- **Tasks 2–6 are independent** of Task 1 only; they can run in parallel after Task 1 lands.

---

## File structure

| File | Status | Purpose |
|---|---|---|
| `framework/skill.lua` | Create | The new `sms.skill` enum module: 7 entries, `---@class` field block, `---@alias sms.Skill` literal-union, explicit assignments. |
| `framework/alt_type.lua` | Create | The new `sms.alt_type` enum module: 2 entries, same shape. |
| `framework/waypoint.lua` | Create | The new `sms.waypoint` module: declares `sms.waypoint`, `sms.waypoint.TYPE` (7 entries), `sms.waypoint.ACTION` (11 entries), with `---@alias sms.WaypointType` and `---@alias sms.WaypointAction`. |
| `framework/load_all.lua` | Modify | Insert `"skill.lua"`, `"alt_type.lua"`, `"waypoint.lua"` after `"countries.lua"` in the `modules` array. |
| `framework/group_spawn.lua` | Modify | Update LuaCATS `---@field skill?` and `---@field alt_type?` annotations on `sms.group.unit_spec` to reference `sms.Skill|string` and `sms.AltType|string`. |
| `framework/test/smoke.sh` | Modify | Add a small block of identity checks for the new enums after the existing `sms.countries` block. |
| `docs/api/skill.md` | Create | Per-symbol API reference page for `sms.skill`. |
| `docs/api/alt_type.md` | Create | Per-symbol API reference page for `sms.alt_type`. |
| `docs/api/waypoint.md` | Create | Per-symbol API reference page for `sms.waypoint.TYPE` / `sms.waypoint.ACTION`. |
| `docs/api/README.md` | Modify | Add three rows to the module-index table immediately after the `countries.md` row. |
| `AGENTS.md` | Modify | Add three rows to §7 module-index table after the `sms.countries` row. |
| `README.md` | Modify | Add `sms.skill`, `sms.alt_type`, `sms.waypoint` to the framework module list under "Repo layout". |

---

## Task 1: Create the three enum modules and wire `load_all.lua`

**Files:**
- Create: `framework/skill.lua`
- Create: `framework/alt_type.lua`
- Create: `framework/waypoint.lua`
- Modify: `framework/load_all.lua` — insert three new entries after `"countries.lua"`.

**Background for the implementer:**

- The framework loads modules in dependency order via `framework/load_all.lua`. The new modules only depend on `sms` (the namespace) and `sms.log` (for the tagged logger constant — even though no log lines are emitted, every existing enum file declares `local log = sms.log.module(...)` for parity).
- Each module follows the `framework/countries.lua` shape exactly: header comment, `assert(...)` prerequisites, `local log = sms.log.module(...)`, `---@class` field block listing every key with its DCS string value, `---@alias` literal-union listing every DCS string, idempotent `sms.<x> = sms.<x> or {}` init, then explicit assignments. **No runtime drift check** (Decision D9 — there's no DCS-global to introspect).
- The `sms.waypoint` module is slightly more complex because it has TWO enum sub-tables (`TYPE` and `ACTION`) under one parent. Each gets its own `---@class` field block + `---@alias`, but both live in the same file.

- [ ] **Step 1.1: Create `framework/skill.lua`**

Write this file verbatim:

```lua
-- dcs-sms framework: skill module (sms.skill).
--
-- Hand-maintained enum of DCS unit-skill strings. Mission code uses
-- sms.skill.<KEY> instead of magic strings:
--
--     sms.group.create({
--       units = { {type = sms.units.planes.F_16C_50, skill = sms.skill.AVERAGE} },
--       ...
--     })
--
-- Values are the verbatim DCS strings ("Average", "Good", "High",
-- "Excellent", "Random"). PLAYER and CLIENT are special placeholder
-- skills DCS recognizes for unit slots that mark a unit as
-- human-controllable (player aircraft / multiplayer clients).
--
-- The sms.Skill alias enables LuaCATS autocomplete on raw-string
-- usage (skill = "Average"). The skill field on sms.group.unit_spec
-- is annotated sms.Skill|string so both forms are typo-checkable.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> countries.lua ->
-- skill.lua. No runtime drift check (no DCS-global to introspect).
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

local log = sms.log.module("sms.skill")

---@class sms.skill
---@field AVERAGE   "Average"
---@field GOOD      "Good"
---@field HIGH      "High"
---@field EXCELLENT "Excellent"
---@field RANDOM    "Random"
---@field PLAYER    "Player"
---@field CLIENT    "Client"
sms.skill = sms.skill or {}

---@alias sms.Skill
---| "Average"
---| "Good"
---| "High"
---| "Excellent"
---| "Random"
---| "Player"
---| "Client"

sms.skill.AVERAGE   = "Average"
sms.skill.GOOD      = "Good"
sms.skill.HIGH      = "High"
sms.skill.EXCELLENT = "Excellent"
sms.skill.RANDOM    = "Random"
sms.skill.PLAYER    = "Player"
sms.skill.CLIENT    = "Client"
```

- [ ] **Step 1.2: Create `framework/alt_type.lua`**

Write this file verbatim:

```lua
-- dcs-sms framework: alt_type module (sms.alt_type).
--
-- Hand-maintained enum of DCS waypoint altitude-reference strings.
-- Mission code uses sms.alt_type.BARO / sms.alt_type.RADIO instead of
-- magic strings:
--
--     local wp = {x=1234, y=0, z=5678, alt=4500, alt_type=sms.alt_type.BARO, ...}
--
-- BARO is altitude above mean sea level (the most common altitude
-- reference for aircraft). RADIO is altitude above ground level (radar
-- altimeter), used for terrain-following or low-level routing.
--
-- The sms.AltType alias enables LuaCATS autocomplete on raw-string
-- usage (alt_type = "BARO"). The alt_type field on sms.group.unit_spec
-- is annotated sms.AltType|string so both forms are typo-checkable.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> countries.lua ->
-- skill.lua -> alt_type.lua.
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

local log = sms.log.module("sms.alt_type")

---@class sms.alt_type
---@field BARO  "BARO"
---@field RADIO "RADIO"
sms.alt_type = sms.alt_type or {}

---@alias sms.AltType
---| "BARO"
---| "RADIO"

sms.alt_type.BARO  = "BARO"
sms.alt_type.RADIO = "RADIO"
```

- [ ] **Step 1.3: Create `framework/waypoint.lua`**

Write this file verbatim:

```lua
-- dcs-sms framework: waypoint module (sms.waypoint).
--
-- Hand-maintained enums for DCS waypoint type and action strings.
-- Mission code uses sms.waypoint.TYPE.<KEY> and sms.waypoint.ACTION.<KEY>
-- instead of magic strings:
--
--     local wp = {
--       x = 1234, y = 0, z = 5678,
--       type   = sms.waypoint.TYPE.TURNING_POINT,    -- "Turning Point"
--       action = sms.waypoint.ACTION.OFF_ROAD,        -- "Off Road"
--       ...
--     }
--
-- TYPE controls the kind of waypoint (turning point vs takeoff vs land).
-- ACTION controls how the unit traverses or arrives (turning point vs
-- fly-over vs from-parking-area-hot vs landing). Both have a
-- "Turning Point" entry but they live in separate enums because DCS
-- treats them as separate fields on the waypoint table.
--
-- "TakeOff" is a DCS alias for "TakeOffParkingHot"; we expose only the
-- canonical TAKEOFF_PARKING_HOT (Decision D4 in the spec).
--
-- OFF_ROAD and ON_ROAD are included on ACTION because dcs-sms emits
-- "Off Road" for ground/ship/train waypoints in framework/group.lua
-- and framework/task.lua (Decision D6).
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> countries.lua ->
-- skill.lua -> alt_type.lua -> waypoint.lua.
--
-- See docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

local log = sms.log.module("sms.waypoint")

sms.waypoint = sms.waypoint or {}

---@class sms.waypoint.TYPE
---@field TAKEOFF_PARKING      "TakeOffParking"
---@field TAKEOFF_PARKING_HOT  "TakeOffParkingHot"
---@field TAKEOFF_GROUND       "TakeOffGround"
---@field TAKEOFF_GROUND_HOT   "TakeOffGroundHot"
---@field TURNING_POINT        "Turning Point"
---@field LAND                 "Land"
---@field LANDING_REFUEL_REARM "LandingReFuAr"
sms.waypoint.TYPE = sms.waypoint.TYPE or {}

---@alias sms.WaypointType
---| "TakeOffParking"
---| "TakeOffParkingHot"
---| "TakeOffGround"
---| "TakeOffGroundHot"
---| "Turning Point"
---| "Land"
---| "LandingReFuAr"

sms.waypoint.TYPE.TAKEOFF_PARKING      = "TakeOffParking"
sms.waypoint.TYPE.TAKEOFF_PARKING_HOT  = "TakeOffParkingHot"
sms.waypoint.TYPE.TAKEOFF_GROUND       = "TakeOffGround"
sms.waypoint.TYPE.TAKEOFF_GROUND_HOT   = "TakeOffGroundHot"
sms.waypoint.TYPE.TURNING_POINT        = "Turning Point"
sms.waypoint.TYPE.LAND                 = "Land"
sms.waypoint.TYPE.LANDING_REFUEL_REARM = "LandingReFuAr"

---@class sms.waypoint.ACTION
---@field TURNING_POINT         "Turning Point"
---@field FLYOVER_POINT         "Fly Over Point"
---@field FROM_PARKING_AREA     "From Parking Area"
---@field FROM_PARKING_AREA_HOT "From Parking Area Hot"
---@field FROM_GROUND_AREA      "From Ground Area"
---@field FROM_GROUND_AREA_HOT  "From Ground Area Hot"
---@field FROM_RUNWAY           "From Runway"
---@field LANDING               "Landing"
---@field LANDING_REFUEL_REARM  "LandingReFuAr"
---@field OFF_ROAD              "Off Road"
---@field ON_ROAD               "On Road"
sms.waypoint.ACTION = sms.waypoint.ACTION or {}

---@alias sms.WaypointAction
---| "Turning Point"
---| "Fly Over Point"
---| "From Parking Area"
---| "From Parking Area Hot"
---| "From Ground Area"
---| "From Ground Area Hot"
---| "From Runway"
---| "Landing"
---| "LandingReFuAr"
---| "Off Road"
---| "On Road"

sms.waypoint.ACTION.TURNING_POINT         = "Turning Point"
sms.waypoint.ACTION.FLYOVER_POINT         = "Fly Over Point"
sms.waypoint.ACTION.FROM_PARKING_AREA     = "From Parking Area"
sms.waypoint.ACTION.FROM_PARKING_AREA_HOT = "From Parking Area Hot"
sms.waypoint.ACTION.FROM_GROUND_AREA      = "From Ground Area"
sms.waypoint.ACTION.FROM_GROUND_AREA_HOT  = "From Ground Area Hot"
sms.waypoint.ACTION.FROM_RUNWAY           = "From Runway"
sms.waypoint.ACTION.LANDING               = "Landing"
sms.waypoint.ACTION.LANDING_REFUEL_REARM  = "LandingReFuAr"
sms.waypoint.ACTION.OFF_ROAD              = "Off Road"
sms.waypoint.ACTION.ON_ROAD               = "On Road"
```

- [ ] **Step 1.4: Modify `framework/load_all.lua`**

The current `modules` list (around line 30) reads:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "countries.lua",
  "units.lua",
  ...
}
```

Insert `"skill.lua"`, `"alt_type.lua"`, `"waypoint.lua"` immediately after `"countries.lua"`. The post-edit list reads:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "countries.lua",
  "skill.lua",
  "alt_type.lua",
  "waypoint.lua",
  "units.lua",
  "statics.lua",
  "targets.lua",
  "designations.lua",
  "group.lua",
  "unit.lua",
  "area.lua",
  "timer.lua",
  "rule.lua",
  "group_spawn.lua",
  "static.lua",
  "events.lua",
  "weapon.lua",
  "task.lua",
  "commands.lua",
  "options.lua",
}
```

- [ ] **Step 1.5: Sanity-check the three new files compile**

Run:

```bash
luac -p framework/skill.lua framework/alt_type.lua framework/waypoint.lua && echo "OK"
```

Expected: prints `OK`. If `luac` isn't installed (likely on Windows for some agents), skip — the smoke test is the real contract.

- [ ] **Step 1.6: Commit**

```bash
git add framework/skill.lua framework/alt_type.lua framework/waypoint.lua framework/load_all.lua docs/superpowers/specs/2026-05-01-sms-skill-waypoint-enums.md docs/superpowers/plans/2026-05-01-sms-skill-waypoint-enums.md
git commit -m "$(printf 'feat(framework): add sms.skill, sms.alt_type, sms.waypoint enum modules\n\nThree hand-listed enum modules covering AI skill levels (7), waypoint\naltitude type (2), and waypoint type+action strings (7+11). Same shape\nas sms.countries: LuaCATS class+alias double form, idempotent or {}\ninit, no runtime drift check.\n')"
```

---

## Task 2: Annotate `skill?` and `alt_type?` fields in `group_spawn.lua`

**Files:**
- Modify: `framework/group_spawn.lua` — update LuaCATS annotations on the `sms.group.unit_spec` class.

**Background for the implementer:**

- `framework/group_spawn.lua` declares `---@class sms.group.unit_spec` around line 34. The current `---@field skill?` and `---@field alt_type?` annotations type the fields as plain `string` and inline-list the accepted values in the comment.
- After this change, both fields will reference the new aliases (`sms.Skill|string`, `sms.AltType|string`), which gives editors autocomplete on raw-string usage AND on `sms.skill.<KEY>` / `sms.alt_type.<KEY>` enum usage. The `|string` half is required because users may pass case-folded variants — actually, re-check: DCS skill strings are case-sensitive. But the alias enumerates the canonical forms, so `|string` lets a user pass any string the alias doesn't enumerate (forward-compat) without an editor red squiggle.
- The new `sms.Skill` and `sms.AltType` aliases are declared in `framework/skill.lua` and `framework/alt_type.lua` respectively (Task 1). Loaded before `group_spawn.lua` per the loader order.

- [ ] **Step 2.1: Update the `---@field skill?` annotation**

Find the existing line (around line 39) in `framework/group_spawn.lua`:

```lua
---@field skill? string  # "Average" | "Good" | "High" | "Excellent" | "Random" (default "Average")
```

Replace with:

```lua
---@field skill? sms.Skill|string  # AI skill level; pass sms.skill.<KEY> for autocomplete (default "Average")
```

- [ ] **Step 2.2: Update the `---@field alt_type?` annotation**

Find the existing line (around line 43):

```lua
---@field alt_type? string  # "BARO" | "RADIO" (default "BARO" for air)
```

Replace with:

```lua
---@field alt_type? sms.AltType|string  # altitude reference; pass sms.alt_type.<KEY> for autocomplete (default "BARO" for air)
```

- [ ] **Step 2.3: Commit**

```bash
git add framework/group_spawn.lua
git commit -m "$(printf 'feat(framework): annotate skill and alt_type spawn-config fields\n\nLuaCATS hint only; runtime spawn path still accepts any string. Drives\nautocomplete on raw-string usage AND on sms.skill / sms.alt_type enum\nusage.\n')"
```

---

## Task 3: Smoke checks for the new enums

**Files:**
- Modify: `framework/test/smoke.sh` — append a new block immediately after the existing `sms.countries` block.

**Background for the implementer:**

- The existing `sms.countries` smoke block sits around lines 80–107 of `framework/test/smoke.sh`. The new block goes immediately after it, before whatever comes next (likely `coalition_int_to_str` checks).
- The harness loads modules via `${DCSSMS} exec --file <file>` and runs assertions via `${DCSSMS} exec --code <lua>`. Pattern is established earlier in the file.
- Per spec Decision D10, we cover one representative entry per enum (5 assertions total) — not exhaustive. The shape is identical to the `sms.countries.USA == "USA"` checks.

- [ ] **Step 3.1: Locate the insertion point**

Find the end of the existing `sms.countries` block. The last line of that block is the `[ -n "${n}" ] && [ "${n}" -ge 80 ] || { echo "FAIL..."; exit 1; }` size-check guard. The new block goes immediately after.

- [ ] **Step 3.2: Insert the smoke block**

Insert verbatim:

```bash
echo "==> load framework/skill.lua, framework/alt_type.lua, framework/waypoint.lua"
"${DCSSMS}" exec --file skill.lua >/dev/null
"${DCSSMS}" exec --file alt_type.lua >/dev/null
"${DCSSMS}" exec --file waypoint.lua >/dev/null

echo "==> sms.skill.AVERAGE == 'Average'"
result=$("${DCSSMS}" exec --code "return sms.skill.AVERAGE")
echo "${result}" | grep -q '"return_value":"Average"' \
  || { echo "FAIL: expected Average, got: ${result}"; exit 1; }

echo "==> sms.skill.PLAYER == 'Player' (player-slot marker)"
result=$("${DCSSMS}" exec --code "return sms.skill.PLAYER")
echo "${result}" | grep -q '"return_value":"Player"' \
  || { echo "FAIL: expected Player, got: ${result}"; exit 1; }

echo "==> sms.alt_type.BARO == 'BARO'"
result=$("${DCSSMS}" exec --code "return sms.alt_type.BARO")
echo "${result}" | grep -q '"return_value":"BARO"' \
  || { echo "FAIL: expected BARO, got: ${result}"; exit 1; }

echo "==> sms.waypoint.TYPE.TURNING_POINT == 'Turning Point'"
result=$("${DCSSMS}" exec --code "return sms.waypoint.TYPE.TURNING_POINT")
echo "${result}" | grep -q '"return_value":"Turning Point"' \
  || { echo "FAIL: expected 'Turning Point', got: ${result}"; exit 1; }

echo "==> sms.waypoint.ACTION.OFF_ROAD == 'Off Road'"
result=$("${DCSSMS}" exec --code "return sms.waypoint.ACTION.OFF_ROAD")
echo "${result}" | grep -q '"return_value":"Off Road"' \
  || { echo "FAIL: expected 'Off Road', got: ${result}"; exit 1; }
```

- [ ] **Step 3.3: Commit**

```bash
git add framework/test/smoke.sh
git commit -m "$(printf 'test(framework): smoke checks for sms.skill, sms.alt_type, sms.waypoint\n\nFive assertions covering one representative entry per enum (skill,\nalt_type, waypoint.TYPE, waypoint.ACTION) plus the player-slot marker\ncase on sms.skill.PLAYER.\n')"
```

---

## Task 4: API reference page `docs/api/skill.md`

**Files:**
- Create: `docs/api/skill.md`

**Background for the implementer:**

- Follow the same shape as `docs/api/countries.md` (just landed at `b3d7b02`). The page is short — just an enum table — so it deviates slightly from the per-function template.
- Cross-link with relative paths. Failure-model link points to `../../AGENTS.md#3-...`.

- [ ] **Step 4.1: Create `docs/api/skill.md`**

Write verbatim:

```markdown
# `sms.skill` — DCS unit skill levels

Hand-maintained enum of the seven DCS strings accepted on the `skill` field of unit specs:

```lua
sms.group.create({
  name = "blue-cap", country = sms.countries.USA, category = "airplane",
  units = {
    {type = sms.units.planes.F_16C_50, alt = 6000, heading = 90,
     skill = sms.skill.AVERAGE},
  },
})
```

Authoring `skill = sms.skill.AVERAGE` instead of `skill = "Average"` gets autocomplete (the table lists every value), prevents typos at edit time, and makes a future search-and-replace across mission scripts trivial. The framework's `sms.group.unit_spec.skill` field is annotated `sms.Skill|string`, so a raw-string `skill = "Average"` is also typo-checkable in LuaCATS-aware editors.

Values follow the invariant `sms.skill.X` resolves to the verbatim DCS string (`"Average"` etc., case-sensitive).

## Loading

Requires `sms.lua` and `log.lua`. Loaded automatically by `framework/load_all.lua` after `countries.lua`.

## Values

| Constant | DCS string | Use |
|---|---|---|
| `sms.skill.AVERAGE` | `"Average"` | Default for AI units. |
| `sms.skill.GOOD` | `"Good"` | Slightly above average. |
| `sms.skill.HIGH` | `"High"` | Skilled AI. |
| `sms.skill.EXCELLENT` | `"Excellent"` | Top tier. |
| `sms.skill.RANDOM` | `"Random"` | DCS picks a level at spawn time. |
| `sms.skill.PLAYER` | `"Player"` | **Special** — marks a unit slot as a player aircraft (single-player). |
| `sms.skill.CLIENT` | `"Client"` | **Special** — marks a unit slot as a multiplayer client (joinable). |

`PLAYER` and `CLIENT` aren't skill levels in the AI-difficulty sense — they're placeholder values DCS recognizes on the same `skill` field to mark a unit as human-controllable. Don't pass them to AI units.

## The `sms.Skill` alias

`sms.Skill` is a LuaCATS string-literal alias listing every value of `sms.skill`. The `skill` field on `sms.group.unit_spec` is annotated `sms.Skill|string`:

- `skill = sms.skill.AVERAGE` — autocompleted, type-safe.
- `skill = "Average"` — accepted, autocompleted from the alias.
- `skill = "average"` — accepted as `string`; **DCS skill strings are case-sensitive**, so this likely silently falls back to a default.

The `|string` half exists so authors can pass arbitrary strings (including any new skill DCS introduces) without editor red squiggles.

## See also

- [`sms.group.create`](group.md) — spawn factory whose `unit_spec.skill` field consumes this enum.
- [`sms.countries`](countries.md) — the parallel country enum.
```

- [ ] **Step 4.2: Commit**

```bash
git add docs/api/skill.md
git commit -m "$(printf 'docs(api): add reference page for sms.skill\n\nDescribes the 7-entry enum (5 AI skill levels plus PLAYER and CLIENT\nplaceholders), the sms.Skill alias, and the case-sensitivity caveat.\n')"
```

---

## Task 5: API reference page `docs/api/alt_type.md`

**Files:**
- Create: `docs/api/alt_type.md`

**Background for the implementer:** same shape as Task 4 / `countries.md`.

- [ ] **Step 5.1: Create `docs/api/alt_type.md`**

Write verbatim:

```markdown
# `sms.alt_type` — DCS waypoint altitude reference

Hand-maintained enum for the `alt_type` field on unit specs and waypoint tables: `BARO` (above mean sea level) or `RADIO` (above ground level).

```lua
local wp = {
  x = 1234, y = 0, z = 5678,
  alt = 4500, alt_type = sms.alt_type.BARO,
  type = sms.waypoint.TYPE.TURNING_POINT,
  ...
}
```

Authoring `alt_type = sms.alt_type.BARO` instead of `alt_type = "BARO"` gives autocomplete on the two valid forms and catches `"baro"` / `"Baro"` / `"BARO_"` typos at edit time. The framework's `sms.group.unit_spec.alt_type` field is annotated `sms.AltType|string` so raw-string usage is typo-checkable too.

## Loading

Requires `sms.lua` and `log.lua`. Loaded automatically by `framework/load_all.lua` after `skill.lua`.

## Values

| Constant | DCS string | Use |
|---|---|---|
| `sms.alt_type.BARO` | `"BARO"` | Altitude above mean sea level. Default for fixed-wing aircraft. |
| `sms.alt_type.RADIO` | `"RADIO"` | Altitude above ground level (radar altimeter). Used for terrain-following routes and helicopter low-level. |

Values are upper-case; DCS rejects lower-case forms.

## The `sms.AltType` alias

`sms.AltType` is a LuaCATS string-literal alias enumerating `"BARO"` and `"RADIO"`. The `alt_type` field on `sms.group.unit_spec` is annotated `sms.AltType|string`:

- `alt_type = sms.alt_type.BARO` — autocompleted, type-safe.
- `alt_type = "BARO"` — accepted, autocompleted from the alias.
- `alt_type = "baro"` — passes the type checker (matches `string`) but **fails at runtime**; DCS expects upper-case.

## See also

- [`sms.waypoint`](waypoint.md) — waypoint type / action enums for the same waypoint tables.
- [`sms.group.create`](group.md) — spawn factory whose unit specs accept `alt_type`.
```

- [ ] **Step 5.2: Commit**

```bash
git add docs/api/alt_type.md
git commit -m "$(printf 'docs(api): add reference page for sms.alt_type\n\nTwo-entry enum (BARO / RADIO) for the waypoint altitude-reference\nfield; describes the case-sensitivity caveat.\n')"
```

---

## Task 6: API reference page `docs/api/waypoint.md`

**Files:**
- Create: `docs/api/waypoint.md`

**Background for the implementer:** larger than the other two pages because there are two enum sub-tables (TYPE with 7 entries, ACTION with 11). Show one combined usage example and tabulate both.

- [ ] **Step 6.1: Create `docs/api/waypoint.md`**

Write verbatim:

```markdown
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
| `sms.waypoint.ACTION.FLYOVER_POINT` | `"Fly Over Point"` | Pass directly over the point without turning. |
| `sms.waypoint.ACTION.FROM_PARKING_AREA` | `"From Parking Area"` | Cold start from parking, then proceed. |
| `sms.waypoint.ACTION.FROM_PARKING_AREA_HOT` | `"From Parking Area Hot"` | Hot start from parking, then proceed. |
| `sms.waypoint.ACTION.FROM_GROUND_AREA` | `"From Ground Area"` | Cold start on the ground. |
| `sms.waypoint.ACTION.FROM_GROUND_AREA_HOT` | `"From Ground Area Hot"` | Hot start on the ground. |
| `sms.waypoint.ACTION.FROM_RUNWAY` | `"From Runway"` | Start at the runway threshold, takeoff. |
| `sms.waypoint.ACTION.LANDING` | `"Landing"` | Land at the airfield. |
| `sms.waypoint.ACTION.LANDING_REFUEL_REARM` | `"LandingReFuAr"` | Land, refuel, rearm. |
| `sms.waypoint.ACTION.OFF_ROAD` | `"Off Road"` | Ground / ship / train unit traverses cross-country. Default for ground-unit waypoints in dcs-sms. |
| `sms.waypoint.ACTION.ON_ROAD` | `"On Road"` | Ground unit follows the road network. |

`OFF_ROAD` and `ON_ROAD` are ground-unit-specific actions; `FLYOVER_POINT` / `FROM_*` / `LANDING*` are air-unit actions; `TURNING_POINT` works for both categories.

## The `sms.WaypointType` and `sms.WaypointAction` aliases

Two LuaCATS string-literal aliases enumerate every value of each sub-table. They drive autocomplete on raw-string usage in any user code that consumes a hand-built waypoint table. The framework doesn't currently annotate any specific field with these aliases (waypoint tables are passthrough to DCS, not first-class types in the framework yet) — that's a future opportunity.

## See also

- [`sms.alt_type`](alt_type.md) — companion enum for the `alt_type` field on the same waypoint tables.
- [`sms.task`](task.md) — task builders that produce waypoints internally; the framework emits `"Turning Point"` and `"Off Road"` literals from those builders today.
- [`sms.group`](group.md) — `group:set_task` consumes routes whose waypoints can be built using these enums.
```

- [ ] **Step 6.2: Commit**

```bash
git add docs/api/waypoint.md
git commit -m "$(printf 'docs(api): add reference page for sms.waypoint\n\nTwo enum sub-tables (TYPE: 7 entries, ACTION: 11 entries) for the\nhand-built waypoint type and action fields; tabulates each and\ncalls out the air vs ground action split.\n')"
```

---

## Task 7: AGENTS.md, README.md, and docs/api/README.md updates

**Files:**
- Modify: `AGENTS.md` — §7 module-index table, three new rows.
- Modify: `README.md` — "Repo layout" framework module list.
- Modify: `docs/api/README.md` — module-index table, three new rows.

**Background for the implementer:**

- Per `CLAUDE.md`, every change adding public `sms.*` surface updates `AGENTS.md` §7 and the relevant `docs/api/` index in the same change-set.
- Three new rows in each table (one per new module).
- README "Repo layout" line is a comma-separated list of every `sms.*` module.

- [ ] **Step 7.1: Update `AGENTS.md` §7**

Find the existing `sms.countries` row in the §7 module-index table:

```markdown
| `sms.countries` | `countries.lua` | [`docs/api/countries.md`](docs/api/countries.md) | Hand-maintained enum of DCS `country.id` keys; provides autocomplete on `country = sms.countries.<KEY>` spawn configs and a `sms.Country` LuaCATS alias for raw-string usage. |
```

Insert three new rows immediately after it:

```markdown
| `sms.skill` | `skill.lua` | [`docs/api/skill.md`](docs/api/skill.md) | Hand-maintained enum of DCS unit skill levels (`AVERAGE` / `GOOD` / `HIGH` / `EXCELLENT` / `RANDOM` / `PLAYER` / `CLIENT`); provides autocomplete on `unit_spec.skill` and a `sms.Skill` LuaCATS alias for raw-string usage. |
| `sms.alt_type` | `alt_type.lua` | [`docs/api/alt_type.md`](docs/api/alt_type.md) | Two-entry enum (`BARO` / `RADIO`) for the waypoint altitude-reference field; provides autocomplete and a `sms.AltType` LuaCATS alias. |
| `sms.waypoint` | `waypoint.lua` | [`docs/api/waypoint.md`](docs/api/waypoint.md) | Two enum sub-tables for hand-built route waypoints: `sms.waypoint.TYPE` (7 entries) and `sms.waypoint.ACTION` (11 entries), with `sms.WaypointType` / `sms.WaypointAction` LuaCATS aliases. |
```

- [ ] **Step 7.2: Update `README.md` "Repo layout" framework module list**

Find the framework module list (around line 13). It currently reads (after the recent `sms.countries` work):

```markdown
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.countries`, `sms.units`, `sms.statics`, `sms.targets`, `sms.designations`, `sms.group` (+ `sms.spawn` factories), `sms.unit`, `sms.area`, `sms.timer`, `sms.rule`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`, `sms.commands`, `sms.options`. ...
```

Add `sms.skill`, `sms.alt_type`, `sms.waypoint` immediately after `sms.countries`:

```markdown
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.countries`, `sms.skill`, `sms.alt_type`, `sms.waypoint`, `sms.units`, `sms.statics`, `sms.targets`, `sms.designations`, `sms.group` (+ `sms.spawn` factories), `sms.unit`, `sms.area`, `sms.timer`, `sms.rule`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`, `sms.commands`, `sms.options`. ...
```

(Preserve the rest of the line — the `See [AGENTS.md] ...` suffix.)

- [ ] **Step 7.3: Update `docs/api/README.md` module-index table**

Find the existing `countries.md` row:

```markdown
| [`countries.md`](countries.md) | `sms.countries` | Hand-maintained enum of DCS `country.id` keys; provides autocomplete on `country = sms.countries.<KEY>` spawn configs. |
```

Insert three rows immediately after:

```markdown
| [`skill.md`](skill.md) | `sms.skill` | Hand-maintained enum of DCS unit skill levels; autocomplete on the `skill` field of unit specs. |
| [`alt_type.md`](alt_type.md) | `sms.alt_type` | Two-entry enum (`BARO` / `RADIO`) for the waypoint altitude reference. |
| [`waypoint.md`](waypoint.md) | `sms.waypoint` | Two enum sub-tables (`TYPE` and `ACTION`) for hand-built route waypoints. |
```

- [ ] **Step 7.4: Commit**

```bash
git add AGENTS.md README.md docs/api/README.md
git commit -m "$(printf 'docs(framework): index sms.skill, sms.alt_type, sms.waypoint\n\nThree new rows in AGENTS.md %s7, the docs/api/ module-index table, and\nthe README Repo-layout framework module list.\n' "§")"
```

---

## Self-review

**Spec coverage check:**

| Spec scope item | Plan task |
|---|---|
| 1. `framework/skill.lua` | Task 1 (Step 1.1) |
| 2. `framework/alt_type.lua` | Task 1 (Step 1.2) |
| 3. `framework/waypoint.lua` (TYPE + ACTION) | Task 1 (Step 1.3) |
| 4. LuaCATS class + alias for each | Task 1 |
| 5. `framework/load_all.lua` wiring | Task 1 (Step 1.4) |
| 6. `group_spawn.lua` annotations | Task 2 |
| 7. `docs/api/skill.md` | Task 4 |
| 7. `docs/api/alt_type.md` | Task 5 |
| 7. `docs/api/waypoint.md` | Task 6 |
| 8. `docs/api/README.md` rows | Task 7 (Step 7.3) |
| 9. AGENTS.md §7 rows | Task 7 (Step 7.1) |
| 10. README.md module list | Task 7 (Step 7.2) |
| 11. Smoke checks | Task 3 |

All 11 spec scope items map to a task.

**Placeholder scan:** No "TBD" / "TODO" / "implement later" / "similar to Task N" / unspecified "add error handling" / "write tests for the above" without code.

**Type / signature consistency:**

- Module names (`sms.skill`, `sms.alt_type`, `sms.waypoint`) used identically across all tasks.
- Alias names (`sms.Skill`, `sms.AltType`, `sms.WaypointType`, `sms.WaypointAction`) declared in Task 1, referenced consistently in Tasks 2, 4, 5, 6.
- Loader order — three new files inserted after `countries.lua` — applied in Task 1 and assumed (correctly) in Tasks 2 (which references `sms.Skill` / `sms.AltType` defined in Task 1).
- Spec values (5+2 / 7+11) match the assignments inside Task 1 and the doc tables in Tasks 4, 5, 6.

No drift.
