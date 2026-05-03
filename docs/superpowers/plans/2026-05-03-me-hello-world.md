# Mission Editor Hello World — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a custom dxgui window inside the DCS Mission Editor with one button that dumps the current selection (groups, statics, trigger zones, drawings, navigation points) to a Lua-table file under `Saved Games\DCS\dcs-sms\me\`, plus the CLI tooling (`install-me-mod` / `uninstall-me-mod`) to install and remove the mod cleanly.

**Architecture:** Five small Lua modules (`init`, `window`, `selection`, `serializer`, `paths`) loaded into the GUI Lua state via a one-line `require` patch to `<DCS>/MissionEditor/MissionEditor.lua`. The patch-fragile selection-state lookup is isolated in `selection.lua` behind `pcall`-contained boundaries. Files written via `lfs` / `io` from inside the GUI environment (no bridge needed). Go CLI subcommands manage the install-dir patching, file copying, and backup/restore.

**Tech Stack:** Lua 5.1 (DCS GUI environment), Go 1.22 (CLI), PowerShell (test driver), `dxgui` (DCS internal widget toolkit).

**Spec:** [`docs/superpowers/specs/2026-05-03-me-hello-world-design.md`](../specs/2026-05-03-me-hello-world-design.md)

---

## Decisions made during plan-writing

These deviate from or extend the spec; recorded here so they're visible at a glance.

- **Lua source location moved from `me-mod/` (top-level) to `tools/me-mod/` (inside the Go module).** Go's `//go:embed` directive can only embed files under the package directory; co-locating the canonical Lua source with `embed.go` removes a fragile pre-build sync step. The spec's `me-mod/` directory is replaced one-for-one with `tools/me-mod/`. README and OvGME folder live there too.
- **OvGME packaging is a folder skeleton only for v1.** Shipping a patched copy of `MissionEditor.lua` would go stale every DCS patch; the CLI is the recommended path. The OvGME folder is created with a placeholder README that points users at the CLI and documents how to assemble the OvGME bundle by hand if they want it.
- **DCS install path discovery added to `dcspath` package.** `DCS_SMS_DCS_PATH` env var, `dcs_install` config key, and an explicit `--dcs-path` flag. No automatic discovery (DCS install dir can live anywhere); first install requires the flag, subsequent uses cache it in config.
- **Unit tests for the Lua serializer run via standalone Lua 5.1.** A PowerShell driver locates `lua.exe` (or `lua5.1.exe`) on `PATH`. If absent, the driver prints manual instructions and exits non-zero — CI / local dev should have one installed.
- **Backup file name is `MissionEditor.lua.dcs-sms.bak`** (matches the spec). Refuse to install if it already exists; that means the user has a previous install that wasn't cleanly uninstalled.
- **The `require` line is appended at EOF of `MissionEditor.lua`**, preceded by a comment marker `-- dcs-sms-me-mod begin` and followed by `-- dcs-sms-me-mod end`. The marker is what the install command uses to detect "already patched" (idempotency) and what the uninstall command uses to remove the patch surgically rather than relying on the backup (in case the user has made other manual edits to MissionEditor.lua since install). Backup is the fallback if the markers are missing for some reason.

---

## File structure

### Created

```
tools/me-mod/
├── README.md                                         — install instructions, manual smoke checklist
├── lua/
│   ├── embed.go                                      — package memod; //go:embed dcs_sms_me
│   └── dcs_sms_me/
│       ├── init.lua                                  — bootstrap (require window + show)
│       ├── window.lua                                — dxgui window + button + status label + click handler
│       ├── selection.lua                             — ME selection-state lookup (patch-fragile bit isolated)
│       ├── serializer.lua                            — Lua value → Lua chunk string
│       └── paths.lua                                 — output dir constants + lfs.mkdir helper
├── test/
│   ├── test_serializer.lua                           — pure-Lua test cases
│   └── run-tests.ps1                                 — PowerShell driver (locates lua.exe)
└── ovgme/
    └── dcs-sms-me-mod/
        ├── README.md                                 — "see the CLI; OvGME bundle is DIY for v1"
        └── MissionEditor/
            └── modules/
                └── dcs_sms_me/
                    └── .gitkeep                      — folder placeholder; built artifact lives here

tools/cmd/dcs-sms/
├── install_me_mod.go                                 — `dcs-sms install-me-mod` subcommand
├── install_me_mod_test.go                            — unit tests for install logic
├── uninstall_me_mod.go                               — `dcs-sms uninstall-me-mod` subcommand
└── uninstall_me_mod_test.go                          — unit tests for uninstall logic

docs/superpowers/plans/
└── 2026-05-03-me-hello-world.md                      — this file
```

### Modified

```
tools/cmd/dcs-sms/dispatch.go                         — printUsage() lists the two new subcommands
tools/internal/dcspath/dcspath.go                     — add DiscoverInstall, env var, config key, save helper
tools/internal/dcspath/dcspath_test.go                — tests for the new install-path functions
AGENTS.md                                             — §10 lists the two new subcommands
```

Each module has one job. `selection.lua` is the only file that touches DCS-internal globals; `serializer.lua` is pure data and unit-testable; `window.lua` owns dxgui construction and the click handler; `init.lua` is a 6-line bootstrap; `paths.lua` is a 5-line constants module.

---

## Task 1: Lua serializer (TDD)

**Files:**
- Create: `tools/me-mod/test/test_serializer.lua`
- Create: `tools/me-mod/test/run-tests.ps1`
- Create: `tools/me-mod/lua/dcs_sms_me/serializer.lua`

The serializer is pure data (no DCS deps), so it gets full TDD treatment.

- [ ] **Step 1.1: Write the failing tests**

Create `tools/me-mod/test/test_serializer.lua`:

```lua
-- Standalone Lua 5.1 test suite for tools/me-mod/lua/dcs_sms_me/serializer.lua.
-- Exits with non-zero status on first failure, prints PASS/FAIL per case.
-- Run via: lua test_serializer.lua  (cwd: tools/me-mod/test/)

package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local serializer = require('serializer')

local failures = 0
local function check(name, ok, msg)
    if ok then
        print('PASS ' .. name)
    else
        print('FAIL ' .. name .. ': ' .. tostring(msg))
        failures = failures + 1
    end
end

local function tables_equal(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not tables_equal(v, b[k]) then return false end end
    for k, _ in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function roundtrip(value)
    local chunk = serializer.serialize(value)
    local fn, err = loadstring(chunk)
    if not fn then return nil, 'loadstring failed: ' .. tostring(err) .. ' for chunk:\n' .. chunk end
    local ok, result = pcall(fn)
    if not ok then return nil, 'eval failed: ' .. tostring(result) end
    return result, nil
end

-- 1. Round-trip a flat numeric array.
do
    local input = {1, 2, 3}
    local out, err = roundtrip(input)
    check('flat numeric array', out and tables_equal(input, out), err)
end

-- 2. Round-trip the callsign shape (mixed numeric + string keys).
do
    local input = {[1] = 3, [2] = 1, [3] = 1, name = 'Uzi11'}
    local out, err = roundtrip(input)
    check('mixed numeric+string keys (callsign)', out and tables_equal(input, out), err)
end

-- 3. Round-trip nested tables with strings, numbers, booleans, nils.
do
    local input = {
        name = 'Convoy 1',
        x = 12345.5,
        y = -678.25,
        active = true,
        skill = 'Average',
        units = {
            [1] = {type = 'M-1 Abrams', heading = 0},
            [2] = {type = 'M-2 Bradley', heading = 1.57},
        },
    }
    local out, err = roundtrip(input)
    check('nested mixed types', out and tables_equal(input, out), err)
end

-- 4. Cycle detection: self-referencing table emits a marker, doesn't loop.
do
    local input = {name = 'cycle'}
    input.self = input
    local chunk = serializer.serialize(input)
    -- Should contain a cycle marker comment and not stack-overflow.
    check('cycle detection emits marker',
        chunk:find('cycle', 1, true) ~= nil,
        'no cycle marker in: ' .. chunk)
end

-- 5. Unsupported types (function/userdata/thread) emit nil placeholder.
do
    local input = {fn = function() end, n = 42}
    local out, err = roundtrip(input)
    check('function emits nil placeholder',
        out and out.n == 42 and out.fn == nil, err)
end

-- 6. sort_keys produces byte-identical output across two runs.
do
    local input = {z = 1, a = 2, m = 3, b = 4}
    local first  = serializer.serialize(input, {sort_keys = true})
    local second = serializer.serialize(input, {sort_keys = true})
    check('sort_keys=true is byte-stable', first == second,
        'differ:\n' .. first .. '\n---\n' .. second)
end

-- 7. Strings with quotes, backslashes, and newlines round-trip.
do
    local input = {s = 'hello "world"\nbackslash: \\'}
    local out, err = roundtrip(input)
    check('strings with quotes/backslash/newline', out and out.s == input.s, err)
end

-- 8. Top-level emits "return { ... }" (so dofile reconstitutes the value).
do
    local chunk = serializer.serialize({x = 1})
    check('top-level emits return statement',
        chunk:match('^return%s') ~= nil, chunk)
end

-- 9. Numeric keys always emitted as [N], not bare or implicit.
do
    local input = {[1] = 'a', [2] = 'b'}
    local chunk = serializer.serialize(input)
    check('numeric keys use [N] form',
        chunk:find('[1]', 1, true) ~= nil and chunk:find('[2]', 1, true) ~= nil,
        chunk)
end

-- 10. Empty table.
do
    local out, err = roundtrip({})
    check('empty table', out and tables_equal({}, out), err)
end

if failures > 0 then
    print(string.format('\n%d test(s) FAILED', failures))
    os.exit(1)
else
    print('\nall tests passed')
    os.exit(0)
end
```

