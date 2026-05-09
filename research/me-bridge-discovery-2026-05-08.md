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

## save survival requires `fixWaypointForGroup` post-injection
**Tag:** command-worthy (now mandatory in the canonical injection sequence)
**Touches:** `Mission.fixWaypointForGroup`, `me_route.lua:2413` (the crash site), save→reload lifecycle
**Snippet:**
```lua
-- Add as the LAST step of the inject helper, after create_group_map_objects.
if type(Mission.fixWaypointForGroup) == "function" then
  pcall(Mission.fixWaypointForGroup, g)
end
```
**Notes:**
- Without this, **save hangs and corrupts the .miz**, requiring a DCS restart to recover.
- The lifecycle ED expects: load-from-.miz puts `wpt.type = "Turning Point"` (string) and `wpt.action = "Turning Point"` (string) into the in-memory waypoint. Then `fixWaypointForGroup` runs as part of load and **transforms `wpt.type` into a TABLE `{type="...", action="..."}` and clears `wpt.action`**. From that point forward, the in-memory waypoint's `type` is a table and `action` is nil. Save reads via `s.type.type` and `s.type.action` (`me_mission.lua:4035-4036` in `unload_air_groups`).
- Our injection (which built the waypoint with string `type`+`action`) skipped that fix, leaving the waypoint in the post-load shape ED never expects to see at save time. Save's `unload_air_groups` reads `s.type.type` (string-indexes a string, silently returns nil), writes nil/nil to disk, then save's post-write reload chokes at `me_route.lua:2413` doing `nil .. ':' .. nil`.
- **Save's post-write reload** — confirmed: `save_mission` writes the .miz, then calls `load(fName)` to verify integrity. Both write AND verify-reload must succeed for save to complete.
- Validated end-to-end: F-16 CAP injected with the fix, File > Save As completes cleanly, saved .miz reopens with the F-16 intact and clickable.

## delete groups via `Mission.remove_group` — iterate-collect-then-remove
**Tag:** command-worthy
**Touches:** `Mission.remove_group(group_obj)` — takes the full group object, not an id
**Snippet:**
```lua
-- Collect first (mutating-while-iterating coalition.<side>.country.<cat>.group is unsafe)
local groups = {}
for _, side in pairs(m.coalition) do
  if type(side) == "table" and side.country then
    for _, country in ipairs(side.country) do
      for _, cat in ipairs({ "plane", "helicopter", "vehicle", "ship", "static" }) do
        if country[cat] and country[cat].group then
          for _, g in ipairs(country[cat].group) do table.insert(groups, g) end
        end
      end
    end
  end
end
-- Then remove
for _, g in ipairs(groups) do pcall(Mission.remove_group, g) end
```
**Notes:**
- Validated by clearing 2 spawned groups (Hawk site + F-16 flight) — both gone, map empty, `coalition.<side>.country[N].<cat>.group` arrays empty, no errors.
- **groupIds and unitIds are NOT reused after delete** — they increment monotonically. After deleting groupId 1 (Hawk) and 2 (F-16) and re-spawning, the new groups got groupId 3 and 4. Worth noting in CLI documentation so users don't expect a freshly-allocated mission to start at id=1 if anything's been deleted.
- Per-side / per-category iteration uses the same coalition-tree walk we already do for `me group list`. Filter combinations work as expected.

## option command runtime semantics confirmed
**Tag:** confirms the proposal §2.11 mappings
**Touches:** WrappedAction[Option] in waypoint task array
**Notes:**
- **Alarm State (name=9):** `value=1` (Green) → radars off, no engagement, even when targets fly directly overhead. `value=2` (Red) → radars active, engages overflying enemies. Confirmed by spawning the same Hawk site setup twice, only changing this option, and observing engagement behavior. Both runtime-active during mission run.
- **ROE (name=0):** `value=0` (Weapons Free) — engages everything in range. `value=4` (Weapon Hold) — defensive only. Both runtime-active.
- F-16 overflight scenario validated: 4×F-16C_50 at 23000ft passing directly over Hawk site, alarm Green / ROE Hold → unmolested overflight; alarm Red / ROE Free → Hawk lit them up and engaged.
- Combined "natural-language test" (red coalition + multi-unit air + multi-waypoint route + ground option commands + save survival) all in one shot — proves the canonical injection sequence handles the full command-surface scope.

## bridge response timeout — 15s sometimes not enough
**Tag:** needs-more
**Touches:** CLI `--timeout` default
**Notes:** Spawning a complex group (full task array + options + payload) with `--timeout 15s` timed out client-side, but `dcs-sms.exe status` immediately after showed the request had been processed (inbox empty, group present). Default `--timeout 5s` and even `15s` is sometimes too short; bumping to `30s` for non-trivial spawns is reasonable. Suspected cause: bridge polls inbox every ~30 UpdateManager ticks and the ME may stutter during heavy operations. Worth investigating whether to (a) raise the CLI default timeout, (b) tighten the bridge poll interval, or (c) leave as-is and document.

