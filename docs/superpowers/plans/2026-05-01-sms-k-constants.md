# sms.K Constants Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse every enum-shaped public `sms.*` table into a single `sms.constants` namespace exposed under the alias `sms.K`, drop the obsolete standalone modules, add new constants for coalition + category, and sweep the entire repo (framework internals, smoke tests, docs, AGENTS.md) onto the new access pattern.

**Architecture:** `framework/constants.lua` is a thin entry point that requires every topic file in `framework/constants/`. Each topic file assigns into `sms.constants.<topic>` and declares any LuaCATS aliases. After all topic files load, `constants.lua` runs `sms.K = sms.constants` so the short alias is available everywhere. `sms.options` builder functions stay where they are; only their enum sub-tables move. `sms.units` and `sms.statics` catalogs move with their `origin_of` helpers; the auto-generator in `tools/internal/genunits/` writes the new path and the new table prelude.

**Tech Stack:** Lua 5.1 (DCS mission environment). Go (tools/). Bash smoke tests under `framework/test/`. LuaCATS for editor type-checking. No new dependencies.

**Spec:** [`docs/superpowers/specs/2026-05-01-sms-k-constants.md`](../specs/2026-05-01-sms-k-constants.md)

---

### Task 1: Foundation — `sms.constants` + `sms.K` alias

Create the entry point and empty topic directory. Wire it into `load_all.lua`. After this task, `sms.K` and `sms.constants` both point at the same empty table; framework still loads and existing tests stay green because no module has been moved yet.

**Files:**
- Create: `framework/constants.lua`
- Create: `framework/constants/` (directory; will hold topic files)
- Modify: `framework/load_all.lua` (insert `"constants.lua"` after `"utils.lua"` and *keep* the existing standalone enum modules for now — they get removed in later tasks)
- Test: `framework/test/smoke.sh` (add identity assertions)

- [ ] **Step 1: Write `framework/constants.lua` (entry point)**

```lua
-- dcs-sms framework: constants module (sms.constants, alias sms.K).
--
-- Single namespace for every enum-shaped public table in the framework:
-- countries, skill, alt_type, waypoint type / action, targets, designations,
-- ROE, alarm-state, formation, reaction-on-threat, radar-using, flare-using,
-- coalition, category, plus the auto-generated unit and static catalogs.
--
-- Each topic lives in framework/constants/<topic>.lua. This entry point
-- dofiles every topic file and finally aliases sms.K = sms.constants so
-- mission code can write sms.K.units.armor.apc.AAV7 instead of the long
-- form sms.constants.units.armor.apc.AAV7.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua.
-- Topic files load inside this file in alphabetical order; cross-topic
-- dependencies do not exist (each topic is a self-contained table).
--
-- See docs/api/constants.md for the per-topic reference.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

---@class sms.constants
sms.constants = sms.constants or {}

local CONSTANTS_DIR = (function()
  local src = (debug.getinfo(1, "S") or {}).source or ""
  local dir = src:match("^@(.*[/\\])constants%.lua$")
  return dir and (dir .. "constants/") or "D:/git/dcs-sms/framework/constants/"
end)()

-- Topic files are added by subsequent tasks. List is alphabetical so a
-- diff between commits shows exactly which topic was added without
-- reordering noise. No file means no dofile — Task 1 has none yet.
local topics = {
  -- (populated by subsequent tasks)
}

for _, name in ipairs(topics) do
  dofile(CONSTANTS_DIR .. name)
end

-- Short alias: sms.K is the documented shorthand. Both names point at the
-- same table; mission code uses sms.K, framework internals use sms.K too.
sms.K = sms.constants
```

- [ ] **Step 2: Create the `framework/constants/` directory**

The directory must exist before subsequent tasks can drop topic files into it. On Windows PowerShell:

```powershell
New-Item -ItemType Directory -Path framework/constants -Force | Out-Null
```

If the directory ends up empty after this task, that is correct — Task 1 only creates the foundation. To prevent git from skipping an empty directory, add a placeholder:

```powershell
New-Item -ItemType File -Path framework/constants/.gitkeep -Force | Out-Null
```

Subsequent tasks delete `.gitkeep` once they add real files.

- [ ] **Step 3: Update `framework/load_all.lua` — add `"constants.lua"` after `"utils.lua"`**

Edit the `modules` table in load_all.lua. Insert `"constants.lua"` immediately after `"utils.lua"` and **before** the existing `"countries.lua"` (which Task 2 will remove). The result must look like:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "constants.lua",        -- new
  "countries.lua",        -- Task 2 will remove
  "skill.lua",            -- Task 2 will remove
  "alt_type.lua",         -- Task 2 will remove
  "waypoint.lua",         -- Task 2 will remove
  "units.lua",            -- Task 5 will move
  "statics.lua",          -- Task 6 will move
  "targets.lua",          -- Task 2 will remove
  "designations.lua",     -- Task 2 will remove
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

- [ ] **Step 4: Add identity assertions to `framework/test/smoke.sh`**

Find the existing assertion sweep (countries / skill / alt_type / waypoint identity checks). Above it, insert a new block:

```bash
log_assert "sms.K is sms.constants alias"      "type(sms.K) == 'table' and sms.K == sms.constants"
log_assert "sms.constants is initialized"     "type(sms.constants) == 'table'"
log_assert "sms.K survives module reload"     "(function() dofile('D:/git/dcs-sms/framework/load_all.lua'); return sms.K == sms.constants end)()"
```

(`log_assert` is the existing helper in smoke.sh — see the surrounding lines for the exact call shape and adapt if `log_assert` takes named flags.)

- [ ] **Step 5: Run the smoke suite**

```bash
bash framework/test/smoke.sh
```

Expected: every existing assertion passes (because no module surface changed), plus the three new assertions for `sms.K`. Investigate any regression before committing.

- [ ] **Step 6: Commit**

```bash
git add framework/constants.lua framework/constants/.gitkeep framework/load_all.lua framework/test/smoke.sh
git commit -m "feat(framework): add sms.constants module + sms.K alias scaffold"
```

---

### Task 2: Move six hand-listed enum modules into `framework/constants/`

Move countries, skill, alt_type, waypoint, targets, designations from `framework/<file>.lua` into `framework/constants/<file>.lua`. Drop the standalone modules (`sms.countries`, `sms.skill`, `sms.alt_type`, `sms.waypoint`, `sms.targets`, `sms.designations`) entirely — no aliases. Update each file's content so it assigns into `sms.constants.<topic>` rather than `sms.<topic>`. Sweep framework-internal references that pointed at the old surface.

**Subtle change in `waypoint.lua`:** the public sub-tables `sms.waypoint.TYPE` and `sms.waypoint.ACTION` become `sms.K.waypoint.type` and `sms.K.waypoint.action` (case-folded). The leaf keys (`TURNING_POINT`, `OFF_ROAD`, etc.) are unchanged.

**Files:**
- Create: `framework/constants/countries.lua` (verbatim move of `framework/countries.lua` with assignments rewritten)
- Create: `framework/constants/skill.lua`
- Create: `framework/constants/alt_type.lua`
- Create: `framework/constants/waypoint.lua` (with `TYPE`→`type`, `ACTION`→`action` rename on the sub-table names)
- Create: `framework/constants/targets.lua`
- Create: `framework/constants/designations.lua`
- Delete: `framework/countries.lua`, `framework/skill.lua`, `framework/alt_type.lua`, `framework/waypoint.lua`, `framework/targets.lua`, `framework/designations.lua`
- Delete: `framework/constants/.gitkeep`
- Modify: `framework/constants.lua` (add the six topic files to the `topics` list)
- Modify: `framework/load_all.lua` (drop the six standalone module entries)
- Modify: `framework/group.lua` (line 395: `start.alt_type = "BARO"` → `sms.K.alt_type.BARO`)
- Modify: `framework/group_spawn.lua` (lines 174 & 214: `"BARO"` → `sms.K.alt_type.BARO`; the `country` and `skill` `---@field` annotations already say `sms.Country|string` / `sms.Skill|string` — those alias names are preserved by D8 in the spec, so no annotation change is needed)
- Modify: `framework/static.lua` (any `sms.countries.*` / `"BARO"` references — grep first; static.lua only references `sms.Country` in annotations, no runtime references to remove, but verify)
- Test: `framework/test/smoke.sh` (existing assertions for `sms.countries.USA == "USA"` etc. → `sms.K.countries.USA == "USA"`)