- [ ] **Step 1.2: Write the PowerShell test driver**

Create `tools/me-mod/test/run-tests.ps1`:

```powershell
# Locates a Lua 5.1 interpreter on PATH and runs test_serializer.lua.
# Exits non-zero on test failure or when no interpreter is available.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $PSCommandPath
Push-Location $here
try {
    $candidates = @('lua.exe', 'lua5.1.exe', 'lua51.exe')
    $lua = $null
    foreach ($name in $candidates) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $lua = $cmd.Source; break }
    }
    if (-not $lua) {
        Write-Host 'No Lua 5.1 interpreter found on PATH.' -ForegroundColor Yellow
        Write-Host 'Tried:' ($candidates -join ', ')
        Write-Host ''
        Write-Host 'To run these tests, install a Lua 5.1 interpreter and put it on PATH.'
        Write-Host 'Recommended for Windows: https://luabinaries.sourceforge.net/'
        Write-Host ''
        Write-Host 'Alternatively, run the test file directly inside DCS via:'
        Write-Host "  dcs-sms exec --file $(Join-Path $here 'test_serializer.lua')"
        exit 2
    }
    Write-Host "Using Lua interpreter: $lua"
    & $lua test_serializer.lua
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
```

- [ ] **Step 1.3: Run tests to verify they fail**

Run: `pwsh tools/me-mod/test/run-tests.ps1`
Expected: either FAIL on every case with "module 'serializer' not found", or exit code 2 if no Lua interpreter is on PATH.

If the interpreter is missing, that's acceptable — the implementation steps below still work; just verify failure manually by `cat`ing the missing file path.

- [ ] **Step 1.4: Implement the serializer**

Create `tools/me-mod/lua/dcs_sms_me/serializer.lua`:

```lua
-- serializer.lua — Lua value → Lua chunk string.
--
-- Returns a chunk that, when loadstring'd / dofile'd, reconstructs the input.
-- Handles mixed-key tables (the DCS callsign problem), cycles (marker), and
-- unsupported value types (function/userdata/thread → nil with comment).
--
-- Public:
--   M.serialize(value, opts) → string
--     opts.indent     = "  "    (default; one indent unit)
--     opts.sort_keys  = true    (default; deterministic key order for diffs)

local M = {}

local function key_repr(k)
    if type(k) == 'string' then
        return '[' .. string.format('%q', k) .. ']'
    elseif type(k) == 'number' then
        return '[' .. tostring(k) .. ']'
    elseif type(k) == 'boolean' then
        return '[' .. tostring(k) .. ']'
    end
    return nil  -- skip keys we can't represent
end

local function value_repr(v)
    local t = type(v)
    if t == 'nil' then return 'nil' end
    if t == 'string' then return string.format('%q', v) end
    if t == 'number' then
        if v ~= v then return '0/0' end           -- NaN
        if v == math.huge then return '1/0' end    -- +inf
        if v == -math.huge then return '-1/0' end  -- -inf
        return tostring(v)
    end
    if t == 'boolean' then return tostring(v) end
    return nil  -- table/function/userdata/thread handled by caller
end

local function sorted_keys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta == tb then
            if ta == 'number' or ta == 'string' then return a < b end
            return tostring(a) < tostring(b)
        end
        return ta < tb
    end)
    return keys
end

-- Forward declarations so the recursion can chain.
local emit_value

local function emit_table(tbl, indent_unit, depth, visited)
    if visited[tbl] then
        return 'nil --[[ cycle ]]'
    end
    visited[tbl] = true

    local keys = sorted_keys(tbl)
    if #keys == 0 then
        visited[tbl] = nil
        return '{}'
    end

    local pad     = indent_unit:rep(depth + 1)
    local pad_end = indent_unit:rep(depth)
    local parts   = {'{'}
    for _, k in ipairs(keys) do
        local k_repr = key_repr(k)
        if k_repr then
            local v_str = emit_value(tbl[k], indent_unit, depth + 1, visited)
            parts[#parts + 1] = pad .. k_repr .. ' = ' .. v_str .. ','
        end
    end
    parts[#parts + 1] = pad_end .. '}'
    visited[tbl] = nil
    return table.concat(parts, '\n')
end

emit_value = function(v, indent_unit, depth, visited)
    local t = type(v)
    if t == 'table' then
        return emit_table(v, indent_unit, depth, visited)
    end
    local simple = value_repr(v)
    if simple then return simple end
    -- Unsupported value type.
    return 'nil --[[ ' .. t .. ' ]]'
end

function M.serialize(value, opts)
    opts = opts or {}
    local indent_unit = opts.indent or '  '
    -- sort_keys is honored implicitly by sorted_keys (always sorts). The
    -- option is kept in the signature for forward-compat with an unsorted
    -- mode if we ever want one.
    local body = emit_value(value, indent_unit, 0, {})
    return 'return ' .. body .. '\n'
end

return M
```

- [ ] **Step 1.5: Run tests to verify they pass**

Run: `pwsh tools/me-mod/test/run-tests.ps1`
Expected: 10 PASS lines and "all tests passed".

If the Lua interpreter is missing, manually run the test cases inside DCS via `dcs-sms exec --file tools/me-mod/test/test_serializer.lua` and verify the output.

- [ ] **Step 1.6: Commit**

```bash
git add tools/me-mod/test/test_serializer.lua tools/me-mod/test/run-tests.ps1 tools/me-mod/lua/dcs_sms_me/serializer.lua
git commit -m "feat(me-mod): add Lua-table serializer with TDD"
```

---

## Task 2: paths.lua

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/paths.lua`

Trivial constants module. No automated tests (covered by manual smoke).

- [ ] **Step 2.1: Write the file**

Create `tools/me-mod/lua/dcs_sms_me/paths.lua`:

```lua
-- paths.lua — output directory constants and dir-creation helper.
--
-- Nests under the same Saved Games\DCS\dcs-sms\ root the bridge uses, in a
-- sibling me/ subdir. Single root keeps user mental model simple.

local lfs = require('lfs')
local M = {}

M.ROOT       = lfs.writedir() .. 'dcs-sms\\'
M.OUTBOX_DIR = M.ROOT .. 'me\\'
M.LOG_TAG    = 'sms.me'

function M.ensure_outbox()
    lfs.mkdir(M.ROOT)
    lfs.mkdir(M.OUTBOX_DIR)
end

return M
```

- [ ] **Step 2.2: Commit**

```bash
git add tools/me-mod/lua/dcs_sms_me/paths.lua
git commit -m "feat(me-mod): add paths.lua constants module"
```

---

## Task 3: selection.lua

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/selection.lua`

The patch-fragile bit, isolated. All ME-internal API access lives here. No automated tests (requires running ME); covered by manual smoke checklist.

- [ ] **Step 3.1: Write the file**

Create `tools/me-mod/lua/dcs_sms_me/selection.lua`:

