## ME Prefab Manager — Airbase Supplies — Design

**Date:** 2026-05-05
**Status:** Brainstorm
**Scope:** Extend the Prefab Manager so a prefab can capture and re-apply an airbase's warehouse settings (coalition, fuel reserves, aircraft pools, weapon pools, operating levels) alongside the groups / statics / zones / drawings it already saves. Detection happens via the ME's existing multi-select rectangle: if the rect covers an airdrome's reference point, we offer to bundle that airbase's supply settings into the prefab on save. ME-mod-only — no change to the public `sms.*` runtime surface.

## Goal

Close the workflow gap surfaced by users: *"I built this airbase the way I want it — planes parked, weapons stocked, fuel set, neutral airfield flipped to BLUE — and now I want to reuse all of that in another mission, in one click."* Today the Prefab Manager captures objects placed by the user (groups, statics, zones, drawings) but ignores per-airbase warehouse customisation, which lives in a different part of the .miz and a different ME panel (Resource Manager). This sub-feature wires that data into the prefab format and into the save/place flow.

## User value

The user's verbatim framing: *"I showed how to save all the planes + statics and everything for an entire airbase to someone. They asked if it was possible to also store that airbase supplies."* The ask is concrete — people building prefabs of "an entire airbase" naturally expect supplies to come along, because the Resource Manager dialog is where they spent the most time tuning that specific airbase. Without this feature, they have to redo every fuel slider and aircraft count by hand on every reuse.

## Non-goals

- **Runtime spawn of warehouse data.** DCS scripting can flip an airbase's coalition at runtime (`Airbase.autoCapture`, set coalition) but cannot mutate stock counts. Warehouse settings are baked at mission-start. Airbase prefabs are therefore an ME-time feature only.
- **Cross-theatre placement.** A Syria-Muwaffaq-Salti supply entry has no meaningful target on Caucasus. v1 refuses with a friendly message.
- **Sub-airbase granularity.** No per-aircraft-type or per-fuel-type cherry-picking. The whole warehouse entry is captured and applied as a unit.
- **Migrating warehouse data between airbases.** "Apply Muwaffaq's supplies to Krasnodar-Center" is out of scope. Airbase identity is by name and v1 only applies to the same-named airbase.
- **General ME-wide marquee-select integration.** We hook the existing multi-select rect for the narrow purpose of detecting airbases inside it. We do not add new selection modes, do not change ME selection semantics, and do not surface the rect to other mod features.

## Background — what the .miz holds

A .miz is a zip archive. Top-level entries: `mission`, `options`, `theatre`, `warehouses`, `l10n/**`, `mapResource`. The supply data lives in **`warehouses`** (no extension). Verified against `D:\git\honu\missions\airfield_inventory_test.miz` (Syria, Muwaffaq Salti customised):

```lua
warehouses = {
    ["airports"] = {
        [1]  = { ...defaults: NEUTRAL, unlimited*, OperatingLevel_*=10... },
        [2]  = { ...defaults... },
        ...
        [68] = {
            -- The customised entry:
            ["coalition"] = "BLUE",
            ["unlimitedFuel"] = false,
            ["unlimitedAircrafts"] = false,
            ["unlimitedMunitions"] = false,
            ["jet_fuel"] = { ["InitFuel"] = 50 },
            ["methanol_mixture"] = { ["InitFuel"] = 60 },
            ["diesel"] = { ["InitFuel"] = 60 },
            ["gasoline"] = { ["InitFuel"] = 50 },
            ["OperatingLevel_Air"] = 10,
            ["OperatingLevel_Eqp"] = 0,
            ["OperatingLevel_Fuel"] = 10,
            ["aircrafts"] = {
                ["helicopters"] = {
                    ["AH-64D"] = { ["initialAmount"] = 100, ["wsType"] = {1,2,6,158}, ["unlimited"] = false },
                    ...
                },
                ["planes"] = { ... },
            },
            ["weapons"] = { ... },
            ["dynamicSpawn"] = false,
            ["dynamicCargo"] = false,
            ["allowHotStart"] = false,
            ["speed"] = 16.666666,
            ["periodicity"] = 30,
            ["size"] = 100,
            ["suppliers"] = {},
        },
        ...
    },
    ["warehouses"] = {},  -- separate section for FARP / static-warehouse buildings
}
```

Every airdrome on the theatre has an entry whether the user touched it or not. "Default" entries are recognisable: `coalition="NEUTRAL"`, all `unlimited*=true`, `aircrafts={}`, `weapons={}`, `OperatingLevel_*=10`.

