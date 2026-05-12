## ME Prefab Manager — Parking Spot Preservation — Design

**Date:** 2026-05-07
**Status:** Brainstorm
**Scope:** Fix [#37](https://github.com/nielsvaes/dcs-sms/issues/37). The Prefab Manager's place pipeline currently strips parking-spot binding (`unit.parking`, `unit.parking_id`, `unit.parking_landing`, `unit.parking_landing_id`) on every placed unit and never re-establishes it, so a "Take Off From Ramp" aircraft saved at parking spot N spawns at a *different* spot at mission load. ME-mod-only — no change to the public `sms.*` runtime surface, no change to the on-disk prefab schema.

## Goal

When a user takes a prefab containing a "Take Off From Ramp" aircraft and places it at its original world anchor in a fresh mission, the aircraft must spawn at the same parking spot it was saved from. When the user places the same prefab at a different anchor (different airfield), the aircraft must be assigned to a free parking spot at the destination airfield (matching vanilla ME's copy/paste UX).

## User-visible bug today (verbatim from #37)

> spawned parked aircraft appear at the correct location in the editor, but do not spawn there in mission. It appears that the units have persisted their x/z coordinates, but not their parking space number. If you select and move the plane, it will snap to its assigned parking space (where it actually spawns in game)

Reported on me-mod v0.3.2 against DCS 2.9.26.23303.

## Non-goals

- **Cross-airfield parking-spot transplant.** If the user places a prefab at a *different* airfield than the one it was saved from, we do *not* try to map "Krasnodar parking 12" onto "Muwaffaq parking 12". v1 falls back to vanilla ME's `attractToAirfield` (closest free spot at the destination).
- **Runtime fix in `sms.*` framework.** This is an ME-mod placement bug, not a runtime/spawn bug. The framework `sms.spawn` paths handle aircraft units differently and are out of scope.
- **Changing the on-disk prefab schema.** The data we need (`parking`, `parking_id`, `parking_landing`, `parking_landing_id`) is *already* preserved by `prefab_distill.lua` (it never strips them); the bug is purely on the place side. No version bump on `meta.sms_prefab_version` is required.
- **Carrier-deck takeoffs.** Ship-deck-launched aircraft don't use airfield parking — they use `linkUnit` + `helipadId` and go through the existing Pass E (`prefab_ops.lua:1047-1073`). v1 leaves Pass E alone and only adds parking handling for non-linkUnit airfield waypoints.

## Root cause

Located by walking the place pipeline in `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` against vanilla ME's `me_copy_paste.lua` (`D:\Program Files\Eagle Dynamics\DCS World\MissionEditor\modules\me_copy_paste.lua`):

1. **Distill preserves the data.** `prefab_distill.lua` does not touch `parking*` fields. `grep parking tools/me-mod/lua/dcs_sms_me/prefab_distill.lua` returns zero hits.
2. **`_remap_ids` preserves the data.** It rewrites `unitId`, `groupId`, `linkUnit.unitId`, `helipadId`, `missionUnitId`, `airdromeId`, plus task-param ids. It does *not* touch `parking*` fields (`prefab_ops.lua:569`).
3. **`inject_group` unconditionally strips the data.** Lines 729-732:
   ```lua
   u.parking = nil
   u.parking_landing = nil
   u.parking_id = nil
   u.parking_landing_id = nil
   ```
   The comment on line 719 says "strip parking links" and explicitly mirrors `me_copy_paste.lua:331-334`, which does the same.
4. **Pass E (the linkWaypoint dance) does not re-attract.** Pass E only handles waypoints whose `linkUnit` resolves to an in-prefab unit (carrier-deck binding). Airfield-parking waypoints have no `linkUnit`, so Pass E skips them entirely.
5. **Vanilla ME's *next* step is missing.** After the linkWaypoint dance at lines 383-391, vanilla ME runs at lines 393-398:
   ```lua
   for k,wpt in base.pairs(group.route.points) do
       if base.panel_route.isAirfieldWaypoint(wpt.type) then
           wpt.airdromeId = nil
           base.panel_route.attractToAirfield(wpt, group)
       end
   end
   ```
   `panel_route.attractToAirfield` for a `takeOffParking` waypoint calls `mod_parking.setAirGroupOnAirport(group, wpt.x, wpt.y)` (`me_route.lua:489-493`), which assigns a parking spot at `(wpt.x, wpt.y)` and writes the resulting `parking`/`parking_id`/etc. back onto the unit.
6. **SMS calls neither.** `grep -E "attractToAirfield|isAirfieldWaypoint|panel_route" tools/me-mod` returns zero hits.

Effect at runtime:

- Editor display: `unit.x`/`unit.y` are still the prefab-saved values (which point at the original parking spot center on the source airfield). With no `parking_id`, ME just renders at those coordinates → "appears at correct location in the editor".
- Mission load: DCS sees `parking_id == nil` on a `takeOffParking` waypoint and runs its own attraction near `(wpt.x, wpt.y)`, which can pick a different free spot than the one the user originally chose → "does not spawn there in mission".
- Manual fix-up via select+drag: ME's drag handler at `me_map_window.lua:1843-1845` calls `attractToAirfield` on drop, performing the spot assignment that injection should have done → "snaps to its assigned parking space (where it actually spawns in game)".

## Why `parking_id` is safe to preserve verbatim

The discriminating question for "preserve" vs "always re-attract" is whether `parking_id` is stable across missions. It is. Evidence from `me_exportToMiz.lua:828-829` (vanilla ME):

```lua
unit.parking    = base.tostring(parking.crossroad_index)
unit.parking_id = parking.name
```

`parking.name` and `parking.crossroad_index` come from the airfield's parking table — part of the terrain definition, baked into the map. Same airfield ⇒ same parking-spot names in any mission. So preserving the source unit's `parking_id` and re-injecting it on a same-anchor place gives the *exact* original spot deterministically, with no reliance on `setAirGroupOnAirport`'s nearest-free-spot heuristic.

This is the same logic that already gates `keep_airdrome_ids` on `keep_position` in `_remap_ids` (`prefab_ops.lua:1002`): airfield-relative ids are only meaningful at the source airfield, which is only the destination when `keep_position == true`.

## Design — preserve-when-keep-position, re-attract otherwise

Two-pronged fix in `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua`. Both prongs are gated on the existing `opts.keep_position` flag — no new public surface.

### Prong 1 (the user's repro path): preserve parking fields when `keep_position == true`

Thread `keep_position` into `inject_group` and gate the parking-strip on it:

```lua
-- inject_group(group, ctx) where ctx = { keep_position = bool }
if not (ctx and ctx.keep_position) then
    u.parking = nil
    u.parking_landing = nil
    u.parking_id = nil
    u.parking_landing_id = nil
end
```

Effect: at the original anchor, the unit retains the source parking binding verbatim. DCS spawns at the recorded spot at mission load with no further work.

This composes correctly with the existing `keep_airdrome_ids` flag — `_remap_ids` already preserves `airdromeId` under the same condition, so the (airdromeId, parking_id) pair stays consistent.

### Prong 2 (placement at a new anchor OR pre-mid-2024 source data): mirror vanilla ME's `attractToAirfield` step

Around mid-2024 DCS started writing `unit.parking` and `unit.parking_id` on parked aircraft in saved missions. Missions saved before that change don't carry these fields, and ME does *not* migrate them at *load* time — only at *save* time (via `me_exportToMiz.fixMissionPlaneAndHel → setWPTtoAirport`). So a pre-mid-2024 `.miz` opened in current ME keeps the un-migrated shape in memory: the parked unit has a `TakeOffParking` waypoint and a last-drag `(x, y)` but no `parking_id`. Distilling the prefab from this in-memory state captures the un-migrated shape too — Prong 1 then has nothing to preserve.

The Pass F gate therefore fires when **either**:

- `opts.keep_position == false` — the source `parking_id` is meaningless at the destination airfield, so we re-attract regardless. *Or:*
- Any unit in the placed group has `parking_id == nil` *after* `inject_group` — the prefab is from an old (pre-mid-2024) source mission and we must migrate. `attractToAirfield` resolves the closest spot at the unit's `(x, y)`. For a ramp-start aircraft the last-drag `(x, y)` is typically within tens of meters of the intended spot (verified on the user's `mission_02.miz` 2024 source: pre-/post-resave delta ≈55 m), so it usually picks the spot the user originally chose. On a tight apron with adjacent parking it could pick a neighbour; there is no way to recover original intent perfectly when the source data never recorded it.

Concretely the gate becomes:

```lua
local needs_attract = (not opts.keep_position)
if not needs_attract and type(g.units) == 'table' then
    -- Modern prefabs: each unit in this group already carries parking_id.
    -- If ANY unit lacks one, this prefab is from a pre-mid-2024 mission
    -- that DCS never migrated in memory. Force attract to populate it.
    for _, u in pairs(g.units) do
        if type(u) == 'table' and not u.parking_id then
            needs_attract = true
            break
        end
    end
end
```

Then run a new Pass F *after* Pass E:

```lua
-- Pass F: airfield re-attraction. Mirrors me_copy_paste.lua:393-398.
-- Skipped on keep_position because Prong 1 already preserved the source binding.
if not opts.keep_position then
    local panel_route = (require 'me_route') -- vanilla ME global; see fallback below
    for _, p in ipairs(placeable) do
        local g = p.copy
        if type(g.route) == 'table' and type(g.route.points) == 'table' then
            for _, wpt in ipairs(g.route.points) do
                if panel_route and type(panel_route.isAirfieldWaypoint) == 'function'
                    and panel_route.isAirfieldWaypoint(wpt.type)
                then
                    wpt.airdromeId = nil
                    pcall(panel_route.attractToAirfield, wpt, g)
                end
            end
        end
    end
end
```

Notes:

- **Module name resolution.** `panel_route` in vanilla ME is a top-level local in modules like `me_copy_paste.lua` (assigned via `local panel_route = require('me_route')`). The resolution path in our pipeline is the same. We `pcall(require, 'me_route')` and degrade gracefully to "leave the waypoint as-is" if it isn't available — the user just gets the current (broken) behaviour rather than a Lua error.
- **Why skip waypoints with `linkUnit`.** `attractToAirfield` calls `module_mission.unlinkWaypoint(wpt)` (`me_route.lua:484`). For airfield waypoints with a `linkUnit` set, Pass E has already done a unlink/relink dance to bind the waypoint to a moving carrier deck. Re-running the unlink would clobber it. Guard Pass F to skip waypoints where `wpt.linkUnit ~= nil` after Pass E. (The check is "is `linkUnit` still a live table after Pass E?" — Pass E nils it on unresolved cross-prefab references, so the check `type(wpt.linkUnit) == 'table' and wpt.linkUnit.unitId` is appropriate.)
- **Pass F uses the live ME modules.** Unlike `_remap_ids` (pure data manipulation), Pass F calls live ME route logic that triggers a parking-spot allocation against the destination airfield. This is exactly what vanilla ME does in its own copy/paste; we are taking the same dependency.

### Why this is strictly better than "vanilla mirror always" (Prong 2 alone)

`setAirGroupOnAirport` picks the *nearest free* spot. That can drift from the original spot when:

- Another unit (placed manually before the prefab) already occupies the original spot.
- Multiple prefab units land near each other and contend for spots.
- DCS's nearest-free-spot heuristic disagrees with the user's intent for any other reason.

Prong 1 sidesteps all of these by writing the exact `parking_id` back. The user's bug repro (`keep_position == true`, placement at original anchor) hits Prong 1.

## Affected files (implementation surface)

- **`tools/me-mod/lua/dcs_sms_me/prefab_ops.lua`** — `inject_group` signature gains a `ctx` parameter; the parking-strip is gated; new Pass F appended after Pass E in `M.place`. Update the comment at lines 719-720 to describe the new conditional. Update the comment block at lines 1029-1046 to mention Pass F.
- **`tools/me-mod/lua/dcs_sms_me/version.lua`** — bump `0.3.2` → `0.3.3` (bugfix). Per [`AGENTS.md §4`](../../../AGENTS.md#4-versioning-and-releases) the in-source version bump rides in the same commit as the change.
- **`CHANGELOG.md`** — add a `me-mod v0.3.3` entry under the existing me-mod section: "fix(me-mod): preserve parking-spot binding for `Take Off From Ramp` aircraft on prefab placement (#37)".
- **No `AGENTS.md` change.** No public `sms.*` surface change.
- **No `docs/api/` change.** Same reason.
- **No prefab schema bump.** `meta.sms_prefab_version` stays at its current value because the on-disk format is unchanged — the data we now preserve was already written by older versions of the distiller.

## Compatibility — older prefabs

Two distinct "older" cases:

**1. Prefab made by me-mod ≤ v0.3.2 from a *current-DCS* source mission.** The prefab on disk *already contains* the parking fields on each unit (distill never stripped them). The fix simply stops discarding that data on the way in:

- Re-placing at original anchor in v0.3.3+ now correctly preserves parking. The bug retroactively fixes itself for previously-saved prefabs.
- Re-placing at a new anchor in v0.3.3+ uses Pass F (vanilla mirror) to assign a fresh spot — same result as a freshly-saved prefab placed elsewhere.

**2. Prefab made from a *pre-mid-2024* source mission (any me-mod version).** The on-disk prefab does *not* contain `parking_id` because the source mission didn't have it (DCS hadn't started writing parking_id yet) and ME doesn't auto-migrate at load. Prong 1 has nothing to preserve. Pass F's "any unit missing parking_id → force attract" condition kicks in and runs `panel_route.attractToAirfield` against the unit's last-drag `(x, y)`. Outcome:

- Aircraft spawn at a parking spot at the correct airfield, oriented to the spot's natural direction (DCS uses parking_id to derive the spawn heading).
- The chosen spot is the *nearest* one to the saved `(x, y)`, which is usually but not always the user's originally-intended spot. On a tight apron with adjacent parking the heuristic can pick a neighbour. The fast user-side workaround is "open the source mission in current DCS, File → Save, re-make the prefab" — that triggers ME's own `setWPTtoAirport` migration and embeds parking_id into the prefab data.

No data migration of the on-disk prefab format is needed in either case. The migration happens in-memory at place time.

## Test plan

Manual via ME because the bug is in the live ME UI dependency path. Steps reproduce #37 and verify the fix:

**Test A — Prong 1 (preserve at original anchor):**

1. Open a fresh mission on Caucasus. Place an Su-25 set to "Take Off From Ramp" at Krasnodar parking spot 12. Note the spot number.
2. Use SMS Prefab Manager to save it as a prefab with `keep_position = true`.
3. File > New, fresh mission, Caucasus.
4. Place the prefab via SMS (no anchor change).
5. **Expected:** unit appears at parking spot 12. Save mission, reopen, run from start: aircraft spawns at parking spot 12 (not a neighbouring spot).
6. **Pre-fix observed:** unit appears at correct *coordinates* in editor but spawns at a different free spot at mission start.

**Test B — Prong 2 (re-attract at new anchor):**

1. Take the prefab from Test A.
2. Place it at Krymsk (different airfield) instead.
3. **Expected:** unit attracts to a free Krymsk parking spot (vanilla ME copy/paste behaviour). Aircraft spawns at that spot at mission start.

**Test C — Pass F doesn't break carrier-deck takeoffs:**

1. Build a prefab containing a hornet set to "Take Off From Ramp" linked to a Stennis carrier (uses `linkUnit` + `helipadId`).
2. Place at original anchor (Prong 1 path) in a fresh mission. Expected: hornet starts on the Stennis deck.
3. Place at a new anchor (Prong 2 path) in another fresh mission. Pass F's `wpt.linkUnit` guard must skip the carrier waypoint so the unlink/relink dance from Pass E is preserved. Expected: hornet still starts on the Stennis deck.

**Test D — regression: non-aircraft prefabs unaffected.**

1. Place a vehicle / static prefab that has no airfield waypoints. Expected: identical placement behaviour to v0.3.2.

**Test E — takeoff + landing pair at the same airfield (CAP-style):**

A common pattern is a ramp-start aircraft whose route ends with a Landing waypoint at the source airfield (RTB). Pass F iterates `route.points` in order via `ipairs` so the takeoff waypoint is processed first; `attractToAirfield` for non-takeoff (Landing) waypoints calls `MapWindow.move_waypoint(group, wpt.index, x, y, true)` which mutates `group.x/y`.

1. Build a prefab containing a ramp-start aircraft at parking spot N, route ends with a Landing waypoint at the same airfield.
2. Place at original anchor (Prong 1, modern source). Verify the aircraft's editor position matches parking spot N and the Landing waypoint binds to the source airfield.
3. Place at a new anchor (Prong 2). Verify the aircraft attracts to a free spot at the destination airfield and the Landing waypoint binds to that destination airfield rather than dragging the group's coordinates somewhere unexpected.
4. Place at original anchor with a pre-mid-2024 source prefab (migration path). Verify both takeoff parking and landing waypoint resolve correctly.

Expected: pass on all four sub-steps. If group/unit positions visibly drift after placement, the iteration order or `attractToAirfield`'s `move_waypoint` side effect is interacting badly with our coord pipeline — investigate before merging.

## Risks / open questions

- **`require('me_route')` availability inside our load order.** ME-mod modules run inside the ME, which has loaded `me_route` as a top-level module by the time the user can press a placement button. `pcall` around the require keeps us safe even if a future ME refactor changes the module name.
- **`attractToAirfield` side effects beyond parking.** `me_route.lua:482-547` also calls `setFlightParams` to recompute speed/altitude. For a takeoff waypoint this re-derives the same values DCS would have used at runtime, so behaviour matches vanilla copy/paste — out of scope to second-guess.
- **`keep_airdrome_ids` interaction.** Already gated on `keep_position` (`prefab_ops.lua:1002`). Prong 1 reuses the same gate, so airdromeId and parking_id stay in sync. No new edge case.
- **Multiple aircraft sharing the same source spot.** Only possible on a malformed source mission — DCS won't let you place two aircraft on the same spot in ME. Out of scope.