## land vs water at a coordinate
**Tag:** command-worthy
**Touches:** `terrain.GetSurfaceType`
**Snippet:**
```lua
return terrain.GetSurfaceType(x, y)  -- "land" or "sea"
```
**Notes:** Mission-table coords (x = N–S, y = E–W). Returns lowercase string. Sea returns `terrain.GetHeight = 0`. Other surface kinds (`shallow_water`, `road`, `runway`) likely also returnable but only `"land"` and `"sea"` observed during the Akrotiri probe sweep (peninsula, surrounding sea, salt-lake region). `terrain` and `Terrain` (capitalized) are the same table — pick one for consistency.

## terrain height at a coordinate
**Tag:** command-worthy
**Touches:** `terrain.GetHeight`, `terrain.GetSurfaceHeightWithSeabed`
**Snippet:**
```lua
local h = terrain.GetHeight(x, y)                       -- meters above sea level
local h_surf, depth = terrain.GetSurfaceHeightWithSeabed(x, y)  -- includes seabed depth (depth = 0 over land)
```
**Notes:** Mission-table coords. `GetHeight` returns 0 over sea (it's the surface above the water). For underwater bathymetry use `GetSurfaceHeightWithSeabed` — second return value is depth in meters (0 over land). Akrotiri runway = 21m, Cypriot peninsula = ~8m, hills 15km N = 125m, mountains 25km N = 479m.

## slope / placement validity (the ME's own steep-slope check)
**Tag:** command-worthy
**Touches:** `MapWindow.isValidSurfacePro`, `MapWindow.isValidSurface`, `MapWindow.checkSurface`, `MapWindow.findValidStrikePoint`
**Snippet:**
```lua
-- ME's "is this surface flat enough for a ground unit" check, with footprint:
local ok = MapWindow.isValidSurfacePro(angle_deg, footprint_m, x, y, 'land')
-- Used internally for VTOL helicopter takeoff at me_map_window.lua:3338
-- with angle=5°, footprint = max(wing_span, length) — same threshold ED uses
-- to draw the steep-slope warning icon.

-- Pure height-delta variant (no surface-type filter):
local flat = MapWindow.isValidSurface(delta_m, side_m, x, y)

-- "Find me a valid land/water spot near (x, y)" — spirals out until found:
local vx, vy = MapWindow.findValidStrikePoint(x, y, {'land'}, 50, nil)
```
**Notes:**
- Returns true at runway, peninsula, 5km-15km N (low rolling hills) for 5°/30m. Returns false at 25km N (479m mountains) for 5°/30m — confirms it correctly detects steep slopes.
- The 'land' filter combined with isValidSurfacePro's slope check is what the ME uses for the icon you see when placing a unit on a too-steep surface — confirmed by reading me_map_window.lua:3298–3368 (`checkSurface`).
- `isValidSurface(delta, side, x, y)` is height-delta-only: max height variation within a `side × side` square must be ≤ `delta`. No surface type check.
- `findValidStrikePoint(x, y, surfTypes, offset, minDepth)` is the "snap to valid spot" used internally by ME's strike-target placement. Useful for "make this anchor placeable" upstream of an injection. Returns `nil, nil` if nothing valid found in 200 spiral rings (huge search radius — safe to assume it'll find something).

## scenery objects (buildings, walls, wires) at/near a coordinate
**Tag:** command-worthy
**Touches:** `terrain.getObjectsAtMapPoint`
**Snippet:**
```lua
-- Single-point query — only returns objects whose AABB contains the point:
local objs = terrain.getObjectsAtMapPoint(x, y)
-- Returns nil OR a list of objects with rich metadata:
--   { id = "161786066",       -- string, persistent
--     model = "israel_block_building_05",  -- known model name
--     type = 65536,            -- numeric type code
--     center = { cx, cy },
--     boxMin = { mnx, mny }, boxMax = { mxx, mxy },
--     sizeOBB = { dx, dy }, radius = 13.3, rotation = 0.077 }

-- Radius scan (necessary — single-point misses nearby objects):
local function scenery_in_radius(x, y, radius, step)
  step = step or 15
  local seen = {}
  for dx = -radius, radius, step do
    for dy = -radius, radius, step do
      if dx*dx + dy*dy <= radius*radius then
        local objs = terrain.getObjectsAtMapPoint(x + dx, y + dy)
        if type(objs) == 'table' then
          for _, o in ipairs(objs) do
            if o.id and not seen[o.id] then seen[o.id] = o end
          end
        end
      end
    end
  end
  local list = {}
  for _, o in pairs(seen) do table.insert(list, o) end
  return list
end
```
**Notes:**
- Detects: buildings (e.g. `israel_block_building_05`, `village_house_02`, `israel_city_house_03`), small statics (`cafe_umbrella`), and infrastructure (`wire` for power lines).
- **Does NOT detect trees / forests** — see the next entry.
- Use `step <= radius_of_smallest_object_you_care_about`. Buildings have radii ~13–20m so step=15 is fine for buildings; for catching `wire`-type small objects use step=5–8.
- Performance: ~50µs per call. A 250m × 25m-step radius scan (≈80 probes) finishes in ~4ms; full SAM-site sweep across 31 candidates × 80 probes ≈ 50ms.