The numeric key `[N]` is the **airdromeNumber** — a per-theatre sequential ID baked into the terrain. Mapping from airdromeNumber to a real airbase comes from the ME's `Mission.AirdromeController`:

```lua
local AC = require('Mission.AirdromeController')
local id = AC.getAirdromeId(68)         -- airdromeNumber → opaque internal id
local ad = AC.getAirdrome(id)
ad:getName()           -- "Muwaffaq Salti"
ad.x, ad.y             -- map coords (the airbase's reference_point)
ad:getCoalitionName()
```

`AC.getAirdromes()` returns the full list. Each airdrome's `(x, y)` is its reference point — the location the airbase name is rendered at on the map. This is what we hit-test the marquee rect against.

## Data model

### Prefab format addition

Add an optional `airbases` field inside `meta`:

```lua
meta = {
    name = "muwaffaq-salti-blue-stocked",
    sms_prefab_version = "0.3.0",   -- bumped from 0.2.0; presence of meta.airbases is the new feature
    theatre = "Syria",
    world_anchor = { x = ..., y = ... },
    created_utc = "...",
    airbases = {
        {
            name           = "Muwaffaq Salti",
            airdrome_number_at_save = 68,    -- informational; we re-resolve by name on apply
            warehouse      = { ...verbatim copy of warehouses.airports[68]... },
        },
        -- More entries possible if the rect covered multiple airbases.
    },
}
```

`airdrome_number_at_save` is stored for debugging only — applying always re-resolves by **name** in case ED changes the airdromeNumber across DCS updates or theatres are merged. The verbatim warehouse entry is the source of truth on apply.

### Version bump

Adding `meta.airbases` is additive — old code reading a 0.3.0 prefab without consuming it is harmless, since the unknown field is ignored. Bumping `sms_prefab_version` from `0.2.0` to `0.3.0` lets future logic gate behaviour cleanly. Old 0.2.0 prefabs continue to load and place exactly as before (no airbase data, no apply step).

## UX flow

### Save side