```lua
-- selection.lua — ME selection-state lookup.
--
-- This is the only file that touches ME-internal globals. Every external
-- call is wrapped in pcall so a DCS patch breaking these APIs degrades to
-- {ok=false, error=...} instead of crashing the user's editor session.
--
-- Public:
--   M.snapshot() → {
--     ok            = boolean,
--     error         = string?,
--     timestamp_utc = string,
--     selection_mode = "multi"|"single",
--     groups        = table[],
--     zones         = table[],
--     drawings      = table[],
--     nav_points    = table[],
--     raw           = table,                -- everything ME handed us, verbatim
--   }

local M = {}

-- Lazy requires inside helpers so a missing module fails gracefully via the
-- outer pcall rather than at module-load time.

local function utc_now()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local function empty_snap()
    return {
        groups        = {},
        zones         = {},
        drawings      = {},
        nav_points    = {},
        raw           = {},
    }
end

local function collect_multi()
    local snap = empty_snap()
    snap.selection_mode = 'multi'

    local multiSelection = require('me_multiSelection')
    local Mission        = require('me_mission')

    local objects, err = safe_call(multiSelection.getSelectedObjects)
    if not objects then
        snap.raw.multi_get_objects_error = tostring(err)
        return snap
    end
    snap.raw.multi_get_objects = objects

    -- objects.selectGroups: table keyed by group id → group descriptor (already
    -- a DCS-shaped or ME-shaped table; we pass it through as-is, then also
    -- attempt Mission.getGroup(id) for the canonical raw form).
    if type(objects.selectGroups) == 'table' then
        for id, desc in pairs(objects.selectGroups) do
            local raw_group = safe_call(Mission.getGroup, id)
            snap.groups[#snap.groups + 1] = raw_group or desc
        end
    end
    if type(objects.selectTriggerZones) == 'table' then
        for _, zone in pairs(objects.selectTriggerZones) do
            snap.zones[#snap.zones + 1] = zone
        end
    end
    if type(objects.selectDrawObjects) == 'table' then
        for _, drw in pairs(objects.selectDrawObjects) do
            snap.drawings[#snap.drawings + 1] = drw
        end
    end
    return snap
end

local function collect_single()
    local snap = empty_snap()
    snap.selection_mode = 'single'

    local MapWindow                = require('me_map_window')
    local Mission                  = require('me_mission')
    local MapController            = require('Mission.MapController')
    local MissionData              = require('Mission.Data')
    local TriggerZoneController    = require('Mission.TriggerZoneController')
    local NavigationPointController = require('Mission.NavigationPointController')

    -- Groups (and statics, which the ME models as single-unit groups).
    local groups = safe_call(MapWindow.getSelectedGroups)
    snap.raw.single_get_groups = groups
    if type(groups) == 'table' then
        for id, _ in pairs(groups) do
            local raw_group = safe_call(Mission.getGroup, id)
            if raw_group then snap.groups[#snap.groups + 1] = raw_group end
        end
    end

    -- Single non-group selection (zone, nav point) via MapController.
    local objectId = safe_call(MapController.getSelectedObjectId)
    snap.raw.single_object_id = objectId
    if objectId then
        local kind = safe_call(MissionData.getObjectType, objectId)
        if kind == safe_call(MissionData.triggerZoneType) then
            local zone = safe_call(TriggerZoneController.getTriggerZone, objectId)
            if zone then snap.zones[#snap.zones + 1] = zone end
        elseif kind == safe_call(MissionData.navigationPointType) then
            local np = safe_call(NavigationPointController.getNavigationPoint, objectId)
            if np then snap.nav_points[#snap.nav_points + 1] = np end
        end
    end

    -- Current draw object (panel_draw module).
    local panel_draw = safe_call(require, 'me_draw_panel')
    if panel_draw and panel_draw.getCurrObject then
        local drawObj = safe_call(panel_draw.getCurrObject)
        snap.raw.single_draw_object = drawObj
        if drawObj then snap.drawings[#snap.drawings + 1] = drawObj end
    end

    return snap
end

function M.snapshot()
    local ok, result = pcall(function()
        local multiSelection = require('me_multiSelection')
        if multiSelection.isVisible and multiSelection.isVisible() then
            return collect_multi()
        end
        return collect_single()
    end)
    if not ok then
        local snap = empty_snap()
        snap.ok = false
        snap.error = tostring(result)
        snap.timestamp_utc = utc_now()
        snap.selection_mode = 'unknown'
        return snap
    end
    result.ok = true
    result.timestamp_utc = utc_now()
    return result
end

return M
```

- [ ] **Step 3.2: Commit**

```bash
git add tools/me-mod/lua/dcs_sms_me/selection.lua
git commit -m "feat(me-mod): add selection.lua snapshot module"
```

---

## Task 4: window.lua

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/window.lua`

dxgui construction + click handler + helpers (`is_empty`, `envelope`, `summarize`, `truncate`, `utc_filename_stamp`). No automated tests; covered by manual smoke.

- [ ] **Step 4.1: Write the file**

Create `tools/me-mod/lua/dcs_sms_me/window.lua`:

```lua
-- window.lua — dxgui window with a "Print selection" button + status label.
--
-- Imperative widget construction (Button.new, Static.new) for v1 — one
-- button + one label has no real layout. Sub-project 3 will switch to .dlg
-- files when there is real layout to describe.
--
-- Public:
--   M.show()    — construct and display the window. Idempotent.

local DialogLoader = require('DialogLoader')
local Static       = require('Static')
local Button       = require('Button')
local Gui          = require('dxgui')

local selection  = require('dcs_sms_me.selection')
local serializer = require('dcs_sms_me.serializer')
local paths      = require('dcs_sms_me.paths')

local M = {}

local window      = nil
local statusLabel = nil

local VERSION = '0.1.0'

local function utc_filename_stamp()
    -- e.g. "2026-05-03T141728Z" — no colons (Windows-safe).
    local stamp = os.date('!%Y-%m-%dT%H%M%SZ')
    return stamp
end

local function truncate(s, max)
    s = tostring(s or '')
    if #s <= max then return s end
    return s:sub(1, max - 1) .. '…'
end

local function is_empty(snap)
    return snap.ok
        and #snap.groups == 0
        and #snap.zones == 0
        and #snap.drawings == 0
        and #snap.nav_points == 0
end

local function envelope(snap)
    return {
        meta = {
            dcs_sms_me_version = VERSION,
            timestamp_utc      = snap.timestamp_utc,
            selection_mode     = snap.selection_mode,
            ok                 = snap.ok,
            error              = snap.error,
        },
        groups     = snap.groups     or {},
        zones      = snap.zones      or {},
        drawings   = snap.drawings   or {},
        nav_points = snap.nav_points or {},
        raw        = snap.raw        or {},
    }
end

local function summarize(snap, fullpath)
    return string.format(
        'mode=%s, groups=%d, zones=%d, drawings=%d, nav_points=%d',
        snap.selection_mode or 'unknown',
        #(snap.groups or {}),
        #(snap.zones or {}),
        #(snap.drawings or {}),
        #(snap.nav_points or {}))
end

function M._set_status(text)
    pcall(function()
        if statusLabel and statusLabel.setText then
            statusLabel:setText(text)
        end
    end)
end

function M._on_print_clicked()
    local snap = selection.snapshot()

    -- (1) Empty selection: no file, just log + status.
    if snap.ok and is_empty(snap) then
        log.write('sms.me', log.WARNING, 'no selection — nothing dumped')
        M._set_status('No selection — nothing dumped')
        return
    end

    -- (2) Open file. Failure means we can't write anything, return.
    paths.ensure_outbox()
    local filename = 'selection-' .. utc_filename_stamp() .. '.lua'
    local fullpath = paths.OUTBOX_DIR .. filename
    local f, err   = io.open(fullpath, 'w')
    if not f then
        local msg = 'open failed: ' .. tostring(err)
        log.write('sms.me', log.ERROR, msg)
        M._set_status('Failed: ' .. truncate(msg, 80) .. ' (see dcs.log)')
        return
    end
    f:write(serializer.serialize(envelope(snap)))
    f:close()

    -- (3) Snapshot itself failed: file written with ok=false, surface that.
    if not snap.ok then
        local msg = 'selection lookup failed: ' .. tostring(snap.error)
        log.write('sms.me', log.ERROR, msg .. ' (file: ' .. fullpath .. ')')
        M._set_status('Failed: ' .. truncate(snap.error or '', 80) .. ' (see dcs.log)')
        return
    end

    -- (4) Success.
    local summary = summarize(snap, fullpath)
    log.write('sms.me', log.INFO, 'selection dumped to ' .. fullpath
                                   .. ' (' .. summary .. ')')
    M._set_status('Dumped ' .. summary .. ' → ' .. filename)
end

function M.show()
    if window then return end
    local ok, err = pcall(function()
        -- Build the window imperatively. Layout: column with title (Static),
        -- button, and status label. Sized to fit a single dump-result line.
        local screen_w, screen_h = Gui.GetWindowSize()
        local w, h = 360, 110
        local x = screen_w - w - 20
        local y = 80

        window = Static.new()
        window:setBounds(x, y, w, h)
        window:setText('dcs-sms ME')
        window:setVisible(true)

        local title = Static.new()
        title:setBounds(10, 6, w - 20, 18)
        title:setText('dcs-sms ME — hello world')
        window:insertWidget(title)

        local button = Button.new()
        button:setBounds(10, 30, w - 20, 28)
        button:setText('Print selection')
        button:addChangeCallback(M._on_print_clicked)
        window:insertWidget(button)

        statusLabel = Static.new()
        statusLabel:setBounds(10, 64, w - 20, 36)
        statusLabel:setText('Ready.')
        window:insertWidget(statusLabel)
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'window construction failed: ' .. tostring(err))
        window = nil
        statusLabel = nil
        return
    end
    log.write('sms.me', log.INFO, 'window opened')
end

return M
```

- [ ] **Step 4.2: Commit**

```bash
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): add window.lua dxgui + click handler"
```

---

## Task 5: init.lua bootstrap

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/init.lua`

Trivial. The require'd module by the patch line in MissionEditor.lua.

- [ ] **Step 5.1: Write the file**

Create `tools/me-mod/lua/dcs_sms_me/init.lua`:

```lua
-- init.lua — loaded by the require() line patched into MissionEditor.lua.
-- Outer pcall is the last-line defense: even if our require chain breaks,
-- the ME continues loading normally.

local ok, err = pcall(function()
    local window = require('dcs_sms_me.window')
    window.show()
end)
if not ok then
    log.write('sms.me', log.ERROR, 'init failed: ' .. tostring(err))
end
```

- [ ] **Step 5.2: Commit**

```bash
git add tools/me-mod/lua/dcs_sms_me/init.lua
git commit -m "feat(me-mod): add init.lua bootstrap"
```

---

## Task 6: DCS install path discovery (TDD)

**Files:**
- Modify: `tools/internal/dcspath/dcspath.go`
- Modify: `tools/internal/dcspath/dcspath_test.go`

Extend the `dcspath` package to discover the DCS install dir (separate from Saved Games). Symmetric with the existing `Discover` chain: explicit override > env var > config file > error (no auto-discovery — DCS install dirs vary too much to guess).

- [ ] **Step 6.1: Write failing tests**

Read the existing test file first to match conventions:

Run: `cat tools/internal/dcspath/dcspath_test.go | head -60`

Append to `tools/internal/dcspath/dcspath_test.go`:

```go
func TestDiscoverFromInstallEnv(t *testing.T) {
    t.Setenv("DCS_SMS_DCS_INSTALL", "")
    if _, ok := DiscoverFromInstallEnv(); ok {
        t.Fatal("expected ok=false when env var unset")
    }
    t.Setenv("DCS_SMS_DCS_INSTALL", `D:\Program Files\Eagle Dynamics\DCS World`)
    v, ok := DiscoverFromInstallEnv()
    if !ok || v != `D:\Program Files\Eagle Dynamics\DCS World` {
        t.Fatalf("got (%q, %v), want (D:\\..., true)", v, ok)
    }
}

func TestDiscoverFromInstallConfig_RoundTrip(t *testing.T) {
    dir := t.TempDir()
    cfg := filepath.Join(dir, "config.toml")
    want := `D:\Program Files\Eagle Dynamics\DCS World`
    if err := SaveInstallConfig(cfg, want); err != nil {
        t.Fatal(err)
    }
    got, err := DiscoverFromInstallConfig(cfg)
    if err != nil {
        t.Fatal(err)
    }
    if got != want {
        t.Fatalf("got %q, want %q", got, want)
    }
}

func TestSaveInstallConfig_PreservesSavedGamesKey(t *testing.T) {
    dir := t.TempDir()
    cfg := filepath.Join(dir, "config.toml")
    if err := SaveConfig(cfg, `C:\Users\X\Saved Games\DCS`); err != nil {
        t.Fatal(err)
    }
    if err := SaveInstallConfig(cfg, `D:\Program Files\Eagle Dynamics\DCS World`); err != nil {
        t.Fatal(err)
    }
    sg, err := DiscoverFromConfig(cfg)
    if err != nil {
        t.Fatalf("saved_games lost after writing dcs_install: %v", err)
    }
    if sg != `C:\Users\X\Saved Games\DCS` {
        t.Fatalf("saved_games clobbered: got %q", sg)
    }
    inst, err := DiscoverFromInstallConfig(cfg)
    if err != nil {
        t.Fatal(err)
    }
    if inst != `D:\Program Files\Eagle Dynamics\DCS World` {
        t.Fatalf("dcs_install wrong: got %q", inst)
    }
}

func TestDiscoverInstall_PriorityOrder(t *testing.T) {
    dir := t.TempDir()
    cfg := filepath.Join(dir, "config.toml")
    if err := SaveInstallConfig(cfg, `C:\from-config`); err != nil {
        t.Fatal(err)
    }
    t.Setenv("DCS_SMS_DCS_INSTALL", `D:\from-env`)

    // Override wins.
    got, err := DiscoverInstall(`E:\from-flag`, cfg)
    if err != nil || got != `E:\from-flag` {
        t.Fatalf("override should win, got (%q, %v)", got, err)
    }

    // Env wins over config.
    got, err = DiscoverInstall("", cfg)
    if err != nil || got != `D:\from-env` {
        t.Fatalf("env should win, got (%q, %v)", got, err)
    }

    // Config wins when env unset.
    t.Setenv("DCS_SMS_DCS_INSTALL", "")
    got, err = DiscoverInstall("", cfg)
    if err != nil || got != `C:\from-config` {
        t.Fatalf("config fallback, got (%q, %v)", got, err)
    }

    // Nothing → error.
    got, err = DiscoverInstall("", filepath.Join(dir, "missing.toml"))
    if err == nil {
        t.Fatalf("expected error when no source provided, got %q", got)
    }
}
```

- [ ] **Step 6.2: Run tests, verify they fail**

Run: `cd tools && go test ./internal/dcspath/ -run "Install" -v`
Expected: undefined references for `DiscoverFromInstallEnv`, `DiscoverFromInstallConfig`, `SaveInstallConfig`, `DiscoverInstall`.

- [ ] **Step 6.3: Implement the new functions**

Append to `tools/internal/dcspath/dcspath.go`:

```go
// DiscoverFromInstallEnv returns the path from the DCS_SMS_DCS_INSTALL env var.
func DiscoverFromInstallEnv() (string, bool) {
    v := os.Getenv("DCS_SMS_DCS_INSTALL")
    if v == "" {
        return "", false
    }
    return v, true
}

// DiscoverFromInstallConfig parses the config file and returns the dcs_install
// value. Returns an error if the file is missing or the key isn't set.
func DiscoverFromInstallConfig(configPath string) (string, error) {
    return discoverConfigKey(configPath, "dcs_install")
}

// discoverConfigKey is the shared scanner for both saved_games and
// dcs_install. (Existing DiscoverFromConfig is left in place as a thin
// wrapper that delegates here so the public API doesn't change.)
func discoverConfigKey(configPath, key string) (string, error) {
    f, err := os.Open(configPath)
    if err != nil {
        return "", err
    }
    defer f.Close()
    scanner := bufio.NewScanner(f)
    for scanner.Scan() {
        line := strings.TrimSpace(scanner.Text())
        if line == "" || strings.HasPrefix(line, "#") {
            continue
        }
        k, v, ok := strings.Cut(line, "=")
        if !ok {
            continue
        }
        if strings.TrimSpace(k) != key {
            continue
        }
        return parseTomlString(strings.TrimSpace(v))
    }
    if err := scanner.Err(); err != nil {
        return "", err
    }
    return "", fmt.Errorf("%s key not found in config", key)
}

// SaveInstallConfig writes (or updates) the dcs_install key in configPath.
// Preserves any other keys (e.g. saved_games) already present.
func SaveInstallConfig(configPath, installPath string) error {
    return upsertConfigKey(configPath, "dcs_install", installPath)
}

// upsertConfigKey writes key = "value" into configPath, replacing any prior
// line for the same key and preserving everything else. Creates the file
// (and parent dirs) if needed.
func upsertConfigKey(configPath, key, value string) error {
    if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
        return err
    }
    var existing []byte
    if data, err := os.ReadFile(configPath); err == nil {
        existing = data
    } else if !errors.Is(err, fs.ErrNotExist) {
        return err
    }
    lines := strings.Split(string(existing), "\n")
    newLine := fmt.Sprintf("%s = %s", key, encodeTomlString(value))
    found := false
    for i, line := range lines {
        trimmed := strings.TrimSpace(line)
        if trimmed == "" || strings.HasPrefix(trimmed, "#") {
            continue
        }
        k, _, ok := strings.Cut(trimmed, "=")
        if !ok {
            continue
        }
        if strings.TrimSpace(k) == key {
            lines[i] = newLine
            found = true
            break
        }
    }
    if !found {
        // Append, ensuring exactly one trailing newline.
        if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
            lines[len(lines)-1] = newLine
        } else {
            lines = append(lines, newLine)
        }
        lines = append(lines, "")
    }
    return os.WriteFile(configPath, []byte(strings.Join(lines, "\n")), 0o644)
}

// DiscoverInstall applies the priority order for DCS install dir:
//  1. override (e.g. --dcs-path flag)
//  2. DCS_SMS_DCS_INSTALL env var
//  3. configPath's dcs_install key
// No automatic discovery — DCS install dirs vary too much.
func DiscoverInstall(override, configPath string) (string, error) {
    if override != "" {
        return override, nil
    }
    if v, ok := DiscoverFromInstallEnv(); ok {
        return v, nil
    }
    if configPath != "" {
        v, err := DiscoverFromInstallConfig(configPath)
        if err == nil {
            return v, nil
        }
        if !errors.Is(err, fs.ErrNotExist) {
            return "", fmt.Errorf("reading %s: %w", configPath, err)
        }
    }
    return "", errors.New("could not discover DCS install path; pass --dcs-path or set DCS_SMS_DCS_INSTALL")
}
```