## terrain LOS (terrain-only, NOT scenery / trees)
**Tag:** command-worthy
**Touches:** `terrain.isVisible`
**Snippet:**
```lua
-- 3D coords with altitude in the middle: (x, alt, y, x2, alt2, y2)
local ok = terrain.isVisible(x1, alt1, y1, x2, alt2, y2)
```
**Notes:** Returns true if a straight line between the two points is unobstructed by the terrain mesh. Does NOT account for buildings, walls, or trees — those passing through the line do not block visibility per this API. Useful for ridge-masking checks ("is this peak visible from there"); useless for occlusion by scenery/vegetation. Mission-table x/y conventions; altitude is height above sea level (or above terrain — only differs by `terrain.GetHeight` either way).

## trees / forests are a script blind spot
**Tag:** confirmed limitation
**Touches:** every terrain-query API
**Notes:** Trees / forests are stored on the terrain mod as binary rasters (`Mods/terrains/<theatre>/*.surface5`, `*.sd5`) and are **not exposed to the script API at all**. Validated against three user-placed AAV7 units explicitly in tree cover (`in-forrest-1/2/3`):

| Probe | in-forrest-1 | in-forrest-2 | in-forrest-3 | Akrotiri runway (open) | 5km N (open) |
|---|---|---|---|---|---|
| `GetSurfaceType` | land | land | land | land | land |
| `isValidSurfacePro(5°, 30m, 'land')` | true | true | false (steep, 338m elev) | true | true |
| `getObjectsAtMapPoint` (80m radius, step=5) | 0 | 0 | 0 | 0 | 0 |
| `getCrossParam` | "" | "" | "" | "" | "" |
| `getTerrainShpare` | "FLAT" | "FLAT" | "FLAT" | "FLAT" | "FLAT" |
| 8-direction LOS sweep, blocked rays @ 25–100m, h=0.5–10m | all 0 | all 0 | small (terrain undulation) | all 0 | all 0 |

The forest spots are **indistinguishable** from the open controls across every API. `in-forrest-3`'s minor LOS-blocking is from terrain undulation at 338m elevation, not vegetation — same signature you'd see at any rough-terrain spot.

The ME's own placement code (`MapWindow.checkSurface` at me_map_window.lua:3298) does NOT check for trees either — it only filters on surface type and slope. ED is consistent: the editor will silently let you place a unit inside a forest with no warning. The user-recalled steep-slope icon **is** the slope check (isValidSurfacePro), not a forest check.

**Workarounds for "avoid trees" placement:**
1. **User-in-the-loop**: framework returns top-N candidates ranked by surface/slope/clear-radius; user visually picks. Pragmatic, low cost, what humans do anyway.
2. **Larger safety margins**: require a 300–500m clear-radius and accept candidates may sit in a small clearing inside a forest.
3. **Pre-built forest mask per theatre**: extract from `.surface5` (binary, undocumented format — see `surface5-extraction` entry if/when reverse-engineered) or screenshot-color-sample the ME map view; ship as JSON. Brittle to DCS updates and theatre-specific.
4. **Mission-play probe via `world.searchObjects(Object.Category.SCENERY, ...)`** — only available in mission-env (not editor). Untested whether trees are SCENERY-categorized at runtime; DCS docs imply they are not.

## terrain query functions that look useful but aren't
**Tag:** confirmed dead-end
**Touches:** `terrain.getCrossParam`, `terrain.getTerrainShpare`
**Notes:**
- `terrain.getCrossParam(x1, y1, x2, y2)` — name suggests "cross-country navigation parameter" but returned `""` for every line tested (over open land, over trees, over urban, over sea, zero-length, 30m, 100m, 1500m). Either takes a different arg shape or is meaningful only on theatres / surfaces we didn't probe. Not useful as a terrain-type discriminator.
- `terrain.getTerrainShpare(x, y)` — returned `"FLAT"` everywhere, including at sea, in cities, and on 479m mountain slopes. Probably unrelated to terrain category (perhaps render-LOD shape or similar). Not useful.

## Mission table coords for unit lookup
**Tag:** recipe
**Touches:** `me_mission.unit_by_name`, `me_mission.group_by_name`
**Snippet:**
```lua
-- Find units by name pattern (case-insensitive substring):
local mm = require('me_mission')
local matches = {}
local seen = {}
local function add(label, x, y, type) if not seen[label] then seen[label]=true; table.insert(matches, {name=label, x=x, y=y, type=type}) end end
for n, u in pairs(mm.unit_by_name or {}) do
  if string.find(string.lower(n), 'pattern') then add(n, u.x, u.y, u.type) end
end
-- Some units may be missing from unit_by_name; group walk catches them:
for n, g in pairs(mm.group_by_name or {}) do
  if string.find(string.lower(n), 'pattern') and g.units and g.units[1] then
    add(n .. ' [via group]', g.units[1].x, g.units[1].y, g.units[1].type)
  end
end
```
**Notes:** During the in-forrest probe, one of three placed units was missing from `unit_by_name` — likely a stale-entry quirk after rename / undo / something. Walking `group_by_name` and falling back to `g.units[1]` caught it. Always do both for reliability.
