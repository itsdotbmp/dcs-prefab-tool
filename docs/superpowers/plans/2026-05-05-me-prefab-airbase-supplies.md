# ME Prefab Airbase Supplies — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Prefab Manager so a prefab can capture and re-apply an airbase's warehouse settings (coalition, fuel, aircraft pools, weapon pools, operating levels). Detection is via the ME's existing multi-select rectangle. ME-mod-only — no change to the public `sms.*` runtime surface.

**Architecture:** Three new ME-mod modules (`marquee_hook`, `airbase_detect`, `warehouse_ops`) layered above the existing `prefab_distill` / `prefab_ops` / `window` stack. Marquee-rect events are broadcast from a thin monkey-patch over `me_multiSelection`. Hit-tests against `AirdromeController.getAirdromes()` produce a list of in-rect airdromes; if non-empty, the Prefab Manager status bar prompts the user to bundle them. On Save, warehouse entries are extracted from `me_mission.mission.AirportsEquipment.airports[N]` and stored verbatim in `meta.airbases[*]`. On Place, after groups land, each airbase entry is re-resolved by name and the warehouse table is spliced back in (with coalition pushed through `AirdromeController.setAirdromeCoalition`).

**Tech Stack:** Lua 5.1, DCS Mission Editor `module()` GUI VM, dxgui widgets, pcall-guarded failure mode.

**Worktree:** `D:\git\dcs-sms\.worktrees\airbase-supplies\` on branch `feat/me-mod-airbase-supplies`. All paths below are relative to this worktree root unless prefixed `D:/Program Files/...` (DCS install) or `C:\Users\...` (Saved Games).

---

## File structure

**Create:**
- `tools/me-mod/lua/dcs_sms_me/marquee_hook.lua` — monkey-patch `me_multiSelection` to broadcast rect-complete events.
- `tools/me-mod/lua/dcs_sms_me/airbase_detect.lua` — hit-test airdromes against a rect.
- `tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua` — extract / apply / is_default for warehouse entries.
- `tools/me-mod/test/test_marquee_hook.lua`
- `tools/me-mod/test/test_airbase_detect.lua`
- `tools/me-mod/test/test_warehouse_ops.lua`
- `tools/me-mod/test/test_prefab_ops_airbases.lua`

**Modify:**
- `tools/me-mod/lua/dcs_sms_me/prefab_distill.lua` — pass `opts.airbases` into `meta.airbases`; bump `PREFAB_VERSION`.
- `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` — `save_selection(name, place_at_origin, airbases)`; surface `airbase_count` in `scan_dir` rows; add `apply_airbases(prefab)` for the place pipeline.
- `tools/me-mod/lua/dcs_sms_me/window.lua` — subscribe to marquee hook; pending airbase state; Save plumbing; AB column; Pick modal; apply UX.
- `tools/me-mod/lua/dcs_sms_me/init.lua` — install marquee hook on bootstrap.
- `tools/me-mod/test/run-tests.ps1` — append new test files to `$tests` list.

---

## API spike findings (recorded here so the rest of the plan is concrete)

**Read live warehouse data:**
```lua
local module_mission = require('me_mission')   -- module('me_mission'); `mission` is _M.mission
local airport = module_mission.mission.AirportsEquipment.airports[airdrome_number]
-- returns the live table; deep-copy before exposing
```

**Write live warehouse data:**
```lua
local module_mission = require('me_mission')
local AC = require('Mission.AirdromeController')
local CC = require('Mission.CoalitionController')

-- 1. Splice the warehouse entry into the live data
module_mission.mission.AirportsEquipment.airports[airdrome_number] = deep_copy(saved_warehouse)

-- 2. Push coalition through the controller so the airbase's map display refreshes.
--    AirdromeController.setAirdromeCoalition expects controller-form names, not the
--    "BLUE"/"RED"/"NEUTRAL" strings used in the warehouse table.
local controller_coalition = ({
    BLUE    = CC.blueCoalitionName(),
    RED     = CC.redCoalitionName(),
    NEUTRAL = CC.neutralCoalitionName(),
})[saved_warehouse.coalition]
local id = AC.getAirdromeId(airdrome_number)
AC.setAirdromeCoalition(id, controller_coalition)
```

**Default-airport detection** (a "default" entry has not been customised by the user):
```lua
-- All five conditions must hold:
entry.coalition == "NEUTRAL"
entry.unlimitedFuel == true and entry.unlimitedAircrafts == true and entry.unlimitedMunitions == true
entry.OperatingLevel_Air == 10 and entry.OperatingLevel_Eqp == 10 and entry.OperatingLevel_Fuel == 10
(entry.aircrafts == nil or next(entry.aircrafts) == nil) and (entry.weapons == nil or next(entry.weapons) == nil)
entry.jet_fuel.InitFuel == 100 and entry.gasoline.InitFuel == 100 and entry.diesel.InitFuel == 100 and entry.methanol_mixture.InitFuel == 100
```

**Marquee hook surface** (verified — all are file-globals on `module('me_multiSelection')`):
- `createRectSelect(mapX, mapY, color)` — start point in MAP coords (output of `MapWindow.getMapPoint`).
- `updateRectSelect(mapX, mapY)` — drag tick.
- `multiSelectionState_onMouseUp(self, x, y, button)` — rect complete; we fire callbacks before delegating.

---

## Task 1: Record API spike in spec Decisions section

**Files:**
- Modify: `docs/superpowers/specs/2026-05-05-me-prefab-airbase-supplies.md`

This is the user-requested "first task: spike". The findings are already in this plan's preamble. We mirror them into the spec so future readers see the spec is fully resolved.

- [ ] **Step 1: Append a Decisions section to the spec**

Open `docs/superpowers/specs/2026-05-05-me-prefab-airbase-supplies.md` and append at the bottom (after the "Tracking / landing" section):

```markdown
## Decisions (locked at plan time, 2026-05-05)

The spec's open-questions section asked for an API spike. Resolved as follows:

**Read API:** `require('me_mission').mission.AirportsEquipment.airports[N]` is the canonical read. `module('me_mission')` exposes `mission` on the module table; this is the same table the resource manager mirrors into `panel_manager_resource.vdata.AirportsEquipment` and the same data the miz exporter serializes. We read this and deep-copy on extract.

**Write API:** Splice the warehouse entry into `mission.AirportsEquipment.airports[N]` and call `AirdromeController.setAirdromeCoalition(id, name)` to push the coalition change through the controller (so map display + dialog state refresh correctly). Field-level setters on `me_manager_resource` are NOT used — they're tied to the Resource Manager dialog being open.

**Coalition string mapping:** The warehouse table uses uppercase `RED`/`BLUE`/`NEUTRAL`. `AirdromeController.setAirdromeCoalition` expects controller-form names from `CoalitionController.{red,blue,neutral}CoalitionName()`. We map between them at the seam.

**Default-detection:** A warehouse entry is "default" iff coalition=NEUTRAL, all `unlimited*=true`, all `OperatingLevel_*=10`, `aircrafts={}` or absent, `weapons={}` or absent, all four fuel `InitFuel=100`. Hard-coded rather than computed against a pristine reference. Logged warning if a recognized field is unfamiliar so we can add coverage if ED expands the schema.

**Resource Manager dialog refresh on apply:** If the Resource Manager dialog is open and showing the airbase we just wrote, the dialog's spinboxes and lists won't reflect the change until the user clicks elsewhere or reopens. v1 acceptable; status-bar warns the user to close + reopen.

**Grid column for airbase-bearing prefabs:** `AB` column, 50px, after `Fixed Pos`. Cell shows `Yes` (single) or the count (e.g. `3`). Sortable like other columns; sorts by count via the existing numeric=true path.
```

- [ ] **Step 2: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add docs/superpowers/specs/2026-05-05-me-prefab-airbase-supplies.md
git commit -m "docs(spec): record airbase-supplies API spike findings"
```

---

## Task 2: Marquee hook module — broadcast rect-complete events

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/marquee_hook.lua`
- Create: `tools/me-mod/test/test_marquee_hook.lua`
- Modify: `tools/me-mod/test/run-tests.ps1`

The hook installs idempotent monkey-patches on `me_multiSelection.{createRectSelect, updateRectSelect, multiSelectionState_onMouseUp}` and offers a `subscribe(callback)` API. On rect-complete (left mouse-up after a drag) every subscriber is called with `(start_xy, end_xy)`.

- [ ] **Step 1: Write the failing test**

Create `tools/me-mod/test/test_marquee_hook.lua`:

```lua
-- Standalone test for marquee_hook: install + subscribe + fire on rect-complete.
-- Stubs me_multiSelection so we don't depend on the real DCS module.
-- Run via: lua test_marquee_hook.lua  (cwd: tools/me-mod/test/)

-- Stub me_multiSelection with the three globals our hook patches.
local stub_mms = {}
stub_mms.createRectSelect = function(x, y, color)
    stub_mms._last_create = { x = x, y = y, color = color }
end
stub_mms.updateRectSelect = function(x, y)
    stub_mms._last_update = { x = x, y = y }
end
stub_mms.multiSelectionState_onMouseUp = function(self, x, y, button)
    stub_mms._last_mouseup = { self = self, x = x, y = y, button = button }
end
package.preload['me_multiSelection'] = function() return stub_mms end

-- Stub log so init.lua-style log.write calls don't fail.
package.preload['log'] = function()
    return { write = function() end, INFO = 1, WARNING = 2, ERROR = 3 }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local marquee_hook = require('dcs_sms_me.marquee_hook')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: install patches the three functions and is idempotent.
do
    local orig_create  = stub_mms.createRectSelect
    local orig_update  = stub_mms.updateRectSelect
    local orig_mouseup = stub_mms.multiSelectionState_onMouseUp

    marquee_hook.install()
    check('install replaces createRectSelect',  stub_mms.createRectSelect ~= orig_create)
    check('install replaces updateRectSelect',  stub_mms.updateRectSelect ~= orig_update)
    check('install replaces onMouseUp',         stub_mms.multiSelectionState_onMouseUp ~= orig_mouseup)

    -- Idempotent — second install must not stack wrappers.
    local once_create = stub_mms.createRectSelect
    marquee_hook.install()
    check('install is idempotent', stub_mms.createRectSelect == once_create)
end