Then update the existing `SaveConfig` and `DiscoverFromConfig` to use the shared helpers (so they don't drift):

Replace the existing `DiscoverFromConfig` body with:

```go
func DiscoverFromConfig(configPath string) (string, error) {
    return discoverConfigKey(configPath, "saved_games")
}
```

Replace the existing `SaveConfig` body with:

```go
func SaveConfig(configPath, savedGamesPath string) error {
    return upsertConfigKey(configPath, "saved_games", savedGamesPath)
}
```

- [ ] **Step 6.4: Run all dcspath tests**

Run: `cd tools && go test ./internal/dcspath/ -v`
Expected: all tests pass (existing + new). The refactor of `SaveConfig`/`DiscoverFromConfig` to use the shared helpers must not break the existing tests.

- [ ] **Step 6.5: Commit**

```bash
git add tools/internal/dcspath/dcspath.go tools/internal/dcspath/dcspath_test.go
git commit -m "feat(tools): add DiscoverInstall + dcs_install config key"
```

---

## Task 7: Embed the Lua mod files in Go

**Files:**
- Create: `tools/me-mod/lua/embed.go`

Required for the install-me-mod subcommand to write the files into the user's DCS install. Mirrors the `tools/lua/embed.go` pattern.

- [ ] **Step 7.1: Write the embed package**

Create `tools/me-mod/lua/embed.go`:

```go
// Package memod exposes the dcs_sms_me/* Lua source as an embed.FS so the
// install-me-mod subcommand can write the files into the user's DCS
// MissionEditor/modules directory. We need this thin wrapper because Go's
// //go:embed directive can only reference files in the same package
// directory or below — keeping the canonical mod source under
// tools/me-mod/lua/ means we also need a Go file here to embed it.
package memod

import "embed"

//go:embed dcs_sms_me
var FS embed.FS

// ModuleDirName is the on-disk subdirectory the install command writes
// into, under <DCS install>/MissionEditor/modules/.
const ModuleDirName = "dcs_sms_me"

// RequireLine is the Lua snippet appended to <DCS install>/MissionEditor/MissionEditor.lua
// to load the mod. Sentinel comments delimit it so install/uninstall can
// detect and remove the patch surgically.
const (
    RequireBeginMarker = "-- dcs-sms-me-mod begin"
    RequireEndMarker   = "-- dcs-sms-me-mod end"
    RequireBody        = "require('dcs_sms_me')"
)

// PatchBlock is the full block appended to MissionEditor.lua at install time.
const PatchBlock = "\n" + RequireBeginMarker + "\n" + RequireBody + "\n" + RequireEndMarker + "\n"
```

- [ ] **Step 7.2: Verify the embed package builds**

Run: `cd tools && go build ./me-mod/lua/`
Expected: success (no output).

Also verify the embedded files are accessible:

Run: `cd tools && go test -run "^$" ./me-mod/lua/ -v` (compiles but runs no tests)
Expected: success.

- [ ] **Step 7.3: Commit**

```bash
git add tools/me-mod/lua/embed.go
git commit -m "feat(tools): embed me-mod Lua sources for install command"
```

---

## Task 8: install-me-mod CLI subcommand (TDD)

**Files:**
- Create: `tools/cmd/dcs-sms/install_me_mod.go`
- Create: `tools/cmd/dcs-sms/install_me_mod_test.go`
- Modify: `tools/cmd/dcs-sms/dispatch.go`

The CLI subcommand. Logic to test:
- File copy from embedded FS to `<install>/MissionEditor/modules/dcs_sms_me/`.
- Backup of `MissionEditor.lua` to `MissionEditor.lua.dcs-sms.bak` (refuse if backup already exists).
- Append patch block (delimited by sentinel markers) to `MissionEditor.lua`.
- Idempotency: if patch markers are already present, only re-copy the modules dir.

- [ ] **Step 8.1: Write failing tests**

Create `tools/cmd/dcs-sms/install_me_mod_test.go`:

```go
package main

import (
    "bytes"
    "os"
    "path/filepath"
    "strings"
    "testing"
)

// helper: build a fake DCS install dir and return its path.
func newFakeInstall(t *testing.T) string {
    t.Helper()
    root := t.TempDir()
    me := filepath.Join(root, "MissionEditor")
    if err := os.MkdirAll(filepath.Join(me, "modules"), 0o755); err != nil {
        t.Fatal(err)
    }
    if err := os.WriteFile(filepath.Join(me, "MissionEditor.lua"),
        []byte("-- original ME bootstrap\nlocal x = 1\n"), 0o644); err != nil {
        t.Fatal(err)
    }
    return root
}

func TestInstallMeMod_CopiesModuleFiles(t *testing.T) {
    install := newFakeInstall(t)
    var stdout, stderr bytes.Buffer
    code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr)
    if code != 0 {
        t.Fatalf("exit %d, stderr: %s", code, stderr.String())
    }
    moduleDir := filepath.Join(install, "MissionEditor", "modules", "dcs_sms_me")
    for _, name := range []string{"init.lua", "window.lua", "selection.lua", "serializer.lua", "paths.lua"} {
        p := filepath.Join(moduleDir, name)
        if info, err := os.Stat(p); err != nil || info.Size() == 0 {
            t.Errorf("expected %s present and non-empty: %v", p, err)
        }
    }
}

func TestInstallMeMod_PatchesAndBacksUp(t *testing.T) {
    install := newFakeInstall(t)
    var stdout, stderr bytes.Buffer
    if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
        t.Fatalf("exit %d, stderr: %s", code, stderr.String())
    }
    bak, err := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua.dcs-sms.bak"))
    if err != nil {
        t.Fatalf("backup not created: %v", err)
    }
    if !strings.Contains(string(bak), "original ME bootstrap") {
        t.Fatalf("backup does not contain original content: %q", bak)
    }
    patched, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
    if !strings.Contains(string(patched), "-- dcs-sms-me-mod begin") ||
       !strings.Contains(string(patched), "require('dcs_sms_me')") ||
       !strings.Contains(string(patched), "-- dcs-sms-me-mod end") {
        t.Fatalf("patched MissionEditor.lua missing markers/require: %s", patched)
    }
    if !strings.Contains(string(patched), "original ME bootstrap") {
        t.Fatalf("original content lost from MissionEditor.lua: %s", patched)
    }
}

func TestInstallMeMod_RefusesIfBackupExists(t *testing.T) {
    install := newFakeInstall(t)
    // Simulate a stale backup from a previous incomplete uninstall.
    if err := os.WriteFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua.dcs-sms.bak"),
        []byte("stale"), 0o644); err != nil {
        t.Fatal(err)
    }
    var stdout, stderr bytes.Buffer
    code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr)
    if code == 0 {
        t.Fatal("expected non-zero exit when backup already exists")
    }
    if !strings.Contains(stderr.String(), "backup") {
        t.Fatalf("stderr should mention backup, got: %s", stderr.String())
    }
}

func TestInstallMeMod_Idempotent_ReinstallPreservesPatch(t *testing.T) {
    install := newFakeInstall(t)
    var stdout, stderr bytes.Buffer
    if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
        t.Fatalf("first install exit %d, stderr: %s", code, stderr.String())
    }
    firstPatched, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))

    // Second run: should NOT add a second require line, should NOT touch the
    // existing backup, should still re-copy module files.
    stdout.Reset(); stderr.Reset()
    if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
        t.Fatalf("re-install exit %d, stderr: %s", code, stderr.String())
    }
    secondPatched, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
    if !bytes.Equal(firstPatched, secondPatched) {
        t.Fatalf("MissionEditor.lua changed on re-install:\n--- first:\n%s\n--- second:\n%s",
            firstPatched, secondPatched)
    }
    // Module files should still exist.
    if _, err := os.Stat(filepath.Join(install, "MissionEditor", "modules", "dcs_sms_me", "init.lua")); err != nil {
        t.Fatalf("module file missing after re-install: %v", err)
    }
}
```

- [ ] **Step 8.2: Run tests, verify they fail**

Run: `cd tools && go test ./cmd/dcs-sms/ -run "InstallMeMod" -v`
Expected: undefined `installMeModCmd`.

- [ ] **Step 8.3: Implement the subcommand**

Create `tools/cmd/dcs-sms/install_me_mod.go`:

```go
package main

import (
    "bytes"
    "errors"
    "flag"
    "fmt"
    "io"
    "io/fs"
    "os"
    "path/filepath"
    "strings"

    "github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
    memod "github.com/nielsvaes/dcs-sms/tools/me-mod/lua"
)

func init() {
    register("install-me-mod", installMeModCmd)
}

const meModBackupSuffix = ".dcs-sms.bak"

func installMeModCmd(args []string, stdout, stderr io.Writer) int {
    fs := flag.NewFlagSet("install-me-mod", flag.ContinueOnError)
    fs.SetOutput(stderr)
    flagDCSPath := fs.String("dcs-path", "", "override DCS install path")
    flagNoSave := fs.Bool("no-config-save", false, "do not persist --dcs-path to config")
    if err := fs.Parse(args); err != nil {
        return 2
    }

    cfg, _ := dcspath.DefaultConfigPath()
    install, err := dcspath.DiscoverInstall(*flagDCSPath, cfg)
    if err != nil {
        fmt.Fprintln(stderr, "dcs-sms install-me-mod:", err)
        return 3
    }

    // Sanity check: <install>/MissionEditor/MissionEditor.lua must exist.
    meDir := filepath.Join(install, "MissionEditor")
    meFile := filepath.Join(meDir, "MissionEditor.lua")
    if _, err := os.Stat(meFile); err != nil {
        fmt.Fprintf(stderr, "dcs-sms install-me-mod: %s not found (is --dcs-path correct?)\n", meFile)
        return 3
    }

    // Step 1: copy module files.
    moduleDst := filepath.Join(meDir, "modules", memod.ModuleDirName)
    if err := os.MkdirAll(moduleDst, 0o755); err != nil {
        fmt.Fprintln(stderr, "dcs-sms install-me-mod: mkdir modules:", err)
        return 3
    }
    if err := copyEmbedDir(memod.FS, memod.ModuleDirName, moduleDst); err != nil {
        fmt.Fprintln(stderr, "dcs-sms install-me-mod: copy modules:", err)
        return 3
    }
    fmt.Fprintf(stdout, "copied %s/* → %s\n", memod.ModuleDirName, moduleDst)

    // Step 2: patch MissionEditor.lua (idempotent).
    meSrc, err := os.ReadFile(meFile)
    if err != nil {
        fmt.Fprintln(stderr, "dcs-sms install-me-mod: read ME file:", err)
        return 3
    }
    if bytes.Contains(meSrc, []byte(memod.RequireBeginMarker)) {
        fmt.Fprintf(stdout, "patch already present in %s, skipping\n", meFile)
    } else {
        backup := meFile + meModBackupSuffix
        if _, err := os.Stat(backup); err == nil {
            fmt.Fprintf(stderr,
                "dcs-sms install-me-mod: refusing to overwrite existing backup %s\n"+
                "  (run `dcs-sms uninstall-me-mod` first, or remove the .bak manually)\n",
                backup)
            return 3
        } else if !errors.Is(err, os.ErrNotExist) {
            fmt.Fprintln(stderr, "dcs-sms install-me-mod: stat backup:", err)
            return 3
        }
        if err := os.WriteFile(backup, meSrc, 0o644); err != nil {
            fmt.Fprintln(stderr, "dcs-sms install-me-mod: write backup:", err)
            return 3
        }
        patched := append(meSrc, []byte(memod.PatchBlock)...)
        if err := os.WriteFile(meFile, patched, 0o644); err != nil {
            fmt.Fprintln(stderr, "dcs-sms install-me-mod: write ME file:", err)
            return 3
        }
        fmt.Fprintf(stdout, "patched %s (backup: %s)\n", meFile, backup)
    }

    // Step 3: cache --dcs-path to config (unless --no-config-save).
    if *flagDCSPath != "" && !*flagNoSave {
        if cfg != "" {
            if err := dcspath.SaveInstallConfig(cfg, *flagDCSPath); err != nil {
                fmt.Fprintln(stderr, "dcs-sms install-me-mod: warning: could not save config:", err)
            } else {
                fmt.Fprintf(stdout, "saved dcs_install = %q to %s\n", *flagDCSPath, cfg)
            }
        }
    }

    fmt.Fprintln(stdout, "")
    fmt.Fprintln(stdout, "Install complete. Open the Mission Editor; the dcs-sms ME window should appear in the upper right.")
    return 0
}

// copyEmbedDir walks an embed.FS subtree and writes every file to dstDir,
// preserving the relative directory structure under srcSubdir.
func copyEmbedDir(efs fs.FS, srcSubdir, dstDir string) error {
    return fs.WalkDir(efs, srcSubdir, func(path string, d fs.DirEntry, walkErr error) error {
        if walkErr != nil {
            return walkErr
        }
        rel := strings.TrimPrefix(path, srcSubdir)
        rel = strings.TrimPrefix(rel, "/")
        target := filepath.Join(dstDir, filepath.FromSlash(rel))
        if d.IsDir() {
            return os.MkdirAll(target, 0o755)
        }
        data, err := fs.ReadFile(efs, path)
        if err != nil {
            return fmt.Errorf("read %s: %w", path, err)
        }
        if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
            return err
        }
        return os.WriteFile(target, data, 0o644)
    })
}
```

- [ ] **Step 8.4: Run tests, verify they pass**

Run: `cd tools && go test ./cmd/dcs-sms/ -run "InstallMeMod" -v`
Expected: 4 PASS.

- [ ] **Step 8.5: Update dispatch.go usage text**

Edit `tools/cmd/dcs-sms/dispatch.go`. In `printUsage`, after the existing `install-hook` line, insert:

```go
    fmt.Fprintln(w, "  install-me-mod   install/update the Mission Editor mod into <DCS install>/MissionEditor/")
```

- [ ] **Step 8.6: Verify the full build still passes**

Run: `cd tools && go build ./... && go test ./...`
Expected: clean build, all tests pass.

- [ ] **Step 8.7: Commit**

```bash
git add tools/cmd/dcs-sms/install_me_mod.go tools/cmd/dcs-sms/install_me_mod_test.go tools/cmd/dcs-sms/dispatch.go
git commit -m "feat(tools): add install-me-mod CLI subcommand"
```

---

## Task 9: uninstall-me-mod CLI subcommand (TDD)

**Files:**
- Create: `tools/cmd/dcs-sms/uninstall_me_mod.go`
- Create: `tools/cmd/dcs-sms/uninstall_me_mod_test.go`
- Modify: `tools/cmd/dcs-sms/dispatch.go`

Reverses the install: removes the patch block (preferring marker-based surgical removal; falls back to backup restoration if markers are absent), deletes the modules dir.

- [ ] **Step 9.1: Write failing tests**

Create `tools/cmd/dcs-sms/uninstall_me_mod_test.go`:

```go
package main

import (
    "bytes"
    "os"
    "path/filepath"
    "strings"
    "testing"
)

// reuse newFakeInstall from install_me_mod_test.go (same package).

func installFirst(t *testing.T) string {
    t.Helper()
    install := newFakeInstall(t)
    var stdout, stderr bytes.Buffer
    if code := installMeModCmd([]string{"--dcs-path", install, "--no-config-save"}, &stdout, &stderr); code != 0 {
        t.Fatalf("install setup failed: %s", stderr.String())
    }
    return install
}

func TestUninstallMeMod_RemovesMarkerBlockSurgically(t *testing.T) {
    install := installFirst(t)
    var stdout, stderr bytes.Buffer
    if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
        t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
    }
    me, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
    if strings.Contains(string(me), "dcs-sms-me-mod") || strings.Contains(string(me), "require('dcs_sms_me')") {
        t.Fatalf("patch markers still present after uninstall: %s", me)
    }
    if !strings.Contains(string(me), "original ME bootstrap") {
        t.Fatalf("original content lost: %s", me)
    }
}

func TestUninstallMeMod_RemovesModuleDir(t *testing.T) {
    install := installFirst(t)
    var stdout, stderr bytes.Buffer
    if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
        t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
    }
    if _, err := os.Stat(filepath.Join(install, "MissionEditor", "modules", "dcs_sms_me")); !os.IsNotExist(err) {
        t.Fatalf("module dir still exists: %v", err)
    }
}

func TestUninstallMeMod_RemovesBackupFile(t *testing.T) {
    install := installFirst(t)
    var stdout, stderr bytes.Buffer
    if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
        t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
    }
    if _, err := os.Stat(filepath.Join(install, "MissionEditor", "MissionEditor.lua.dcs-sms.bak")); !os.IsNotExist(err) {
        t.Fatalf("backup file still exists: %v", err)
    }
}

func TestUninstallMeMod_FallsBackToBackupWhenMarkersMissing(t *testing.T) {
    install := installFirst(t)
    // Simulate a user manually editing MissionEditor.lua and stripping markers
    // but leaving "require('dcs_sms_me')" mangled.
    meFile := filepath.Join(install, "MissionEditor", "MissionEditor.lua")
    if err := os.WriteFile(meFile, []byte("-- corrupted by user\nrequire('dcs_sms_me')\n"), 0o644); err != nil {
        t.Fatal(err)
    }
    var stdout, stderr bytes.Buffer
    if code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr); code != 0 {
        t.Fatalf("uninstall exit %d, stderr: %s", code, stderr.String())
    }
    me, _ := os.ReadFile(meFile)
    if !strings.Contains(string(me), "original ME bootstrap") {
        t.Fatalf("backup-restore failed: %s", me)
    }
    if strings.Contains(string(me), "corrupted by user") {
        t.Fatalf("backup-restore did not overwrite corrupted file: %s", me)
    }
}

func TestUninstallMeMod_NoOpWhenNothingInstalled(t *testing.T) {
    install := newFakeInstall(t)
    var stdout, stderr bytes.Buffer
    code := uninstallMeModCmd([]string{"--dcs-path", install}, &stdout, &stderr)
    if code != 0 {
        t.Fatalf("uninstall on clean install should succeed, exit %d, stderr: %s", code, stderr.String())
    }
    // Original file untouched.
    me, _ := os.ReadFile(filepath.Join(install, "MissionEditor", "MissionEditor.lua"))
    if !strings.Contains(string(me), "original ME bootstrap") {
        t.Fatalf("original content lost: %s", me)
    }
}
```

- [ ] **Step 9.2: Run tests, verify they fail**

Run: `cd tools && go test ./cmd/dcs-sms/ -run "UninstallMeMod" -v`
Expected: undefined `uninstallMeModCmd`.

- [ ] **Step 9.3: Implement the subcommand**

Create `tools/cmd/dcs-sms/uninstall_me_mod.go`:

```go
package main

import (
    "bytes"
    "errors"
    "flag"
    "fmt"
    "io"
    "os"
    "path/filepath"

    "github.com/nielsvaes/dcs-sms/tools/internal/dcspath"
    memod "github.com/nielsvaes/dcs-sms/tools/me-mod/lua"
)

func init() {
    register("uninstall-me-mod", uninstallMeModCmd)
}

func uninstallMeModCmd(args []string, stdout, stderr io.Writer) int {
    fs := flag.NewFlagSet("uninstall-me-mod", flag.ContinueOnError)
    fs.SetOutput(stderr)
    flagDCSPath := fs.String("dcs-path", "", "override DCS install path")
    if err := fs.Parse(args); err != nil {
        return 2
    }

    cfg, _ := dcspath.DefaultConfigPath()
    install, err := dcspath.DiscoverInstall(*flagDCSPath, cfg)
    if err != nil {
        fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod:", err)
        return 3
    }

    meDir := filepath.Join(install, "MissionEditor")
    meFile := filepath.Join(meDir, "MissionEditor.lua")
    if _, err := os.Stat(meFile); err != nil {
        fmt.Fprintf(stderr, "dcs-sms uninstall-me-mod: %s not found (is --dcs-path correct?)\n", meFile)
        return 3
    }

    // Step 1: revert MissionEditor.lua. Prefer marker-based surgical removal;
    // fall back to backup-file restore if markers are absent.
    src, err := os.ReadFile(meFile)
    if err != nil {
        fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: read ME file:", err)
        return 3
    }
    backup := meFile + meModBackupSuffix
    cleaned, removedByMarker := removeMarkerBlock(src, memod.RequireBeginMarker, memod.RequireEndMarker)
    if removedByMarker {
        if err := os.WriteFile(meFile, cleaned, 0o644); err != nil {
            fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: write ME file:", err)
            return 3
        }
        fmt.Fprintf(stdout, "removed patch markers from %s\n", meFile)
    } else if _, err := os.Stat(backup); err == nil {
        bakData, err := os.ReadFile(backup)
        if err != nil {
            fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: read backup:", err)
            return 3
        }
        if err := os.WriteFile(meFile, bakData, 0o644); err != nil {
            fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: restore from backup:", err)
            return 3
        }
        fmt.Fprintf(stdout, "no markers found; restored %s from %s\n", meFile, backup)
    } else if err != nil && !errors.Is(err, os.ErrNotExist) {
        fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: stat backup:", err)
        return 3
    } else {
        fmt.Fprintf(stdout, "no patch markers and no backup found; %s left untouched\n", meFile)
    }

    // Step 2: delete the modules dir.
    moduleDir := filepath.Join(meDir, "modules", memod.ModuleDirName)
    if err := os.RemoveAll(moduleDir); err != nil {
        fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: remove module dir:", err)
        return 3
    }
    fmt.Fprintf(stdout, "removed %s\n", moduleDir)

    // Step 3: delete the backup file (if present).
    if err := os.Remove(backup); err != nil && !errors.Is(err, os.ErrNotExist) {
        fmt.Fprintln(stderr, "dcs-sms uninstall-me-mod: remove backup:", err)
        return 3
    }

    fmt.Fprintln(stdout, "uninstall complete.")
    return 0
}

// removeMarkerBlock returns src with everything from beginMarker through
// endMarker (inclusive, including any leading newline before beginMarker
// and trailing newline after endMarker) removed. The bool indicates whether
// any removal happened.
func removeMarkerBlock(src []byte, beginMarker, endMarker string) ([]byte, bool) {
    beginIdx := bytes.Index(src, []byte(beginMarker))
    if beginIdx < 0 {
        return src, false
    }
    endIdx := bytes.Index(src[beginIdx:], []byte(endMarker))
    if endIdx < 0 {
        return src, false
    }
    endIdx += beginIdx + len(endMarker)
    // Eat one trailing newline if present.
    if endIdx < len(src) && src[endIdx] == '\n' {
        endIdx++
    }
    // Eat one leading newline before the marker if present.
    if beginIdx > 0 && src[beginIdx-1] == '\n' {
        beginIdx--
    }
    out := make([]byte, 0, len(src)-(endIdx-beginIdx))
    out = append(out, src[:beginIdx]...)
    out = append(out, src[endIdx:]...)
    return out, true
}
```

- [ ] **Step 9.4: Run tests, verify they pass**

Run: `cd tools && go test ./cmd/dcs-sms/ -run "UninstallMeMod" -v`
Expected: 5 PASS.

- [ ] **Step 9.5: Update dispatch.go usage text**

Edit `tools/cmd/dcs-sms/dispatch.go`. In `printUsage`, after the `install-me-mod` line, insert:

```go
    fmt.Fprintln(w, "  uninstall-me-mod remove the Mission Editor mod (revert MissionEditor.lua, delete modules)")
```

- [ ] **Step 9.6: Verify the full build still passes**

Run: `cd tools && go build ./... && go test ./...`
Expected: clean build, all tests pass.

- [ ] **Step 9.7: Commit**

```bash
git add tools/cmd/dcs-sms/uninstall_me_mod.go tools/cmd/dcs-sms/uninstall_me_mod_test.go tools/cmd/dcs-sms/dispatch.go
git commit -m "feat(tools): add uninstall-me-mod CLI subcommand"
```

---

## Task 10: README + OvGME folder skeleton

**Files:**
- Create: `tools/me-mod/README.md`
- Create: `tools/me-mod/ovgme/dcs-sms-me-mod/README.md`
- Create: `tools/me-mod/ovgme/dcs-sms-me-mod/MissionEditor/modules/dcs_sms_me/.gitkeep`

User-facing docs and the OvGME folder skeleton (folder structure but no built artifact in v1).

- [ ] **Step 10.1: Write the main README**

Create `tools/me-mod/README.md`:

```markdown
# dcs-sms Mission Editor mod (hello-world)

A custom dxgui window that lives inside the DCS Mission Editor. One button:
**Print selection**. Click it, and whatever you have selected in the ME
(groups, statics, trigger zones, drawings, navigation points) is dumped to a
Lua-table file under `Saved Games\DCS\dcs-sms\me\`.

This is the **hello world** for the ME mod track. The full feature set
("save objective", "place objective", an objective library) lands in
follow-up sub-projects. See [`docs/superpowers/specs/2026-05-03-me-hello-world-design.md`](../../docs/superpowers/specs/2026-05-03-me-hello-world-design.md).

## Install (recommended path)

```powershell
dcs-sms install-me-mod --dcs-path "D:\Program Files\Eagle Dynamics\DCS World"
```

The `--dcs-path` is cached to `%AppData%\dcs-sms\config.toml` after the first
run, so subsequent installs/uninstalls don't need it. You can also set
`DCS_SMS_DCS_INSTALL` instead of using the flag.

What this does:

1. Backs up `<DCS>\MissionEditor\MissionEditor.lua` →
   `MissionEditor.lua.dcs-sms.bak`. Refuses if a backup already exists (run
   `dcs-sms uninstall-me-mod` first to clean up).
2. Appends a `require('dcs_sms_me')` block (delimited by sentinel comments)
   to `MissionEditor.lua`.
3. Copies the mod files to `<DCS>\MissionEditor\modules\dcs_sms_me\`.

Re-running the install is safe — it re-copies the module files but does not
re-patch `MissionEditor.lua` if the markers are already present.

## Uninstall

```powershell
dcs-sms uninstall-me-mod
```

Removes the patch block from `MissionEditor.lua` (surgically, by markers;
falls back to backup-restore if the markers were edited away), deletes the
modules dir, deletes the backup.

## OvGME (DIY for v1)

The folder `tools/me-mod/ovgme/dcs-sms-me-mod/` is the OvGME-package
skeleton. To assemble a usable OvGME mod by hand:

1. Copy `tools/me-mod/lua/dcs_sms_me/*` into
   `ovgme/dcs-sms-me-mod/MissionEditor/modules/dcs_sms_me/`.
2. Copy your CURRENT `<DCS>\MissionEditor\MissionEditor.lua` into
   `ovgme/dcs-sms-me-mod/MissionEditor/MissionEditor.lua` and append the
   patch block (`-- dcs-sms-me-mod begin` … `require('dcs_sms_me')` …
   `-- dcs-sms-me-mod end`).
3. Drop `dcs-sms-me-mod/` into your OvGME mods folder and enable it.

Automation for this is deferred. The CLI is the supported install path.

## Manual smoke checklist

After install, run through this list to verify the mod works end-to-end.

1. **Install:** run `dcs-sms install-me-mod`. Verify
   `<DCS>\MissionEditor\MissionEditor.lua.dcs-sms.bak` exists. Verify the
   `require('dcs_sms_me')` line was appended (between sentinel markers).
   Verify `<DCS>\MissionEditor\modules\dcs_sms_me\` contains all five files.
2. **Cold start:** open the Mission Editor. Verify the small "dcs-sms ME"
   window appears in the upper right. Verify `dcs.log` shows
   `[sms.me] window opened`.
3. **Empty selection:** with nothing selected, click the button. Verify
   the in-window status reads "No selection — nothing dumped". Verify
   `dcs.log` shows a `WARNING` line. Verify NO file is written under
   `Saved Games\DCS\dcs-sms\me\`.
4. **Single group:** place one ground unit, select it, click the button.
   Verify a dump file appears. Open it in a text editor; confirm the unit
   table contains expected keys (`units`, `route`, `x`, `y`) and that
   mixed-key fields like `callsign` look right.
5. **Multi-selection:** open the multi-select panel, select several groups,
   a trigger zone, a drawing. Click. Verify all categories appear in the
   dump.
6. **Failure path:** rename `me_multiSelection.getSelectedObjects` (or stub
   it to throw) to simulate a DCS patch breakage. Click. Verify the status
   label shows "Failed: ..." and `dcs.log` shows the error. Verify the ME
   does not crash.
7. **Uninstall:** run `dcs-sms uninstall-me-mod`. Verify
   `MissionEditor.lua` is restored. Verify the modules dir is gone. Verify
   the `.bak` file is gone.

## Running the unit tests

The Lua serializer has a standalone test suite:

```powershell
pwsh tools/me-mod/test/run-tests.ps1
```

Requires `lua.exe` (Lua 5.1) on `PATH`. If you don't have one, install from
https://luabinaries.sourceforge.net/ or run the test file inside DCS via
`dcs-sms exec --file tools/me-mod/test/test_serializer.lua`.

## Layout

```
tools/me-mod/
├── README.md                   ← you are here
├── lua/
│   ├── embed.go                ← Go embed package for the mod files
│   └── dcs_sms_me/
│       ├── init.lua            ← bootstrap (require window, show)
│       ├── window.lua          ← dxgui window + button + click handler
│       ├── selection.lua       ← ME selection-state lookup (patch-fragile)
│       ├── serializer.lua      ← Lua value → Lua chunk string
│       └── paths.lua           ← output dir constants
├── test/
│   ├── test_serializer.lua     ← pure-Lua test cases
│   └── run-tests.ps1           ← PowerShell driver
└── ovgme/
    └── dcs-sms-me-mod/         ← OvGME package skeleton (DIY, see above)
```
```

- [ ] **Step 10.2: Write the OvGME placeholder README**

Create `tools/me-mod/ovgme/dcs-sms-me-mod/README.md`:

```markdown
# dcs-sms-me-mod (OvGME package skeleton)

This folder is the skeleton for an OvGME-installable copy of the dcs-sms
Mission Editor mod.

**v1 ships the folder structure only.** The CLI (`dcs-sms install-me-mod`)
is the supported install path because it patches your CURRENT
`MissionEditor.lua` rather than shipping a frozen copy that goes stale on
every DCS patch.

To assemble an OvGME bundle by hand, see the "OvGME (DIY for v1)" section
in `tools/me-mod/README.md`.
```

- [ ] **Step 10.3: Create the modules dir placeholder**

Create `tools/me-mod/ovgme/dcs-sms-me-mod/MissionEditor/modules/dcs_sms_me/.gitkeep` with content:

```
This directory is intentionally empty.
The OvGME bundle is DIY for v1 — see ../../../README.md.
```

- [ ] **Step 10.4: Commit**

```bash
git add tools/me-mod/README.md tools/me-mod/ovgme/
git commit -m "docs(me-mod): add README and OvGME folder skeleton"
```

---

## Task 11: AGENTS.md §10 update

**Files:**
- Modify: `AGENTS.md`

Add the two new CLI subcommands to the §10 (Out-of-DCS tooling) listing. Per CLAUDE.md, doc updates land in the same PR as code; this is the sync.

- [ ] **Step 11.1: Read current §10 to match style**

Run: `grep -n "install-hook" AGENTS.md`

- [ ] **Step 11.2: Edit §10**

Open `AGENTS.md`, find the bullet list under "## 10. Out-of-DCS tooling (`tools/`)", and after the existing `install-hook` line append:

```markdown
- `install-me-mod` — installs the Mission Editor mod into `<DCS install>/MissionEditor/`. Patches `MissionEditor.lua` with sentinel-marker delimited `require('dcs_sms_me')`, copies the mod files to `MissionEditor/modules/dcs_sms_me/`. Backs up `MissionEditor.lua` first. Idempotent. Cache `--dcs-path` in `%AppData%\dcs-sms\config.toml` (or env `DCS_SMS_DCS_INSTALL`).
- `uninstall-me-mod` — reverses `install-me-mod`. Removes the patch block from `MissionEditor.lua` (surgically, by markers; falls back to backup-restore), deletes the modules dir, deletes the backup file.
```

The exact placement: directly under the `install-hook` bullet and before the `status` bullet (or wherever fits the existing alphabetical/grouping order).

- [ ] **Step 11.3: Verify the section reads cleanly**

Run: `sed -n '/## 10\./,/^## /p' AGENTS.md | head -60`
Expected: the bullet list now contains both new entries.

- [ ] **Step 11.4: Commit**

```bash
git add AGENTS.md
git commit -m "docs(agents): list install-me-mod and uninstall-me-mod in §10"
```

---

## Task 12: Final validation

**No file changes.** A final checkpoint that everything builds and tests pass before handoff.

- [ ] **Step 12.1: Run the full Go test suite**

Run: `cd tools && go test ./... -count=1`
Expected: all packages pass.

- [ ] **Step 12.2: Run go vet**

Run: `cd tools && go vet ./...`
Expected: no output.

- [ ] **Step 12.3: Build the dcs-sms binary**

Run: `cd tools && go build -o dcs-sms.exe ./cmd/dcs-sms/`
Expected: `dcs-sms.exe` exists and runs.

Run: `tools/dcs-sms.exe --help`
Expected: usage text now lists `install-me-mod` and `uninstall-me-mod`.

(Don't commit the binary; it's gitignored.)

- [ ] **Step 12.4: Run the Lua serializer tests if Lua is available**

Run: `pwsh tools/me-mod/test/run-tests.ps1`
Expected: 10 PASS or exit code 2 with clear instructions.

- [ ] **Step 12.5: Verify the branch state**

Run: `git log --oneline main..HEAD`
Expected: a series of clean conventional commits, one per task. No working-tree changes.

Run: `git status`
Expected: clean.

If anything is dirty, fix it now and amend the most recent commit.

---

## Self-review notes

These are checks the plan-writer ran to verify completeness; nothing actionable for the implementer.

**Spec coverage:**
- Goal (window + button + dump file) — Tasks 1–5.
- Install model (CLI + OvGME) — Tasks 8, 9, 10. (OvGME deferred to skeleton-only per Decisions.)
- Output format (Lua chunk, mixed-key safe, `meta`/`groups`/`zones`/`drawings`/`nav_points`/`raw`) — Tasks 1, 4.
- Failure model (log + nil + never throw, in-window status label, all the table rows in spec §"Failure model") — Tasks 3, 4, 5.
- Testing (unit serializer + manual smoke) — Tasks 1, 10, 12.
- Selection lookup contract (multi + single modes, all the listed APIs, `raw` insurance) — Task 3.
- Cross-cutting commitments (no AGENTS.md §7 / docs/api change because no `sms.*` surface; CLI subcommands documented) — Task 11.

**Placeholder scan:** no TBD/TODO; every code block is complete; no "similar to Task N" handwaves.

**Type consistency:**
- `M.snapshot()` keys (`ok`, `error`, `timestamp_utc`, `selection_mode`, `groups`, `zones`, `drawings`, `nav_points`, `raw`) used identically in `selection.lua`, `window.lua` `is_empty`/`envelope`/`summarize`.
- `paths.OUTBOX_DIR` / `paths.ensure_outbox` used in `window.lua` exactly as declared in `paths.lua`.
- `serializer.serialize(value, opts)` signature consistent across `test_serializer.lua` and `window.lua`.
- Go: `installMeModCmd` / `uninstallMeModCmd` signatures match `commandFunc`. `memod.FS`, `memod.ModuleDirName`, `memod.RequireBeginMarker/EndMarker`, `memod.PatchBlock` all consumed where defined.
- `meModBackupSuffix` defined in `install_me_mod.go` and reused in `uninstall_me_mod.go` (same file package).
