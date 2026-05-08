# ME bridge discovery — findings log

**Date:** 2026-05-08
**Method:** Live demo-driven probing via `dcs-sms exec --target gui`. See `docs/superpowers/specs/2026-05-08-me-discovery-session-design.md` for the framework.
**Theatre during session:** Syria (will note theatre per finding if it matters).

## Tag legend

- **command-worthy** — Recurring pattern. Promote to native `dcs-sms me <verb>` in a follow-up spec.
- **recipe** — Useful but specialized. Stays as a documented snippet for future agents.
- **needs-more** — Hit something interesting; didn't fully crack it. Revisit.

---

<!-- New findings appended below this line. -->

## get the open theatre name
**Tag:** command-worthy
**Touches:** `Mission.TheatreOfWarData`
**Snippet:**
```lua
return require('Mission.TheatreOfWarData').getName()
```
**Notes:** Returns e.g. `"Syria"`. Standard accessor used internally by ED at mission save and prefab capture.

## find an airbase by name
**Tag:** command-worthy
**Touches:** `Mission.AirdromeController`, airdrome instance fields
**Snippet:**
```lua
local AC = require('Mission.AirdromeController')
for _, ad in ipairs(AC.getAirdromes() or {}) do
  if ad:getName() == 'Akrotiri' then
    return { x = ad.x, y = ad.y, id = ad:getAirdromeNumber(), coalition = ad:getCoalitionName() }
  end
end
```
**Notes:** Position lives on the airdrome as bare `.x` / `.y` fields (NOT `getRefPoint`/`getPosition` — those are nil on the class). Methods available: `getName, getAirdromeNumber, getCoalitionName, getAngle, getHeight, getBounds, getFrequencyList, getFueldepots, getRoadnet, getWarehouses` (plus matching setters and `clone`/`construct`/`new`). `getBounds()` returned nil during testing — runway extents may live elsewhere.

## place a saved prefab at coordinates
**Tag:** command-worthy
**Touches:** `dcs_sms_me.prefab_ops`, prefab files in `<SavedGames>/DCS/dcs-sms/prefabs/*.prefab`
**Snippet:**
```lua
local prefab_ops = require('dcs_sms_me.prefab_ops')
local writedir = lfs.writedir():gsub("\\", "/")
local path = writedir .. "dcs-sms/prefabs/<prefab-name>.prefab"
local prefab, err = prefab_ops.load(path)
if not prefab then return { error = err } end
local record, err2 = prefab_ops.place(prefab, { anchor = { x = X, y = Y }, rotation = 0 })
return { ok = record ~= nil, err = err2, groups = record and #record.groups or 0 }
```
**Notes:** Forward slashes in path avoid `\b` and similar escape disasters. `place` returns a "record" that the prefab manager uses for undo. Prefab can be from a different theatre — geometry transforms relative to anchor.

## spawn a single unit / group from scratch (broken)
**Tag:** needs-more
**Touches:** `me_mission.create_group`, `me_mission.insert_unit`, `me_mission.create_group_objects`, `me_mission.create_group_map_objects`
**Snippet:**
```lua
-- THIS WORKS PARTIALLY but produces a malformed group (missing waypoint name/type/speed UI fields).
local g = me_mission.create_group('USA', 'plane', 'F-16C Akrotiri', nil, true, 251, 0, x, y, 'F-16C_50')
local u = me_mission.insert_unit(g, 'F-16C_50', 'Average', 1, 'F-16C #001', x, y, 0, nil, nil)
table.insert(g.route.points, { x=x, y=y, alt=1524, alt_type='BARO', speed=220, action='Turning Point', type='Turning Point', ETA=0, ETA_locked=true, formation_template='', task={id='ComboTask', params={tasks={}}} })
pcall(me_mission.create_group_objects, g)
pcall(me_mission.create_group_map_objects, g)
```
**Notes:** Group appears on map but the waypoint UI is partially blank when selected. The minimum required fields beyond what we set above are unclear. **This is the case that motivates the reference-mission strategy** — instead of synthesizing the group, copy a known-good example. Re-attempt by extracting a CAP F-16 from the reference mission and using its full structure as the template.

## load a .miz programmatically (File > Open)
**Tag:** command-worthy
**Touches:** `me_toolbar.loadMission`, `module_mission.load`, `module_mission.removeMission`, `progressBar.setUpdateFunction`
**Snippet:**
```lua
local me_toolbar = require('me_toolbar')
me_toolbar.loadMission('D:/git/honu/empty_miz_to_load.miz')  -- forward slashes!
```
**Notes:** Use forward slashes in the path to avoid the shell-to-JSON-to-Lua escape stack mangling backslashes. The call is **asynchronous**: `loadMission` schedules the actual `module_mission.load(filename)` via `progressBar.setUpdateFunction`, which fires on a later UpdateManager tick. A snippet that calls `loadMission` and then immediately reads `module_mission.mission` will see the post-teardown / pre-reload state (often just `{bullseye=...}`). To verify the load succeeded, either (a) re-probe the mission table on a follow-up tick, or (b) wait for `module_mission.getMissionPathIsSaved()` / `MeSettings.getMissionPath()` to reflect the new file. Implementation source: `me_toolbar.lua:595–629`.