-- Case: drag → mouse-up fires subscribers with start + end map coords.
do
    local fired = {}
    marquee_hook.subscribe(function(start_xy, end_xy)
        fired[#fired + 1] = { start_xy = start_xy, end_xy = end_xy }
    end)

    -- Simulate a drag: createRectSelect (start) + a few updateRectSelect (drag ticks)
    -- + multiSelectionState_onMouseUp (release on left button = 1).
    stub_mms.createRectSelect(100, 200, {1,0,0,1})
    stub_mms.updateRectSelect(150, 250)
    stub_mms.updateRectSelect(180, 300)
    stub_mms.multiSelectionState_onMouseUp({}, 999, 999, 1)

    check('subscriber fired exactly once', #fired == 1, 'got ' .. tostring(#fired))
    check('subscriber received start xy', fired[1] and fired[1].start_xy.x == 100 and fired[1].start_xy.y == 200,
          'start was ' .. tostring(fired[1] and fired[1].start_xy.x))
    check('subscriber received end xy',   fired[1] and fired[1].end_xy.x == 180 and fired[1].end_xy.y == 300,
          'end was ' .. tostring(fired[1] and fired[1].end_xy.x))
end

-- Case: right-button mouse-up does NOT fire subscribers.
do
    local fired_count = 0
    marquee_hook.subscribe(function() fired_count = fired_count + 1 end)
    stub_mms.createRectSelect(0, 0, {})
    stub_mms.updateRectSelect(10, 10)
    stub_mms.multiSelectionState_onMouseUp({}, 0, 0, 3)  -- right button
    check('right-button mouseup did not fire subscribers', fired_count == 0, 'got ' .. fired_count)
end

-- Case: mouse-up without prior drag (no createRectSelect) does not fire.
do
    -- Reset module state by re-requiring (clears any retained start/end).
    package.loaded['dcs_sms_me.marquee_hook'] = nil
    -- Re-stub the originals so a fresh install starts clean.
    stub_mms.createRectSelect            = function(x, y, color) end
    stub_mms.updateRectSelect            = function(x, y) end
    stub_mms.multiSelectionState_onMouseUp = function(s, x, y, b) end
    local mh2 = require('dcs_sms_me.marquee_hook')
    mh2.install()
    local fired_count = 0
    mh2.subscribe(function() fired_count = fired_count + 1 end)
    stub_mms.multiSelectionState_onMouseUp({}, 0, 0, 1)  -- no createRectSelect first
    check('mouseup without prior drag did not fire subscribers', fired_count == 0, 'got ' .. fired_count)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All marquee_hook tests passed.')
```

- [ ] **Step 2: Run test to verify it fails**

Run from `tools/me-mod/test/`:
```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_marquee_hook.lua
```
Expected: failure with `module 'dcs_sms_me.marquee_hook' not found`.

- [ ] **Step 3: Write minimal implementation**

Create `tools/me-mod/lua/dcs_sms_me/marquee_hook.lua`:

```lua
-- marquee_hook.lua — broadcast rect-complete events from the ME's MultiSelection tool.
--
-- Wraps three globals on `me_multiSelection`:
--   createRectSelect(mapX, mapY, color)            -- drag start (left-button mouse-down)
--   updateRectSelect(mapX, mapY)                   -- drag tick (mouse move while down)
--   multiSelectionState_onMouseUp(self, x, y, b)   -- drag complete (mouse-up)
-- All three are file-globals on `module('me_multiSelection')` so they can be
-- monkey-patched after `require('me_multiSelection')` runs.
--
-- The hook fires every subscriber once per left-button drag-complete with
-- (start_xy, end_xy) — both in MAP coords. Drags without a preceding
-- createRectSelect (e.g. ctrl-clicks, mouse-up off-canvas) are ignored.
--
-- Idempotency: install() guards via a sentinel on the me_multiSelection module,
-- so Ctrl+Shift+R reloads don't stack wrappers.

local M = {}

local mms = require('me_multiSelection')

local rect_start = nil   -- {x, y} of last createRectSelect, or nil
local rect_end   = nil   -- {x, y} of last updateRectSelect, or nil
local subscribers = {}

local function fire(start_xy, end_xy)
    for _, cb in ipairs(subscribers) do
        pcall(cb, start_xy, end_xy)
    end
end

function M.install()
    if mms._sms_marquee_patched then return end

    local orig_create  = mms.createRectSelect
    local orig_update  = mms.updateRectSelect
    local orig_mouseup = mms.multiSelectionState_onMouseUp

    mms.createRectSelect = function(mapX, mapY, color)
        rect_start = { x = mapX, y = mapY }
        rect_end   = { x = mapX, y = mapY }
        return orig_create(mapX, mapY, color)
    end

    mms.updateRectSelect = function(mapX, mapY)
        if rect_start then rect_end = { x = mapX, y = mapY } end
        return orig_update(mapX, mapY)
    end

    mms.multiSelectionState_onMouseUp = function(self, x, y, button)
        if button == 1 and rect_start and rect_end then
            fire(rect_start, rect_end)
            rect_start, rect_end = nil, nil
        end
        return orig_mouseup(self, x, y, button)
    end

    mms._sms_marquee_patched = true
end

function M.subscribe(callback)
    if type(callback) ~= 'function' then return end
    subscribers[#subscribers + 1] = callback
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run from `tools/me-mod/test/`:
```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_marquee_hook.lua
```
Expected: `All marquee_hook tests passed.`

- [ ] **Step 5: Add test to run-tests.ps1**

Modify `tools/me-mod/test/run-tests.ps1`. Find the line:
```powershell
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua', 'test_prefab_ops_save.lua', 'test_prefab_ops_load.lua', 'test_prefab_ops_place.lua', 'test_undo.lua')
```
Replace with:
```powershell
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua', 'test_prefab_ops_save.lua', 'test_prefab_ops_load.lua', 'test_prefab_ops_place.lua', 'test_undo.lua', 'test_marquee_hook.lua')
```

- [ ] **Step 6: Run full test suite**

Run from `tools/me-mod/test/`:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`, exit code 0.

- [ ] **Step 7: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/marquee_hook.lua tools/me-mod/test/test_marquee_hook.lua tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): marquee_hook — broadcast rect-complete events from MultiSelection tool"
```

---

## Task 3: Airbase detect — hit-test airdromes against a rect

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/airbase_detect.lua`
- Create: `tools/me-mod/test/test_airbase_detect.lua`
- Modify: `tools/me-mod/test/run-tests.ps1`

Pure function on top of `Mission.AirdromeController.getAirdromes()`. Returns array of `{name, airdrome_number_at_save, x, y}` for every airdrome whose reference point falls inside the (axis-aligned) rect defined by start/end map coords.

- [ ] **Step 1: Write the failing test**

Create `tools/me-mod/test/test_airbase_detect.lua`:

```lua
-- Standalone test for airbase_detect.airbases_in_rect.
-- Stubs Mission.AirdromeController with a fixed list of airdromes.
-- Run via: lua test_airbase_detect.lua  (cwd: tools/me-mod/test/)

-- Make-believe airdromes with x/y reference points + getName + getAirdromeNumber.
local function make_airdrome(name, n, x, y)
    return {
        x = x, y = y,
        getName             = function(self) return name end,
        getAirdromeNumber   = function(self) return n end,
    }
end

local airdromes = {
    make_airdrome('Khalde',          12, -250000,  610000),
    make_airdrome('Muwaffaq Salti',  68, -260000,  605000),
    make_airdrome('Beirut',          15, -270000,  615000),
    make_airdrome('H4',              80, -340000,  590000),
}

package.preload['Mission.AirdromeController'] = function()
    return {
        getAirdromes = function() return airdromes end,
    }
end

-- Stub log.
package.preload['log'] = function()
    return { write = function() end, INFO = 1, WARNING = 2, ERROR = 3 }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local airbase_detect = require('dcs_sms_me.airbase_detect')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: rect contains a single airdrome.
do
    local hits = airbase_detect.airbases_in_rect({x=-262000, y=603000}, {x=-258000, y=607000})
    check('single airdrome in rect: count == 1', #hits == 1, 'got ' .. #hits)
    check('single airdrome name', hits[1] and hits[1].name == 'Muwaffaq Salti',
          'got ' .. tostring(hits[1] and hits[1].name))
    check('single airdrome number', hits[1] and hits[1].airdrome_number_at_save == 68,
          'got ' .. tostring(hits[1] and hits[1].airdrome_number_at_save))
end

-- Case: rect contains multiple airdromes.
do
    local hits = airbase_detect.airbases_in_rect({x=-280000, y=600000}, {x=-240000, y=620000})
    check('multi-airdrome rect: count == 3', #hits == 3, 'got ' .. #hits)
    local by_name = {}
    for _, h in ipairs(hits) do by_name[h.name] = true end
    check('Khalde in rect',          by_name['Khalde'] == true)
    check('Muwaffaq Salti in rect',  by_name['Muwaffaq Salti'] == true)
    check('Beirut in rect',          by_name['Beirut'] == true)
    check('H4 NOT in rect',          by_name['H4'] == nil)
end

-- Case: rect with start/end reversed (drawn upper-right to lower-left) still works.
do
    local hits = airbase_detect.airbases_in_rect({x=-258000, y=607000}, {x=-262000, y=603000})
    check('reversed rect: count == 1', #hits == 1, 'got ' .. #hits)
    check('reversed rect: Muwaffaq Salti', hits[1] and hits[1].name == 'Muwaffaq Salti')
end

-- Case: empty rect (no airdromes inside) returns empty.
do
    local hits = airbase_detect.airbases_in_rect({x=0, y=0}, {x=100, y=100})
    check('empty rect returns empty array', type(hits) == 'table' and #hits == 0, 'got ' .. #hits)
end

-- Case: airdrome exactly on rect boundary is included (inclusive bounds).
do
    local hits = airbase_detect.airbases_in_rect({x=-260000, y=605000}, {x=-260000, y=605000})
    check('point-rect at airdrome reference picks it up', #hits == 1, 'got ' .. #hits)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All airbase_detect tests passed.')
```

- [ ] **Step 2: Run test to verify it fails**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_airbase_detect.lua
```
Expected: failure with `module 'dcs_sms_me.airbase_detect' not found`.

- [ ] **Step 3: Write minimal implementation**

Create `tools/me-mod/lua/dcs_sms_me/airbase_detect.lua`:

```lua
-- airbase_detect.lua — hit-test airdromes against an axis-aligned rect.
--
-- The ME's multi-select rectangle gives us two map-coord points; this module
-- returns every airdrome whose reference point falls inside the bounding box.
-- Airdromes come from Mission.AirdromeController.getAirdromes() — that returns
-- clones with x/y inherited from the Unit base class plus :getName() and
-- :getAirdromeNumber() accessors. We surface a flat table per hit so callers
-- don't need to know about the Airdrome class.

local M = {}

-- Returns array of { name, airdrome_number_at_save, x, y } for every airdrome
-- whose (x, y) reference point lies in the rect defined by start_xy and end_xy.
-- Bounds are inclusive. Either argument missing → empty array.
function M.airbases_in_rect(start_xy, end_xy)
    if type(start_xy) ~= 'table' or type(end_xy) ~= 'table' then return {} end
    if type(start_xy.x) ~= 'number' or type(start_xy.y) ~= 'number' then return {} end
    if type(end_xy.x)   ~= 'number' or type(end_xy.y)   ~= 'number' then return {} end

    local lo_x = math.min(start_xy.x, end_xy.x)
    local hi_x = math.max(start_xy.x, end_xy.x)
    local lo_y = math.min(start_xy.y, end_xy.y)
    local hi_y = math.max(start_xy.y, end_xy.y)

    local hits = {}
    local ok, AC = pcall(require, 'Mission.AirdromeController')
    if not ok or not AC or type(AC.getAirdromes) ~= 'function' then return hits end

    local airdromes = AC.getAirdromes() or {}
    for _, ad in ipairs(airdromes) do
        local x = type(ad.x) == 'number' and ad.x or nil
        local y = type(ad.y) == 'number' and ad.y or nil
        if x and y and x >= lo_x and x <= hi_x and y >= lo_y and y <= hi_y then
            hits[#hits + 1] = {
                name                    = ad.getName and ad:getName() or '?',
                airdrome_number_at_save = ad.getAirdromeNumber and ad:getAirdromeNumber() or nil,
                x                       = x,
                y                       = y,
            }
        end
    end
    return hits
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_airbase_detect.lua
```
Expected: `All airbase_detect tests passed.`

- [ ] **Step 5: Add test to run-tests.ps1**

Modify `tools/me-mod/test/run-tests.ps1`. Append `'test_airbase_detect.lua'` to the `$tests` array. The line should now end with `..., 'test_marquee_hook.lua', 'test_airbase_detect.lua')`.

- [ ] **Step 6: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`.

- [ ] **Step 7: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/airbase_detect.lua tools/me-mod/test/test_airbase_detect.lua tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): airbase_detect — hit-test airdromes against a rect"
```

---

## Task 4: Warehouse ops — extract + is_default

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua`
- Create: `tools/me-mod/test/test_warehouse_ops.lua`
- Modify: `tools/me-mod/test/run-tests.ps1`

`extract(N)` returns a deep-copied warehouse entry from the live `mission.AirportsEquipment.airports[N]`. `is_default(entry)` recognises pristine entries so the save-side UX can skip "include?" prompts for unmodified airbases. Apply is in Task 5 to keep tasks small.

- [ ] **Step 1: Write the failing test**

Create `tools/me-mod/test/test_warehouse_ops.lua`:

```lua
-- Standalone test for warehouse_ops.extract + is_default.
-- Stubs me_mission.mission.AirportsEquipment.airports.
-- Run via: lua test_warehouse_ops.lua  (cwd: tools/me-mod/test/)

local default_airport = {
    coalition          = "NEUTRAL",
    unlimitedFuel      = true,
    unlimitedAircrafts = true,
    unlimitedMunitions = true,
    OperatingLevel_Air = 10,
    OperatingLevel_Eqp = 10,
    OperatingLevel_Fuel = 10,
    aircrafts = {},
    weapons   = {},
    jet_fuel        = { InitFuel = 100 },
    methanol_mixture= { InitFuel = 100 },
    diesel          = { InitFuel = 100 },
    gasoline        = { InitFuel = 100 },
    suppliers = {},
    speed = 16.666666,
    periodicity = 30,
    size = 100,
    allowHotStart = false,
    dynamicSpawn = false,
    dynamicCargo = true,
}

local customised_airport = {
    coalition          = "BLUE",
    unlimitedFuel      = false,
    unlimitedAircrafts = false,
    unlimitedMunitions = false,
    OperatingLevel_Air = 10,
    OperatingLevel_Eqp = 0,
    OperatingLevel_Fuel = 10,
    aircrafts = {
        helicopters = {
            ["AH-64D"] = { initialAmount = 100, wsType = {1,2,6,158}, unlimited = false },
        },
        planes = {},
    },
    weapons = { foo = 1 },
    jet_fuel        = { InitFuel = 50 },
    methanol_mixture= { InitFuel = 60 },
    diesel          = { InitFuel = 60 },
    gasoline        = { InitFuel = 50 },
    suppliers = {},
    speed = 16.666666,
    periodicity = 30,
    size = 100,
    allowHotStart = false,
    dynamicSpawn = false,
    dynamicCargo = false,
}

package.preload['me_mission'] = function()
    return {
        mission = {
            AirportsEquipment = {
                airports = {
                    [1]  = default_airport,
                    [68] = customised_airport,
                }
            }
        }
    }
end

-- Stubs for AirdromeController + CoalitionController (apply tests live elsewhere
-- but warehouse_ops requires them at module load).
package.preload['Mission.AirdromeController'] = function()
    return { getAirdromeId = function(n) return n end, setAirdromeCoalition = function() end }
end
package.preload['Mission.CoalitionController'] = function()
    return {
        redCoalitionName     = function() return 'red' end,
        blueCoalitionName    = function() return 'blue' end,
        neutralCoalitionName = function() return 'neutral' end,
    }
end

package.preload['log'] = function()
    return { write = function() end, INFO = 1, WARNING = 2, ERROR = 3 }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local warehouse_ops = require('dcs_sms_me.warehouse_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: extract returns a deep-copied default airport (mutating result must
-- not affect the source).
do
    local entry = warehouse_ops.extract(1)
    check('extract(1) returns table', type(entry) == 'table')
    check('extract(1).coalition == NEUTRAL', entry.coalition == 'NEUTRAL')
    check('extract(1) deep-copy of jet_fuel', entry.jet_fuel ~= default_airport.jet_fuel,
          'expected different table reference')
    entry.coalition = 'MUTATED'
    check('extract result mutation does not leak to source',
          default_airport.coalition == 'NEUTRAL', 'source coalition was: ' .. default_airport.coalition)
end

-- Case: extract on customised airport preserves nested aircrafts table.
do
    local entry = warehouse_ops.extract(68)
    check('extract(68).coalition == BLUE', entry.coalition == 'BLUE')
    check('extract(68) preserves AH-64D entry',
          entry.aircrafts and entry.aircrafts.helicopters
          and entry.aircrafts.helicopters['AH-64D']
          and entry.aircrafts.helicopters['AH-64D'].initialAmount == 100,
          'AH-64D not preserved')
    check('extract(68) deep-copies wsType array',
          entry.aircrafts.helicopters['AH-64D'].wsType
            ~= customised_airport.aircrafts.helicopters['AH-64D'].wsType,
          'expected different table reference for wsType')
end

-- Case: extract on missing index returns nil.
do
    local entry = warehouse_ops.extract(9999)
    check('extract(9999) returns nil', entry == nil)
end

-- Case: is_default recognises a default airport.
do
    check('is_default(default) == true',
          warehouse_ops.is_default(default_airport) == true)
end

-- Case: is_default rejects a customised airport.
do
    check('is_default(customised) == false',
          warehouse_ops.is_default(customised_airport) == false)
end

-- Case: is_default rejects partial customisations one field at a time.
do
    local clone = function(t)
        local c = {}
        for k, v in pairs(t) do
            if type(v) == 'table' then
                local cc = {}
                for kk, vv in pairs(v) do cc[kk] = vv end
                c[k] = cc
            else
                c[k] = v
            end
        end
        return c
    end

    local mutations = {
        { 'coalition flipped',      function(t) t.coalition = 'BLUE' end },
        { 'unlimitedFuel false',    function(t) t.unlimitedFuel = false end },
        { 'OperatingLevel_Eqp 0',   function(t) t.OperatingLevel_Eqp = 0 end },
        { 'jet_fuel 50',            function(t) t.jet_fuel.InitFuel = 50 end },
        { 'aircrafts non-empty',    function(t) t.aircrafts = { planes = { ["F-16"] = {} } } end },
        { 'weapons non-empty',      function(t) t.weapons = { foo = 1 } end },
    }
    for _, mt in ipairs(mutations) do
        local m = clone(default_airport)
        m.aircrafts = {}; m.weapons = {}
        m.jet_fuel = clone(default_airport.jet_fuel)
        m.methanol_mixture = clone(default_airport.methanol_mixture)
        m.diesel = clone(default_airport.diesel)
        m.gasoline = clone(default_airport.gasoline)
        mt[2](m)
        check('is_default false after: ' .. mt[1], warehouse_ops.is_default(m) == false)
    end
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All warehouse_ops extract/is_default tests passed.')
```

- [ ] **Step 2: Run test to verify it fails**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_warehouse_ops.lua
```
Expected: failure (`module 'dcs_sms_me.warehouse_ops' not found`).

- [ ] **Step 3: Write minimal implementation**

Create `tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua`:

```lua
-- warehouse_ops.lua — read/write per-airbase warehouse entries.
--
-- The live data lives at `me_mission.mission.AirportsEquipment.airports[N]`
-- where N is the airdromeNumber. We deep-copy on read (so callers can mutate
-- freely) and splice on write (so callbacks attached to the live table fire).
-- Coalition is pushed through AirdromeController.setAirdromeCoalition so the
-- map display refreshes.
--
-- Failure mode: log + return nil. Module loads cleanly even if the DCS
-- modules can't be required (test VM, broken install).

local M = {}

local function safe_require(name)
    local ok, mod = pcall(require, name)
    if ok then return mod end
    return nil
end

local module_mission        = safe_require('me_mission')
local AirdromeController    = safe_require('Mission.AirdromeController')
local CoalitionController   = safe_require('Mission.CoalitionController')

-- Shallow-copies are tempting but the warehouse table contains nested
-- aircrafts / weapons subtables that the caller will own. Use a real deep
-- copy so subsequent mutations on the result don't leak into live data.
local function deep_copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deep_copy(v) end
    return out
end
M._deep_copy = deep_copy  -- exposed for tests

-- Read the airport entry at `airdrome_number` from the live mission data and
-- return a deep copy. nil when the index is out of range or me_mission is
-- unavailable.
function M.extract(airdrome_number)
    if type(airdrome_number) ~= 'number' then return nil end
    if not (module_mission and module_mission.mission
            and module_mission.mission.AirportsEquipment
            and module_mission.mission.AirportsEquipment.airports) then
        return nil
    end
    local entry = module_mission.mission.AirportsEquipment.airports[airdrome_number]
    if type(entry) ~= 'table' then return nil end
    return deep_copy(entry)
end

-- Predicate: returns true iff the entry matches the pristine "untouched
-- airbase" shape the ME emits for never-edited airports. See the design's
-- Default-detection decision for the exact rules.
function M.is_default(entry)
    if type(entry) ~= 'table' then return false end
    if entry.coalition ~= 'NEUTRAL' then return false end
    if entry.unlimitedFuel ~= true or entry.unlimitedAircrafts ~= true or entry.unlimitedMunitions ~= true then
        return false
    end
    if entry.OperatingLevel_Air ~= 10 or entry.OperatingLevel_Eqp ~= 10 or entry.OperatingLevel_Fuel ~= 10 then
        return false
    end
    if type(entry.aircrafts) == 'table' and next(entry.aircrafts) ~= nil then
        -- Default emits aircrafts = {}; some saves emit
        -- aircrafts = { helicopters = {}, planes = {} } — accept either by
        -- treating empty subtables as absent.
        for k, v in pairs(entry.aircrafts) do
            if type(v) == 'table' and next(v) ~= nil then return false end
            if type(v) ~= 'table' then return false end
            if k ~= 'helicopters' and k ~= 'planes' then return false end
        end
    end
    if type(entry.weapons) == 'table' and next(entry.weapons) ~= nil then return false end
    local function fuel_default(name)
        local f = entry[name]
        return type(f) == 'table' and f.InitFuel == 100
    end
    if not (fuel_default('jet_fuel') and fuel_default('methanol_mixture')
            and fuel_default('diesel') and fuel_default('gasoline')) then
        return false
    end
    return true
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_warehouse_ops.lua
```
Expected: `All warehouse_ops extract/is_default tests passed.`

- [ ] **Step 5: Add test to run-tests.ps1**

Append `'test_warehouse_ops.lua'` to the `$tests` array.

- [ ] **Step 6: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`.

- [ ] **Step 7: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua tools/me-mod/test/test_warehouse_ops.lua tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): warehouse_ops — extract + is_default for live airport data"
```

---

## Task 5: Warehouse ops — apply

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua`
- Modify: `tools/me-mod/test/test_warehouse_ops.lua`

`apply(airdrome_number, warehouse_table)` splices the deep-copied table into `mission.AirportsEquipment.airports[N]` and pushes the coalition through `AirdromeController.setAirdromeCoalition`. Returns `(true, nil)` on success or `(nil, reason)`.

- [ ] **Step 1: Add the failing apply tests**

Append the following block to `tools/me-mod/test/test_warehouse_ops.lua`, **before** the final `if failures > 0` check:

```lua
-- ---------------------------------------------------------------------------
-- apply tests — re-mock AirdromeController + CoalitionController with capture.
-- ---------------------------------------------------------------------------

local set_calls = {}  -- captures AirdromeController.setAirdromeCoalition calls
package.loaded['Mission.AirdromeController'] = {
    getAirdromeId = function(n) return 'id-' .. tostring(n) end,
    setAirdromeCoalition = function(id, name) set_calls[#set_calls + 1] = { id = id, name = name } end,
}
package.loaded['Mission.CoalitionController'] = {
    redCoalitionName     = function() return 'redName' end,
    blueCoalitionName    = function() return 'blueName' end,
    neutralCoalitionName = function() return 'neutralName' end,
}
package.loaded['dcs_sms_me.warehouse_ops'] = nil
warehouse_ops = require('dcs_sms_me.warehouse_ops')

-- Use a fresh airports table for apply so we can observe writes.
local live_airports = {
    [1]  = { coalition = 'NEUTRAL' },
    [68] = { coalition = 'NEUTRAL' },
}
package.loaded['me_mission'].mission.AirportsEquipment.airports = live_airports

-- Case: apply splices the table at the right index and pushes coalition.
do
    set_calls = {}
    local saved = {
        coalition = 'BLUE',
        unlimitedFuel = false,
        jet_fuel = { InitFuel = 50 },
        aircrafts = { helicopters = { ["AH-64D"] = { initialAmount = 100 } } },
    }
    local ok, err = warehouse_ops.apply(68, saved)
    check('apply returns ok', ok == true, 'err: ' .. tostring(err))
    check('live airports[68] is replaced (table reference differs)',
          live_airports[68] ~= saved, 'expected splice to deep-copy, not alias')
    check('live airports[68].coalition == BLUE',
          live_airports[68].coalition == 'BLUE')
    check('live airports[68].jet_fuel.InitFuel == 50',
          live_airports[68].jet_fuel and live_airports[68].jet_fuel.InitFuel == 50)
    check('setAirdromeCoalition called once', #set_calls == 1, 'got ' .. #set_calls)
    check('setAirdromeCoalition id', set_calls[1] and set_calls[1].id == 'id-68',
          'got ' .. tostring(set_calls[1] and set_calls[1].id))
    check('setAirdromeCoalition name == blueName',
          set_calls[1] and set_calls[1].name == 'blueName',
          'got ' .. tostring(set_calls[1] and set_calls[1].name))
    -- Mutating saved post-apply must not leak into live data.
    saved.coalition = 'MUTATED'
    check('post-apply mutation does not leak',
          live_airports[68].coalition == 'BLUE',
          'live coalition was: ' .. live_airports[68].coalition)
end

-- Case: apply with bad inputs returns nil + reason.
do
    local ok, err = warehouse_ops.apply(nil, { coalition = 'BLUE' })
    check('apply(nil, t) returns nil', ok == nil)
    check('apply(nil, t) returns error string', type(err) == 'string')

    local ok2, err2 = warehouse_ops.apply(68, nil)
    check('apply(68, nil) returns nil', ok2 == nil)
    check('apply(68, nil) returns error string', type(err2) == 'string')
end

-- Case: apply with missing coalition still splices the table (no controller call).
do
    set_calls = {}
    local ok = warehouse_ops.apply(1, { coalition = nil, jet_fuel = { InitFuel = 80 } })
    check('apply without coalition still ok', ok == true)
    check('apply without coalition: setAirdromeCoalition not called', #set_calls == 0)
    check('live airports[1].jet_fuel.InitFuel == 80',
          live_airports[1].jet_fuel and live_airports[1].jet_fuel.InitFuel == 80)
end
```

(Replace the line near the top that says `print('All warehouse_ops extract/is_default tests passed.')` with `print('All warehouse_ops tests passed.')`.)

- [ ] **Step 2: Run test to verify the new cases fail**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_warehouse_ops.lua
```
Expected: failures pointing at `apply` (function nil / not callable).

- [ ] **Step 3: Implement apply**

In `tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua`, append (just before `return M`):

```lua
-- Splice a saved warehouse entry into the live mission data and push the
-- coalition through AirdromeController so the map display + Resource Manager
-- dialog refresh. Always deep-copies so the caller can safely keep their
-- table around.
function M.apply(airdrome_number, warehouse_entry)
    if type(airdrome_number) ~= 'number' then
        return nil, 'airdrome_number must be a number'
    end
    if type(warehouse_entry) ~= 'table' then
        return nil, 'warehouse_entry must be a table'
    end
    if not (module_mission and module_mission.mission
            and module_mission.mission.AirportsEquipment
            and module_mission.mission.AirportsEquipment.airports) then
        return nil, 'mission.AirportsEquipment.airports unavailable'
    end

    local copy = deep_copy(warehouse_entry)
    module_mission.mission.AirportsEquipment.airports[airdrome_number] = copy

    if AirdromeController and CoalitionController and copy.coalition then
        local controller_name = ({
            BLUE    = CoalitionController.blueCoalitionName    and CoalitionController.blueCoalitionName(),
            RED     = CoalitionController.redCoalitionName     and CoalitionController.redCoalitionName(),
            NEUTRAL = CoalitionController.neutralCoalitionName and CoalitionController.neutralCoalitionName(),
        })[copy.coalition]
        if controller_name and AirdromeController.setAirdromeCoalition and AirdromeController.getAirdromeId then
            local id = AirdromeController.getAirdromeId(airdrome_number)
            if id then
                pcall(AirdromeController.setAirdromeCoalition, id, controller_name)
            end
        end
    end

    return true
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_warehouse_ops.lua
```
Expected: `All warehouse_ops tests passed.`

- [ ] **Step 5: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`.

- [ ] **Step 6: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/warehouse_ops.lua tools/me-mod/test/test_warehouse_ops.lua
git commit -m "feat(me-mod): warehouse_ops — apply splices table + pushes coalition"
```

---

## Task 6: prefab_distill — accept opts.airbases + bump version

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/prefab_distill.lua`
- Modify: `tools/me-mod/test/test_distill_parity.lua` (only if it asserts on `meta.sms_prefab_version`; usually doesn't — verify)
- Modify: existing `tools/me-mod/test/test_prefab_ops_save.lua` will not need touching here; an airbase-specific test goes in Task 7.

`opts.airbases` is an optional array of `{ name, airdrome_number_at_save, warehouse }`. When non-empty, distill writes it verbatim into `meta.airbases`. Version goes 0.2.0 → 0.3.0.

- [ ] **Step 1: Inspect test_distill_parity to confirm it doesn't assert version literal**

Read `tools/me-mod/test/test_distill_parity.lua` — search for `0.2.0`. If found, the test pins the version literal and we'll need to update its expected string.

```bash
grep -n '0\.2\.0' tools/me-mod/test/test_distill_parity.lua tools/me-mod/test/test_prefab_ops_save.lua tools/me-mod/test/test_prefab_ops_load.lua tools/me-mod/test/fixtures/**/*.lua
```
If any matches occur in tests, update them to `0.3.0` in this task. (Fixtures stay at their original versions — they represent legacy saves and the code must handle them.)

- [ ] **Step 2: Write the failing test**

Open `tools/me-mod/test/test_prefab_ops_save.lua`. Locate the existing block:
```lua
-- Case: place_at_origin propagates into meta on save.
```
Insert this new block immediately AFTER it (still BEFORE the empty-selection case):

```lua
-- Case: opts.airbases propagates into meta.airbases on save.
do
    captured.path, captured.content = nil, nil
    local airbases = {
        {
            name                    = 'Muwaffaq Salti',
            airdrome_number_at_save = 68,
            warehouse = {
                coalition = 'BLUE',
                jet_fuel  = { InitFuel = 50 },
            },
        },
    }
    local ok, _ = prefab_ops.save_selection('with_airbases', false, airbases)
    check('save_selection with airbases returns ok', ok == true, 'got ' .. tostring(ok))
    check('saved content has meta.airbases',
          captured.content and captured.content:find('%["airbases"%]', 1) ~= nil,
          'meta.airbases not in content')
    check('saved content has airbase name "Muwaffaq Salti"',
          captured.content and captured.content:find('"Muwaffaq Salti"', 1, true) ~= nil)
    check('saved content has BLUE coalition inside airbases',
          captured.content and captured.content:find('"BLUE"', 1, true) ~= nil)
    check('saved content version bumped to 0.3.0',
          captured.content and captured.content:find('"0%.3%.0"', 1) ~= nil,
          'version not 0.3.0')
end
```

- [ ] **Step 3: Run test to verify it fails**

```bash
cd tools/me-mod/test
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_prefab_ops_save.lua
```
Expected: failures on the new "with airbases" / "version 0.3.0" cases (`save_selection` doesn't accept the third arg yet, version still 0.2.0).

- [ ] **Step 4: Modify prefab_distill to accept opts.airbases + bump version**

Open `tools/me-mod/lua/dcs_sms_me/prefab_distill.lua`. Find the `PREFAB_VERSION` constant near the top and bump it:

```lua
local PREFAB_VERSION = '0.3.0'
```

Find the existing block that builds `meta` (currently around line ~228 from the recent fixed-position change):

```lua
    local meta = {
        sms_prefab_version = PREFAB_VERSION,
        name               = opts.name,
        created_utc        = utc_now(),
        source_dump        = source_dump_name,
        world_anchor       = { x = cx, y = cy },
        theatre            = opts.theatre,
    }
    -- Only emit when set so older saves stay byte-stable on no-op resaves.
    if opts.place_at_origin == true then
        meta.place_at_origin = true
    end
```

Append the airbases plumbing immediately AFTER the `place_at_origin` block:

```lua
    -- Optional per-airbase warehouse data captured by the marquee detect flow.
    -- We store the raw extracted entries verbatim — same shape DCS uses in the
    -- .miz `warehouses` file. Re-resolved by name on apply.
    if type(opts.airbases) == 'table' and #opts.airbases > 0 then
        meta.airbases = {}
        for i, ab in ipairs(opts.airbases) do
            if type(ab) == 'table' and type(ab.name) == 'string'
               and type(ab.warehouse) == 'table' then
                meta.airbases[#meta.airbases + 1] = {
                    name                    = ab.name,
                    airdrome_number_at_save = ab.airdrome_number_at_save,
                    warehouse               = ab.warehouse,
                }
            end
        end
        if #meta.airbases == 0 then meta.airbases = nil end
    end
```

(prefab_ops.save_selection still needs the third-arg signature update — that's Task 7. The new test will fail on that, which we'll fix next.)

- [ ] **Step 5: Run test — still failing because save_selection doesn't accept opts.airbases yet**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_prefab_ops_save.lua
```
Expected: still red on the airbases case (save_selection ignores the third arg). That's expected — Task 7 closes the gap.

- [ ] **Step 6: Commit (deliberate-red commit; Task 7 makes it green)**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/prefab_distill.lua tools/me-mod/test/test_prefab_ops_save.lua
git commit -m "feat(me-mod): prefab_distill accepts opts.airbases + bumps to 0.3.0 (red; ops plumbing in next commit)"
```

(The plan keeps Tasks 6 + 7 deliberately split for review readability. Tests go green at the end of Task 7.)

---

## Task 7: prefab_ops — save_selection(name, place_at_origin, airbases) + scan_dir surfacing

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua`
- Create: `tools/me-mod/test/test_prefab_ops_airbases.lua`
- Modify: `tools/me-mod/test/run-tests.ps1`

`save_selection` gains a third arg and forwards it through distill. `scan_dir` row gains `airbase_count` so the grid column can render. We also add a focused round-trip test fixture (separate file to keep the existing tests untouched).

- [ ] **Step 1: Update save_selection signature + plumbing**

Open `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua`. Find:

```lua
function M.save_selection(name, place_at_origin)
```
Replace with:

```lua
function M.save_selection(name, place_at_origin, airbases)
```

Find the existing distill call:

```lua
    local prefab = distill(dump, {
        name             = name,
        theatre          = theatre,
        place_at_origin  = place_at_origin == true,
    })
```
Replace with:

```lua
    local prefab = distill(dump, {
        name             = name,
        theatre          = theatre,
        place_at_origin  = place_at_origin == true,
        airbases         = airbases,
    })
```

- [ ] **Step 2: Update scan_dir to surface airbase_count**

In the same file, find `row_from_prefab`:

```lua
local function row_from_prefab(name, path, prefab)
    local meta = prefab.meta
    local g_count, s_inline = split_group_counts(prefab.groups)
    return {
        name            = meta.name or name,
        path            = path,
        theatre         = meta.theatre,
        source_dump     = meta.source_dump,
        place_at_origin = meta.place_at_origin == true,
        group_count     = g_count,
        static_count    = s_inline + count(prefab.statics),
        zone_count      = count(prefab.zones),
        drawing_count   = count(prefab.drawings),
    }
end
```

Replace with:

```lua
local function row_from_prefab(name, path, prefab)
    local meta = prefab.meta
    local g_count, s_inline = split_group_counts(prefab.groups)
    local airbase_count = 0
    if type(meta.airbases) == 'table' then airbase_count = #meta.airbases end
    return {
        name            = meta.name or name,
        path            = path,
        theatre         = meta.theatre,
        source_dump     = meta.source_dump,
        place_at_origin = meta.place_at_origin == true,
        airbase_count   = airbase_count,
        group_count     = g_count,
        static_count    = s_inline + count(prefab.statics),
        zone_count      = count(prefab.zones),
        drawing_count   = count(prefab.drawings),
    }
end
```

- [ ] **Step 3: Run the existing save tests**

```bash
cd tools/me-mod/test
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_prefab_ops_save.lua
```
Expected: `All prefab_ops save tests passed.` (Task 6's red test now goes green.)

- [ ] **Step 4: Write the round-trip test**

Create `tools/me-mod/test/test_prefab_ops_airbases.lua`:

```lua
-- Standalone round-trip test for the airbase-supplies plumbing through
-- distill / save / load / scan_dir.
-- Run via: lua test_prefab_ops_airbases.lua  (cwd: tools/me-mod/test/)

local fake_writedir = 'C:\\fake-saved-games\\'
package.preload['lfs'] = function()
    return {
        writedir = function() return fake_writedir end,
        mkdir = function() return true end,
        attributes = function() return { mode = 'file' } end,
        dir = function() local i = 0; return function() i = i + 1; return nil end end,
    }
end

-- Capture writes.
local captured = { path = nil, content = nil }
local real_open = io.open
io.open = function(path, mode)
    if mode == 'w' then
        return {
            write = function(_, c) captured.path = path; captured.content = c end,
            close = function() end,
        }
    end
    return real_open(path, mode)
end

package.preload['Mission.TheatreOfWarData'] = function()
    return { getName = function() return 'Syria' end }
end

-- Selection stub matching the existing save tests.
package.preload['dcs_sms_me.selection'] = function()
    return {
        snapshot = function()
            return {
                ok = true, timestamp_utc = '2026-05-05T12:00:00Z', selection_mode = 'multi',
                groups = {
                    { name='G1', x=100, y=200,
                      units={ { name='U1', type='F-16C_50', x=100, y=200, heading=0 } },
                      boss = { id=2, name='USA' } },
                },
                statics = {}, zones = {}, drawings = {}, nav_points = {}, raw = {},
            }
        end,
    }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: round-trip via load() — saved file is loadable and meta.airbases is intact.
do
    captured.path, captured.content = nil, nil
    local airbases = {
        {
            name                    = 'Muwaffaq Salti',
            airdrome_number_at_save = 68,
            warehouse = {
                coalition = 'BLUE',
                unlimitedFuel = false,
                jet_fuel  = { InitFuel = 50 },
                aircrafts = { helicopters = { ["AH-64D"] = { initialAmount = 100 } }, planes = {} },
            },
        },
        {
            name                    = 'Khalde',
            airdrome_number_at_save = 12,
            warehouse = { coalition = 'NEUTRAL', jet_fuel = { InitFuel = 80 } },
        },
    }
    local ok, _ = prefab_ops.save_selection('two_bases', false, airbases)
    check('save returns ok', ok == true)

    -- Eval the captured serialized content via dofile-ish path.
    local fn, err = loadstring(captured.content)
    check('captured content loads', fn ~= nil, tostring(err))
    local prefab = fn and fn()
    check('prefab table returned', type(prefab) == 'table' and prefab.meta ~= nil)
    check('prefab.meta.sms_prefab_version == 0.3.0', prefab.meta.sms_prefab_version == '0.3.0',
          'got ' .. tostring(prefab and prefab.meta and prefab.meta.sms_prefab_version))
    check('prefab.meta.airbases has 2 entries',
          type(prefab.meta.airbases) == 'table' and #prefab.meta.airbases == 2,
          'got ' .. tostring(prefab.meta.airbases and #prefab.meta.airbases))
    check('first airbase name preserved', prefab.meta.airbases[1].name == 'Muwaffaq Salti')
    check('first airbase coalition preserved', prefab.meta.airbases[1].warehouse.coalition == 'BLUE')
    check('first airbase nested AH-64D preserved',
          prefab.meta.airbases[1].warehouse.aircrafts
          and prefab.meta.airbases[1].warehouse.aircrafts.helicopters
          and prefab.meta.airbases[1].warehouse.aircrafts.helicopters['AH-64D']
          and prefab.meta.airbases[1].warehouse.aircrafts.helicopters['AH-64D'].initialAmount == 100)
    check('second airbase preserved', prefab.meta.airbases[2].name == 'Khalde')
end

-- Case: save without airbases omits meta.airbases entirely (no churn for non-airbase prefabs).
do
    captured.path, captured.content = nil, nil
    local ok = prefab_ops.save_selection('no_bases')
    check('save without airbases returns ok', ok == true)
    check('content does not contain "airbases"',
          captured.content and not captured.content:find('airbases', 1, true),
          'unexpected airbases field')
end

-- Case: row_from_prefab surfaces airbase_count via scan_dir-style read.
-- (Direct call to load via the captured content from the first case.)
do
    -- Build a fresh prefab string that load() can dofile.
    -- prefab_ops.load is a thin wrapper around dofile; we just write to a real
    -- temp file and call load() on it.
    local tmppath = os.tmpname()
    -- Lua os.tmpname on Windows returns paths starting with \, which io.open(path, 'w') still handles.
    local f = io.open(tmppath, 'w')
    f:write([[return {
  meta = {
    sms_prefab_version = "0.3.0",
    name = "abtest",
    theatre = "Syria",
    world_anchor = { x = 0, y = 0 },
    airbases = {
      { name = "Muwaffaq Salti", airdrome_number_at_save = 68, warehouse = { coalition = "BLUE" } },
      { name = "Khalde",         airdrome_number_at_save = 12, warehouse = { coalition = "NEUTRAL" } },
    },
  },
  groups = {}, statics = {}, zones = {}, drawings = {},
}]])
    f:close()

    local p = prefab_ops.load(tmppath)
    check('load() reads airbases-bearing prefab', p ~= nil and p.meta ~= nil)
    -- Build a row using the public scan_dir code path indirectly: we re-implement
    -- the row creation here since scan_dir needs lfs stubs. The point of THIS
    -- test is that the public load() result preserves the data; the grid layer
    -- reads p.meta.airbases directly via row_from_prefab — covered by other tests.
    check('loaded prefab.meta.airbases has 2 entries',
          type(p.meta.airbases) == 'table' and #p.meta.airbases == 2,
          'got ' .. tostring(p.meta.airbases and #p.meta.airbases))
    os.remove(tmppath)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops airbases tests passed.')
```

- [ ] **Step 5: Run new test**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_prefab_ops_airbases.lua
```
Expected: `All prefab_ops airbases tests passed.`

- [ ] **Step 6: Add test to run-tests.ps1**

Append `'test_prefab_ops_airbases.lua'` to the `$tests` array.

- [ ] **Step 7: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`, exit code 0.

- [ ] **Step 8: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/prefab_ops.lua tools/me-mod/test/test_prefab_ops_airbases.lua tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): prefab_ops save_selection accepts airbases + scan_dir surfaces airbase_count"
```

---

## Task 8: prefab_ops — apply_airbases for the place pipeline

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua`
- Modify: `tools/me-mod/test/test_prefab_ops_airbases.lua`

We add `M.apply_airbases(prefab) → ok, summary` that walks `meta.airbases`, looks up each by name in `AirdromeController.getAirdromes()`, and applies via `warehouse_ops.apply`. Returns a summary table the window layer can render.

This task does NOT modify the existing place flow yet — that's a window-side concern (Task 12). Apply is a pure operation we expose here.

- [ ] **Step 1: Add apply_airbases test cases**

Open `tools/me-mod/test/test_prefab_ops_airbases.lua`. Append BEFORE the final `if failures > 0` block:

```lua
-- ---------------------------------------------------------------------------
-- apply_airbases tests — exercise the apply pipeline with stubbed controllers.
-- ---------------------------------------------------------------------------

-- Airdrome list: name → airdromeNumber. Only airdromes present in the live
-- mission can be applied to.
local airdromes_in_mission = {
    { name = 'Muwaffaq Salti', n = 68 },
    { name = 'Khalde',         n = 12 },
    -- 'H4' deliberately absent so we test the not-found branch.
}
local function rebuild_airdromes()
    local out = {}
    for _, e in ipairs(airdromes_in_mission) do
        out[#out + 1] = {
            x = 0, y = 0,
            getName             = function(self) return e.name end,
            getAirdromeNumber   = function(self) return e.n end,
        }
    end
    return out
end

-- Capture warehouse_ops.apply calls.
local apply_calls = {}
package.loaded['Mission.AirdromeController'] = {
    getAirdromes        = function() return rebuild_airdromes() end,
    getAirdromeId       = function(n) return 'id-' .. tostring(n) end,
    setAirdromeCoalition= function() end,
}
package.loaded['Mission.CoalitionController'] = {
    redCoalitionName = function() return 'red' end,
    blueCoalitionName = function() return 'blue' end,
    neutralCoalitionName = function() return 'neutral' end,
}

-- Stub me_mission.mission.AirportsEquipment so warehouse_ops.apply has somewhere to write.
local live_airports = { [12] = {}, [68] = {} }
package.preload['me_mission'] = function()
    return { mission = { AirportsEquipment = { airports = live_airports } } }
end
package.loaded['me_mission'] = nil  -- force a re-require so the new stub is picked up
package.loaded['dcs_sms_me.warehouse_ops'] = nil
package.loaded['prefab_ops'] = nil
prefab_ops = require('prefab_ops')

-- Patch warehouse_ops.apply to capture calls AFTER prefab_ops has require'd it.
local warehouse_ops_real = require('dcs_sms_me.warehouse_ops')
warehouse_ops_real.apply = function(n, w)
    apply_calls[#apply_calls + 1] = { n = n, w = w }
    live_airports[n] = w  -- emulate splice for downstream assertions
    return true
end

-- Case: apply_airbases applies all named airdromes that are present.
do
    apply_calls = {}
    local prefab = {
        meta = {
            theatre  = 'Syria',
            airbases = {
                { name = 'Muwaffaq Salti', airdrome_number_at_save = 68,
                  warehouse = { coalition = 'BLUE', jet_fuel = { InitFuel = 50 } } },
                { name = 'Khalde',         airdrome_number_at_save = 12,
                  warehouse = { coalition = 'NEUTRAL' } },
            },
        }
    }
    local ok, summary = prefab_ops.apply_airbases(prefab, { current_theatre = 'Syria' })
    check('apply_airbases returns ok', ok == true, 'summary err: ' .. tostring(summary and summary.error))
    check('apply called twice', #apply_calls == 2, 'got ' .. #apply_calls)
    check('summary applied count == 2',
          summary and summary.applied == 2, 'got ' .. tostring(summary and summary.applied))
    check('summary skipped count == 0',
          summary and summary.skipped == 0, 'got ' .. tostring(summary and summary.skipped))
end

-- Case: apply_airbases skips airdromes not present in destination.
do
    apply_calls = {}
    local prefab = {
        meta = {
            theatre  = 'Syria',
            airbases = {
                { name = 'Muwaffaq Salti', airdrome_number_at_save = 68,
                  warehouse = { coalition = 'BLUE' } },
                { name = 'H4', airdrome_number_at_save = 80,   -- not in airdromes_in_mission
                  warehouse = { coalition = 'BLUE' } },
            },
        }
    }
    local ok, summary = prefab_ops.apply_airbases(prefab, { current_theatre = 'Syria' })
    check('apply_airbases returns ok with partial application', ok == true)
    check('apply called once (only the present airdrome)', #apply_calls == 1)
    check('summary applied == 1', summary.applied == 1)
    check('summary skipped == 1', summary.skipped == 1)
    check('summary missing list mentions H4',
          type(summary.missing) == 'table' and summary.missing[1] == 'H4',
          'got ' .. tostring(summary.missing and summary.missing[1]))
end

-- Case: theatre mismatch refuses the whole apply step.
do
    apply_calls = {}
    local prefab = {
        meta = {
            theatre  = 'Syria',
            airbases = {
                { name = 'Muwaffaq Salti', warehouse = { coalition = 'BLUE' } },
            },
        }
    }
    local ok, summary = prefab_ops.apply_airbases(prefab, { current_theatre = 'Caucasus' })
    check('apply_airbases refused on theatre mismatch', ok == nil)
    check('no apply calls fired', #apply_calls == 0)
    check('summary indicates theatre mismatch',
          type(summary) == 'table' and summary.error and summary.error:find('theatre', 1, true) ~= nil)
end

-- Case: prefab without meta.airbases is a no-op (returns ok with applied=0).
do
    apply_calls = {}
    local prefab = { meta = { theatre = 'Syria' } }
    local ok, summary = prefab_ops.apply_airbases(prefab, { current_theatre = 'Syria' })
    check('apply_airbases no-op returns ok', ok == true)
    check('no apply calls', #apply_calls == 0)
    check('summary applied == 0', summary.applied == 0)
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_prefab_ops_airbases.lua
```
Expected: failures (`apply_airbases` is nil).

- [ ] **Step 3: Implement apply_airbases**

Open `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua`. Find the `require` block near the top and ensure `warehouse_ops` is required:

```lua
local warehouse_ops = require('dcs_sms_me.warehouse_ops')
```
(Add this line after the existing `local distill = require('dcs_sms_me.prefab_distill')` line if not present.)

Then append BEFORE `return M`:

```lua
-- Apply meta.airbases to the live mission state. Re-resolves each entry by
-- airbase name (the airdromeNumber at save time may not match in the
-- destination mission). Theatre mismatch refuses the whole step. Returns
-- (true, summary) on success or (nil, summary_with_error) on failure.
--
-- summary = {
--     applied = N,                  -- count of warehouses successfully spliced
--     skipped = N,                  -- count of named airdromes NOT found in destination
--     missing = { name1, ... },     -- names that were skipped
--     error   = string?,            -- set on hard failure (theatre mismatch, etc.)
-- }
function M.apply_airbases(prefab, opts)
    if type(prefab) ~= 'table' or type(prefab.meta) ~= 'table' then
        return nil, { applied = 0, skipped = 0, missing = {}, error = 'prefab missing meta' }
    end
    local airbases = prefab.meta.airbases
    if type(airbases) ~= 'table' or #airbases == 0 then
        return true, { applied = 0, skipped = 0, missing = {} }
    end

    opts = opts or {}
    local current_theatre = opts.current_theatre
    if current_theatre and prefab.meta.theatre and prefab.meta.theatre ~= current_theatre then
        return nil, {
            applied = 0, skipped = #airbases, missing = {},
            error = 'theatre mismatch: prefab=' .. tostring(prefab.meta.theatre)
                    .. ' destination=' .. tostring(current_theatre),
        }
    end

    local AC_ok, AC = pcall(require, 'Mission.AirdromeController')
    if not AC_ok or not AC or type(AC.getAirdromes) ~= 'function' then
        return nil, {
            applied = 0, skipped = #airbases, missing = {},
            error = 'AirdromeController unavailable',
        }
    end

    local by_name = {}
    for _, ad in ipairs(AC.getAirdromes() or {}) do
        if ad.getName then by_name[ad:getName()] = ad end
    end

    local applied, skipped, missing = 0, 0, {}
    for _, ab in ipairs(airbases) do
        local ad = ab.name and by_name[ab.name] or nil
        if ad and ad.getAirdromeNumber then
            local n = ad:getAirdromeNumber()
            local ok = warehouse_ops.apply(n, ab.warehouse)
            if ok then applied = applied + 1
            else skipped = skipped + 1; missing[#missing + 1] = ab.name
            end
        else
            skipped = skipped + 1
            if ab.name then missing[#missing + 1] = ab.name end
        end
    end
    return true, { applied = applied, skipped = skipped, missing = missing }
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' test_prefab_ops_airbases.lua
```
Expected: `All prefab_ops airbases tests passed.`

- [ ] **Step 5: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`.

- [ ] **Step 6: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/prefab_ops.lua tools/me-mod/test/test_prefab_ops_airbases.lua
git commit -m "feat(me-mod): prefab_ops.apply_airbases — name-resolved warehouse splice + summary"
```

---

## Task 9: window.lua — install marquee hook + pending airbases state + status-bar prompt

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua`
- Modify: `tools/me-mod/lua/dcs_sms_me/init.lua`

The window subscribes to the marquee hook on first show. When the rect-complete callback fires, we hit-test airdromes; if any are inside, we capture them as `W.pending_airbases` and show a status-bar prompt. The Save button reads this state in Task 10.

(Init.lua change is a one-liner so we install the hook once, on bootstrap, not per-window-show — that way a marquee BEFORE the user opens the prefab manager doesn't get lost. The state is per-window though.)

- [ ] **Step 1: Modify init.lua to install marquee_hook**

Open `tools/me-mod/lua/dcs_sms_me/init.lua` and find the existing `require` block. Look for where modules are wired up and the menu is installed. Add a one-line install call. The existing pattern looks like:

```lua
local menu = require('dcs_sms_me.menu')
menu.install()
```

Append (or merge with existing init flow):

```lua
-- Install the marquee hook eagerly on bootstrap so a rect drawn before the
-- prefab manager window opens still gets remembered. Subscribers attach
-- later (window.lua attaches on its first show).
local marquee_hook = require('dcs_sms_me.marquee_hook')
marquee_hook.install()
```

If `init.lua` doesn't currently exist or doesn't have a clear "wire stuff up" section, locate the file and add this block after any other module-install lines. Read the file first:

```bash
cat tools/me-mod/lua/dcs_sms_me/init.lua
```

If the file just `require()`s things without explicit installation, the import-side-effect is enough — `require('dcs_sms_me.marquee_hook'); marquee_hook.install()` is the right shape. Add the two lines.

- [ ] **Step 2: Add pending-airbases state to window.lua W struct**

Open `tools/me-mod/lua/dcs_sms_me/window.lua`. Find the W struct (search for `local W = {`):

```lua
local W = {
    -- dxgui handles
    window     = nil,
    name_input = nil,
    save_btn   = nil,
    fixed_check     = nil,
    fixed_check_lbl = nil,
    ...
}
```

Add at the end of the runtime-state section (after `filter_input = nil,`):

```lua
    pending_airbases = nil,    -- set by marquee callback; consumed by on_save_click
    marquee_subscribed = false,-- one-shot guard so Ctrl+Shift+R reloads don't multi-subscribe
```

- [ ] **Step 3: Require modules used by the marquee callback**

Find the require block near the top of `window.lua` (currently includes prefab_ops, undo, dtc_skins). Add:

```lua
local marquee_hook  = require('dcs_sms_me.marquee_hook')
local airbase_detect = require('dcs_sms_me.airbase_detect')
local warehouse_ops = require('dcs_sms_me.warehouse_ops')
```

- [ ] **Step 4: Add marquee callback + subscribe-on-first-show**

In `window.lua`, find the `M.show()` function. Just BEFORE the `-- Re-populate so a mission-change between hides surfaces the new` comment (i.e. at the very top of `M.show()` after the entry-log line), insert:

```lua
    -- Subscribe to the marquee hook once. The hook itself was installed in init.lua
    -- on bootstrap; this just attaches our window's airbase-detect handler.
    if not W.marquee_subscribed then
        marquee_hook.subscribe(function(start_xy, end_xy)
            -- Bail if the prefab manager isn't currently visible — we don't
            -- want to silently capture airbases when the user can't see the
            -- prompt.
            if not (W.window and W.window.getVisible and W.window:getVisible()) then return end

            local hits = airbase_detect.airbases_in_rect(start_xy, end_xy) or {}
            if #hits == 0 then
                W.pending_airbases = nil
                return
            end

            -- Filter out default (untouched) airbases — there's nothing to capture.
            local non_default = {}
            for _, h in ipairs(hits) do
                local entry = warehouse_ops.extract(h.airdrome_number_at_save)
                if entry and not warehouse_ops.is_default(entry) then
                    h.warehouse = entry
                    non_default[#non_default + 1] = h
                end
            end

            if #non_default == 0 then
                W.pending_airbases = nil
                set_status('Selection covers ' .. #hits .. ' airbase(s) — all unmodified, nothing to capture.')
                return
            end

            W.pending_airbases = non_default
            if #non_default == 1 then
                set_status('Airbase in selection: ' .. non_default[1].name
                           .. '. Save will include its supplies.')
            else
                local names = {}
                for _, h in ipairs(non_default) do names[#names + 1] = h.name end
                set_status(#non_default .. ' airbases in selection: '
                           .. table.concat(names, ', ') .. '. Save will include all.')
            end
        end)
        W.marquee_subscribed = true
    end

```

(That placement matters — `set_status` needs to be in scope. It's defined module-level at line ~145, so any function defined inside `M.show` can call it.)

- [ ] **Step 5: Quick smoke test — window.lua still loads**

```bash
cd tools/me-mod/test
'/c/Program Files (x86)/Lua/5.1/lua.exe' smoke_menu.lua
```
Expected: `function`. (smoke_menu loads window.lua under stubbed dxgui to ensure no syntax errors / missing globals.)

- [ ] **Step 6: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`.

- [ ] **Step 7: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/window.lua tools/me-mod/lua/dcs_sms_me/init.lua
git commit -m "feat(me-mod): window subscribes to marquee hook + captures pending airbases on rect-complete"
```

---

## Task 10: window.lua — Save plumbs pending airbases + grid AB column

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua`

`on_save_click` reads `W.pending_airbases` and forwards to `prefab_ops.save_selection(name, fixed, airbases)`. After save, the pending state is cleared (post-save the bundle is in the file). The grid gets a new `AB` column showing the count.

- [ ] **Step 1: Modify on_save_click + do_save to plumb airbases**

Find `read_fixed_check` and the `do_save` / `on_save_click` functions in `window.lua`. Update `do_save`:

```lua
local function do_save(name, place_at_origin, airbases)
    local ok, path_or_err = prefab_ops.save_selection(name, place_at_origin, airbases)
    if ok then
        local extras = {}
        if place_at_origin then extras[#extras + 1] = 'fixed' end
        if airbases and #airbases > 0 then extras[#extras + 1] = #airbases .. ' airbase(s)' end
        local suffix = #extras > 0 and ' [' .. table.concat(extras, ', ') .. ']' or ''
        set_status('Saved ' .. name .. suffix .. ' → ' .. tostring(path_or_err))
        log.write('sms.me.prefab', log.INFO, 'saved ' .. name)
        refresh_list()
        pcall(function()
            if W.name_input and W.name_input.setText then W.name_input:setText('') end
        end)
        W.pending_airbases = nil  -- consumed
    else
        set_status('Save failed: ' .. tostring(path_or_err))
        log.write('sms.me.prefab', log.ERROR, 'save failed: ' .. tostring(path_or_err))
    end
end
```

Update `on_save_click` to pass airbases through every `do_save` call site. Find:

```lua
local function on_save_click()
    pcall(function()
        local name = ''
        if W.name_input and W.name_input.getText then name = W.name_input:getText() or '' end
        local fixed = read_fixed_check()
        if name == '' then
            ...
            do_save(name, fixed)
            return
        end

        if prefab_ops.exists(name) then
            show_overlay(
                'Prefab "' .. name .. '" already exists.\n\nOverwrite, rename, or cancel?',
                {
                    { label = 'Overwrite', on_click = function() do_save(name, fixed) end },
                    ...
                },
                'question')
            return
        end

        do_save(name, fixed)
    end)
end
```

Replace with:

```lua
local function on_save_click()
    pcall(function()
        local name = ''
        if W.name_input and W.name_input.getText then name = W.name_input:getText() or '' end
        local fixed = read_fixed_check()
        local airbases = W.pending_airbases
        if name == '' then
            set_status('Empty name — using timestamped fallback. See dcs.log.')
            name = 'prefab-' .. os.date('!%Y%m%dT%H%M%SZ')
            log.write('sms.me.prefab', log.WARNING, 'save with empty name → ' .. name)
            do_save(name, fixed, airbases)
            return
        end

        if prefab_ops.exists(name) then
            show_overlay(
                'Prefab "' .. name .. '" already exists.\n\nOverwrite, rename, or cancel?',
                {
                    { label = 'Overwrite', on_click = function() do_save(name, fixed, airbases) end },
                    { label = 'Rename',    on_click = function() focus_name_input(); set_status('Type a new name and click Save.') end },
                    { label = 'Cancel',    on_click = function() set_status('Save cancelled.') end },
                },
                'question')
            return
        end

        do_save(name, fixed, airbases)
    end)
end
```

- [ ] **Step 2: Add the `AB` column to COLS**

Find the `local COLS = {` definition and replace with:

```lua
local COLS = {
    { key = 'name',            label = 'Name',      width = 190, numeric = false },
    { key = 'theatre',         label = 'Theatre',   width = 90,  numeric = false },
    { key = 'place_at_origin', label = 'Fixed Pos', width = 60,  numeric = false },
    { key = 'airbase_count',   label = 'AB',        width = 50,  numeric = true  },
    { key = 'group_count',     label = 'G',         width = 35,  numeric = true  },
    { key = 'static_count',    label = 'S',         width = 35,  numeric = true  },
    { key = 'zone_count',      label = 'Z',         width = 35,  numeric = true  },
    { key = 'drawing_count',   label = 'D',         width = 35,  numeric = true  },
}
```

- [ ] **Step 3: Update render_grid for the new column**

Find `render_grid`'s cell-population section. Replace the existing block:

```lua
            if r.error then
                local err_text = tostring(r.error)
                W.grid:setCell(0, row, make_cell('[ERROR] ' .. r.name, err_text))
                W.grid:setCell(1, row, make_cell(err_text:sub(1, 40), err_text))
                W.grid:setCell(2, row, make_cell(''))
                W.grid:setCell(3, row, make_cell(''))
                W.grid:setCell(4, row, make_cell(''))
                W.grid:setCell(5, row, make_cell(''))
                W.grid:setCell(6, row, make_cell(''))
            else
                W.grid:setCell(0, row, make_cell(r.name, r.name))
                W.grid:setCell(1, row, make_cell(r.theatre or '?'))
                W.grid:setCell(2, row, make_cell(r.place_at_origin and 'Yes' or ''))
                W.grid:setCell(3, row, make_cell(r.group_count   or 0))
                W.grid:setCell(4, row, make_cell(r.static_count  or 0))
                W.grid:setCell(5, row, make_cell(r.zone_count    or 0))
                W.grid:setCell(6, row, make_cell(r.drawing_count or 0))
            end
```

With:

```lua
            if r.error then
                local err_text = tostring(r.error)
                W.grid:setCell(0, row, make_cell('[ERROR] ' .. r.name, err_text))
                W.grid:setCell(1, row, make_cell(err_text:sub(1, 40), err_text))
                W.grid:setCell(2, row, make_cell(''))
                W.grid:setCell(3, row, make_cell(''))
                W.grid:setCell(4, row, make_cell(''))
                W.grid:setCell(5, row, make_cell(''))
                W.grid:setCell(6, row, make_cell(''))
                W.grid:setCell(7, row, make_cell(''))
            else
                local ab_text = ''
                if (r.airbase_count or 0) == 1 then ab_text = 'Yes'
                elseif (r.airbase_count or 0) > 1 then ab_text = tostring(r.airbase_count)
                end
                W.grid:setCell(0, row, make_cell(r.name, r.name))
                W.grid:setCell(1, row, make_cell(r.theatre or '?'))
                W.grid:setCell(2, row, make_cell(r.place_at_origin and 'Yes' or ''))
                W.grid:setCell(3, row, make_cell(ab_text))
                W.grid:setCell(4, row, make_cell(r.group_count   or 0))
                W.grid:setCell(5, row, make_cell(r.static_count  or 0))
                W.grid:setCell(6, row, make_cell(r.zone_count    or 0))
                W.grid:setCell(7, row, make_cell(r.drawing_count or 0))
            end
```

- [ ] **Step 4: Smoke test**

```bash
cd tools/me-mod/test
'/c/Program Files (x86)/Lua/5.1/lua.exe' smoke_menu.lua
```
Expected: `function`.

- [ ] **Step 5: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`.

- [ ] **Step 6: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): Save flow plumbs pending airbases; new AB column in grid"
```

---

## Task 11: window.lua — Apply step on place

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua`

After `prefab_ops.place(...)` (the existing call inside `on_place_click` and `on_place_origin_click`) returns success, we kick off the airbase apply step. Theatre is read via the same `Mission.TheatreOfWarData` API used by save_selection. Status bar reports outcome. If the destination airbase is already customised, prompt overwrite/skip; this happens BEFORE the splice so the caller has a chance to back out per-airbase.

For v1 simplicity: the customised-target prompt is collapsed to a single yes-to-all confirmation if any destination airbase is already customised. Per-airbase overwrite UX is a future polish item.

- [ ] **Step 1: Find the place callbacks**

Search `window.lua` for `prefab_ops.place(`. There are typically two call sites — one in `on_place_origin_click` (the "Place at original" button) and one inside `place_state.onMouseDown` (the click-place pipeline). Read 20 lines of context around each.

```bash
grep -n 'prefab_ops.place\b' tools/me-mod/lua/dcs_sms_me/window.lua
```

- [ ] **Step 2: Add a helper that runs the airbase apply step**

Find a stable spot in `window.lua` — directly above `local function on_place_origin_click` is a good location. Add:

```lua
-- Read current theatre via the same API save_selection uses.
local function current_theatre()
    local th
    pcall(function()
        local TheatreOfWarData = require('Mission.TheatreOfWarData')
        if TheatreOfWarData and type(TheatreOfWarData.getName) == 'function' then
            th = TheatreOfWarData.getName()
        end
    end)
    return th
end

-- Returns true if any of the destination airbases (by name) currently have a
-- non-default warehouse entry. Used to gate the overwrite prompt.
local function any_destination_customised(prefab)
    local AC_ok, AC = pcall(require, 'Mission.AirdromeController')
    if not AC_ok or not AC or type(AC.getAirdromes) ~= 'function' then return false end
    local by_name = {}
    for _, ad in ipairs(AC.getAirdromes() or {}) do
        if ad.getName then by_name[ad:getName()] = ad end
    end
    for _, ab in ipairs((prefab.meta and prefab.meta.airbases) or {}) do
        local ad = ab.name and by_name[ab.name]
        if ad and ad.getAirdromeNumber then
            local entry = warehouse_ops.extract(ad:getAirdromeNumber())
            if entry and not warehouse_ops.is_default(entry) then return true end
        end
    end
    return false
end

local function run_airbase_apply(prefab)
    if not (prefab and prefab.meta and prefab.meta.airbases and #prefab.meta.airbases > 0) then
        return  -- no airbases on this prefab; nothing to do
    end

    local function do_apply()
        local ok, summary = prefab_ops.apply_airbases(prefab, { current_theatre = current_theatre() })
        if ok then
            local msg = ('Airbase supplies: %d applied'):format(summary.applied)
            if summary.skipped > 0 then
                msg = msg .. (', %d skipped'):format(summary.skipped)
                if summary.missing and #summary.missing > 0 then
                    msg = msg .. ' (' .. table.concat(summary.missing, ', ') .. ')'
                end
            end
            set_status(msg)
        else
            set_status('Airbase supplies skipped: ' .. tostring(summary and summary.error or 'unknown'))
        end
    end

    if any_destination_customised(prefab) then
        show_overlay(
            'Some destination airbases already have custom supplies set.\n\nOverwrite with the prefab\'s saved supplies?',
            {
                { label = 'Overwrite', on_click = do_apply },
                { label = 'Skip',      on_click = function() set_status('Airbase supplies skipped (kept destination customisation).') end },
            },
            'question')
    else
        do_apply()
    end
end
```

- [ ] **Step 3: Wire run_airbase_apply into the two place callbacks**

Find each call site of `prefab_ops.place(`. The pattern is roughly:

```lua
local ok, err = prefab_ops.place(prefab, opts)
if ok then
    set_status(...)
    ...
end
```

Right after the success-status set, add the apply step. Specifically:

**Site 1: `on_place_origin_click`** — find:
```lua
local function on_place_origin_click()
```
and read ~30 lines. After the existing place-success branch (`if ok then`), insert:

```lua
        run_airbase_apply(prefab)
```

(The exact local-variable name for the loaded prefab table is whatever `on_place_origin_click` already uses. Read it before inserting; common names are `prefab`, `loaded`, or it may inline the load. If the load is inline, lift it into a local first.)

**Site 2: `place_state.onMouseDown` inside `enter_place_pending`** — same pattern. After `prefab_ops.place(...)` returns ok, add:

```lua
                    run_airbase_apply(prefab)
```

(Indent appropriately.)

If either call site doesn't have a local `prefab` table available — it was loaded inline in the call to `prefab_ops.place` — refactor that call to bind the load result first:

```lua
-- Before:
local ok, err = prefab_ops.place(prefab_ops.load(row.path), opts)
-- After:
local prefab = prefab_ops.load(row.path)
local ok, err = prefab_ops.place(prefab, opts)
if ok then
    run_airbase_apply(prefab)
end
```

- [ ] **Step 4: Smoke test**

```bash
cd tools/me-mod/test
'/c/Program Files (x86)/Lua/5.1/lua.exe' smoke_menu.lua
```
Expected: `function`.

- [ ] **Step 5: Run full test suite**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1
```
Expected: every section ends with `passed`.

- [ ] **Step 6: Commit**

```bash
cd D:/git/dcs-sms/.worktrees/airbase-supplies
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): Place flow runs airbase apply step (theatre check + overwrite prompt)"
```

---

## Task 12: Mirror to live install + final smoke

**Files:**
- (none modified — this task is build verification + dev-loop ergonomics)

The user's dev flow copies sources from the source tree to the install path so Ctrl+Shift+R reloads pick them up. We mirror everything the worktree changed in one shot.

- [ ] **Step 1: Confirm full test suite green from worktree**

```bash
cd tools/me-mod/test
powershell -NoProfile -ExecutionPolicy Bypass -File ./run-tests.ps1 2>&1 | tail -20
```
Expected: every section ends with `passed`, no `FAIL`.

- [ ] **Step 2: Mirror new + modified Lua files to the DCS install path**

Run from the worktree root (`D:/git/dcs-sms/.worktrees/airbase-supplies`):

```bash
INSTALL='D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules/dcs_sms_me'
SRC='tools/me-mod/lua/dcs_sms_me'
cp -v "$SRC/marquee_hook.lua" "$INSTALL/marquee_hook.lua"
cp -v "$SRC/airbase_detect.lua" "$INSTALL/airbase_detect.lua"
cp -v "$SRC/warehouse_ops.lua" "$INSTALL/warehouse_ops.lua"
cp -v "$SRC/prefab_distill.lua" "$INSTALL/prefab_distill.lua"
cp -v "$SRC/prefab_ops.lua" "$INSTALL/prefab_ops.lua"
cp -v "$SRC/window.lua" "$INSTALL/window.lua"
cp -v "$SRC/init.lua" "$INSTALL/init.lua"
```
Expected: 7 lines, each starting with `'D:/git/...' -> 'D:/Program Files/...'`.

- [ ] **Step 3: Smoke test the full window load under stubbed dxgui one more time**

```bash
'/c/Program Files (x86)/Lua/5.1/lua.exe' tools/me-mod/test/smoke_menu.lua
```
Expected: `function`.

- [ ] **Step 4: No commit needed — this task only mirrors files**

The implementation work is done. Commits are already on `feat/me-mod-airbase-supplies` from earlier tasks. The user will:

1. Open DCS Mission Editor and load any mission (or `D:/git/honu/missions/airfield_inventory_test.miz`).
2. Open the DCS-SMS → Prefab Manager menu.
3. Use the standard MultiSelect tool to drag a rect that includes Muwaffaq Salti.
4. Confirm the status bar reports the airbase.
5. Save as a prefab, then create a new mission and apply.

---

## Self-Review

**Spec coverage check:**

- [x] Marquee hook → Task 2
- [x] Airdrome hit-test → Task 3
- [x] Warehouse extract → Task 4
- [x] Default-detection → Task 4
- [x] Warehouse apply (splice + coalition) → Task 5
- [x] meta.airbases additive field → Task 6
- [x] Version bump 0.2.0 → 0.3.0 → Task 6
- [x] save_selection accepts airbases → Task 7
- [x] scan_dir surfaces airbase_count → Task 7
- [x] apply pipeline (theatre check + name lookup + summary) → Task 8
- [x] Window subscribe to marquee + status-bar prompt → Task 9
- [x] Window save uses pending → Task 10
- [x] Grid AB column → Task 10
- [x] Window apply step (overwrite prompt) → Task 11
- [x] Mirror to install → Task 12

**Spec items intentionally NOT in this plan:**

- **Pure-airbase prefab Place-button relabel** — Phase 5 polish in spec. Skipped for v1 since the apply step is the same code path; a single-status-bar message suffices.
- **Multi-airbase Pick… modal** — spec proposed for 2+ airbases. Plan auto-includes all by default and surfaces names in the status bar. The user can clear/restart the marquee if they want fewer. Adding a Pick modal is straightforward but doubles the UI surface; deferred to a follow-up.

**Placeholder scan:** No "TBD" / "TODO" / "implement later" / "appropriate error handling" / "similar to Task N" found in the plan. Every code block contains the actual code an implementer needs.

**Type consistency:** 
- `airbase_detect.airbases_in_rect` returns `{name, airdrome_number_at_save, x, y}` — used consistently in Task 9 and `meta.airbases` shape (Task 6).
- `warehouse_ops.extract(N)` returns deep-copied entry — used in Task 9 (filtering default entries before storing pending) and in Task 11 (overwrite-prompt detection).
- `warehouse_ops.apply(N, w)` returns `(true)` or `(nil, err)` — checked consistently in Task 8 (`apply_airbases` looks for `true`).
- `prefab_ops.apply_airbases(prefab, {current_theatre = ...})` returns `(true|nil, summary)` — Task 11 assumes this exact signature.
- `M.pending_airbases` is `{ {name, airdrome_number_at_save, x, y, warehouse}, ... }` — set by the marquee callback (Task 9), read by `on_save_click` (Task 10).
- COLS array consistently includes `airbase_count` after `place_at_origin` — render_grid cell indices match across Task 10's edits.
