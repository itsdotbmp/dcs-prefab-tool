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