## "make a new mission on Syria" — partial finding
**Tag:** needs-more
**Touches:** `Mission.CoalitionController`, `me_toolbar.createMission`, `module_mission.create_new_mission`
**Snippet:**
```lua
-- Calling these from an isEmptyME=true state opens the New Mission Settings UI dialog
-- but does NOT create the mission programmatically.
local CC = require('Mission.CoalitionController')
CC.setDefaultCoalitions()
CC.showPanel(nil, 'Syria')  -- shows the picker UI; user must click OK
```
**Notes:** `me_toolbar.createMission(returnScreen, terrain)` is the user-flow entry point but (a) shows a confirmation dialog when there's unsaved work, (b) calls `showPanel` which opens UI rather than creating. `module_mission.create_new_mission(true)` resets the mission table but errors deep in `me_weather.lua:2162` (`SW_bound nil`) when called from an `isEmptyME=true` state — `me_weather.initModule` expects MapWindow data that doesn't exist yet. Workaround for now: load a known-empty .miz via `me_toolbar.loadMission(path)` instead of trying to create a fresh empty mission programmatically. Full programmatic "new mission" needs more probing — likely the `CoalitionController` panel's OK-button handler is the function we want, or a dedicated `applyAndCreate` somewhere we haven't traced.

## DCS ME coordinate axes (critical correction)
**Tag:** command-worthy
**Touches:** every spawn / move / position command
**Notes:** In the ME `mission` table, **`x` = North–South (north positive)** and **`y` = East–West (east positive)**. This contradicts the assumption baked into the proposal v1 (which described coords as "meters in DCS map space" without axis specifics). To go *north* of an anchor, increase `x`. To go *east*, increase `y`. Altitude is `alt` (a separate field) — there is no `z` at the mission-table level. Confirmed by visually observing a spawn that was supposed to be 9km north of Akrotiri and instead landed 9km east — the mistake was offsetting `y` thinking it was N-S. After swapping to offset `x`, the spawn appeared correctly north of the runway.

## inject a single group "ME-perfect" (template extraction works!)
**Tag:** command-worthy
**Touches:** `module_mission.{create_group_objects, create_group_map_objects, fixAddPropAircraft, getNewGroupId, getNewUnitId, check_group_name, getUnitName, group_by_name, group_by_id, unit_by_name, unit_by_id, countryCoalition}`, `prefab_ops.inject_group` as guide
**Snippet:**
```lua
-- Canonical sequence (mirrors prefab_ops.inject_group). Required because
-- create_group + insert_unit alone produces a malformed group with blank
-- waypoint UI (the "broken F-16" problem we started with).
--
-- All-or-nothing: skip any of these and the icon may render but the group
-- won't be selectable / Unit List window won't open / payload UI won't
-- populate / etc.

local Mission = module_mission

-- 1. Build the group table verbatim from a known-good source (e.g. extracted
--    from a reference miz on disk). Synthesizing from scratch will miss
--    fields the ME UI requires.
local g = { ...full group structure... }

-- 2. **REQUIRED:** group.type = "plane" | "helicopter" | "vehicle" | "ship" | "static"
--    me_units_list.applyFilter (line 91) does filters[group.type]; nil crashes
--    Unit List window setup. Mission table doesn't have this on disk-loaded
--    groups (the category is the container key) — this is a runtime field
--    set by the load path. Set it ourselves.
g.type = "plane"

-- 3. Translate to target position. ME uses x=N-S, y=E-W. Translate group.x/y,
--    units[*].x/y, route.points[*].x/y. Set alt on units + route points.

-- 4. Allocate fresh IDs.
g.groupId = Mission.getNewGroupId()
for _, u in ipairs(g.units) do u.unitId = Mission.getNewUnitId() end

-- 5. Reserve collision-safe names (only if not unique already).
g.name = Mission.check_group_name(g.name)
for _, u in ipairs(g.units) do u.name = Mission.getUnitName(g.name) end

-- 6. **Lookup table registration BEFORE create_group_objects.** Selection,
--    Unit List, and panel updates all read these.
Mission.group_by_name[g.name] = g
Mission.group_by_id[g.groupId] = g
for _, u in ipairs(g.units) do
  Mission.unit_by_name[u.name] = u
  Mission.unit_by_id[u.unitId] = u
end

-- 7. Boss back-references and color.
g.boss = target_country  -- the country table from m.coalition.<side>.country[N]
g.mapObjects = { units = {}, zones = {}, route = {} }  -- create_group_map_objects overwrites; harmless to pre-init
if Mission.countryCoalition[target_country.name] then
  g.color = Mission.countryCoalition[target_country.name].color
end
for _, u in ipairs(g.units) do u.boss = g end
for _, wpt in ipairs(g.route.points) do wpt.boss = g end

-- 8. **Defensive:** ensure country.boss = coalition. me_units_list.applyFilter
--    (line 88) does group.boss.boss.name; nil crashes the Unit List. Usually
--    set by mission load, but set defensively.
if not target_country.boss then target_country.boss = m.coalition.<side> end

-- 9. **Canonical insertion order** (do not deviate):
local ok = Mission.create_group_objects(g)              -- wires unit.boss/index, route.boss, wpt.boss/index
table.insert(target_country.plane.group, g)             -- THEN insert into mission table
local ok = Mission.create_group_map_objects(g)          -- THEN create map symbols
Mission.fixAddPropAircraft()                            -- fills F-16-style AddPropAircraft defaults
```
**Notes:**
- `create_group_objects` does NOT set `group.boss` — only `route.boss`, `wpt.boss`, `unit.boss`. We must set `group.boss = country` ourselves.
- `create_group_map_objects` **overwrites** `group.mapObjects` with `{units={}, zones={}}` (then adds `route` if `group.route` exists). Pre-init is decorative but harmless.
- `unit_symbol` insertion uses `unit.index` — `create_group_objects` sets this, so call create_group_objects first.
- The `mapObjects[<symbol_id>] = symbol_obj` table at module scope is the master rendering registry. `group.mapObjects.units[1]` etc. are per-group references back into that registry. Both get populated by `create_group_map_objects → insert_unit_symbol`.
- **Cross-airframe template swaps work:** taking the A-4E-C CAP shape verbatim and just changing `units[1].type = "F-16C_50"` (with `livery_id = ""` and `AddPropAircraft = nil`) produces a working F-16 CAP after `fixAddPropAircraft` runs. The F-16-specific `AddPropAircraft` keys (HMD, etc.) are populated by the fix.
- **Validation:** spawned F-16 CAP from A-4E-C template, ~9km north of Akrotiri at 3000m. Map icon visible, group selectable, Unit List window opens, payload panel populated, **mission ran successfully with the plane in-game**. Strategy proven end-to-end.