- [ ] **Step 1: Write `framework/constants/countries.lua`**

Take the entire contents of the current `framework/countries.lua` and apply this rewrite recipe:

1. Banner first line stays "dcs-sms framework: countries module" but now mentions "(sms.constants.countries / sms.K.countries)".
2. The `---@class sms.countries` annotation becomes `---@class sms.constants.countries` and the table is initialized as `sms.constants.countries = sms.constants.countries or {}`.
3. The `---@alias sms.Country` block stays unchanged — the alias name is top-level and is still referenced as `sms.Country` from `sms.group.unit_spec.country`.
4. Every assignment `sms.countries.X = "X"` becomes `sms.constants.countries.X = "X"`.
5. The drift check at the bottom (`for key in pairs(country.id) do ...`) writes into `sms.constants.countries[key]` and the warn message changes to mention `framework/constants/countries.lua`.

Verify: after this file is loaded, `sms.K.countries.USA == "USA"` is true.

- [ ] **Step 2: Write `framework/constants/skill.lua`**

Same recipe applied to `framework/skill.lua`. Result: `sms.constants.skill.AVERAGE = "Average"` etc., `---@class sms.constants.skill`, `---@alias sms.Skill` unchanged, banner mentions the new path.

- [ ] **Step 3: Write `framework/constants/alt_type.lua`**

Same recipe. `sms.constants.alt_type.BARO = "BARO"`, `RADIO = "RADIO"`. Banner mentions the new path.

- [ ] **Step 4: Write `framework/constants/waypoint.lua`** (case-fold `TYPE`/`ACTION`)

Take the entire contents of `framework/waypoint.lua` and apply:

1. Banner mentions `sms.K.waypoint.type.TURNING_POINT` (lowercase `type`) as the example.
2. Outer table: `---@class sms.constants.waypoint`, `sms.constants.waypoint = sms.constants.waypoint or {}`.
3. Sub-tables: `---@class sms.constants.waypoint.type` (was `sms.waypoint.TYPE`) and `---@class sms.constants.waypoint.action`. Initialize as `sms.constants.waypoint.type = sms.constants.waypoint.type or {}` etc.
4. The outer `---@field` block changes from `---@field TYPE sms.waypoint.TYPE` to `---@field type sms.constants.waypoint.type` and same for `action`.
5. Every assignment `sms.waypoint.TYPE.X = "..."` becomes `sms.constants.waypoint.type.X = "..."` (lowercase middle segment, leaf keys unchanged).
6. Aliases `sms.WaypointType` and `sms.WaypointAction` are unchanged.

Verify: `sms.K.waypoint.type.TURNING_POINT == "Turning Point"` and `sms.K.waypoint.action.OFF_ROAD == "Off Road"`.

- [ ] **Step 5: Write `framework/constants/targets.lua`**

Same recipe applied to `framework/targets.lua`. `sms.constants.targets.AIR = "Air"`, etc. Drop the `local log = sms.log.module(...)` line if the file doesn't actually log anywhere — `targets.lua` is data-only, no log calls; the existing module already omits the logger.

- [ ] **Step 6: Write `framework/constants/designations.lua`**

Same recipe. `sms.constants.designations.LASER = "Laser"`, etc.

- [ ] **Step 7: Update `framework/constants.lua` `topics` list**

Edit the `topics` table in `framework/constants.lua`:

```lua
local topics = {
  "alt_type.lua",
  "countries.lua",
  "designations.lua",
  "skill.lua",
  "targets.lua",
  "waypoint.lua",
}
```

(Alphabetical, six entries.)

- [ ] **Step 8: Update `framework/load_all.lua` — drop the six standalone entries**

Remove `"countries.lua"`, `"skill.lua"`, `"alt_type.lua"`, `"waypoint.lua"`, `"targets.lua"`, `"designations.lua"` from the `modules` list. The list now has `"constants.lua"` immediately after `"utils.lua"` and the next entry is `"units.lua"` (which Task 5 will move) followed by `"statics.lua"` (Task 6).

- [ ] **Step 9: Sweep `framework/group.lua`**

Find the line `if is_air then start.alt_type = "BARO" end` (around line 395). Replace with:

```lua
if is_air then start.alt_type = sms.K.alt_type.BARO end
```

- [ ] **Step 10: Sweep `framework/group_spawn.lua`**

Find every `"BARO"` literal. As of the survey there are two:

```lua
-- Line 174 (approx)
if u_spec.alt_type ~= nil then dcs_unit.alt_type = u_spec.alt_type else dcs_unit.alt_type = sms.K.alt_type.BARO end
```

```lua
-- Line 214 (approx)
alt_type = sms.K.alt_type.BARO,
```

Re-grep before editing — line numbers may have shifted.

- [ ] **Step 11: Delete the six standalone module files**

```bash
rm framework/countries.lua framework/skill.lua framework/alt_type.lua framework/waypoint.lua framework/targets.lua framework/designations.lua
rm framework/constants/.gitkeep
```

- [ ] **Step 12: Update `framework/test/smoke.sh` identity assertions**

Find the existing block of assertions that reference the old surface (greps like `sms\.countries\.`, `sms\.skill\.`, `sms\.alt_type\.`, `sms\.waypoint\.`, `sms\.targets\.`, `sms\.designations\.`). Rewrite each to `sms.K.<topic>.<KEY>` form. Examples:

- `sms.countries.USA == "USA"` → `sms.K.countries.USA == "USA"`
- `sms.skill.AVERAGE == "Average"` → `sms.K.skill.AVERAGE == "Average"`
- `sms.skill.PLAYER == "Player"` → `sms.K.skill.PLAYER == "Player"`
- `sms.alt_type.BARO == "BARO"` → `sms.K.alt_type.BARO == "BARO"`
- `sms.alt_type.RADIO == "RADIO"` → `sms.K.alt_type.RADIO == "RADIO"`
- `sms.waypoint.TYPE.TURNING_POINT == "Turning Point"` → `sms.K.waypoint.type.TURNING_POINT == "Turning Point"`
- `sms.waypoint.TYPE.LANDING_REFUEL_REARM == "LandingReFuAr"` → `sms.K.waypoint.type.LANDING_REFUEL_REARM == "LandingReFuAr"`
- `sms.waypoint.ACTION.OFF_ROAD == "Off Road"` → `sms.K.waypoint.action.OFF_ROAD == "Off Road"`
- `sms.waypoint.ACTION.LANDING_REFUEL_REARM == "LandingReFuAr"` → `sms.K.waypoint.action.LANDING_REFUEL_REARM == "LandingReFuAr"`

Add a new assertion that the old surface is gone:

```bash
log_assert "sms.countries is gone"   "sms.countries == nil"
log_assert "sms.skill is gone"       "sms.skill == nil"
log_assert "sms.alt_type is gone"    "sms.alt_type == nil"
log_assert "sms.waypoint is gone"    "sms.waypoint == nil"
log_assert "sms.targets is gone"     "sms.targets == nil"
log_assert "sms.designations is gone" "sms.designations == nil"
```

- [ ] **Step 13: Run the smoke suite**

```bash
bash framework/test/smoke.sh
bash framework/test/smoke_group.sh
bash framework/test/smoke_unit.sh
```