1. User selects with the ME's standard multi-select rect (the existing tool — we don't add a new selection mode).
2. The Prefab Manager hooks the rect-complete event (see [Marquee hook](#marquee-hook) below) and hit-tests every airdrome's reference point against the final rect.
3. If 1+ airdromes fall inside the rect, the status bar lights up:
   *"1 airbase in selection: Muwaffaq Salti. Include supplies in next save? [Yes] [No]"*
   For 2+, list them: *"3 airbases in selection: A, B, C. Include all? [Yes] [Pick…] [No]"*. "Pick…" opens a small modal with one checkbox per airbase, defaulted to all-on.
4. The chosen set is held as pending state on the Prefab Manager (`W.pending_airbases`). The Save button reads it at click time, writes the warehouse copies into `meta.airbases`, and clears the state.
5. The grid shows a marker for prefabs that contain airbase data — same pattern as the **Fixed Pos** column. Working name: **`Bases`** with the count, or **`AB`** with `Yes` / blank. Decision deferred to UX section.

### Apply side

The existing place flow is unchanged for the groups / statics / zones / drawings half. After those land, if the prefab carries `meta.airbases`, run an extra **apply step**:

1. Read theatre. If `meta.theatre ~= currentMissionTheatre`: status-bar refusal *"Airbase supplies belong to <theatre> — skipped"*. Groups already placed remain. v1 does no fallback.
2. For each `meta.airbases[*]`:
   a. Look up airdrome by name (`AC.getAirdromes()` walk + `:getName()` match).
   b. If not found: skip with a status-bar warning. (DCS rename of airbase between save and apply.)
   c. If found and the destination airbase has default settings: write the saved warehouse table verbatim into the live data, set coalition.
   d. If found and the destination airbase has been customised already: modal prompt — Overwrite / Skip / Cancel-place. Overwrite is destructive of in-flight ME work, so we ask.
3. Status bar reports outcome: *"Applied supplies for 2 airbases. 1 skipped (theatre)."*

For prefabs that carry **only** airbase data (no groups / statics / zones / drawings), the apply step is the entire place. Map-click placement is meaningless; the prefab applies to its named airbase or it doesn't apply at all. UX in that case: the Place buttons re-label to *"Apply airbase supplies"* and skip the cursor-follow preview.

### Detection of "default" entries

When extracting on save, we compare the airdrome's current warehouse entry to a default-shape table. If it matches the default (NEUTRAL, all `unlimited*=true`, empty `aircrafts`, empty `weapons`, all `OperatingLevel_*=10`), we **don't** offer to include it — there's nothing meaningful to capture. Status bar instead says *"Muwaffaq Salti is unmodified — nothing to save"*.

## Architecture

### Marquee hook

`tools/me-mod/lua/dcs_sms_me/marquee_hook.lua` (new). Wraps three globals on `me_multiSelection`:

```
createRectSelect(mapX, mapY, color)            -- start; capture (mapX, mapY) as rect_start
updateRectSelect(mapX, mapY)                   -- drag tick; capture rect_end
multiSelectionState_onMouseUp(self, x, y, b)   -- complete; if button==1, fire callback(start, end)
```

All three are file-globals on `module('me_multiSelection')`, so monkey-patching is clean. Sentinel flag `mms._sms_marquee_patched` to make Ctrl+Shift+R reloads idempotent. Same pattern as the existing `me_menubar.hideME` hook.

The hook itself is feature-agnostic: it broadcasts rect-complete events to anything subscribed. The airbase detection is its first subscriber. Future use cases (selection-driven prefab box, area-of-interest queries) can subscribe without re-hooking.

### Airdrome hit-test

`tools/me-mod/lua/dcs_sms_me/airbase_detect.lua` (new). One function:

```lua
function M.airbases_in_rect(start_xy, end_xy)
    local lo_x, hi_x = math.min(start_xy.x, end_xy.x), math.max(start_xy.x, end_xy.x)
    local lo_y, hi_y = math.min(start_xy.y, end_xy.y), math.max(start_xy.y, end_xy.y)
    local hits = {}
    for _, ad in ipairs(AC.getAirdromes()) do
        if ad.x >= lo_x and ad.x <= hi_x and ad.y >= lo_y and ad.y <= hi_y then
            hits[#hits + 1] = { name = ad:getName(), airdrome_number_at_save = ad:getAirdromeNumber() }
        end
    end
    return hits
end
```

### Warehouse extract / apply

`tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua` (new). Two functions:

- `extract(airdrome_number) → table` — returns a deep copy of the airport's current warehouse entry. Uses the same data path the resource manager dialog reads from (`vdata.AirportsEquipment['airports'][N]` or, preferably, an accessor on `mod_mission` if one exists; plan-time spike).
- `apply(airdrome_number, warehouse_table) → ok, err` — writes the table into the live data. Mirrors the per-field setters in `me_manager_resource` so the resource manager dialog reflects the change if it's open. Sets coalition via `AirdromeController.setAirdromeCoalition`.

Both are pcall-guarded; failures degrade to nil + log per the framework's failure mode.

### Prefab pipeline changes

- `prefab_distill.lua` — accepts `opts.airbases` (array of `{name, airdrome_number, warehouse}`); writes `meta.airbases` only when non-empty.
- `prefab_ops.save_selection` — reads pending-airbases state from the window (or accepts as a third arg), forwards to distill.
- `prefab_ops.scan_dir` — surfaces an `airbase_count` (or `has_airbases`) field on the row so the grid column can render.
- `prefab_ops.place` — after the existing place finishes, calls `warehouse_ops.apply` for each `meta.airbases[*]` entry.
- `window.lua` — new pending-airbases state, status-bar prompt rendering, optional grid column.

## Edge cases

- **Marquee drawn while *not* in select mode.** The ME's MultiSelection tool has Select / Deselect / Add-select / Move / MoveAnchor modes. Detection should fire on Select (and arguably Add-select) only — Deselect probably shouldn't trigger an "include airbase?" prompt. Plan-time decision; accepting all three is also defensible.
- **Marquee drawn before the Prefab Manager window is open.** No subscriber → no prompt. Acceptable: airbase capture is opt-in via the Prefab Manager flow.
- **Multiple airbases in rect.** Surfaced in the prompt with a Pick… modal. All-on is the default.
- **Airbase rename between save and apply.** Skipped with warning. Future: fuzzy-match by `(theatre, airdrome_number_at_save)` as a fallback hint, but v1 is name-only.
- **Airbase already customised in target mission.** Prompt overwrite / skip / cancel. Default action: skip (least destructive).
- **Place-at-original on a prefab containing airbase data.** Same name-match as place-at-click. Coordinates of the airbase don't change with map clicks regardless.
- **Prefab made on a DCS version where the warehouse format changes.** The prefab carries the verbatim entry. If ED restructures the warehouse table in a future patch, old airbase prefabs will write a stale shape. Acceptable for v1; gate future migrations on `sms_prefab_version`.

## Implementation phases

Suggested order; each phase is independently mergeable.

1. **Marquee hook** — `marquee_hook.lua` + unit test stubbing the three monkey-patched functions. Useful even without the airbase work.
2. **Airdrome hit-test** — `airbase_detect.lua` + unit test with stubbed `AirdromeController`.
3. **Save-side UX** — pending-airbases state, status-bar prompt, save plumbs into distill / ops. Grid column for "has airbases".
4. **Apply-side mechanics** — `warehouse_ops.apply`, place-pipeline hook, default-vs-customised detection, theatre check, overwrite prompt.
5. **Pure-airbase prefabs** — relabel Place buttons when the prefab is airbase-only; skip cursor-follow preview.

Phases 1–3 ship a working "save the supplies" loop that's load-bearing visible. Phase 4 closes the loop. Phase 5 is polish.

## Open questions

- **Read API for the live `airports` table.** The resource manager uses `vdata.AirportsEquipment['airports'][N]` (private to `me_manager_resource`). Cleaner accessor on `mod_mission` would be preferred — quick code dive at plan time.
- **Write API.** Same question. The resource manager mutates fields directly via per-field setters that fire callbacks (`getAirdrome().jet_fuel.InitFuel = ...`). For wholesale-replace, either we emulate every setter or we splice the table and the dialog refreshes correctly. Spike at plan time.
- **Grid column shape.** `Bases` with a count vs `AB` with `Yes`/blank. Lean toward `AB` to keep parity with the new `Fixed Pos` column.
- **Default-detection fidelity.** Do we hard-code the "default" shape, or compute it from a known-pristine airport on the same theatre? The latter is more robust to future ED additions but harder to reason about. Probably hard-code for v1, log + flag if a field looks unfamiliar.

## AGENTS.md / docs/api impact

None — `tools/me-mod/` is not part of the public `sms.*` surface (per CLAUDE.md and the AGENTS.md sync rule). No `docs/api/` page covers it; AGENTS.md §7 module index doesn't list it.

## Tracking / landing

This depends on the marquee hook (Phase 1), which is reusable beyond this feature. Two reasonable shapes for the GitHub side:

- **One issue, this whole spec.** Cleaner narrative — the marquee hook gets shipped *because* of airbase supplies and the issue tracks the user-facing feature.
- **Two issues** — `feat(me-mod): marquee-select hook for ME multi-select rect` (depends-on-by) `feat(me-mod): capture airbase supplies in prefabs (Resource Manager round-trip)`. Cleaner if the marquee hook gets a second consumer before this feature lands.

Defer to user preference at landing time.

## Decisions (locked at plan time, 2026-05-05)

The spec's open-questions section asked for an API spike. Resolved as follows:

**Read API:** `require('me_mission').mission.AirportsEquipment.airports[N]` is the canonical read. `module('me_mission')` exposes `mission` on the module table; this is the same table the resource manager mirrors into `panel_manager_resource.vdata.AirportsEquipment` and the same data the miz exporter serializes. We read this and deep-copy on extract.

**Write API:** Splice the warehouse entry into `mission.AirportsEquipment.airports[N]` and call `AirdromeController.setAirdromeCoalition(id, name)` to push the coalition change through the controller (so map display + dialog state refresh correctly). Field-level setters on `me_manager_resource` are NOT used — they're tied to the Resource Manager dialog being open.

**Coalition string mapping:** The warehouse table uses uppercase `RED`/`BLUE`/`NEUTRAL`. `AirdromeController.setAirdromeCoalition` expects controller-form names from `CoalitionController.{red,blue,neutral}CoalitionName()`. We map between them at the seam.

**Default-detection (revised 2026-05-05 after first round of testing):** A warehouse entry is "default" iff all three `unlimited*` flags are true. The earlier richer rule (coalition NEUTRAL + OperatingLevel + fuel + aircrafts/weapons checks) misclassified pre-coloured airbases — many maps ship airbases pre-assigned to RED or BLUE in their default state, which the strict rule treated as "customised". The unlimited flags are gating UI state in the Resource Manager — every other stock control is locked while they're true — so they're a tight signal that the user hasn't dialed in any specific values worth bundling.

**Apply-time prompt (revised 2026-05-05):** When a prefab carries `meta.airbases`, placing it always shows a single confirmation overlay listing the airbase names, with Yes/No. Earlier design used `is_default` to gate an "overwrite?" prompt only when destinations were already customised; that produced false overwrite prompts for pre-coloured airbases on fresh missions. Universal confirm is simpler and avoids the false-positive trap.

**Resource Manager dialog refresh on apply:** If the Resource Manager dialog is open and showing the airbase we just wrote, the dialog's spinboxes and lists won't reflect the change until the user clicks elsewhere or reopens. v1 acceptable; status-bar warns the user to close + reopen.

**Grid column for airbase-bearing prefabs:** `AB` column, 50px, after `Fixed Pos`. Cell shows `Yes` (single) or the count (e.g. `3`). Sortable like other columns; sorts by count via the existing numeric=true path.