## multi-unit ground synthesis works (no template needed)
**Tag:** command-worthy
**Touches:** same as the single-unit injection — `Mission.{create_group_objects, create_group_map_objects, getNewGroupId, getNewUnitId, check_group_name, getUnitName, group_by_name, group_by_id, unit_by_name, unit_by_id}`
**Snippet:**
```lua
-- Synthesizing a 5-unit Hawk site from sms.K type names, with the canonical
-- injection sequence from probe #1, produces an "ME-perfect" multi-unit
-- ground group — selectable, in Unit List, runs in mission.
--
-- KEY LOOP-ORDERING FIX: getUnitName allocates a unique unit name by
-- inspecting unit_by_name. So each unit must be REGISTERED in unit_by_name
-- before the next unit's getUnitName call, otherwise all units get the same
-- name. Translation: the per-unit work — allocate id → name → register →
-- set boss → append to g.units — must happen in ONE loop body, not in
-- separate name-all/register-all passes.
for i, spec in ipairs(layout) do
  local u = { type = spec.type, name = "placeholder", unitId = Mission.getNewUnitId(), ... }
  u.name = Mission.getUnitName(g.name)              -- allocates name N
  Mission.unit_by_name[u.name] = u                  -- register THIS unit before next iteration
  Mission.unit_by_id[u.unitId] = u
  u.boss = g
  g.units[i] = u
end
```
**Notes:**
- Group shape used: `task = "Ground Nothing"`, single waypoint with `action = "Off Road"`, `speed = 0`, `speed_locked = true`, `task = { id = "ComboTask", params = { tasks = {} } }` (empty enroute tasks). All standard for stationary ground.
- Layout: 5 Hawk units (pcp, sr, tr, cwar, ln) in a +-shape, 50m spacing. Headings set per unit (radars facing center, etc.). x = N-S, y = E-W axes — same as everywhere.
- Confirmed end-to-end: 5 selectable units, Unit List shows all 5 distinct entries, mission runs and the SAM site comes alive (radars working, threat detection active).
- **Implication for the proposal:** `me group create vehicle --units "[type1,type2,...]"` synthesis can be implemented without `--from-template ref:samsite.<x>` for the common case. Templates are only needed when the GROUP SHAPE is rich (the broken-F-16 problem was about waypoint/task structure complexity, not unit-list complexity). For stationary ground sites with no waypoint tasks, synthesis suffices.
- **What we did NOT yet test:** synthesis of groups with rich waypoint tasks (FAC_AttackGroup, FireAtPoint, EngageTargets), multi-unit *air* groups (CAP flights with 2-4 aircraft), or groups with `formation_template` non-empty. Those may still need template extraction.

## bridge response timeout — 15s sometimes not enough
**Tag:** needs-more
**Touches:** CLI `--timeout` default
**Notes:** Spawning a complex group (full task array + options + payload) with `--timeout 15s` timed out client-side, but `dcs-sms.exe status` immediately after showed the request had been processed (inbox empty, group present). Default `--timeout 5s` and even `15s` is sometimes too short; bumping to `30s` for non-trivial spawns is reasonable. Suspected cause: bridge polls inbox every ~30 UpdateManager ticks and the ME may stutter during heavy operations. Worth investigating whether to (a) raise the CLI default timeout, (b) tighten the bridge poll interval, or (c) leave as-is and document.