(`smoke_group.sh` and `smoke_unit.sh` reference `skill = "Average"` and `alt_type = "BARO"` raw strings inside Lua chunks they send to DCS — those still work because DCS itself doesn't care about the constants, only that the wire-format string is correct. The smoke chunks themselves are swept in Task 7.)

Expected: every assertion green. Investigate any regression before committing.

- [ ] **Step 14: Commit**

```bash
git add framework/constants.lua framework/constants/ framework/load_all.lua framework/group.lua framework/group_spawn.lua framework/test/smoke.sh
git rm framework/countries.lua framework/skill.lua framework/alt_type.lua framework/waypoint.lua framework/targets.lua framework/designations.lua framework/constants/.gitkeep
git commit -m "refactor(framework): move six enum modules under sms.K (drop sms.countries/skill/alt_type/waypoint/targets/designations)"
```

---

### Task 3: Move option enum tables (`sms.options.ROE` etc.) under `sms.K`

The enum *tables* on `sms.options` (`ROE`, `REACTION_ON_THREAT`, `RADAR_USING`, `FLARE_USING`, `ALARM_STATE`, `FORMATION`) move out of `framework/options.lua` and into individual topic files under `framework/constants/`. The builder *functions* (`sms.options.roe`, `sms.options.alarm_state`, etc.) stay on `sms.options` and continue to consume their internal lookup tables (`_roe_air`, `_alarm_state`, `_formation_dcs`, etc., all private). Mission code that today does `sms.options.roe(sms.options.ROE.WEAPON_FREE)` becomes `sms.options.roe(sms.K.roe.WEAPON_FREE)`.

**Files:**
- Create: `framework/constants/roe.lua`
- Create: `framework/constants/alarm_state.lua`
- Create: `framework/constants/reaction_on_threat.lua`
- Create: `framework/constants/radar_using.lua`
- Create: `framework/constants/flare_using.lua`
- Create: `framework/constants/formation.lua`
- Modify: `framework/options.lua` (delete the six `sms.options.<TABLE> = {...}` blocks at the top of the file, lines ~50-92)
- Modify: `framework/constants.lua` (add the six topic files to the `topics` list)
- Test: `framework/test/smoke.sh` (assertions for `sms.K.roe.*`, `sms.K.alarm_state.*`, `sms.K.formation.*`, etc.)

- [ ] **Step 1: Write `framework/constants/roe.lua`**

```lua
-- dcs-sms framework: ROE constants (sms.constants.roe / sms.K.roe).
--
-- ROE strings consumed by the sms.options.roe(value) builder. The builder
-- is responsible for category-specific validation (some values are
-- air-only) — this table just lists every value the framework recognises.
--
-- Loading order: ... -> constants.lua -> framework/constants/roe.lua.
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.roe
---@field WEAPON_FREE           "weapon_free"
---@field OPEN_FIRE_WEAPON_FREE "open_fire_weapon_free"
---@field OPEN_FIRE             "open_fire"
---@field RETURN_FIRE           "return_fire"
---@field WEAPON_HOLD           "weapon_hold"
sms.constants.roe = sms.constants.roe or {}

sms.constants.roe.WEAPON_FREE           = "weapon_free"
sms.constants.roe.OPEN_FIRE_WEAPON_FREE = "open_fire_weapon_free"
sms.constants.roe.OPEN_FIRE             = "open_fire"
sms.constants.roe.RETURN_FIRE           = "return_fire"
sms.constants.roe.WEAPON_HOLD           = "weapon_hold"
```

- [ ] **Step 2: Write `framework/constants/alarm_state.lua`**

```lua
-- dcs-sms framework: alarm_state constants (sms.constants.alarm_state /
-- sms.K.alarm_state). Consumed by sms.options.alarm_state(value).

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.alarm_state
---@field AUTO  "auto"
---@field GREEN "green"
---@field RED   "red"
sms.constants.alarm_state = sms.constants.alarm_state or {}

sms.constants.alarm_state.AUTO  = "auto"
sms.constants.alarm_state.GREEN = "green"
sms.constants.alarm_state.RED   = "red"
```

- [ ] **Step 3: Write `framework/constants/reaction_on_threat.lua`**

Same shape with the five values from the existing `sms.options.REACTION_ON_THREAT` table:

```lua
sms.constants.reaction_on_threat.NO_REACTION         = "no_reaction"
sms.constants.reaction_on_threat.PASSIVE_DEFENCE     = "passive_defence"
sms.constants.reaction_on_threat.EVADE_FIRE          = "evade_fire"
sms.constants.reaction_on_threat.BYPASS_AND_ESCAPE   = "bypass_and_escape"
sms.constants.reaction_on_threat.ALLOW_ABORT_MISSION = "allow_abort_mission"
```

(Plus the `---@class sms.constants.reaction_on_threat` field block, the `assert`s, and the load-order banner.)

- [ ] **Step 4: Write `framework/constants/radar_using.lua`**

```lua
sms.constants.radar_using.NEVER                  = "never"
sms.constants.radar_using.FOR_ATTACK_ONLY        = "for_attack_only"
sms.constants.radar_using.FOR_SEARCH_IF_REQUIRED = "for_search_if_required"
sms.constants.radar_using.FOR_CONTINUOUS_SEARCH  = "for_continuous_search"
```

- [ ] **Step 5: Write `framework/constants/flare_using.lua`**

```lua
sms.constants.flare_using.NEVER                    = "never"
sms.constants.flare_using.AGAINST_FIRED_MISSILE    = "against_fired_missile"
sms.constants.flare_using.WHEN_FLYING_IN_SAM_WEZ   = "when_flying_in_sam_wez"
sms.constants.flare_using.WHEN_FLYING_NEAR_ENEMIES = "when_flying_near_enemies"
```

- [ ] **Step 6: Write `framework/constants/formation.lua`**

```lua
sms.constants.formation.LINE_ABREAST  = "line_abreast"
sms.constants.formation.TRAIL         = "trail"
sms.constants.formation.WEDGE         = "wedge"
sms.constants.formation.ECHELON_RIGHT = "echelon_right"
sms.constants.formation.ECHELON_LEFT  = "echelon_left"
sms.constants.formation.FINGER_FOUR   = "finger_four"
sms.constants.formation.SPREAD        = "spread"
```

- [ ] **Step 7: Strip the six enum-table blocks from `framework/options.lua`**

In `framework/options.lua`, find lines ~46-92 (the block with `sms.options.ROE = {...}` through `sms.options.FORMATION = {...}`). Delete the *six public* enum tables. Keep the comment header that introduces the section but rewrite it to:

```lua
-- ============================================================
-- Enum strings consumed by the builders below live on sms.K (see
-- framework/constants/{roe,reaction_on_threat,radar_using,flare_using,
-- alarm_state,formation}.lua). The private lookup tables in this file
-- (_roe_air, _alarm_state, _formation_dcs, etc.) map those strings to
-- the DCS-side numeric values and stay private.
-- ============================================================
```

The private lookup tables (`_roe_air`, `_roe_ground`, `_roe_naval`, `_reaction_on_threat`, `_radar_using`, `_flare_using`, `_alarm_state`, `_formation_dcs`) stay unchanged — they are private to the builders and consume the same lowercase wire-format strings.

- [ ] **Step 8: Update `framework/constants.lua` `topics` list**

```lua
local topics = {
  "alarm_state.lua",
  "alt_type.lua",
  "countries.lua",
  "designations.lua",
  "flare_using.lua",
  "formation.lua",
  "radar_using.lua",
  "reaction_on_threat.lua",
  "roe.lua",
  "skill.lua",
  "targets.lua",
  "waypoint.lua",
}
```

- [ ] **Step 9: Add identity assertions to `framework/test/smoke.sh`**

```bash
log_assert "sms.K.roe.WEAPON_FREE"           "sms.K.roe.WEAPON_FREE == 'weapon_free'"
log_assert "sms.K.roe.WEAPON_HOLD"           "sms.K.roe.WEAPON_HOLD == 'weapon_hold'"
log_assert "sms.K.alarm_state.RED"           "sms.K.alarm_state.RED == 'red'"
log_assert "sms.K.alarm_state.AUTO"          "sms.K.alarm_state.AUTO == 'auto'"
log_assert "sms.K.formation.WEDGE"           "sms.K.formation.WEDGE == 'wedge'"
log_assert "sms.K.formation.FINGER_FOUR"     "sms.K.formation.FINGER_FOUR == 'finger_four'"
log_assert "sms.K.reaction_on_threat.EVADE_FIRE" "sms.K.reaction_on_threat.EVADE_FIRE == 'evade_fire'"
log_assert "sms.K.radar_using.NEVER"         "sms.K.radar_using.NEVER == 'never'"
log_assert "sms.K.flare_using.AGAINST_FIRED_MISSILE" "sms.K.flare_using.AGAINST_FIRED_MISSILE == 'against_fired_missile'"
log_assert "sms.options.ROE is gone"         "sms.options.ROE == nil"
log_assert "sms.options.ALARM_STATE is gone" "sms.options.ALARM_STATE == nil"
log_assert "sms.options.FORMATION is gone"   "sms.options.FORMATION == nil"
log_assert "sms.options.roe builder lives"   "type(sms.options.roe) == 'function'"
log_assert "sms.options.alarm_state lives"   "type(sms.options.alarm_state) == 'function'"
```

- [ ] **Step 10: Run smoke**

```bash
bash framework/test/smoke.sh
```

Expected: every assertion green; the new builder calls (`sms.options.roe(sms.K.roe.WEAPON_FREE)`) still work because the builders accept either the constant or the raw string.

- [ ] **Step 11: Commit**

```bash
git add framework/constants/ framework/constants.lua framework/options.lua framework/test/smoke.sh
git commit -m "refactor(options): move enum tables off sms.options onto sms.K (roe/alarm_state/formation/etc.)"
```

---

### Task 4: Add `sms.K.coalition` and `sms.K.category` + sweep framework internals

Two brand-new constants tables for previously-raw wire-format strings. After this task, mission code can write `sms.K.coalition.BLUE` instead of `"blue"` and `sms.K.category.AIRPLANE` instead of `"airplane"`. Also sweeps framework-internal usages of these raw strings.

**Files:**
- Create: `framework/constants/coalition.lua`
- Create: `framework/constants/category.lua`
- Modify: `framework/constants.lua` (add the two topic files)
- Modify: `framework/utils.lua` (`coalition_int_to_str` — the private lookup table `_coalition_str` stays private; the `---@return` annotation gains `sms.Coalition` as an alternative)
- Modify: `framework/options.lua` (`_roe_resolve_for_category` — switch raw string comparisons to `sms.K.category.*`)
- Modify: `framework/group_spawn.lua` (any `"airplane"` / `"helicopter"` / `"ground"` / `"ship"` / `"train"` runtime literal — replace with `sms.K.category.*`)
- Modify: `framework/group.lua`, `framework/static.lua`, `framework/unit.lua`, `framework/weapon.lua` (any raw `"red"` / `"blue"` / `"neutral"` / category strings — re-grep first; `weapon.lua` and `unit.lua` use the helper `sms.utils.coalition_int_to_str` so they don't compare raw strings, but sanity-check)
- Test: `framework/test/smoke.sh` (identity assertions)

- [ ] **Step 1: Write `framework/constants/coalition.lua`**

```lua
-- dcs-sms framework: coalition constants (sms.constants.coalition / sms.K.coalition).
--
-- DCS coalitions on the wire are the lowercase strings "red", "blue",
-- and "neutral". sms.utils.coalition_int_to_str returns one of these.
-- Mission code uses sms.K.coalition.RED etc. instead of magic strings.
--
-- Loading order: ... -> constants.lua -> framework/constants/coalition.lua.
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.coalition
---@field RED     "red"
---@field BLUE    "blue"
---@field NEUTRAL "neutral"
sms.constants.coalition = sms.constants.coalition or {}

---@alias sms.Coalition
---| "red"
---| "blue"
---| "neutral"

sms.constants.coalition.RED     = "red"
sms.constants.coalition.BLUE    = "blue"
sms.constants.coalition.NEUTRAL = "neutral"
```

- [ ] **Step 2: Write `framework/constants/category.lua`**

```lua
-- dcs-sms framework: category constants (sms.constants.category / sms.K.category).
--
-- DCS group categories on the wire are the lowercase strings "airplane",
-- "helicopter", "ground", "ship", "train". The framework uses these
-- strings for category dispatch (set_option ROE, _sms_air_only, etc.).
-- Mission code uses sms.K.category.AIRPLANE etc. instead of magic strings.
--
-- Loading order: ... -> constants.lua -> framework/constants/category.lua.
-- See docs/api/constants.md.

assert(type(sms) == "table",           "framework/sms.lua must be loaded first")
assert(type(sms.constants) == "table", "framework/constants.lua must be loaded first")

---@class sms.constants.category
---@field AIRPLANE   "airplane"
---@field HELICOPTER "helicopter"
---@field GROUND     "ground"
---@field SHIP       "ship"
---@field TRAIN      "train"
sms.constants.category = sms.constants.category or {}

---@alias sms.Category
---| "airplane"
---| "helicopter"
---| "ground"
---| "ship"
---| "train"

sms.constants.category.AIRPLANE   = "airplane"
sms.constants.category.HELICOPTER = "helicopter"
sms.constants.category.GROUND     = "ground"
sms.constants.category.SHIP       = "ship"
sms.constants.category.TRAIN      = "train"
```

- [ ] **Step 3: Update `framework/constants.lua` `topics` list**

```lua
local topics = {
  "alarm_state.lua",
  "alt_type.lua",
  "category.lua",
  "coalition.lua",
  "countries.lua",
  "designations.lua",
  "flare_using.lua",
  "formation.lua",
  "radar_using.lua",
  "reaction_on_threat.lua",
  "roe.lua",
  "skill.lua",
  "targets.lua",
  "waypoint.lua",
}
```

- [ ] **Step 4: Sweep framework internals — categories**

Run a focused grep:

```bash
grep -rn '"airplane"\|"helicopter"\|"ground"\|"ship"\|"train"' framework/*.lua
```

Expected hits (verify before editing):

- `framework/options.lua` `_roe_resolve_for_category`: rewrite the `if/elseif` chain:

```lua
sms.options._roe_resolve_for_category = function(category)
  if category == sms.K.category.AIRPLANE or category == sms.K.category.HELICOPTER then
    return AI.Option.Air.id.ROE, _roe_air, "air"
  elseif category == sms.K.category.GROUND or category == sms.K.category.TRAIN then
    return AI.Option.Ground.id.ROE, _roe_ground, "ground"
  elseif category == sms.K.category.SHIP then
    return AI.Option.Naval.id.ROE, _roe_naval, "naval"
  end
  return nil, nil, tostring(category)
end
```

- `framework/group.lua`, `framework/group_spawn.lua`, `framework/unit.lua`, `framework/static.lua`, `framework/weapon.lua`: every literal-string comparison or assignment of a category swaps to `sms.K.category.*`. Comments and log strings that *describe* the wire-format value stay as plain strings (per spec D12 — wire-format references stay literal in prose).

- [ ] **Step 5: Sweep framework internals — coalitions**

```bash
grep -rn '"red"\|"blue"\|"neutral"' framework/*.lua
```

The runtime references to swap are only string-literal *comparisons* and *return values*. The `_coalition_str` table in `utils.lua` is the canonical wire-format mapping — leave it alone (it's the int-to-string table, the strings ARE the wire format). Anywhere downstream code does `if coalition_string == "blue" then ...` or `coalition = "blue"` → swap to `sms.K.coalition.BLUE`. Re-verify after editing each file by re-running the grep.

- [ ] **Step 6: Update LuaCATS annotations on internal types**

Where a type was previously `string`, sharpen it where the alias now exists:

- `framework/utils.lua` `coalition_int_to_str` `---@return` line: change `"red"|"blue"|"neutral"|nil` to `sms.Coalition|nil`.

(The `sms.Country|string`, `sms.Skill|string`, `sms.AltType|string`, `sms.WaypointType|string`, `sms.WaypointAction|string` annotations on `sms.group.unit_spec` etc. are already correct — alias names didn't move.)

- [ ] **Step 7: Add identity assertions to `framework/test/smoke.sh`**

```bash
log_assert "sms.K.coalition.BLUE"     "sms.K.coalition.BLUE == 'blue'"
log_assert "sms.K.coalition.RED"      "sms.K.coalition.RED == 'red'"
log_assert "sms.K.coalition.NEUTRAL"  "sms.K.coalition.NEUTRAL == 'neutral'"
log_assert "sms.K.category.AIRPLANE"  "sms.K.category.AIRPLANE == 'airplane'"
log_assert "sms.K.category.HELICOPTER" "sms.K.category.HELICOPTER == 'helicopter'"
log_assert "sms.K.category.GROUND"    "sms.K.category.GROUND == 'ground'"
log_assert "sms.K.category.SHIP"      "sms.K.category.SHIP == 'ship'"
log_assert "sms.K.category.TRAIN"     "sms.K.category.TRAIN == 'train'"
```

- [ ] **Step 8: Run smoke**

```bash
bash framework/test/smoke.sh
bash framework/test/smoke_group.sh
bash framework/test/smoke_unit.sh
bash framework/test/smoke_events.sh
bash framework/test/smoke_static.sh
bash framework/test/smoke_weapon.sh
bash framework/test/smoke_spawn.sh
```

Run the full suite — coalition/category sweeps touch many files and ROE category dispatch is critical. Investigate any regression before committing.

- [ ] **Step 9: Commit**

```bash
git add framework/constants/coalition.lua framework/constants/category.lua framework/constants.lua framework/utils.lua framework/options.lua framework/group.lua framework/group_spawn.lua framework/unit.lua framework/static.lua framework/weapon.lua framework/test/smoke.sh
git commit -m "feat(framework): add sms.K.coalition + sms.K.category constants; sweep framework internals"
```

---

### Task 5: Move `framework/units.lua` catalog under `sms.K.units`

The 1533-line auto-generated `framework/units.lua` becomes `framework/constants/units.lua`. The Go-side generator in `tools/internal/genunits/` updates its output path and the table-prelude string. The `origin_of` helper moves with the catalog. The LuaCATS alias `sms.GroupSpawnType` is unchanged.

**Files:**
- Move (with content rewrite): `framework/units.lua` → `framework/constants/units.lua`
- Modify: `framework/constants.lua` (add `"units.lua"` to topics list — alphabetical, between `targets.lua` and `waypoint.lua`)
- Modify: `framework/load_all.lua` (drop `"units.lua"` from the standalone modules list — already done in Task 2's edits if present; verify)
- Modify: `tools/internal/genunits/emit.go` (the `EmitUnits` namespace string changes from `"sms.units"` to `"sms.constants.units"`)
- Modify: `tools/internal/genunits/genunits.go` (the `OutDir` semantics — `units.lua` now writes to `<OutDir>/constants/units.lua`)
- Modify: `tools/internal/genunits/emit_test.go` (assertion `sms.units = sms.units or {}` → `sms.constants.units = sms.constants.units or {}`)
- Modify: `tools/cmd/dcs-sms/genunits.go` (the help-text "wrote %s/units.lua" → "wrote %s/constants/units.lua")
- Modify: `tools/cmd/dcs-sms/dispatch.go` line 59 (the `gen-units` blurb — change "regenerate framework/units.lua + statics.lua" to "regenerate framework/constants/units.lua + statics.lua")
- Test: `framework/test/smoke.sh` (assertions for `sms.K.units.*`)

- [ ] **Step 1: Move and rewrite `framework/units.lua` → `framework/constants/units.lua`**

The file is 1533 lines, almost entirely auto-generated category tables. The mechanical rewrite:

1. The first banner line stays "AUTO-GENERATED" (regenerator will rewrite anyway).
2. Banner second line "See docs/api/units.md for usage" stays — `units.md` is preserved as the catalog navigation page.
3. `local log = sms.log.module("sms.units")` → `local log = sms.log.module("sms.constants.units")` (the log tag matches the new namespace).
4. `---@class sms.units` → `---@class sms.constants.units` and `sms.units = sms.units or {}` → `sms.constants.units = sms.constants.units or {}`.
5. The `---@alias sms.GroupSpawnType` block is unchanged — the alias name didn't move.
6. Every `sms.units.<category> = {...}` → `sms.constants.units.<category> = {...}` (twelve such top-level assignments based on the survey).
7. The `_origin` table at the bottom is unchanged (it's a private local).
8. `sms.units.origin_of = function(...)` → `sms.constants.units.origin_of = function(...)`.

This file is large enough that an editor will benefit from doing the rewrite as a single search-and-replace pass after copying:

```bash
# Move
mv framework/units.lua framework/constants/units.lua
# Rewrite all top-level public assignments. Only top-level — leave nested
# {key = "string"} table contents alone, those are catalog values.
sed -i 's/^sms\.units\./sms.constants.units./g' framework/constants/units.lua
sed -i 's/^---@class sms\.units$/---@class sms.constants.units/' framework/constants/units.lua
sed -i 's/sms\.log\.module("sms\.units")/sms.log.module("sms.constants.units")/' framework/constants/units.lua
```

(On Windows PowerShell, equivalent regex replacement; the implementer adapts.)

After the sed pass, manually verify the file: every `sms.units` token now reads `sms.constants.units`, except inside the alphabetical `---@alias sms.GroupSpawnType` block (which contains `---| "AAV7"` etc. — those are catalog values, no `sms.units.` token). The catalog table contents (`AAV7 = "AAV7"`) are untouched because the sed pattern is anchored on `^sms\.units\.`.

- [ ] **Step 2: Update `framework/constants.lua` `topics` list**

```lua
local topics = {
  "alarm_state.lua",
  "alt_type.lua",
  "category.lua",
  "coalition.lua",
  "countries.lua",
  "designations.lua",
  "flare_using.lua",
  "formation.lua",
  "radar_using.lua",
  "reaction_on_threat.lua",
  "roe.lua",
  "skill.lua",
  "targets.lua",
  "units.lua",
  "waypoint.lua",
}
```

- [ ] **Step 3: Update `framework/load_all.lua`**

Drop `"units.lua"` from the `modules` list. After this, `units.lua` is loaded only via `constants.lua` → `framework/constants/units.lua`.

- [ ] **Step 4: Update the Go-side generator namespace string**

In `tools/internal/genunits/emit.go`, find:

```go
func EmitUnits(w io.Writer, entries []ClassifiedEntry, datamineCommit, generatedAt string) error {
	return emit(w, entries, "units",
		"sms.units", "sms.GroupSpawnType",
		datamineCommit, generatedAt)
}
```

Change the namespace argument from `"sms.units"` to `"sms.constants.units"`. Leave the alias `"sms.GroupSpawnType"` alone (alias name unchanged). Same for `EmitStatics` later in Task 6 — but only do `EmitUnits` in this task.

- [ ] **Step 5: Update the Go-side OutDir semantics**

In `tools/internal/genunits/genunits.go` line 140:

```go
if err := writeFile(filepath.Join(opts.OutDir, "units.lua"), func(w *os.File) error { ... }); err != nil {
    return 0, 0, fmt.Errorf("genunits: write units.lua: %w", err)
}
```

Change to:

```go
if err := writeFile(filepath.Join(opts.OutDir, "constants", "units.lua"), func(w *os.File) error { ... }); err != nil {
    return 0, 0, fmt.Errorf("genunits: write constants/units.lua: %w", err)
}
```

(Leave the statics.lua line for Task 6.)

- [ ] **Step 6: Update generator help-text and stdout**

In `tools/cmd/dcs-sms/genunits.go` line 67:

```go
fmt.Fprintf(stdout, "wrote %s/units.lua (%d entries) and %s/statics.lua (%d entries)\n", outDir, u, outDir, s)
```

Change to:

```go
fmt.Fprintf(stdout, "wrote %s/constants/units.lua (%d entries) and %s/constants/statics.lua (%d entries)\n", outDir, u, outDir, s)
```

In the same file's banner comment (lines ~19-20):

```go
//	0 — success; framework/units.lua + framework/statics.lua written.
```

Change to `framework/constants/units.lua + framework/constants/statics.lua`.

In `tools/cmd/dcs-sms/dispatch.go` line 59:

```go
fmt.Fprintln(w, "  gen-units     regenerate framework/units.lua + statics.lua from dcs-lua-datamine")
```

Change to:

```go
fmt.Fprintln(w, "  gen-units     regenerate framework/constants/{units,statics}.lua from dcs-lua-datamine")
```

- [ ] **Step 7: Update generator test assertion**

In `tools/internal/genunits/emit_test.go` line 46:

```go
`sms.units = sms.units or {}`,
```

Change to:

```go
`sms.constants.units = sms.constants.units or {}`,
```

(Statics line at 121 — leave for Task 6.)

- [ ] **Step 8: Run Go tests**

```bash
go test ./tools/...
```

Expected: green. The unit-test fixture asserts the generator emits `sms.constants.units = sms.constants.units or {}` now, plus the `---@class sms.constants.units` annotation.

- [ ] **Step 9: Add identity assertions to `framework/test/smoke.sh`**

```bash
log_assert "sms.K.units.armor.apc.AAV7"           "sms.K.units.armor.apc.AAV7 == 'AAV7'"
log_assert "sms.K.units.air_defence.aaa.Vulcan"   "sms.K.units.air_defence.aaa.Vulcan == 'Vulcan'"
log_assert "sms.K.units.planes.F_16C_50"          "type(sms.K.units.planes) == 'table' and type(sms.K.units.planes.F_16C_50) == 'string'"
log_assert "sms.K.units.origin_of base"           "sms.K.units.origin_of('AAV7') == nil"
log_assert "sms.K.units.origin_of asset-pack"     "type(sms.K.units.origin_of('Tiger_I')) == 'string'"
log_assert "sms.units is gone"                    "sms.units == nil"
```

- [ ] **Step 10: Run framework smoke**

```bash
bash framework/test/smoke.sh
```

Expected: green.

- [ ] **Step 11: Commit**

```bash
git add framework/constants/units.lua framework/constants.lua framework/load_all.lua framework/test/smoke.sh tools/internal/genunits/emit.go tools/internal/genunits/genunits.go tools/internal/genunits/emit_test.go tools/cmd/dcs-sms/genunits.go tools/cmd/dcs-sms/dispatch.go
git rm framework/units.lua
git commit -m "refactor(framework): move sms.units catalog under sms.K (gen-units writes framework/constants/units.lua)"
```

---

### Task 6: Move `framework/statics.lua` catalog under `sms.K.statics`

Mirrors Task 5 for the statics catalog. Same Go generator now also writes the new statics path.

**Files:**
- Move (with content rewrite): `framework/statics.lua` → `framework/constants/statics.lua`
- Modify: `framework/constants.lua` (add `"statics.lua"` to topics list — alphabetical position is between `skill.lua` and `targets.lua`)
- Modify: `framework/load_all.lua` (drop `"statics.lua"`)
- Modify: `tools/internal/genunits/emit.go` (`EmitStatics` namespace `"sms.statics"` → `"sms.constants.statics"`)
- Modify: `tools/internal/genunits/genunits.go` line 145 (statics path → `<OutDir>/constants/statics.lua`)
- Modify: `tools/internal/genunits/emit_test.go` line 121 (`sms.statics = sms.statics or {}` → `sms.constants.statics = sms.constants.statics or {}`)
- Test: `framework/test/smoke.sh`

- [ ] **Step 1: Move and rewrite `framework/statics.lua` → `framework/constants/statics.lua`**

Mirror Task 5 Step 1: `mv` the file then `sed` rewrite top-level assignments:

```bash
mv framework/statics.lua framework/constants/statics.lua
sed -i 's/^sms\.statics\./sms.constants.statics./g' framework/constants/statics.lua
sed -i 's/^---@class sms\.statics$/---@class sms.constants.statics/' framework/constants/statics.lua
sed -i 's/sms\.log\.module("sms\.statics")/sms.log.module("sms.constants.statics")/' framework/constants/statics.lua
```

Verify: every `sms.statics` token now reads `sms.constants.statics`, except inside the `---@alias sms.StaticSpawnType` block (catalog values, no `sms.statics.` token).

- [ ] **Step 2: Update `framework/constants.lua` `topics` list**

```lua
local topics = {
  "alarm_state.lua",
  "alt_type.lua",
  "category.lua",
  "coalition.lua",
  "countries.lua",
  "designations.lua",
  "flare_using.lua",
  "formation.lua",
  "radar_using.lua",
  "reaction_on_threat.lua",
  "roe.lua",
  "skill.lua",
  "statics.lua",
  "targets.lua",
  "units.lua",
  "waypoint.lua",
}
```

- [ ] **Step 3: Update `framework/load_all.lua`** (drop `"statics.lua"`)

- [ ] **Step 4: Update Go-side EmitStatics namespace**

In `tools/internal/genunits/emit.go`, change:

```go
return emit(w, entries, "statics",
    "sms.statics", "sms.StaticSpawnType",
    datamineCommit, generatedAt)
```

The namespace `"sms.statics"` → `"sms.constants.statics"`.

- [ ] **Step 5: Update Go-side OutDir for statics**

In `tools/internal/genunits/genunits.go` line 145, change `filepath.Join(opts.OutDir, "statics.lua")` → `filepath.Join(opts.OutDir, "constants", "statics.lua")`.

- [ ] **Step 6: Update generator test assertion**

`tools/internal/genunits/emit_test.go` line 121: `sms.statics = sms.statics or {}` → `sms.constants.statics = sms.constants.statics or {}`.

- [ ] **Step 7: Run Go tests**

```bash
go test ./tools/...
```

- [ ] **Step 8: Add smoke-test assertions**

```bash
log_assert "sms.K.statics.cargos exists"     "type(sms.K.statics.cargos) == 'table'"
log_assert "sms.K.statics.fortifications exists" "type(sms.K.statics.fortifications) == 'table'"
log_assert "sms.K.statics.origin_of"         "type(sms.K.statics.origin_of) == 'function'"
log_assert "sms.statics is gone"             "sms.statics == nil"
```

- [ ] **Step 9: Run smoke**

```bash
bash framework/test/smoke.sh
```

- [ ] **Step 10: Commit**

```bash
git add framework/constants/statics.lua framework/constants.lua framework/load_all.lua framework/test/smoke.sh tools/internal/genunits/emit.go tools/internal/genunits/genunits.go tools/internal/genunits/emit_test.go
git rm framework/statics.lua
git commit -m "refactor(framework): move sms.statics catalog under sms.K"
```

---

### Task 7: Sweep `framework/test/smoke_*.sh` Lua chunks

The per-module smoke tests (`smoke_group.sh`, `smoke_unit.sh`, `smoke_events.sh`, `smoke_static.sh`, `smoke_weapon.sh`, `smoke_spawn.sh`) embed Lua chunks with raw `country = "USA"`, `category = "ground"`, `skill = "Average"`, `alt_type = "BARO"` literals. These are sent to DCS via the bridge and run inside the mission environment, where `sms.K` is now populated. Sweep every Lua chunk to use `sms.K.*` so the smoke suite itself models idiomatic post-refactor mission code.

**Files:**
- Modify: `framework/test/smoke_group.sh` (`skill = "Average"` → `skill = sms.K.skill.AVERAGE`)
- Modify: `framework/test/smoke_unit.sh` (same)
- Modify: `framework/test/smoke_events.sh` (5 hits: `country = "USA", category = "ground"` → constants)
- Modify: `framework/test/smoke_static.sh` (re-grep for raw country / category strings)
- Modify: `framework/test/smoke_weapon.sh` (2 hits at lines 117/118 and 277/278)
- Modify: `framework/test/smoke_spawn.sh` (re-grep)

- [ ] **Step 1: Locate every raw-string usage**

```bash
grep -n 'country\s*=\s*"\|category\s*=\s*"\|skill\s*=\s*"\|alt_type\s*=\s*"\|coalition\s*=\s*"' framework/test/smoke_*.sh
```

Expected hit pattern (verify before editing — line numbers may shift):

- `smoke_group.sh:71`: `skill = "Average",` → `skill = sms.K.skill.AVERAGE,`
- `smoke_unit.sh:73`: same
- `smoke_events.sh:194,259,327,355,383`: `country = "USA",` → `country = sms.K.countries.USA,`; `category = "ground",` → `category = sms.K.category.GROUND,`
- `smoke_weapon.sh:117,118,277,278`: same pattern

- [ ] **Step 2: Apply the sweep**

For each file, use the Edit tool with exact string matches. Examples:

```
country  = "USA",
category = "ground",
```

becomes

```
country  = sms.K.countries.USA,
category = sms.K.category.GROUND,
```

Preserve the column-aligned `=` so existing formatting is retained.

- [ ] **Step 3: Re-run grep**

```bash
grep -n 'country\s*=\s*"\|category\s*=\s*"\|skill\s*=\s*"\|alt_type\s*=\s*"' framework/test/smoke_*.sh
```

Expected: no matches (every previously-raw assignment now uses `sms.K`).

- [ ] **Step 4: Run every smoke test**

```bash
for f in framework/test/smoke*.sh; do
  echo "=== $f ==="
  bash "$f" || echo "FAILED: $f"
done
```

Expected: every smoke green. The `sms.K.*` lookups happen before the spawn payload is constructed, so a typo like `sms.K.skill.AVERAGEX` would yield `nil` and the spawn would fail. Smoke catching this is the *point* of the sweep.

- [ ] **Step 5: Commit**

```bash
git add framework/test/smoke_*.sh
git commit -m "test(framework): sweep smoke chunks to use sms.K constants"
```

---

### Task 8: Rewrite `docs/api/constants.md` and delete obsolete per-topic doc pages

Replace the existing `docs/api/constants.md` (today: a small `sms.targets` + `sms.designations` reference) with a single comprehensive page covering every `sms.K.*` topic. Delete the standalone per-topic doc pages that have been folded in: `countries.md`, `skill.md`, `alt_type.md`, `waypoint.md`. Keep `units.md` and `statics.md` (catalog navigation pages with their own structure — they are *not* enum reference pages, they describe how to navigate the nested catalogs).

**Files:**
- Modify: `docs/api/constants.md` (rewrite from ~165 lines to a comprehensive single-page reference)
- Delete: `docs/api/countries.md`, `docs/api/skill.md`, `docs/api/alt_type.md`, `docs/api/waypoint.md`
- Modify: `docs/api/units.md` (rewrite to describe `sms.K.units.*` access — same content, new namespace; the catalog navigation pattern is unchanged)
- Modify: `docs/api/statics.md` (same)

- [ ] **Step 1: Read the existing pages to gather content**

```bash
cat docs/api/constants.md docs/api/countries.md docs/api/skill.md docs/api/alt_type.md docs/api/waypoint.md
```

The new page should preserve every example and every important note from the four pages being deleted, plus the existing targets / designations content from the current `constants.md`. Nothing of value gets lost.

- [ ] **Step 2: Write the new `docs/api/constants.md`**

Structure:

```markdown
# `sms.constants` (alias `sms.K`) — every wire-format constant

`sms.constants` is the single namespace for every DCS enum-shaped value the
framework knows about: countries, coalitions, categories, skill levels,
waypoint types and actions, ROE / alarm state / formation strings, target
attribute strings, FAC designations, plus the auto-generated unit and
static catalogs.

`sms.K` is an alias for `sms.constants` — the long form works too, but
every example below uses `sms.K` because it's what the framework's own
internals use.

Mission code uses `sms.K.<topic>.<KEY>` instead of magic strings:

```lua
sms.group.create({
  country  = sms.K.countries.USA,
  category = sms.K.category.AIRPLANE,
  units    = { {type = sms.K.units.planes.F_16C_50, skill = sms.K.skill.AVERAGE} },
  ...
})
```

Autocomplete in any LuaCATS-aware editor lists every member; a typo
(`sms.K.skill.AVERAGEX`) is a static type error rather than a silent
runtime failure when DCS receives a bogus string.

[... per-topic sections, in this order:]

## `sms.K.coalition`
## `sms.K.category`
## `sms.K.countries`
## `sms.K.skill`
## `sms.K.alt_type`
## `sms.K.waypoint.type`
## `sms.K.waypoint.action`
## `sms.K.targets`
## `sms.K.designations`
## `sms.K.roe`
## `sms.K.alarm_state`
## `sms.K.reaction_on_threat`
## `sms.K.radar_using`
## `sms.K.flare_using`
## `sms.K.formation`
## `sms.K.units` (see `units.md` for catalog navigation)
## `sms.K.statics` (see `statics.md` for catalog navigation)
```

For each topic section: a one-paragraph blurb on what it is and where it's used, an exhaustive table of `KEY → "wire string" → notes`, plus a runnable example showing the constant in a real call site.

For `coalition` and `category`, the example shows assignment to a spawn config (`country`, `category`, the `coalition` returned by `sms.unit:get_coalition()`). For `countries`, the example shows `sms.group.create` with the constant. For `skill` / `alt_type`, the existing examples in `skill.md` / `alt_type.md` carry over verbatim with the namespace updated. For `waypoint.type` / `waypoint.action`, carry over the table from `waypoint.md` and update the namespace.

For ROE / alarm-state / formation / etc., the example shows the option-builder receiving the constant: `cap:set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))`.

For targets / designations, the existing constants.md content carries over with the `sms.targets.AIR` → `sms.K.targets.AIR` and `sms.designations.LASER` → `sms.K.designations.LASER` rewrite.

For `units` / `statics`, the section is a one-paragraph pointer: "the catalog is auto-generated from dcs-lua-datamine; see `units.md` for navigation patterns and `origin_of`."

The new page is expected to be ~400-600 lines depending on how exhaustive each table is. Length is fine — completeness beats brevity here, the page is reference material.

- [ ] **Step 3: Delete the four obsolete pages**

```bash
git rm docs/api/countries.md docs/api/skill.md docs/api/alt_type.md docs/api/waypoint.md
```

- [ ] **Step 4: Update `docs/api/units.md`** (catalog navigation page)

Find every reference to `sms.units.<...>` and rewrite to `sms.K.units.<...>`. The page structure (overview + nested category navigation + `origin_of` example) is unchanged. Add one cross-link near the top: "see `constants.md` for the unified `sms.K` reference".

- [ ] **Step 5: Update `docs/api/statics.md`** — same recipe as units.md.

- [ ] **Step 6: Verify no orphaned links**

```bash
grep -rn 'countries\.md\|skill\.md\|alt_type\.md\|waypoint\.md' docs/
```

Any link to one of the deleted pages → repoint at `constants.md` (with anchor if useful).

- [ ] **Step 7: Commit**

```bash
git add docs/api/constants.md docs/api/units.md docs/api/statics.md
git rm docs/api/countries.md docs/api/skill.md docs/api/alt_type.md docs/api/waypoint.md
git commit -m "docs(api): unify enum reference pages into constants.md (drop countries.md/skill.md/alt_type.md/waypoint.md)"
```

---

### Task 9: Sweep `docs/api/*.md` example code

Every Lua snippet in the remaining doc pages currently uses raw strings for fields that now have constants. Sweep each page to show idiomatic post-refactor mission code.

**Files:**
- Modify: `docs/api/examples.md` (most heavily affected — multiple recipes with country/category/coalition/skill literals)
- Modify: `docs/api/group.md` (spawn examples)
- Modify: `docs/api/static.md` (static spawn examples)
- Modify: `docs/api/task.md` (task examples may have category / coalition literals)
- Modify: `docs/api/commands.md` (callsign / freq examples — most are unaffected; verify)
- Modify: `docs/api/options.md` (every `sms.options.roe("weapon_free")` → `sms.options.roe(sms.K.roe.WEAPON_FREE)`)
- Modify: `docs/api/events.md` (any spawn examples in the event docs)
- Modify: `docs/api/utils.md` (the `coalition_int_to_str` and `resolve_country` examples may have raw strings)
- Modify: `docs/api/area.md`, `docs/api/timer.md`, `docs/api/rule.md`, `docs/api/log.md`, `docs/api/weapon.md`, `docs/api/unit.md` — re-grep to find any remaining raw strings; many will have nothing to do.

- [ ] **Step 1: Locate every raw-string usage**

```bash
grep -rn 'country\s*=\s*"\|category\s*=\s*"\|coalition\s*=\s*"\|skill\s*=\s*"\|alt_type\s*=\s*"\|"BARO"\|"RADIO"\|"airplane"\|"helicopter"\|"ground"\|"ship"\|"red"\|"blue"\|"neutral"' docs/api/*.md
```

(This pulls in some prose hits — sweep is for code blocks only. Walk the list and edit only Lua snippets, not prose tables.)

- [ ] **Step 2: Walk each page and rewrite Lua snippets**

For each file with hits:

- Lua code blocks (between ```` ```lua ```` and ```` ``` ````): every raw-string assignment that has a constant — rewrite to `sms.K.<topic>.<KEY>`.
- Prose tables and inline-code references that *describe* the wire format: leave the literal string (e.g. "`category` is a lowercase string: `\"airplane\"`, `\"helicopter\"`, ..."), but add a sentence pointing readers to `sms.K.category.*` for authoring.

Examples of the rewrite shape, drawn from the survey:

`docs/api/examples.md`:
```diff
-  category = "airplane",
+  category = sms.K.category.AIRPLANE,
```

`docs/api/group.md`:
```diff
-  country  = "USA",
-  category = "ground",
+  country  = sms.K.countries.USA,
+  category = sms.K.category.GROUND,
```

`docs/api/options.md`:
```diff
-cap:set_option(sms.options.roe("weapon_free"))
+cap:set_option(sms.options.roe(sms.K.roe.WEAPON_FREE))
```

`docs/api/events.md`:
```diff
-  country  = "Russia",
-  category = "ground",
+  country  = sms.K.countries.RUSSIA,
+  category = sms.K.category.GROUND,
```

(Note: `"Russia"` mixed-case in events.md is a separate case — `resolve_country` is case-insensitive so it works at runtime, but the constant is `RUSSIA` (upper-snake). The sweep prefers the constant.)

`docs/api/utils.md` `resolve_country` example:
```diff
-  country  = "russia",
+  country  = sms.K.countries.RUSSIA,
```

(The `resolve_country` page should also keep one example showing case-insensitive raw-string usage, with a sentence "for authoring code, prefer the constant".)

- [ ] **Step 3: Re-grep to confirm sweep coverage**

```bash
grep -rn '```lua' docs/api/*.md | xargs -I {} sh -c 'echo {}'  # locate code blocks
grep -rn 'country\s*=\s*"\|category\s*=\s*"\|coalition\s*=\s*"\|skill\s*=\s*"\|alt_type\s*=\s*"' docs/api/*.md
```

Expected after sweep: zero hits inside Lua code blocks. Prose hits are acceptable when they describe the wire format.

- [ ] **Step 4: Commit**

```bash
git add docs/api/examples.md docs/api/group.md docs/api/static.md docs/api/options.md docs/api/events.md docs/api/utils.md docs/api/task.md docs/api/commands.md
# Plus any other pages where sweep found hits — implementer adds based on grep output.
git commit -m "docs(api): sweep example Lua to use sms.K constants"
```

---

### Task 10: Update `docs/api/README.md` module index

The module-index table currently has eight rows for the enum-shaped modules. Replace with one row pointing at `constants.md`. The auto-generated catalog rows for `units.md` / `statics.md` stay (they're navigation pages, not constants reference). The `sms.targets` / `sms.designations` rows that pointed at `constants.md` get folded in.

**Files:**
- Modify: `docs/api/README.md`

- [ ] **Step 1: Find the module-index table in `docs/api/README.md`**

It's the table starting with `| Page | Module(s) | Summary |`. Today it has rows for: `task`, `commands`, `options`, `group`, `unit`, `static`, `countries`, `skill`, `alt_type`, `waypoint`, `area`, `weapon`, `events`, `timer`, `rule`, `utils`, `log`, `constants`, `examples`. That's 19 rows.

- [ ] **Step 2: Rewrite the table**

Drop these four rows entirely:
- `[countries.md](countries.md) | sms.countries | ...`
- `[skill.md](skill.md) | sms.skill | ...`
- `[alt_type.md](alt_type.md) | sms.alt_type | ...`
- `[waypoint.md](waypoint.md) | sms.waypoint | ...`

Rewrite the existing `constants` row to cover the consolidated namespace:

```markdown
| [`constants.md`](constants.md) | `sms.constants` (alias `sms.K`) | Single namespace for every DCS wire-format constant: countries, coalitions, categories, skill levels, waypoint types/actions, ROE / alarm-state / formation strings, target attributes, FAC designations. Also covers `sms.K.units` / `sms.K.statics` (catalogs auto-generated from dcs-lua-datamine; see `units.md` / `statics.md` for catalog navigation). |
```

Keep the `units.md` and `statics.md` rows as catalog navigation pointers — they stay as separate pages because they describe how to walk a 1500-line nested catalog, not "here's the list of values".

- [ ] **Step 3: Commit**

```bash
git add docs/api/README.md
git commit -m "docs(api): collapse module index to single sms.K row"
```

---

### Task 11: Update `AGENTS.md` §4 conventions and §7 module index

Final task. AGENTS.md is the orientation document — drift here costs time on every future agent invocation. Two edits.

**Files:**
- Modify: `AGENTS.md` (§4 Conventions table — coalition + category rows; §7 Module index — collapse eight enum rows into one)

- [ ] **Step 1: Update AGENTS.md §4 Coalition + Categories rows**

Find the conventions table (around line 108). Today's rows for coalitions and categories are:

```markdown
| **Coalition strings** | Lowercase: `"red"`, `"blue"`, `"neutral"`. (DCS internally uses `0/1/2` — never expose these.) |
| **Categories** | Lowercase: `"ground"`, `"airplane"`, `"helicopter"`, `"ship"`, `"train"`. |
```

Rewrite to:

```markdown
| **Coalition strings** | DCS wire format is lowercase `"red"` / `"blue"` / `"neutral"` — exposed as `sms.K.coalition.RED` / `BLUE` / `NEUTRAL`. (DCS internally uses `0/1/2` — never expose these.) |
| **Categories** | DCS wire format is lowercase `"airplane"` / `"helicopter"` / `"ground"` / `"ship"` / `"train"` — exposed as `sms.K.category.AIRPLANE` / `HELICOPTER` / `GROUND` / `SHIP` / `TRAIN`. |
```

The wire-format strings stay visible because debugging `dcs.log` needs them; the constant is the recommended authoring form.

- [ ] **Step 2: Update AGENTS.md §7 Module index**

Find the module-index table (around line 205). Today it has rows for: `sms` (root), `sms.log`, `sms.utils`, `sms.units`, `sms.statics`, `sms.countries`, `sms.skill`, `sms.alt_type`, `sms.waypoint`, `sms.targets`, `sms.designations`, `sms.group`, `sms.unit`, `sms.area`, `sms.timer`, `sms.rule`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`, `sms.commands`, `sms.options`. Twenty-two rows.

Drop these eight rows entirely:
- `sms.units`
- `sms.statics`
- `sms.countries`
- `sms.skill`
- `sms.alt_type`
- `sms.waypoint`
- `sms.targets`
- `sms.designations`

Insert a single replacement row in the position where the old enum rows were (after `sms.utils`, before `sms.group`):

```markdown
| `sms.constants` (alias `sms.K`) | `constants.lua` + `constants/*.lua` | [`docs/api/constants.md`](docs/api/constants.md) | Single namespace for every wire-format constant: `sms.K.coalition`, `sms.K.category`, `sms.K.countries`, `sms.K.skill`, `sms.K.alt_type`, `sms.K.waypoint.type` / `.action`, `sms.K.targets`, `sms.K.designations`, `sms.K.roe` / `alarm_state` / `formation` / `reaction_on_threat` / `radar_using` / `flare_using`, plus the auto-generated `sms.K.units` and `sms.K.statics` catalogs (`origin_of` helpers preserved). |
```

After this edit the table has 15 rows.

- [ ] **Step 3: Update AGENTS.md §6 Loading order paragraph**

§6 currently says:

> The bridge currently loads framework files via `net.dostring_in` in this order:
>
> ```
> sms.lua → log.lua → utils.lua → targets.lua → designations.lua → group.lua → unit.lua → area.lua → timer.lua → group_spawn.lua → static.lua → events.lua → weapon.lua → task.lua → commands.lua → options.lua
> ```

Rewrite the chain to reflect post-refactor reality:

```
sms.lua → log.lua → utils.lua → constants.lua (which dofiles every framework/constants/*.lua) → group.lua → unit.lua → area.lua → timer.lua → rule.lua → group_spawn.lua → static.lua → events.lua → weapon.lua → task.lua → commands.lua → options.lua
```

(Also adds `rule.lua` which was missing from the §6 chain — it's been in `load_all.lua` for a while.)

- [ ] **Step 4: Verify AGENTS.md cross-links still resolve**

```bash
grep -n 'docs/api/' AGENTS.md
```

Expected: every link points at a file that still exists. Anything pointing at the now-deleted `countries.md` / `skill.md` / `alt_type.md` / `waypoint.md` should already have been updated by Task 8's link-pointer review, but re-confirm.

- [ ] **Step 5: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): reframe §4 coalition/category rows; collapse §7 enum rows under sms.K"
```

---

## Done.

After Task 11, the framework's public surface has exactly one `sms.constants` namespace (alias `sms.K`) holding every wire-format constant, the obsolete standalone modules are gone, the docs / smoke tests / framework internals all reference `sms.K.*`, AGENTS.md and `docs/api/README.md` reflect the new shape, and the auto-generators write to the new path. The `/bring-it-home` step (separate user invocation) handles merge / PR / cleanup.
