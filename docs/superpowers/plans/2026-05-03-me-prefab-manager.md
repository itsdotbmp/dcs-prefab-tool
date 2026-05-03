# ME Prefab Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing ME hello-world mod into a full Prefab Manager with Save / Place / Library / Tools-menu / narrow undo.

**Architecture:** Replace the always-on "Print selection" window with a Tools-menu-launched Prefab Manager window. The window saves the user's ME selection as a portable prefab file, places saved prefabs back into the open mission at design-time, browses the library, and provides single-slot undo for its own place operations. The framework's `sms.prefab` runtime is unchanged. To make Save work as one click, the framework's `prefab_distill.lua` and `utils_serialize.lua` are duplicated into the ME mod (different VM, different package layout); a CI parity test asserts byte-identical *output* between the two copies.

**Tech Stack:** Lua 5.1 (DCS GUI Lua state), dxgui (`Window`, `Button`, `Static`, etc.), ME-internal modules (`Mission`, `me_multiSelection`, `MapWindow`, `TriggerZoneController`, `panel_draw`, etc.), Go (embed.FS for me-mod files; no Go changes needed for this sub-project — new `.lua` files are picked up automatically by the existing `//go:embed dcs_sms_me` directive in `tools/me-mod/lua/embed.go`), PowerShell (test driver scripts).

**Spec:** `docs/superpowers/specs/2026-05-03-me-prefab-manager.md`. Read the spec's **Decisions** section before starting any task.

**Branch:** `feat/me-prefab-manager` (already created from `main`).

**Per-task commits:** Each task ends with a commit. Use `feat(me-mod): ...` or `test(me-mod): ...` or `docs(me-mod): ...` prefixes. Co-author line: `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

**Implementation discovery — read first:** Tasks 6 (place) and 8 (menu) require finding the right ME-internal API symbols (`Mission.addGroup`, Tools-menu API, etc.). The DCS install is at `D:/Program Files/Eagle Dynamics/DCS World/`; the ME Lua source lives under `MissionEditor/modules/`. Each affected task lists which directories to investigate first. If a symbol turns out to not exist, fall back to the documented alternative; if neither works, stop and surface the blocker — do not invent an API.

---

## Phase A — Foundation

### Task 1: Lift `prefab_distill.lua` into the ME mod

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/prefab_distill.lua`

**Background:** The me-mod runs in DCS's GUI Lua state, with no framework loaded. The existing `framework/prefab_distill.lua` sets `sms.prefab.distill = ...` and asserts on `sms` and `sms.log` being present. The me-mod copy can't do that. It must be a standalone Lua module that returns an M table. The algorithm is identical; only the packaging changes.

The framework copy uses `sms.K.statics[entry.units[1].type]` as a fast path for static classification, falling through to shape-inference. The framework's `sms.K.statics` is currently empty, so in practice everything goes through shape-inference. The me-mod copy uses shape-inference only (no catalog) — if the framework's catalog grows in the future, we update the me-mod's local `STATIC_TYPES` table to match, and the parity test (Task 2) catches divergence.

- [ ] **Step 1: Create `tools/me-mod/lua/dcs_sms_me/prefab_distill.lua`**

```lua
-- prefab_distill.lua — pure-data transform from ME selection dump to prefab.
--
-- This is a packaged-as-module mirror of framework/prefab_distill.lua.
-- The two MUST produce identical output for the same input — see
-- tools/me-mod/test/test_distill_parity.lua. The framework copy is
-- canonical; this copy adapts only the packaging (returns M instead of
-- setting sms.prefab.distill) and replaces the optional sms.K.statics
-- catalog with an internal table (currently empty; both must stay in sync).
--
-- No DCS dependencies — runnable in standalone Lua 5.1 for unit tests.

local M = {}

local PREFAB_VERSION = "0.1.0"

-- Shape-inference catalog. Currently empty; mirrors framework's
-- sms.K.statics population (also currently empty). If the framework adds
-- entries, mirror them here and the parity test will catch any divergence.
local STATIC_TYPES = {}

local function rad_to_deg(r)
    return r * (180 / math.pi)
end

local function utc_now()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function is_static_entity(entry)
    if entry.units and entry.units[1] and STATIC_TYPES[entry.units[1].type] then
        return true
    end
    if entry.category and entry.dead ~= nil and not entry.route then
        return true
    end
    return false
end

local function strip_back_refs(value, visited)
    if type(value) ~= 'table' then return value end
    if visited[value] then return nil end
    visited[value] = true

    local out = {}
    local captured_country
    for k, v in pairs(value) do
        if k == 'boss' then
            if type(v) == 'table' then
                if type(v.id) == 'number' then
                    captured_country = v.id
                elseif type(v.country) == 'table' and type(v.country.id) == 'number' then
                    captured_country = v.country.id
                end
            end
        else
            local cv, sub_country = strip_back_refs(v, visited)
            out[k] = cv
            if sub_country and not captured_country then
                captured_country = sub_country
            end
        end
    end

    visited[value] = nil
    return out, captured_country
end

local function convert_headings(t)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'heading' and type(v) == 'number' then
            t[k] = rad_to_deg(v)
        elseif type(v) == 'table' then
            convert_headings(v)
        end
    end
end

local function rebase_xy(t, ax, ay)
    if type(t) ~= 'table' then return end
    if type(t.x) == 'number' and type(t.y) == 'number' then
        t.x = t.x - ax
        t.y = t.y - ay
    end
    for _, v in pairs(t) do
        if type(v) == 'table' then
            rebase_xy(v, ax, ay)
        end
    end
end

local function noop_log(...) end

function M.distill(dump_or_path, opts)
    opts = opts or {}
    local log_warn  = (opts._log and opts._log.warn)  or noop_log
    local log_error = (opts._log and opts._log.error) or noop_log

    if not opts.name or opts.name == '' then
        log_warn('distill: opts.name is required')
        return nil
    end

    local dump
    local source_dump_name
    if type(dump_or_path) == 'string' then
        local ok, result = pcall(dofile, dump_or_path)
        if not ok then
            log_error('distill: dofile failed for ' .. dump_or_path .. ': ' .. tostring(result))
            return nil
        end
        dump = result
        source_dump_name = dump_or_path:match('([^/\\]+)$') or dump_or_path
    elseif type(dump_or_path) == 'table' then
        dump = dump_or_path
    else
        log_warn('distill: dump must be a path string or table')
        return nil
    end

    if type(dump) ~= 'table' then
        log_warn('distill: dump did not load to a table')
        return nil
    end

    local raw_groups   = dump.groups   or {}
    local raw_statics  = dump.statics  or {}
    local raw_zones    = dump.zones    or {}
    local raw_drawings = dump.drawings or {}

    if #raw_groups == 0 and #raw_statics == 0 and #raw_zones == 0 and #raw_drawings == 0 then
        log_warn('distill: dump has no entities — nothing to distill')
        return nil
    end

    local clean_groups   = {}
    local clean_statics  = {}
    for _, entry in ipairs(raw_groups) do
        local cleaned, country = strip_back_refs(entry, {})
        if cleaned then
            if country and not cleaned.country then
                cleaned.country = country
            end
            if cleaned.units then
                for _, u in pairs(cleaned.units) do
                    if u and not u.country then u.country = country end
                end
            end
            if is_static_entity(cleaned) then
                clean_statics[#clean_statics + 1] = cleaned
            else
                clean_groups[#clean_groups + 1] = cleaned
            end
        end
    end
    for _, entry in ipairs(raw_statics) do
        local cleaned, country = strip_back_refs(entry, {})
        if cleaned then
            if country and not cleaned.country then
                cleaned.country = country
            end
            clean_statics[#clean_statics + 1] = cleaned
        end
    end
    local clean_zones = {}
    for _, z in ipairs(raw_zones) do
        local cleaned = strip_back_refs(z, {})
        if cleaned then clean_zones[#clean_zones + 1] = cleaned end
    end
    local clean_drawings = {}
    for _, d in ipairs(raw_drawings) do
        local cleaned = strip_back_refs(d, {})
        if cleaned then clean_drawings[#clean_drawings + 1] = cleaned end
    end

    local sum_x, sum_y, n = 0, 0, 0
    local function add_point(p)
        if type(p) == 'table' and type(p.x) == 'number' and type(p.y) == 'number' then
            sum_x = sum_x + p.x; sum_y = sum_y + p.y; n = n + 1
        end
    end
    for _, g in ipairs(clean_groups)   do add_point(g) end
    for _, s in ipairs(clean_statics)  do add_point(s) end
    for _, z in ipairs(clean_zones)    do add_point(z) end
    for _, d in ipairs(clean_drawings) do
        if d.mapData then add_point(d.mapData) else add_point(d) end
    end
    if n == 0 then
        log_warn('distill: no positionable entities — cannot anchor')
        return nil
    end
    local cx, cy = sum_x / n, sum_y / n

    for _, g in ipairs(clean_groups)   do rebase_xy(g, cx, cy) end
    for _, s in ipairs(clean_statics)  do rebase_xy(s, cx, cy) end
    for _, z in ipairs(clean_zones)    do rebase_xy(z, cx, cy) end
    for _, d in ipairs(clean_drawings) do rebase_xy(d, cx, cy) end

    for _, g in ipairs(clean_groups)   do convert_headings(g) end
    for _, s in ipairs(clean_statics)  do convert_headings(s) end

    return {
        meta = {
            sms_prefab_version = PREFAB_VERSION,
            name               = opts.name,
            created_utc        = utc_now(),
            source_dump        = source_dump_name,
            world_anchor       = { x = cx, y = cy },
            theatre            = opts.theatre,
        },
        groups   = clean_groups,
        statics  = clean_statics,
        zones    = clean_zones,
        drawings = clean_drawings,
    }
end

return M
```

- [ ] **Step 2: Smoke-load it**

Run from a PowerShell prompt with Lua 5.1 on PATH:

```pwsh
cd D:/git/dcs-sms
lua -e "package.path='tools/me-mod/lua/dcs_sms_me/?.lua;'..package.path; local d = require('prefab_distill'); print(type(d.distill))"
```

Expected output: `function`

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/prefab_distill.lua
git commit -m "feat(me-mod): lift prefab_distill into ME GUI-state copy

Module-style mirror of framework/prefab_distill.lua. Algorithm identical;
packaging adapted (returns M instead of setting sms.prefab.distill) and
sms.K.statics catalog inlined as STATIC_TYPES (currently empty in both;
parity test will catch divergence if it grows).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Parity tests (serializer + distill)

**Files:**
- Create: `tools/me-mod/test/test_serializer_parity.lua`
- Create: `tools/me-mod/test/test_distill_parity.lua`
- Create: `tools/me-mod/test/fixtures/dump_synthetic_aerial.lua` (copied from `framework/test/fixtures/dump_synthetic_aerial.lua`)
- Modify: `tools/me-mod/test/run-tests.ps1` (extend to run the new tests)

**Background:** The two parity tests are the drift-control mechanism. They load BOTH the framework copy and the me-mod copy in the same standalone Lua VM, run identical inputs through both, and assert deep-equal output. The framework copy expects `sms` and `sms.log` globals; the test stubs them.

The framework's distill uses `sms.K.statics` as a fast path; we set it to `{}` (empty) so both copies fall through to shape-inference and produce identical output.

- [ ] **Step 1: Copy the synthetic fixture into the me-mod test dir**

```pwsh
cd D:/git/dcs-sms
mkdir tools/me-mod/test/fixtures -ErrorAction SilentlyContinue
Copy-Item framework/test/fixtures/dump_synthetic_aerial.lua tools/me-mod/test/fixtures/dump_synthetic_aerial.lua
```

We copy rather than reference across trees because the test driver `cd`s into `tools/me-mod/test/` and `dofile`s by relative path. This duplicates ~5 KB of fixture for cleanliness; acceptable.

- [ ] **Step 2: Create `tools/me-mod/test/test_serializer_parity.lua`**

```lua
-- Parity test: framework/utils_serialize.lua vs tools/me-mod/lua/dcs_sms_me/serializer.lua.
-- Both must produce byte-identical output for the same input.
-- Run via: lua test_serializer_parity.lua  (cwd: tools/me-mod/test/)

-- 1) Load me-mod copy (module-style).
package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local memod_serializer = require('serializer')

-- 2) Load framework copy. It's framework-style: expects sms + sms.log,
-- writes sms.utils.serialize. Stub the contract.
sms = {}
sms.log = { module = function() return { warn=function() end, error=function() end, info=function() end, debug=function() end } end }
sms.utils = sms.utils or {}
dofile('../../../framework/utils_serialize.lua')
local fw_serialize = sms.utils.serialize

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function assert_parity(name, value)
    local a = memod_serializer.serialize(value)
    local b = fw_serialize(value)
    check(name, a == b, 'me-mod=' .. tostring(#a) .. 'B fw=' .. tostring(#b) .. 'B; diff at ' .. tostring((function()
        for i = 1, math.max(#a, #b) do
            if a:sub(i,i) ~= b:sub(i,i) then return i end
        end
        return -1
    end)()))
end

-- Cases — same inputs as framework/test/test_utils_serialize.lua.
assert_parity('empty table', {})
assert_parity('flat array', {1, 2, 3})
assert_parity('callsign mixed-key', {[1]=3, [2]=1, [3]=1, name='Uzi11'})
assert_parity('nested', {a=1, b={c=2, d={e=3}}})
assert_parity('numbers: int, float, negative', {1, -1, 0.5, -3.14})
assert_parity('strings with quotes and newlines', {s='hello "world"\nline2'})
assert_parity('booleans', {t=true, f=false})

-- Cycle (visited-set; same marker text in both).
local cyc = {x=1}; cyc.self = cyc
assert_parity('cycle', cyc)

-- NaN / inf normalization (both should emit 0/0 / 1/0 / -1/0).
assert_parity('inf and nan', {math.huge, -math.huge, 0/0})

-- Boolean keys (both should emit [true] / [false]).
assert_parity('boolean keys', {[true]=1, [false]=2})

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All parity tests passed.')
```

- [ ] **Step 3: Run the serializer parity test, expect FAIL initially if anything diverges**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_serializer_parity.lua
```

Expected: all PASS (because the existing me-mod `serializer.lua` was already byte-identical to `framework/utils_serialize.lua` per Sub-project 1 spec). If you see any FAIL, the divergence is real — diff the two source files (`framework/utils_serialize.lua` vs `tools/me-mod/lua/dcs_sms_me/serializer.lua`) and reconcile by aligning the me-mod copy to the framework copy.

- [ ] **Step 4: Create `tools/me-mod/test/test_distill_parity.lua`**

```lua
-- Parity test: framework/prefab_distill.lua vs tools/me-mod/lua/dcs_sms_me/prefab_distill.lua.
-- Both must produce deep-equal output for the same input.
-- Run via: lua test_distill_parity.lua  (cwd: tools/me-mod/test/)

-- 1) Load me-mod copy (module-style).
package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local memod_distill = require('prefab_distill').distill

-- 2) Load framework copy. Framework-style: stub sms, sms.log, sms.K.
sms = {}
sms.log = { module = function() return { warn=function() end, error=function() end, info=function() end, debug=function() end } end }
sms.K = { statics = {} }   -- empty catalog → both fall through to shape-inference
sms.prefab = nil
package.path = '../../../framework/?.lua;' .. package.path
dofile('../../../framework/prefab_distill.lua')
local fw_distill = sms.prefab.distill

-- Recursive deep-equal that ignores meta.created_utc (timestamp differs per call).
local function deep_equal(a, b, path)
    path = path or 'root'
    if type(a) ~= type(b) then return false, path .. ': type ' .. type(a) .. ' vs ' .. type(b) end
    if type(a) ~= 'table' then
        if a ~= b then return false, path .. ': ' .. tostring(a) .. ' vs ' .. tostring(b) end
        return true
    end
    for k, v in pairs(a) do
        if not (path == 'root.meta' and k == 'created_utc') then
            local ok, why = deep_equal(v, b[k], path .. '.' .. tostring(k))
            if not ok then return false, why end
        end
    end
    for k, _ in pairs(b) do
        if a[k] == nil and not (path == 'root.meta' and k == 'created_utc') then
            return false, path .. '.' .. tostring(k) .. ': missing in a'
        end
    end
    return true
end

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function load_dump(path)
    local f = assert(loadfile(path))
    return f()
end

local function assert_parity(name, dump, opts)
    local a = memod_distill(dump, opts)
    local b = fw_distill(dump, opts)
    if a == nil and b == nil then
        check(name .. ' (both nil)', true)
        return
    end
    if (a == nil) ~= (b == nil) then
        check(name, false, 'memod=' .. tostring(a) .. ' fw=' .. tostring(b))
        return
    end
    local ok, why = deep_equal(a, b)
    check(name, ok, why)
end

-- Case 1: real synthetic fixture.
local fixture = load_dump('fixtures/dump_synthetic_aerial.lua')
assert_parity('synthetic aerial fixture', fixture, {name='test', theatre='Caucasus'})

-- Case 2: minimal single group.
assert_parity('single group at origin', {
    groups = { { name='G1', x=0, y=0, units={ { name='U1', type='F-16C_50', x=0, y=0, heading=0 } } } }
}, {name='one'})

-- Case 3: two groups for centroid.
assert_parity('two groups for centroid', {
    groups = {
        { name='G1', x=0,   y=0,   units={ { name='U1', type='F-16C_50', x=0,   y=0,   heading=0 } } },
        { name='G2', x=200, y=400, units={ { name='U2', type='F-16C_50', x=200, y=400, heading=math.pi } } },
    }
}, {name='two'})

-- Case 4: opts.name missing → both should return nil.
assert_parity('no name → nil', { groups={ { x=0, y=0 } } }, {})

-- Case 5: empty dump → both should return nil.
assert_parity('empty dump → nil', { groups={}, statics={}, zones={}, drawings={} }, {name='empty'})

-- Case 6: zones + drawings mixed.
assert_parity('zones+drawings', {
    groups = {},
    statics = {},
    zones    = { { name='Z1', x=100, y=200, radius=50, type=0, properties={} } },
    drawings = { { name='D1', primitiveType='Polygon', mapData={ x=300, y=400 }, points={ {x=0,y=0}, {x=10,y=0}, {x=10,y=10} } } },
}, {name='zd'})

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All distill-parity tests passed.')
```

- [ ] **Step 5: Run the distill parity test**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_distill_parity.lua
```

Expected: all PASS. If anything FAILs, the path is to inspect which key diverged (the test prints a path like `root.groups.1.units.1.x`), then reconcile the me-mod copy against the framework copy. Output divergence at the `meta.created_utc` field is filtered out by the deep-equal helper.

- [ ] **Step 6: Extend `tools/me-mod/test/run-tests.ps1` to run all three tests**

Replace the entire file content with:

```pwsh
# Locates a Lua 5.1 interpreter on PATH and runs all me-mod unit tests:
#   - test_serializer.lua
#   - test_serializer_parity.lua
#   - test_distill_parity.lua
# Exits non-zero on any test failure or when no interpreter is available.

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
        exit 2
    }
    Write-Host "Using Lua interpreter: $lua"
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua')
    $anyFailed = $false
    foreach ($t in $tests) {
        if (-not (Test-Path $t)) { continue }
        Write-Host ""
        Write-Host "=== $t ===" -ForegroundColor Cyan
        & $lua $t
        if ($LASTEXITCODE -ne 0) { $anyFailed = $true }
    }
    if ($anyFailed) { exit 1 } else { exit 0 }
} finally {
    Pop-Location
}
```

- [ ] **Step 7: Run the full me-mod test suite**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
./run-tests.ps1
```

Expected: all three test files pass. If `test_serializer.lua` fails for an unrelated reason (it was passing before this branch), stop and surface — don't paper over.

- [ ] **Step 8: Run the framework tests too — they must still pass**

```pwsh
cd D:/git/dcs-sms/framework/test
./run_distill_tests.ps1
```

Expected: existing framework tests pass unchanged (we touched no framework files).

- [ ] **Step 9: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/test/test_serializer_parity.lua tools/me-mod/test/test_distill_parity.lua tools/me-mod/test/fixtures tools/me-mod/test/run-tests.ps1
git commit -m "test(me-mod): parity tests for distill + serializer

Loads framework and me-mod copies in the same Lua VM, runs identical
fixtures through both, asserts deep-equal output. Drift becomes a CI
build break instead of a runtime bug.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Extend `paths.lua` with the prefabs directory

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/paths.lua`

- [ ] **Step 1: Replace `tools/me-mod/lua/dcs_sms_me/paths.lua` content**

```lua
-- paths.lua — output directory constants and dir-creation helpers.
--
-- Nests under the same Saved Games\DCS\dcs-sms\ root the bridge uses, with
-- per-feature subdirs:
--   me/        — selection dumps (sub-project 2)
--   prefabs/   — distilled prefab files (sub-project 3)

local lfs = require('lfs')
local M = {}

M.ROOT        = lfs.writedir() .. 'dcs-sms\\'
M.OUTBOX_DIR  = M.ROOT .. 'me\\'
M.PREFABS_DIR = M.ROOT .. 'prefabs\\'
M.LOG_TAG     = 'sms.me'

function M.ensure_outbox()
    lfs.mkdir(M.ROOT)
    lfs.mkdir(M.OUTBOX_DIR)
end

function M.ensure_prefabs()
    lfs.mkdir(M.ROOT)
    lfs.mkdir(M.PREFABS_DIR)
end

return M
```

- [ ] **Step 2: Verify it loads**

```pwsh
cd D:/git/dcs-sms
lua -e "package.path='tools/me-mod/lua/dcs_sms_me/?.lua;'..package.path; package.cpath=package.cpath; local lfs={writedir=function() return 'C:\\fake\\' end}; package.preload['lfs']=function() return lfs end; local p=require('paths'); print(p.PREFABS_DIR); assert(p.PREFABS_DIR=='C:\\fake\\dcs-sms\\prefabs\\', 'expected prefabs dir')"
```

Expected: prints `C:\fake\dcs-sms\prefabs\` and exits 0.

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/paths.lua
git commit -m "feat(me-mod): add PREFABS_DIR + ensure_prefabs() to paths.lua

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase B — Operations

### Task 4: `prefab_ops.lua` — Save half (save_selection + exists)

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` (initial content with the save half; later tasks extend)
- Create: `tools/me-mod/test/test_prefab_ops_save.lua`
- Modify: `tools/me-mod/test/run-tests.ps1` (add new test)

**Background:** `save_selection(name)` reads the current ME selection via `selection.snapshot()`, wraps it in dump-envelope shape, distills, serializes, writes file. The unit test stubs `selection` and `lfs` to exercise the envelope-wrapping and file-path logic.

The dump-envelope shape that distill expects has top-level `groups`, `statics`, `zones`, `drawings` arrays. `selection.snapshot()` returns those plus `ok`, `error`, `timestamp_utc`, `selection_mode`, `raw`. We pass through the four data arrays.

- [ ] **Step 1: Write the failing unit test — `tools/me-mod/test/test_prefab_ops_save.lua`**

```lua
-- Standalone test for prefab_ops.save_selection envelope wrapping + path logic.
-- Stubs lfs and selection to avoid DCS dependencies.
-- Run via: lua test_prefab_ops_save.lua  (cwd: tools/me-mod/test/)

-- Stub lfs (writedir + mkdir).
local fake_writedir = 'C:\\fake-saved-games\\'
package.preload['lfs'] = function()
    return {
        writedir = function() return fake_writedir end,
        mkdir = function(p) return true end,
    }
end

-- Capture io.open calls so we can inspect what the save wrote.
local captured = { path = nil, content = nil }
local real_open = io.open
io.open = function(path, mode)
    if mode == 'w' then
        return {
            write = function(self, content) captured.path = path; captured.content = content end,
            close = function(self) end,
        }
    end
    return real_open(path, mode)
end

-- Stub selection.snapshot.
package.preload['dcs_sms_me.selection'] = function()
    return {
        snapshot = function()
            return {
                ok = true,
                timestamp_utc = '2026-05-03T12:00:00Z',
                selection_mode = 'multi',
                groups = {
                    { name='G1', x=100, y=200,
                      units={ { name='U1', type='F-16C_50', x=100, y=200, heading=0 } },
                      boss = { id=2, name='USA' } },
                },
                statics = {},
                zones = {},
                drawings = {},
                nav_points = {},
                raw = {},
            }
        end,
    }
end

-- Empty-snapshot variant for the empty-selection case.
local empty_selection_module = {
    snapshot = function()
        return { ok=true, timestamp_utc='2026-05-03T12:00:00Z', selection_mode='multi',
                 groups={}, statics={}, zones={}, drawings={}, nav_points={}, raw={} }
    end,
}

package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: save_selection with valid selection produces a file at the right path.
do
    captured.path, captured.content = nil, nil
    local ok, path = prefab_ops.save_selection('test_jet')
    check('save_selection returns ok', ok == true, 'got ' .. tostring(ok))
    check('save_selection returns path', path == fake_writedir .. 'dcs-sms\\prefabs\\test_jet.lua',
          'got ' .. tostring(path))
    check('io.open was called with that path', captured.path == path, 'got ' .. tostring(captured.path))
    check('content begins with "return {"',
          type(captured.content) == 'string' and captured.content:sub(1,8) == 'return {',
          'got ' .. (captured.content and captured.content:sub(1,30) or 'nil'))
    check('content has meta.name',
          captured.content and captured.content:find('"name"%s*=%s*"test_jet"', 1) ~= nil,
          'meta.name not found in content')
end

-- Case: save_selection with empty selection returns nil + reason.
do
    package.loaded['dcs_sms_me.selection'] = empty_selection_module
    package.loaded['dcs_sms_me.prefab_ops'] = nil  -- force re-require so it picks up new selection module
    local prefab_ops2 = require('prefab_ops')
    local ok, err = prefab_ops2.save_selection('empty')
    check('empty save returns nil',  ok == nil, 'got ' .. tostring(ok))
    check('empty save returns error', type(err) == 'string' and err:find('selection'), 'got ' .. tostring(err))
end

-- Case: exists() with a file present.
do
    -- Simulate file presence by stubbing io.open in read mode for the path.
    local target = fake_writedir .. 'dcs-sms\\prefabs\\already_here.lua'
    local missing = fake_writedir .. 'dcs-sms\\prefabs\\not_here.lua'
    io.open = function(path, mode)
        if mode == 'r' or mode == nil then
            if path == target then return { close = function() end } end
            return nil, 'not found'
        end
        return real_open(path, mode)
    end
    package.loaded['dcs_sms_me.prefab_ops'] = nil
    local prefab_ops3 = require('prefab_ops')
    check('exists() true for present file', prefab_ops3.exists('already_here') == true,
          'expected true')
    check('exists() false for absent file', prefab_ops3.exists('not_here') == false,
          'expected false')
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops save tests passed.')
```

- [ ] **Step 2: Run the test, expect FAIL (module doesn't exist yet)**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_prefab_ops_save.lua
```

Expected: fails with `module 'prefab_ops' not found`.

- [ ] **Step 3: Create `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua`** (initial: save + exists; load/place added in later tasks)

```lua
-- prefab_ops.lua — prefab save / load / place operations.
--
-- This file ships in three parts (one per group). Save + exists land
-- here in Task 4; scan_dir + load in Task 5; place in Task 6.
--
-- All public symbols return either a positive value (path, table,
-- record) on success, or nil + error_string on failure. No throws.

local lfs        = require('lfs')
local paths      = require('dcs_sms_me.paths')
local distill    = require('dcs_sms_me.prefab_distill').distill
local serializer = require('dcs_sms_me.serializer')
local selection  = require('dcs_sms_me.selection')

local M = {}

local function prefab_path(name)
    return paths.PREFABS_DIR .. name .. '.lua'
end

function M.exists(name)
    if type(name) ~= 'string' or name == '' then return false end
    local f = io.open(prefab_path(name), 'r')
    if f then f:close(); return true end
    return false
end

-- Wrap a selection.snapshot() result into the dump-envelope shape that
-- prefab_distill.distill expects (top-level groups/statics/zones/drawings).
local function selection_to_dump(snap)
    return {
        groups   = snap.groups   or {},
        statics  = snap.statics  or {},   -- may be empty if statics ride inside groups (per Sub-project 2)
        zones    = snap.zones    or {},
        drawings = snap.drawings or {},
    }
end

local function any_selection(snap)
    return (#(snap.groups or {})   > 0)
        or (#(snap.statics or {})  > 0)
        or (#(snap.zones or {})    > 0)
        or (#(snap.drawings or {}) > 0)
end

function M.save_selection(name)
    if type(name) ~= 'string' or name == '' then
        return nil, 'name required'
    end

    local snap = selection.snapshot()
    if not snap or not snap.ok then
        return nil, 'selection lookup failed: ' .. tostring(snap and snap.error or 'no snapshot')
    end
    if not any_selection(snap) then
        return nil, 'no selection — nothing to save'
    end

    local dump = selection_to_dump(snap)
    local prefab = distill(dump, { name = name })
    if not prefab then
        return nil, 'distill returned nil — check log for details'
    end

    local serialized = serializer.serialize(prefab)
    if type(serialized) ~= 'string' then
        return nil, 'serialize returned non-string'
    end

    paths.ensure_prefabs()
    local path = prefab_path(name)
    local f, oerr = io.open(path, 'w')
    if not f then
        return nil, 'open failed: ' .. tostring(oerr)
    end
    f:write(serialized)
    f:close()

    return true, path
end

return M
```

- [ ] **Step 4: Run the test, expect PASS**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_prefab_ops_save.lua
```

Expected: all PASS.

- [ ] **Step 5: Add the new test to the run-tests driver**

Modify `tools/me-mod/test/run-tests.ps1` line that starts with `$tests = @(...)`. Replace with:

```pwsh
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua', 'test_prefab_ops_save.lua')
```

- [ ] **Step 6: Run the full test suite**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
./run-tests.ps1
```

Expected: all four test files pass.

- [ ] **Step 7: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/prefab_ops.lua tools/me-mod/test/test_prefab_ops_save.lua tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): prefab_ops save_selection + exists

save_selection wraps the current selection.snapshot() in a dump-envelope
shape, runs it through distill + serialize, writes to
<saved-games>\dcs-sms\prefabs\<name>.lua. Empty selection or distill
failure returns nil + error string; never throws.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `prefab_ops.lua` — Load half (scan_dir + load)

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` (extend with scan_dir + load)
- Create: `tools/me-mod/test/test_prefab_ops_load.lua`
- Create: `tools/me-mod/test/fixtures/prefabs_dir/farp_alpha.lua` (good prefab)
- Create: `tools/me-mod/test/fixtures/prefabs_dir/sam_site.lua` (good prefab)
- Create: `tools/me-mod/test/fixtures/prefabs_dir/broken.lua` (deliberately invalid)
- Modify: `tools/me-mod/test/run-tests.ps1` (add new test)

**Background:** `scan_dir()` returns one row per `*.lua` in the prefabs dir, with metadata (name, theatre, group/static/zone/drawing counts, optional source_dump, optional error). `load(path)` returns the loaded prefab table or nil + error.

scan_dir uses `lfs.dir` to enumerate; loading each file is `pcall(dofile, ...)` to isolate per-file failures.

- [ ] **Step 1: Create the fixture prefab files**

`tools/me-mod/test/fixtures/prefabs_dir/farp_alpha.lua`:

```lua
return {
    ["meta"] = {
        ["name"] = "farp_alpha",
        ["sms_prefab_version"] = "0.1.0",
        ["theatre"] = "Caucasus",
        ["created_utc"] = "2026-05-03T12:00:00Z",
        ["world_anchor"] = { ["x"] = 0, ["y"] = 0 },
    },
    ["groups"] = {
        [1] = { ["name"] = "G1", ["x"] = 0, ["y"] = 0,
                ["units"] = { [1] = { ["name"] = "U1", ["type"] = "F-16C_50" } } },
        [2] = { ["name"] = "G2", ["x"] = 0, ["y"] = 0,
                ["units"] = { [1] = { ["name"] = "U2", ["type"] = "F-16C_50" } } },
    },
    ["statics"]  = { [1] = { ["name"] = "S1", ["x"] = 0, ["y"] = 0 } },
    ["zones"]    = {},
    ["drawings"] = {},
}
```

`tools/me-mod/test/fixtures/prefabs_dir/sam_site.lua`:

```lua
return {
    ["meta"] = {
        ["name"] = "sam_site",
        ["sms_prefab_version"] = "0.1.0",
        ["theatre"] = "Caucasus",
        ["created_utc"] = "2026-05-03T12:00:00Z",
        ["world_anchor"] = { ["x"] = 1000, ["y"] = 2000 },
        ["source_dump"]  = "selection-2026-05-03T091254Z.lua",
    },
    ["groups"]   = { [1] = { ["name"] = "SA-6", ["x"] = 0, ["y"] = 0,
                             ["units"] = { [1] = { ["name"] = "Launcher" } } } },
    ["statics"]  = {},
    ["zones"]    = { [1] = { ["name"] = "Z1", ["x"] = 0, ["y"] = 0, ["radius"] = 100 } },
    ["drawings"] = {},
}
```

`tools/me-mod/test/fixtures/prefabs_dir/broken.lua`:

```lua
this is not valid lua syntax )))
```

- [ ] **Step 2: Write the failing test — `tools/me-mod/test/test_prefab_ops_load.lua`**

```lua
-- Standalone test for prefab_ops.scan_dir + load.
-- Run via: lua test_prefab_ops_load.lua  (cwd: tools/me-mod/test/)

local fake_writedir = 'fixtures\\fake_root\\'  -- relative; we don't actually need lfs.writedir to be Windows-style
local fixtures_dir  = 'fixtures/prefabs_dir/'

-- Stub lfs.writedir to point at fixtures, and lfs.dir to enumerate files.
local function list_dir(path)
    local fixtures_path = path:gsub('\\', '/'):gsub('/$', '')
    local p = io.popen('dir /b "' .. fixtures_path:gsub('/', '\\') .. '" 2>nul')
    local files = {}
    if p then
        for line in p:lines() do files[#files + 1] = line end
        p:close()
    end
    return files
end

package.preload['lfs'] = function()
    return {
        writedir = function() return '' end,  -- unused for these tests
        mkdir    = function() return true end,
        attributes = function(path) return { mode = 'file' } end,
        dir = function(p)
            local files = list_dir(p)
            local i = 0
            return function()
                i = i + 1
                return files[i]
            end
        end,
    }
end

-- Override paths.PREFABS_DIR to point at fixtures.
package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local paths = require('dcs_sms_me.paths')
paths.PREFABS_DIR = fixtures_dir

-- Stub selection (not used by load, but prefab_ops requires it).
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: scan_dir returns one row per .lua file.
do
    local rows = prefab_ops.scan_dir()
    check('scan_dir returns array of length 3', type(rows) == 'table' and #rows == 3,
          'got ' .. tostring(rows and #rows or nil))

    -- Find each row by name.
    local by_name = {}
    for _, r in ipairs(rows) do by_name[r.name] = r end

    check('farp_alpha row present', by_name['farp_alpha'] ~= nil)
    check('sam_site row present',   by_name['sam_site']   ~= nil)
    check('broken row present',     by_name['broken']     ~= nil)

    if by_name['farp_alpha'] then
        local r = by_name['farp_alpha']
        check('farp_alpha theatre', r.theatre == 'Caucasus')
        check('farp_alpha group_count == 2',  r.group_count == 2,  'got ' .. tostring(r.group_count))
        check('farp_alpha static_count == 1', r.static_count == 1, 'got ' .. tostring(r.static_count))
        check('farp_alpha no error',          r.error == nil)
    end
    if by_name['sam_site'] then
        local r = by_name['sam_site']
        check('sam_site source_dump', r.source_dump == 'selection-2026-05-03T091254Z.lua',
              'got ' .. tostring(r.source_dump))
        check('sam_site zone_count == 1', r.zone_count == 1, 'got ' .. tostring(r.zone_count))
    end
    if by_name['broken'] then
        local r = by_name['broken']
        check('broken row has error', type(r.error) == 'string',
              'expected error string, got ' .. tostring(r.error))
    end
end

-- Case: load returns the table or nil+error.
do
    local p, err = prefab_ops.load(fixtures_dir .. 'farp_alpha.lua')
    check('load returns table',     type(p) == 'table' and p.meta and p.meta.name == 'farp_alpha',
          'got ' .. tostring(p))

    local bad, berr = prefab_ops.load(fixtures_dir .. 'broken.lua')
    check('load broken returns nil',       bad == nil)
    check('load broken returns error str', type(berr) == 'string')
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops load tests passed.')
```

- [ ] **Step 3: Run the test, expect FAIL (functions don't exist yet)**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_prefab_ops_load.lua
```

Expected: fails with `attempt to call nil` for `scan_dir` or `load`.

- [ ] **Step 4: Extend `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` with the load half**

Append (do not replace) to `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` — insert these functions BEFORE the final `return M` line:

```lua
-- ---------------------------------------------------------------------------
-- Load + scan
-- ---------------------------------------------------------------------------

function M.load(path)
    if type(path) ~= 'string' or path == '' then return nil, 'path required' end
    local ok, result = pcall(dofile, path)
    if not ok then return nil, 'dofile failed: ' .. tostring(result) end
    if type(result) ~= 'table' then return nil, 'file did not return a table' end
    if type(result.meta) ~= 'table' or type(result.meta.name) ~= 'string' then
        return nil, 'missing meta.name'
    end
    return result
end

local function count(t)
    if type(t) ~= 'table' then return 0 end
    return #t
end

local function row_from_prefab(name, path, prefab)
    local meta = prefab.meta
    return {
        name          = meta.name or name,
        path          = path,
        theatre       = meta.theatre,
        source_dump   = meta.source_dump,
        group_count   = count(prefab.groups),
        static_count  = count(prefab.statics),
        zone_count    = count(prefab.zones),
        drawing_count = count(prefab.drawings),
    }
end

function M.scan_dir()
    paths.ensure_prefabs()
    local rows = {}
    local ok, iter = pcall(lfs.dir, paths.PREFABS_DIR)
    if not ok then return rows end

    for entry in iter do
        if entry ~= '.' and entry ~= '..' and entry:match('%.lua$') then
            local name = entry:gsub('%.lua$', '')
            local path = paths.PREFABS_DIR .. entry
            local prefab, err = M.load(path)
            if prefab then
                rows[#rows + 1] = row_from_prefab(name, path, prefab)
            else
                rows[#rows + 1] = { name = name, path = path, error = err }
            end
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end
```

- [ ] **Step 5: Run the test, expect PASS**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_prefab_ops_load.lua
```

Expected: all PASS.

- [ ] **Step 6: Add the new test to the driver**

Modify `tools/me-mod/test/run-tests.ps1`'s `$tests` array to:

```pwsh
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua', 'test_prefab_ops_save.lua', 'test_prefab_ops_load.lua')
```

- [ ] **Step 7: Run full test suite**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
./run-tests.ps1
```

Expected: five test files pass.

- [ ] **Step 8: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/prefab_ops.lua tools/me-mod/test/test_prefab_ops_load.lua tools/me-mod/test/fixtures/prefabs_dir tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): prefab_ops scan_dir + load

scan_dir enumerates *.lua under PREFABS_DIR, returning per-file rows
with metadata; per-file load failures appear as rows with an 'error'
field rather than being skipped silently. Sorted A-Z by name.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `prefab_ops.lua` — Place half + ME-API discovery

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` (extend with place + math helpers)
- Create: `tools/me-mod/test/test_prefab_ops_place.lua`
- Modify: `tools/me-mod/test/run-tests.ps1` (add new test)

**Background:** `place(prefab, opts)` injects a prefab into the open mission. Two halves: pure math (rotate + translate coords) which is unit-testable, and ME-internal API calls which are runtime-only.

**ME-API discovery:** before writing place, investigate the ME's mutation API. Spend ~10 minutes reading these locations to find the canonical add/remove symbols:

- `D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules/me_mission.lua` — likely contains `Mission.addGroup`, `Mission.removeGroup`, `Mission.addStaticObject`, etc.
- `D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules/me_copy_paste.lua` — copy/paste in the ME goes through these mutation paths; reading it shows which symbols are "blessed" for adding entities programmatically.
- `D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules/Mission/TriggerZoneController.lua` — for trigger zone add.
- `D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules/me_draw_panel.lua` — for drawing add.

Commit to whatever symbols you find. If a symbol isn't there for a given entity type, log a warning and skip that type at runtime — partial-success is fine per the spec. Do NOT invent API.

Common patterns to expect: `Mission.addGroup(country_id, category_id, group_table)`, `Mission.addStaticObject(country_id, static_table)` returning a runtime ID. Inverse: `Mission.removeGroup(id)`. Country and category are typically passed as numeric IDs found on the entity itself.

- [ ] **Step 1: Write the failing test for the math half — `tools/me-mod/test/test_prefab_ops_place.lua`**

```lua
-- Standalone test for prefab_ops place math (rotate + translate).
-- The ME-API injection itself is not unit-testable; covered by manual smoke.
-- Run via: lua test_prefab_ops_place.lua  (cwd: tools/me-mod/test/)

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             dir = function() return function() return nil end end }
end
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

package.path = '../lua/dcs_sms_me/?.lua;' .. package.path
local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function approx(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) <= eps
end

-- Math helper: place_xy(rel_x, rel_y, anchor, rotation_deg) → (world_x, world_y)
do
    local x, y = prefab_ops._place_xy(100, 0, { x = 1000, y = 2000 }, 0)
    check('rot 0: (100, 0) at anchor (1000, 2000) → (1100, 2000)',
          approx(x, 1100) and approx(y, 2000), 'got ' .. x .. ', ' .. y)

    local x2, y2 = prefab_ops._place_xy(100, 0, { x = 0, y = 0 }, 90)
    check('rot 90: (100, 0) → (0, 100)',
          approx(x2, 0) and approx(y2, 100), 'got ' .. x2 .. ', ' .. y2)

    local x3, y3 = prefab_ops._place_xy(0, 100, { x = 0, y = 0 }, 90)
    check('rot 90: (0, 100) → (-100, 0)',
          approx(x3, -100) and approx(y3, 0), 'got ' .. x3 .. ', ' .. y3)

    local x4, y4 = prefab_ops._place_xy(100, 0, { x = 500, y = 500 }, 180)
    check('rot 180: (100, 0) at anchor (500, 500) → (400, 500)',
          approx(x4, 400) and approx(y4, 500), 'got ' .. x4 .. ', ' .. y4)
end

-- Heading composition: world_heading_deg = (file_heading_deg + rotation_deg) mod 360
do
    check('heading 30 + rotation 60 = 90', prefab_ops._heading_world(30, 60) == 90)
    check('heading 350 + rotation 20 = 10', prefab_ops._heading_world(350, 20) == 10)
    check('heading -30 + rotation 0 = 330', prefab_ops._heading_world(-30, 0) == 330)
end

-- Resolve effective anchor: keep_position uses meta.world_anchor.
do
    local prefab = { meta = { world_anchor = { x = 5000, y = 6000 } }, groups = {}, statics = {}, zones = {}, drawings = {} }
    local a, r = prefab_ops._resolve_anchor(prefab, { keep_position = true, anchor = { x = 1, y = 1 }, rotation = 30 })
    check('keep_position: anchor from meta', a.x == 5000 and a.y == 6000)
    check('keep_position: rotation forced 0', r == 0)

    local a2, r2 = prefab_ops._resolve_anchor(prefab, { anchor = { x = 100, y = 200 }, rotation = 45 })
    check('non-keep_position: anchor from opts', a2.x == 100 and a2.y == 200)
    check('non-keep_position: rotation passed through', r2 == 45)

    local a3 = prefab_ops._resolve_anchor(prefab, { rotation = 0 })
    check('no anchor + no keep_position: returns nil', a3 == nil)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops place tests passed.')
```

- [ ] **Step 2: Run the test, expect FAIL**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_prefab_ops_place.lua
```

Expected: fails with `attempt to call nil` for `_place_xy`, `_heading_world`, or `_resolve_anchor`.

- [ ] **Step 3: Investigate ME-API symbols**

Spend ~10 minutes reading these files and recording the symbols you find. Take notes; you'll commit to specific symbols in Step 4.

```pwsh
$me = "D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules"
Select-String -Path "$me/me_mission.lua" -Pattern '^function .*addGroup|^function .*removeGroup|^function .*addStatic|^function .*removeStatic' | Select-Object -First 20
Select-String -Path "$me/me_copy_paste.lua" -Pattern 'addGroup|addStatic|addZone|addDrawing' | Select-Object -First 20
Select-String -Path "$me/Mission/TriggerZoneController.lua" -Pattern '^function .*add|^function .*remove' | Select-Object -First 20
Select-String -Path "$me/me_draw_panel.lua" -Pattern '^function .*add|^function .*remove' | Select-Object -First 20
```

If a directory or file doesn't exist, note that and look in nearby files. The DCS install layout is stable across recent versions; if everything is missing, the install path may be wrong.

- [ ] **Step 4: Extend `tools/me-mod/lua/dcs_sms_me/prefab_ops.lua` with the place half**

Append BEFORE the final `return M` line. Replace the `<TBD>` placeholders with the actual symbols you found in Step 3. If a symbol doesn't exist for a given entity type, leave the `pcall` in place but log "X API not found"; partial-success at runtime is fine.

```lua
-- ---------------------------------------------------------------------------
-- Place math (unit-testable, exposed under M._<name>)
-- ---------------------------------------------------------------------------

function M._place_xy(rel_x, rel_y, anchor, rotation_deg)
    local r = (rotation_deg or 0) * (math.pi / 180)
    local c, s = math.cos(r), math.sin(r)
    local rx = rel_x * c - rel_y * s
    local ry = rel_x * s + rel_y * c
    return anchor.x + rx, anchor.y + ry
end

function M._heading_world(file_heading_deg, rotation_deg)
    local h = ((file_heading_deg or 0) + (rotation_deg or 0)) % 360
    if h < 0 then h = h + 360 end
    return h
end

function M._resolve_anchor(prefab, opts)
    if opts.keep_position then
        local wa = prefab.meta and prefab.meta.world_anchor
        if not (wa and type(wa.x) == 'number' and type(wa.y) == 'number') then
            return nil
        end
        return { x = wa.x, y = wa.y }, 0
    end
    if not (opts.anchor and type(opts.anchor.x) == 'number' and type(opts.anchor.y) == 'number') then
        return nil
    end
    return { x = opts.anchor.x, y = opts.anchor.y }, opts.rotation or 0
end

-- ---------------------------------------------------------------------------
-- Place — runtime ME-API injection
-- ---------------------------------------------------------------------------

-- Walk a group/static table and rewrite every {x, y} pair using the
-- place_xy transform. Mutates in place.
local function transform_coords(t, anchor, rotation_deg)
    if type(t) ~= 'table' then return end
    if type(t.x) == 'number' and type(t.y) == 'number' then
        t.x, t.y = M._place_xy(t.x, t.y, anchor, rotation_deg)
    end
    for _, v in pairs(t) do
        if type(v) == 'table' then transform_coords(v, anchor, rotation_deg) end
    end
end

local function transform_headings(t, rotation_deg)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'heading' and type(v) == 'number' then
            t[k] = M._heading_world(v, rotation_deg) * (math.pi / 180)  -- back to radians for DCS
        elseif type(v) == 'table' then
            transform_headings(v, rotation_deg)
        end
    end
end

-- Deep-copy a table. Used so place can transform without mutating the
-- registered template (caller may place the same prefab multiple times).
local function deep_copy(v, seen)
    if type(v) ~= 'table' then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, vv in pairs(v) do out[k] = deep_copy(vv, seen) end
    return out
end

-- ME-API call wrappers. Each returns runtime_id, err. Symbols TBD per
-- ME-API discovery (Step 3 of Task 6). If a symbol turns out not to
-- exist, the pcall wrapper degrades it to a logged failure.
local function inject_group(group, country)
    -- IMPLEMENTATION NOTE: replace this body with the actual ME mutation
    -- call discovered in Step 3. Expected shape:
    --   local id = Mission.addGroup(country, category_for(group), group)
    --   return id
    local Mission = require('me_mission')
    if not (Mission and Mission.addGroup) then
        return nil, 'Mission.addGroup not available'
    end
    local cat = group.category or 0
    local ok, result = pcall(Mission.addGroup, country, cat, group)
    if not ok then return nil, tostring(result) end
    return result
end

local function inject_static(static, country)
    local Mission = require('me_mission')
    if not (Mission and Mission.addStaticObject) then
        return nil, 'Mission.addStaticObject not available'
    end
    local ok, result = pcall(Mission.addStaticObject, country, static)
    if not ok then return nil, tostring(result) end
    return result
end

local function inject_zone(zone)
    local ok_req, ctrl = pcall(require, 'Mission.TriggerZoneController')
    if not (ok_req and ctrl and (ctrl.add or ctrl.addTriggerZone)) then
        return nil, 'TriggerZoneController.add not available'
    end
    local fn = ctrl.add or ctrl.addTriggerZone
    local ok, result = pcall(fn, zone)
    if not ok then return nil, tostring(result) end
    return result
end

local function inject_drawing(drawing)
    local ok_req, panel = pcall(require, 'me_draw_panel')
    if not (ok_req and panel and panel.add) then
        return nil, 'panel_draw.add not available'
    end
    local ok, result = pcall(panel.add, drawing)
    if not ok then return nil, tostring(result) end
    return result
end

local function remove_group(id)
    local Mission = require('me_mission')
    if Mission and Mission.removeGroup then return pcall(Mission.removeGroup, id) end
    return false, 'Mission.removeGroup not available'
end
local function remove_static(id)
    local Mission = require('me_mission')
    if Mission and Mission.removeStaticObject then return pcall(Mission.removeStaticObject, id) end
    return false, 'Mission.removeStaticObject not available'
end
local function remove_zone(id)
    local ok_req, ctrl = pcall(require, 'Mission.TriggerZoneController')
    if ok_req and ctrl and (ctrl.remove or ctrl.removeTriggerZone) then
        return pcall(ctrl.remove or ctrl.removeTriggerZone, id)
    end
    return false, 'TriggerZoneController.remove not available'
end
local function remove_drawing(id)
    local ok_req, panel = pcall(require, 'me_draw_panel')
    if ok_req and panel and panel.remove then return pcall(panel.remove, id) end
    return false, 'panel_draw.remove not available'
end

M._remove = {
    group   = remove_group,
    static  = remove_static,
    zone    = remove_zone,
    drawing = remove_drawing,
}

function M.place(prefab, opts)
    if type(prefab) ~= 'table' or type(prefab.meta) ~= 'table' then
        return nil, 'invalid prefab'
    end
    opts = opts or {}

    local anchor, rotation = M._resolve_anchor(prefab, opts)
    if not anchor then
        return nil, 'no anchor (and not keep_position)'
    end

    local record = {
        prefab_name = prefab.meta.name,
        groups = {}, statics = {}, zones = {}, drawings = {},
        errors = {},
    }

    local function injection_count()
        return #record.groups + #record.statics + #record.zones + #record.drawings
    end

    -- Groups
    for _, g_template in ipairs(prefab.groups or {}) do
        local g = deep_copy(g_template)
        transform_coords(g, anchor, rotation)
        transform_headings(g, rotation)
        local id, err = inject_group(g, g.country or 0)
        if id then
            record.groups[#record.groups + 1] = { orig_name = g_template.name, runtime_id = id }
        else
            record.errors[#record.errors + 1] = 'group ' .. tostring(g_template.name) .. ': ' .. tostring(err)
        end
    end

    -- Statics
    for _, s_template in ipairs(prefab.statics or {}) do
        local s = deep_copy(s_template)
        transform_coords(s, anchor, rotation)
        transform_headings(s, rotation)
        local id, err = inject_static(s, s.country or 0)
        if id then
            record.statics[#record.statics + 1] = { orig_name = s_template.name, runtime_id = id }
        else
            record.errors[#record.errors + 1] = 'static ' .. tostring(s_template.name) .. ': ' .. tostring(err)
        end
    end

    -- Zones
    for _, z_template in ipairs(prefab.zones or {}) do
        local z = deep_copy(z_template)
        transform_coords(z, anchor, rotation)
        local id, err = inject_zone(z)
        if id then
            record.zones[#record.zones + 1] = { orig_name = z_template.name, runtime_id = id }
        else
            record.errors[#record.errors + 1] = 'zone ' .. tostring(z_template.name) .. ': ' .. tostring(err)
        end
    end

    -- Drawings
    for _, d_template in ipairs(prefab.drawings or {}) do
        local d = deep_copy(d_template)
        transform_coords(d, anchor, rotation)
        local id, err = inject_drawing(d)
        if id then
            record.drawings[#record.drawings + 1] = { orig_name = d_template.name, runtime_id = id }
        else
            record.errors[#record.errors + 1] = 'drawing ' .. tostring(d_template.name) .. ': ' .. tostring(err)
        end
    end

    if injection_count() == 0 then
        return nil, 'no entities injected (' .. #record.errors .. ' errors — see log)'
    end
    return record
end
```

- [ ] **Step 5: Run the test, expect PASS**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_prefab_ops_place.lua
```

Expected: all PASS for the math + anchor-resolution helpers.

- [ ] **Step 6: Add the new test to the driver**

Modify `tools/me-mod/test/run-tests.ps1`'s `$tests` array to:

```pwsh
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua', 'test_prefab_ops_save.lua', 'test_prefab_ops_load.lua', 'test_prefab_ops_place.lua')
```

- [ ] **Step 7: Run full test suite**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
./run-tests.ps1
```

Expected: six test files pass.

- [ ] **Step 8: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/prefab_ops.lua tools/me-mod/test/test_prefab_ops_place.lua tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): prefab_ops place + ME-API injection

Place math (rotate + translate) is unit-tested. ME-API call wrappers
are pcall-guarded so missing symbols degrade to logged per-entity
failures rather than aborting the whole place. Returns an
injection_record consumed by undo.lua.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: `undo.lua` — single-slot undo

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/undo.lua`
- Create: `tools/me-mod/test/test_undo.lua`
- Modify: `tools/me-mod/test/run-tests.ps1` (add new test)

**Background:** Single-slot undo for the most recent place. Holds an `injection_record`; on `undo()` calls the matching ME remove API for each entry. Per-entity `pcall` so partial failures don't abort the rest.

The test stubs `prefab_ops._remove.{group,static,zone,drawing}` to capture which IDs would be removed.

- [ ] **Step 1: Write the failing test — `tools/me-mod/test/test_undo.lua`**

```lua
-- Standalone test for undo.lua. Stubs prefab_ops._remove to capture the
-- IDs that would be removed without actually calling DCS.
-- Run via: lua test_undo.lua  (cwd: tools/me-mod/test/)

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             dir = function() return function() return nil end end }
end
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

package.path = '../lua/dcs_sms_me/?.lua;' .. package.path

-- Stub out prefab_ops._remove BEFORE undo loads.
local removed = { group = {}, static = {}, zone = {}, drawing = {} }
local prefab_ops = require('prefab_ops')
prefab_ops._remove = {
    group   = function(id) removed.group[#removed.group + 1] = id; return true end,
    static  = function(id) removed.static[#removed.static + 1] = id; return true end,
    zone    = function(id) removed.zone[#removed.zone + 1] = id; return true end,
    drawing = function(id) removed.drawing[#removed.drawing + 1] = id; return true end,
}

local undo = require('undo')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- has_record() false initially.
check('has_record() initial false', undo.has_record() == false)

-- After record(), undo() removes everything in the record.
do
    undo.record({
        prefab_name = 'farp_alpha',
        groups   = { { orig_name='G1', runtime_id=101 }, { orig_name='G2', runtime_id=102 } },
        statics  = { { orig_name='S1', runtime_id=201 } },
        zones    = { { orig_name='Z1', runtime_id=301 } },
        drawings = {},
        errors = {},
    })
    check('has_record() after record', undo.has_record() == true)

    removed = { group = {}, static = {}, zone = {}, drawing = {} }
    prefab_ops._remove.group   = function(id) removed.group[#removed.group + 1] = id; return true end
    prefab_ops._remove.static  = function(id) removed.static[#removed.static + 1] = id; return true end
    prefab_ops._remove.zone    = function(id) removed.zone[#removed.zone + 1] = id; return true end
    prefab_ops._remove.drawing = function(id) removed.drawing[#removed.drawing + 1] = id; return true end

    local ok, err = undo.undo()
    check('undo returns ok', ok == true, 'got ' .. tostring(ok) .. ', err=' .. tostring(err))
    check('removed 2 groups',  #removed.group  == 2 and removed.group[1]  == 101 and removed.group[2]  == 102)
    check('removed 1 static',  #removed.static == 1 and removed.static[1] == 201)
    check('removed 1 zone',    #removed.zone   == 1 and removed.zone[1]   == 301)
    check('removed 0 drawings', #removed.drawing == 0)
    check('has_record() false after undo', undo.has_record() == false)
end

-- undo() on empty slot returns nil + 'nothing to undo'.
do
    local ok, err = undo.undo()
    check('undo on empty slot returns nil', ok == nil)
    check('undo on empty slot returns reason', type(err) == 'string' and err:find('nothing'))
end

-- record() replaces the slot (no stack).
do
    undo.record({ prefab_name='a', groups={ { orig_name='X', runtime_id=1 } }, statics={}, zones={}, drawings={}, errors={} })
    undo.record({ prefab_name='b', groups={ { orig_name='Y', runtime_id=2 } }, statics={}, zones={}, drawings={}, errors={} })

    removed = { group = {}, static = {}, zone = {}, drawing = {} }
    prefab_ops._remove.group = function(id) removed.group[#removed.group + 1] = id; return true end

    undo.undo()
    check('second record overwrites first', #removed.group == 1 and removed.group[1] == 2)
end

-- Per-entity remove failure: undo continues, slot still cleared.
do
    undo.record({
        prefab_name='c',
        groups   = { { orig_name='G1', runtime_id=11 }, { orig_name='G2', runtime_id=12 } },
        statics  = {}, zones = {}, drawings = {}, errors = {},
    })
    local calls = 0
    prefab_ops._remove.group = function(id)
        calls = calls + 1
        if calls == 1 then return false, 'simulated failure' end
        return true
    end
    local ok = undo.undo()
    check('undo with one per-entity failure still returns ok', ok == true)
    check('all entities attempted', calls == 2)
    check('slot cleared after partial-failure undo', undo.has_record() == false)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All undo tests passed.')
```

- [ ] **Step 2: Run the test, expect FAIL (module doesn't exist)**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_undo.lua
```

Expected: fails with `module 'undo' not found`.

- [ ] **Step 3: Create `tools/me-mod/lua/dcs_sms_me/undo.lua`**

```lua
-- undo.lua — single-slot undo for prefab place operations.
--
-- Holds the most recent injection_record from prefab_ops.place. On undo(),
-- walks the record's per-type arrays and calls prefab_ops._remove.<type>
-- for each entry (per-entity pcall — partial failures don't abort).
-- Slot is cleared after undo regardless of partial errors.
--
-- Public:
--   M.record(injection_record)      -- replaces the slot
--   M.undo()      → ok, err_string
--   M.has_record() → boolean
--   M.clear()

local prefab_ops = require('dcs_sms_me.prefab_ops')

local M = {}
local slot = nil

function M.record(injection_record)
    slot = injection_record
end

function M.has_record()
    return slot ~= nil
end

function M.clear()
    slot = nil
end

local function remove_each(arr, kind)
    if not arr then return 0 end
    local errors = 0
    local fn = prefab_ops._remove and prefab_ops._remove[kind]
    if not fn then return #arr end  -- nothing we can do; count all as errors
    for _, entry in ipairs(arr) do
        local ok = fn(entry.runtime_id)
        if not ok then errors = errors + 1 end
    end
    return errors
end

function M.undo()
    if slot == nil then return nil, 'nothing to undo' end
    local r = slot
    slot = nil  -- clear before doing work — slot consumed regardless of partial failures

    local errors = 0
    errors = errors + remove_each(r.groups,   'group')
    errors = errors + remove_each(r.statics,  'static')
    errors = errors + remove_each(r.zones,    'zone')
    errors = errors + remove_each(r.drawings, 'drawing')

    return true, errors > 0 and (errors .. ' partial failures') or nil
end

return M
```

- [ ] **Step 4: Run the test, expect PASS**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
lua test_undo.lua
```

Expected: all PASS.

- [ ] **Step 5: Add the new test to the driver**

Modify `tools/me-mod/test/run-tests.ps1`'s `$tests` array to:

```pwsh
    $tests = @('test_serializer.lua', 'test_serializer_parity.lua', 'test_distill_parity.lua', 'test_prefab_ops_save.lua', 'test_prefab_ops_load.lua', 'test_prefab_ops_place.lua', 'test_undo.lua')
```

- [ ] **Step 6: Run full test suite**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
./run-tests.ps1
```

Expected: seven test files pass.

- [ ] **Step 7: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/undo.lua tools/me-mod/test/test_undo.lua tools/me-mod/test/run-tests.ps1
git commit -m "feat(me-mod): undo.lua single-slot undo for place

Slot holds the most recent injection_record. undo() walks the per-type
arrays and calls prefab_ops._remove for each — per-entity pcall so a
single failed remove doesn't abort the rest. Slot cleared after undo
regardless of partial errors.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase C — UI

### Task 8: `menu.lua` — Tools menu integration

**Files:**
- Create: `tools/me-mod/lua/dcs_sms_me/menu.lua`

**Background:** Registers a "DCS-SMS Prefab Manager" entry in the ME's Tools menu. On click, calls `window.toggle()`.

**ME-API discovery:** before writing menu, find the Tools-menu API. Try in order:

1. `D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/MissionEditor.lua` — top-level patches go here; search for "Tools" or "menu" or "addItem".
2. `D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules/me_main_window.lua` (or similar) — likely owns the main menubar.
3. `D:/Program Files/Eagle Dynamics/DCS World/MissionEditor/modules/MainWindow/*.lua` — if there's a MainWindow submodule tree.

Look for symbols like `MainWindow.getToolsMenu`, `Menu.add`, `addToolsMenuItem`, or for the existing Tools menu handlers (Recordings, Mission Generator, Lua Console). Whatever pattern those use is the pattern we copy.

If no Tools-menu API turns out to be exposed cleanly, fall back to a small floating "Open Prefab Manager" toggle button at top-right of the screen.

- [ ] **Step 1: Investigate ME menu API**

```pwsh
$me = "D:/Program Files/Eagle Dynamics/DCS World/MissionEditor"
Select-String -Path "$me/MissionEditor.lua" -Pattern 'Tools|menu|addItem|getToolsMenu' | Select-Object -First 20
Get-ChildItem "$me/modules" -Filter "*main*" -File | ForEach-Object { Write-Host $_.FullName; Select-String -Path $_.FullName -Pattern 'Tools|getToolsMenu|Menu\.add' | Select-Object -First 10 }
Get-ChildItem "$me/modules" -Filter "*menu*" -Recurse -File | ForEach-Object { $_.FullName }
```

Take notes on the API you find. If you cannot find a Tools-menu API after this investigation, document that and proceed with the floating-button fallback (Step 2 below) only — do not attempt the menu path.

- [ ] **Step 2: Create `tools/me-mod/lua/dcs_sms_me/menu.lua`**

Replace the `<TBD>` placeholders with the symbols you found. If only the fallback is viable, set `MENU_AVAILABLE = false` in the implementation and the menu code path becomes a no-op.

```lua
-- menu.lua — Tools-menu entry registration with floating-button fallback.
--
-- Tries to register an entry in the ME's Tools menu first. If the menu API
-- isn't available, falls back to a tiny floating toggle button.
-- Either way, clicking the entry/button calls window.toggle().

local M = {}

local function get_window()
    return require('dcs_sms_me.window')
end

local function try_install_menu()
    -- IMPLEMENTATION NOTE: replace this body with the actual ME menu API
    -- discovered in Step 1. Common pattern:
    --   local MainWindow = require('me_main_window')
    --   if not MainWindow.getToolsMenu then return false end
    --   local menu = MainWindow.getToolsMenu()
    --   menu:addItem('DCS-SMS Prefab Manager', function() get_window().toggle() end)
    --   return true
    --
    -- If no such API exists, return false; floating-button fallback runs.
    local ok, MainWindow = pcall(require, 'me_main_window')
    if not (ok and MainWindow and MainWindow.getToolsMenu) then return false end
    local ok2, menu = pcall(MainWindow.getToolsMenu)
    if not ok2 or not menu then return false end
    local ok3 = pcall(function()
        if menu.addItem then
            menu:addItem('DCS-SMS Prefab Manager', function()
                pcall(function() get_window().toggle() end)
            end)
        elseif menu.add then
            menu:add('DCS-SMS Prefab Manager', function()
                pcall(function() get_window().toggle() end)
            end)
        else
            error('no addItem/add on tools menu')
        end
    end)
    return ok3
end

local function install_floating_fallback()
    local ok, err = pcall(function()
        local Window = require('Window')
        local Button = require('Button')
        local Skin   = require('Skin')
        local Gui    = require('dxgui')
        local screen_w, _ = Gui.GetWindowSize()
        local w, h = 200, 36
        local x = screen_w - w - 20
        local y = 8
        local fb = Window.new(x, y, w, h, '')
        fb:setSkin(Skin.windowSkin())
        fb:setVisible(true)
        fb:setDraggable(true)
        fb:setResizable(false)
        fb:setZOrder(195)
        local btn = Button.new()
        btn:setBounds(0, 0, w, h)
        btn:setText('Prefab Manager')
        btn:addChangeCallback(function() pcall(function() get_window().toggle() end) end)
        fb:insertWidget(btn)
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'menu fallback failed: ' .. tostring(err))
    end
end

function M.install()
    if try_install_menu() then
        log.write('sms.me', log.INFO, 'Tools menu entry installed')
        return true
    end
    log.write('sms.me', log.WARNING, 'Tools menu API unavailable; using floating-button fallback')
    install_floating_fallback()
    return false
end

return M
```

- [ ] **Step 3: Smoke-load the module (no DCS — should at least require without syntax errors)**

```pwsh
cd D:/git/dcs-sms
lua -e "package.path='tools/me-mod/lua/dcs_sms_me/?.lua;'..package.path; package.preload['Window']=function() return {new=function() return {setSkin=function() end, setVisible=function() end, setDraggable=function() end, setResizable=function() end, setZOrder=function() end, insertWidget=function() end} end} end; package.preload['Button']=function() return {new=function() return {setBounds=function() end, setText=function() end, addChangeCallback=function() end} end} end; package.preload['Skin']=function() return {windowSkin=function() return {} end} end; package.preload['dxgui']=function() return {GetWindowSize=function() return 1920,1080 end} end; package.preload['me_main_window']=function() return {} end; log = {write=function() end, ERROR=1, WARNING=2, INFO=3}; package.preload['dcs_sms_me.window']=function() return {toggle=function() end} end; local m = require('menu'); print(type(m.install))"
```

Expected: prints `function`. (The smoke test passes a stubbed-out `me_main_window` with no `getToolsMenu`, so `try_install_menu` returns false and the floating-button fallback runs against the stubbed dxgui types.)

- [ ] **Step 4: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/menu.lua
git commit -m "feat(me-mod): Tools-menu entry with floating-button fallback

Tries MainWindow.getToolsMenu first; falls back to a tiny floating
'Prefab Manager' toggle button if the menu API isn't exposed. Either
way, clicking it calls window.toggle().

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: `window.lua` rewrite — skeleton + idle layout

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua` (full rewrite)

**Background:** Replace the hello-world button with the Prefab Manager layout. This task lands the *skeleton* — all panels rendered, but only the Save and Reload buttons wired. Library list shows scan results. Place/Rename/Delete/Undo buttons exist but are no-ops in this task; later tasks wire them.

The window is constructed lazily (in `M.show()`). `M.toggle()` shows or hides. Internal state machine tracked but mostly unused until Task 12.

- [ ] **Step 1: Replace `tools/me-mod/lua/dcs_sms_me/window.lua` content in full**

```lua
-- window.lua — Prefab Manager.
--
-- Single window, all panels visible. Constructed lazily on first show().
-- All callbacks are pcall-guarded so dxgui or DCS-API failures degrade to
-- a status-label message rather than crashing the editor.
--
-- Public:
--   M.show()    — idempotent
--   M.hide()    — idempotent
--   M.toggle()  — show if hidden, hide if shown

local Window  = require('Window')
local Static  = require('Static')
local Button  = require('Button')
local TextBox = require('TextBox')   -- if not exposed, see fallback in M.show()
local ListBox = require('ListBox')
local Gui     = require('dxgui')
local Skin    = require('Skin')

local prefab_ops = require('dcs_sms_me.prefab_ops')
local undo       = require('dcs_sms_me.undo')

local M = {}

local W = {
    -- dxgui handles
    window     = nil,
    name_input = nil,
    save_btn   = nil,
    reload_btn = nil,
    list_box   = nil,
    list_label = nil,
    rotation_input = nil,
    place_click_btn   = nil,
    place_origin_btn  = nil,
    rename_btn = nil,
    delete_btn = nil,
    undo_btn   = nil,
    status     = nil,

    -- runtime state
    rows           = {},        -- last scan_dir result
    selected_idx   = nil,        -- index into rows of currently selected library row
    place_pending  = false,      -- in place-pending mode (Task 12)
    place_pending_name = nil,    -- name of prefab being placed
}

local function set_status(text)
    pcall(function()
        if W.status and W.status.setText then W.status:setText(tostring(text or '')) end
    end)
end
M._set_status = set_status  -- exposed for later tasks

local function refresh_list()
    W.rows = prefab_ops.scan_dir() or {}
    pcall(function()
        if W.list_label and W.list_label.setText then
            W.list_label:setText(string.format('Prefabs (%d)', #W.rows))
        end
    end)
    pcall(function()
        if W.list_box and W.list_box.removeItems then W.list_box:removeItems() end
        for _, r in ipairs(W.rows) do
            local label
            if r.error then
                label = string.format('%s    [ERROR: %s]', r.name, tostring(r.error):sub(1, 40))
            else
                label = string.format('%s    %s · %dg %ds %dz %dd',
                    r.name,
                    r.theatre or '?',
                    r.group_count or 0,
                    r.static_count or 0,
                    r.zone_count or 0,
                    r.drawing_count or 0)
            end
            if W.list_box and W.list_box.insertItem then
                W.list_box:insertItem(label)
            end
        end
    end)
end
M._refresh_list = refresh_list  -- exposed for later tasks

local function selected_row()
    if not W.selected_idx then return nil end
    return W.rows[W.selected_idx]
end
M._selected_row = selected_row

-- Save click handler (wired in this task).
local function on_save_click()
    pcall(function()
        local name = ''
        if W.name_input and W.name_input.getText then name = W.name_input:getText() or '' end
        if name == '' then
            set_status('Empty name — falling back to timestamped filename. See dcs.log.')
            name = 'prefab-' .. os.date('!%Y%m%dT%H%M%SZ')
            log.write('sms.me.prefab', log.WARNING, 'save with empty name → ' .. name)
        end
        if prefab_ops.exists(name) then
            -- Modal handling lands in Task 13. For now, log and refuse.
            set_status('Name "' .. name .. '" already exists. Pick a different name (Overwrite UI lands later).')
            log.write('sms.me.prefab', log.WARNING, 'save refused — collision: ' .. name)
            return
        end
        local ok, path_or_err = prefab_ops.save_selection(name)
        if ok then
            set_status('Saved ' .. name .. ' → ' .. tostring(path_or_err))
            log.write('sms.me.prefab', log.INFO, 'saved ' .. name)
            refresh_list()
        else
            set_status('Save failed: ' .. tostring(path_or_err))
            log.write('sms.me.prefab', log.ERROR, 'save failed: ' .. tostring(path_or_err))
        end
    end)
end

local function on_reload_click()
    pcall(function() refresh_list(); set_status('Library reloaded.') end)
end

-- List-row select callback.
local function on_list_select(_, idx)
    pcall(function()
        if type(idx) == 'number' then
            W.selected_idx = idx
        end
    end)
end

-- Stub click handlers for Task 9 — wired in later tasks.
local function on_place_click() set_status('Place at click — wired in Task 12') end
local function on_place_origin_click() set_status('Place at original — wired in Task 12') end
local function on_rename_click() set_status('Rename — wired in Task 13') end
local function on_delete_click() set_status('Delete — wired in Task 13') end
local function on_undo_click()
    pcall(function()
        if not undo.has_record() then set_status('Nothing to undo.'); return end
        local ok, err = undo.undo()
        if ok then
            set_status('Undid last place' .. (err and (' (' .. err .. ')') or ''))
        else
            set_status('Undo failed: ' .. tostring(err))
        end
    end)
end

function M.show()
    if W.window then
        pcall(function() W.window:setVisible(true) end)
        return
    end
    local ok, err = pcall(function()
        local screen_w, _ = Gui.GetWindowSize()
        local w, h = 420, 320
        local x = screen_w - w - 20
        local y = 80

        W.window = Window.new(x, y, w, h, 'dcs-sms — Prefab Manager')
        W.window:setSkin(Skin.windowSkin())
        W.window:setVisible(true)
        W.window:setDraggable(true)
        W.window:setResizable(false)
        W.window:setZOrder(190)

        -- Save panel (top): "Name: [______] [Save]"
        local section_label_save = Static.new()
        section_label_save:setBounds(10, 6, w - 20, 16)
        section_label_save:setText('Save current selection')
        W.window:insertWidget(section_label_save)

        local name_label = Static.new()
        name_label:setBounds(10, 26, 50, 22)
        name_label:setText('Name:')
        W.window:insertWidget(name_label)

        W.name_input = TextBox.new()
        W.name_input:setBounds(64, 26, w - 64 - 80 - 16, 22)
        if W.name_input.setText then W.name_input:setText('') end
        W.window:insertWidget(W.name_input)

        W.save_btn = Button.new()
        W.save_btn:setBounds(w - 90, 26, 80, 22)
        W.save_btn:setText('Save')
        W.save_btn:addChangeCallback(on_save_click)
        W.window:insertWidget(W.save_btn)

        -- Library section
        W.list_label = Static.new()
        W.list_label:setBounds(10, 60, w - 20 - 80, 16)
        W.list_label:setText('Prefabs (0)')
        W.window:insertWidget(W.list_label)

        W.reload_btn = Button.new()
        W.reload_btn:setBounds(w - 90, 56, 80, 22)
        W.reload_btn:setText('Reload')
        W.reload_btn:addChangeCallback(on_reload_click)
        W.window:insertWidget(W.reload_btn)

        W.list_box = ListBox.new()
        W.list_box:setBounds(10, 80, w - 20, 130)
        if W.list_box.addChangeCallback then
            W.list_box:addChangeCallback(on_list_select)
        end
        W.window:insertWidget(W.list_box)

        -- Action panel
        local rotation_label = Static.new()
        rotation_label:setBounds(10, 218, 60, 22)
        rotation_label:setText('Rotation:')
        W.window:insertWidget(rotation_label)

        W.rotation_input = TextBox.new()
        W.rotation_input:setBounds(70, 218, 50, 22)
        if W.rotation_input.setText then W.rotation_input:setText('0') end
        W.window:insertWidget(W.rotation_input)

        local rotation_unit = Static.new()
        rotation_unit:setBounds(122, 218, 20, 22)
        rotation_unit:setText('°')
        W.window:insertWidget(rotation_unit)

        local btn_y_1 = 244
        W.place_click_btn = Button.new()
        W.place_click_btn:setBounds(10, btn_y_1, 130, 22)
        W.place_click_btn:setText('Place at click')
        W.place_click_btn:addChangeCallback(on_place_click)
        W.window:insertWidget(W.place_click_btn)

        W.place_origin_btn = Button.new()
        W.place_origin_btn:setBounds(146, btn_y_1, 130, 22)
        W.place_origin_btn:setText('Place at original')
        W.place_origin_btn:addChangeCallback(on_place_origin_click)
        W.window:insertWidget(W.place_origin_btn)

        local btn_y_2 = 270
        W.rename_btn = Button.new()
        W.rename_btn:setBounds(10, btn_y_2, 80, 22)
        W.rename_btn:setText('Rename')
        W.rename_btn:addChangeCallback(on_rename_click)
        W.window:insertWidget(W.rename_btn)

        W.delete_btn = Button.new()
        W.delete_btn:setBounds(96, btn_y_2, 80, 22)
        W.delete_btn:setText('Delete')
        W.delete_btn:addChangeCallback(on_delete_click)
        W.window:insertWidget(W.delete_btn)

        W.undo_btn = Button.new()
        W.undo_btn:setBounds(182, btn_y_2, 130, 22)
        W.undo_btn:setText('Undo last place')
        W.undo_btn:addChangeCallback(on_undo_click)
        W.window:insertWidget(W.undo_btn)

        -- Status
        W.status = Static.new()
        W.status:setBounds(10, 296, w - 20, 16)
        W.status:setText('Ready.')
        W.window:insertWidget(W.status)

        refresh_list()
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'window construction failed: ' .. tostring(err))
        W.window = nil
        return
    end
    log.write('sms.me', log.INFO, 'Prefab Manager window opened')
end

function M.hide()
    pcall(function()
        if W.window and W.window.setVisible then W.window:setVisible(false) end
    end)
end

function M.toggle()
    if W.window then
        local visible = false
        pcall(function() if W.window.isVisible then visible = W.window:isVisible() end end)
        if visible then M.hide() else pcall(function() W.window:setVisible(true) end) end
    else
        M.show()
    end
end

return M
```

- [ ] **Step 2: Smoke-load it (no DCS — just confirms syntax + module wiring)**

```pwsh
cd D:/git/dcs-sms
$preload = @'
local stub = function() return setmetatable({}, {__index=function() return function() end end}) end
package.preload['lfs']=function() return {writedir=function() return '' end, mkdir=function() return true end, dir=function() return function() return nil end end} end
local function widget_factory()
    return setmetatable({new=function() return setmetatable({}, {__index=function() return function() end end}) end}, {__index=function() return function() end end})
end
package.preload['Window']  = widget_factory
package.preload['Static']  = widget_factory
package.preload['Button']  = widget_factory
package.preload['TextBox'] = widget_factory
package.preload['ListBox'] = widget_factory
package.preload['Skin']    = function() return {windowSkin=function() return {} end} end
package.preload['dxgui']   = function() return {GetWindowSize=function() return 1920,1080 end} end
log = { write=function() end, ERROR=1, WARNING=2, INFO=3 }
package.preload['dcs_sms_me.selection'] = function() return {snapshot=function() return {ok=true, groups={}, statics={}, zones={}, drawings={}} end} end
package.path = 'tools/me-mod/lua/dcs_sms_me/?.lua;' .. package.path
local w = require('window')
print(type(w.show), type(w.toggle), type(w.hide))
w.show()
w.hide()
w.toggle()
print('window smoke ok')
'@
$preload | lua -
```

Expected: prints `function function function` then `window smoke ok`.

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): rewrite window.lua as Prefab Manager skeleton

All panels rendered (Save / Library / Action / Status). Save and Reload
wired up. Place / Rename / Delete buttons land later. Lazy construction
on first show(); all callbacks pcall-guarded.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Wire library row → enable contextual buttons

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua` (extend list-row select handler)

**Background:** Selecting a row in the library should populate runtime state and enable/disable buttons that depend on having a selection. In Task 9 we tracked `W.selected_idx` but didn't gate the place/rename/delete buttons on it. This task adds the gating: those buttons no-op with a status message when nothing is selected.

This is a small task — mostly glue.

- [ ] **Step 1: Update the `on_list_select` and the four contextual button handlers in `tools/me-mod/lua/dcs_sms_me/window.lua`**

Replace the `on_list_select` function (and the four stub handlers below it) with the following block:

```lua
local function require_selection(action_label)
    local row = selected_row()
    if not row then
        set_status('Select a prefab in the list first (' .. action_label .. ').')
        return nil
    end
    if row.error then
        set_status('Cannot ' .. action_label .. ' — file has load error.')
        return nil
    end
    return row
end

local function on_list_select(_, idx)
    pcall(function()
        if type(idx) == 'number' then
            W.selected_idx = idx
            local row = selected_row()
            if row then
                set_status('Selected: ' .. tostring(row.name))
            end
        end
    end)
end

local function on_place_click()
    if not require_selection('place') then return end
    set_status('Place at click — wired in Task 12')
end

local function on_place_origin_click()
    if not require_selection('place at original') then return end
    set_status('Place at original — wired in Task 12')
end

local function on_rename_click()
    if not require_selection('rename') then return end
    set_status('Rename — wired in Task 13')
end

local function on_delete_click()
    if not require_selection('delete') then return end
    set_status('Delete — wired in Task 13')
end
```

- [ ] **Step 2: Re-run the smoke load to make sure nothing broke**

```pwsh
cd D:/git/dcs-sms
$preload = @'
local stub = function() return setmetatable({}, {__index=function() return function() end end}) end
package.preload['lfs']=function() return {writedir=function() return '' end, mkdir=function() return true end, dir=function() return function() return nil end end} end
local function widget_factory()
    return setmetatable({new=function() return setmetatable({}, {__index=function() return function() end end}) end}, {__index=function() return function() end end})
end
package.preload['Window']  = widget_factory
package.preload['Static']  = widget_factory
package.preload['Button']  = widget_factory
package.preload['TextBox'] = widget_factory
package.preload['ListBox'] = widget_factory
package.preload['Skin']    = function() return {windowSkin=function() return {} end} end
package.preload['dxgui']   = function() return {GetWindowSize=function() return 1920,1080 end} end
log = { write=function() end, ERROR=1, WARNING=2, INFO=3 }
package.preload['dcs_sms_me.selection'] = function() return {snapshot=function() return {ok=true, groups={}, statics={}, zones={}, drawings={}} end} end
package.path = 'tools/me-mod/lua/dcs_sms_me/?.lua;' .. package.path
local w = require('window')
w.show()
print('select-gating smoke ok')
'@
$preload | lua -
```

Expected: prints `select-gating smoke ok`.

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): gate Place/Rename/Delete on a library selection

Contextual buttons now no-op with a 'Select a prefab first' status when
nothing is selected. Rows with load errors block destructive actions
to avoid acting on a half-loaded prefab.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Save name-collision modal (Overwrite / Rename / Cancel)

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua` (replace `on_save_click` to pop a real modal)

**Background:** Today (after Task 9) save refuses on collision. This task replaces that with a modal: Overwrite saves anyway, Rename re-focuses the name input, Cancel does nothing.

Implementation: a small in-window overlay panel rather than a real OS-level modal. Same approach scales to rename + delete in Task 13. The overlay is its own `Window` widget centered on top of the main window with `setZOrder` higher than the main, so it eats clicks. Buttons inside dispatch the choice. We hide the overlay when done.

- [ ] **Step 1: Add the overlay helpers + replace `on_save_click` in `tools/me-mod/lua/dcs_sms_me/window.lua`**

Insert ABOVE `on_save_click` (the existing one), then replace `on_save_click` itself:

```lua
-- ---------------------------------------------------------------------------
-- Modal overlay helper. Shows a small centered window with a message and
-- up to 3 buttons. Each button calls the supplied callback then closes the
-- overlay. Buttons:
--   { {label='OK',  on_click=function() ... end}, ... }
-- ---------------------------------------------------------------------------

local function show_overlay(message, buttons)
    local screen_w, screen_h = Gui.GetWindowSize()
    local w, h = 420, 130
    local x = (screen_w - w) / 2
    local y = (screen_h - h) / 2

    local overlay = nil
    local function close()
        pcall(function() if overlay and overlay.setVisible then overlay:setVisible(false) end end)
    end

    local ok, err = pcall(function()
        overlay = Window.new(x, y, w, h, '')
        overlay:setSkin(Skin.windowSkin())
        overlay:setVisible(true)
        overlay:setDraggable(true)
        overlay:setResizable(false)
        overlay:setZOrder(220)

        local msg = Static.new()
        msg:setBounds(10, 10, w - 20, h - 60)
        msg:setText(tostring(message or ''))
        overlay:insertWidget(msg)

        local n = #buttons
        local bw = math.floor((w - 20 - (n - 1) * 10) / n)
        for i, b in ipairs(buttons) do
            local btn = Button.new()
            btn:setBounds(10 + (i - 1) * (bw + 10), h - 36, bw, 22)
            btn:setText(b.label or '?')
            btn:addChangeCallback(function()
                pcall(b.on_click or function() end)
                close()
            end)
            overlay:insertWidget(btn)
        end
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'overlay construction failed: ' .. tostring(err))
        -- Best-effort: just call the first (default) button to keep flow.
        if buttons[1] and buttons[1].on_click then pcall(buttons[1].on_click) end
    end
end
M._show_overlay = show_overlay  -- exposed for later tasks

local function focus_name_input()
    pcall(function()
        if W.name_input and W.name_input.setFocused then W.name_input:setFocused(true) end
    end)
end

local function do_save(name)
    local ok, path_or_err = prefab_ops.save_selection(name)
    if ok then
        set_status('Saved ' .. name .. ' → ' .. tostring(path_or_err))
        log.write('sms.me.prefab', log.INFO, 'saved ' .. name)
        refresh_list()
    else
        set_status('Save failed: ' .. tostring(path_or_err))
        log.write('sms.me.prefab', log.ERROR, 'save failed: ' .. tostring(path_or_err))
    end
end

local function on_save_click()
    pcall(function()
        local name = ''
        if W.name_input and W.name_input.getText then name = W.name_input:getText() or '' end
        if name == '' then
            set_status('Empty name — using timestamped fallback. See dcs.log.')
            name = 'prefab-' .. os.date('!%Y%m%dT%H%M%SZ')
            log.write('sms.me.prefab', log.WARNING, 'save with empty name → ' .. name)
            do_save(name)
            return
        end

        if prefab_ops.exists(name) then
            show_overlay(
                'Prefab "' .. name .. '" already exists.\n\nOverwrite, rename, or cancel?',
                {
                    { label = 'Overwrite', on_click = function() do_save(name) end },
                    { label = 'Rename',    on_click = function() focus_name_input(); set_status('Type a new name and click Save.') end },
                    { label = 'Cancel',    on_click = function() set_status('Save cancelled.') end },
                })
            return
        end

        do_save(name)
    end)
end
```

- [ ] **Step 2: Re-run the smoke load**

```pwsh
cd D:/git/dcs-sms
$preload = @'
local function widget_factory()
    return setmetatable({new=function() return setmetatable({}, {__index=function() return function() end end}) end}, {__index=function() return function() end end})
end
package.preload['lfs']=function() return {writedir=function() return '' end, mkdir=function() return true end, dir=function() return function() return nil end end} end
package.preload['Window']  = widget_factory
package.preload['Static']  = widget_factory
package.preload['Button']  = widget_factory
package.preload['TextBox'] = widget_factory
package.preload['ListBox'] = widget_factory
package.preload['Skin']    = function() return {windowSkin=function() return {} end} end
package.preload['dxgui']   = function() return {GetWindowSize=function() return 1920,1080 end} end
log = { write=function() end, ERROR=1, WARNING=2, INFO=3 }
package.preload['dcs_sms_me.selection'] = function() return {snapshot=function() return {ok=true, groups={}, statics={}, zones={}, drawings={}} end} end
package.path = 'tools/me-mod/lua/dcs_sms_me/?.lua;' .. package.path
local w = require('window')
w.show()
print('save modal smoke ok')
'@
$preload | lua -
```

Expected: prints `save modal smoke ok`.

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): name-collision modal for Save (Overwrite/Rename/Cancel)

Reusable overlay helper added — same pattern will host rename + delete
modals in Task 13. Empty save name still falls back to timestamped
filename (logged warning, not modal).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 12: Place at click + Place at original (place-pending state)

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua` (real handlers for `on_place_click` and `on_place_origin_click` + place-pending state)

**Background:** Place at original is straightforward — load prefab, call `prefab_ops.place(p, {keep_position=true, rotation=N})`, record undo. Place at click needs the place-pending state machine + map-click capture.

**ME-API discovery for map-click:** before writing the click handler, find the right hook.

- Try `MapWindow.addClickHandler` or similar. If it doesn't exist:
- Hook the dxgui input via a transparent overlay over the map area. Look for the symbol that returns the map's bounding rectangle (e.g., `MapWindow.getRect()`).
- Use the screen→world coord helper. Likely `MapWindow.screenToWorld(x, y)` or similar.

Take notes; if neither works cleanly, place-pending fails immediately with a clear error message and the user can fall back to "Place at original".

- [ ] **Step 1: Investigate map-click + screen→world API**

```pwsh
$me = "D:/Program Files/Eagle Dynamics/DCS World/MissionEditor"
Get-ChildItem "$me/modules" -Filter "*map*" -Recurse -File | ForEach-Object { $_.FullName }
Select-String -Path "$me/modules/me_map_window.lua" -Pattern 'addClickHandler|onClick|screenToWorld|getRect' | Select-Object -First 20
Select-String -Path "$me/modules/MapWindow.lua" -Pattern 'addClickHandler|onClick|screenToWorld|getRect' -ErrorAction SilentlyContinue | Select-Object -First 20
```

Document what you find. Pick the cleanest available approach.

- [ ] **Step 2: Replace `on_place_click` and `on_place_origin_click` in `tools/me-mod/lua/dcs_sms_me/window.lua`**

Also add the new place-pending state helpers above them. Replace the `<TBD>` map-click and screen→world calls with what you found in Step 1.

```lua
-- ---------------------------------------------------------------------------
-- Place-pending state machine
-- ---------------------------------------------------------------------------

local exit_place_pending  -- forward declaration; assigned below

local function enter_place_pending(prefab_name, prefab_table, rotation_deg)
    W.place_pending = true
    W.place_pending_name = prefab_name
    pcall(function()
        if W.window and W.window.setText then W.window:setText('Click on map to place ' .. prefab_name .. ' (Esc to cancel)') end
    end)
    pcall(function()
        if W.place_click_btn and W.place_click_btn.setText then W.place_click_btn:setText('Cancel') end
    end)
    set_status('Click on the map to place ' .. prefab_name .. '...')

    -- Map-click hook. Replace these <TBD> calls with whatever the ME exposes
    -- per Step 1 investigation. If neither hook nor overlay works, the
    -- handler logs and exits place-pending immediately so the user sees a
    -- clear failure rather than a stuck-pending state.
    local ok = pcall(function()
        local MapWindow = require('me_map_window')
        if MapWindow and MapWindow.addClickHandler then
            MapWindow.addClickHandler('dcs_sms_me', function(screen_x, screen_y)
                pcall(function()
                    if not W.place_pending then return end  -- ignore stale clicks
                    local wx, wy
                    if MapWindow.screenToWorld then
                        wx, wy = MapWindow.screenToWorld(screen_x, screen_y)
                    end
                    if not (wx and wy) then
                        set_status('Place failed: screen→world conversion unavailable')
                        log.write('sms.me.prefab', log.ERROR, 'place: screenToWorld returned nil')
                        exit_place_pending()
                        return
                    end
                    local rec, err = prefab_ops.place(prefab_table, { anchor = { x = wx, y = wy }, rotation = rotation_deg })
                    if rec then
                        undo.record(rec)
                        set_status(string.format('Placed %s (%dg %ds %dz %dd) at (%.0f, %.0f)',
                            prefab_name, #rec.groups, #rec.statics, #rec.zones, #rec.drawings, wx, wy))
                        log.write('sms.me.prefab', log.INFO, 'placed ' .. prefab_name)
                    else
                        set_status('Place failed: ' .. tostring(err))
                        log.write('sms.me.prefab', log.ERROR, 'place failed: ' .. tostring(err))
                    end
                    exit_place_pending()
                end)
            end)
            return
        end
        error('MapWindow.addClickHandler not available')
    end)
    if not ok then
        set_status('Place at click unavailable — try Place at original. See dcs.log.')
        log.write('sms.me.prefab', log.ERROR, 'map-click hook unavailable')
        exit_place_pending()
    end
end

exit_place_pending = function()
    W.place_pending = false
    W.place_pending_name = nil
    pcall(function()
        if W.window and W.window.setText then W.window:setText('dcs-sms — Prefab Manager') end
    end)
    pcall(function()
        if W.place_click_btn and W.place_click_btn.setText then W.place_click_btn:setText('Place at click') end
    end)
    pcall(function()
        local MapWindow = require('me_map_window')
        if MapWindow and MapWindow.removeClickHandler then
            MapWindow.removeClickHandler('dcs_sms_me')
        end
    end)
end

local function get_rotation_deg()
    local s = '0'
    pcall(function()
        if W.rotation_input and W.rotation_input.getText then s = W.rotation_input:getText() or '0' end
    end)
    local n = tonumber(s)
    if not n then return 0 end
    return n
end

local function on_place_click()
    if W.place_pending then
        -- Acting as Cancel.
        set_status('Place cancelled.')
        exit_place_pending()
        return
    end
    local row = require_selection('place')
    if not row then return end
    local prefab, lerr = prefab_ops.load(row.path)
    if not prefab then
        set_status('Load failed: ' .. tostring(lerr))
        log.write('sms.me.prefab', log.ERROR, 'load failed for ' .. row.path .. ': ' .. tostring(lerr))
        return
    end
    enter_place_pending(row.name, prefab, get_rotation_deg())
end

local function on_place_origin_click()
    local row = require_selection('place at original')
    if not row then return end
    local prefab, lerr = prefab_ops.load(row.path)
    if not prefab then
        set_status('Load failed: ' .. tostring(lerr))
        log.write('sms.me.prefab', log.ERROR, 'load failed for ' .. row.path .. ': ' .. tostring(lerr))
        return
    end
    local rotation_deg = get_rotation_deg()
    local rec, err = prefab_ops.place(prefab, { keep_position = true, rotation = rotation_deg })
    if rec then
        undo.record(rec)
        local wa = prefab.meta and prefab.meta.world_anchor or { x = 0, y = 0 }
        set_status(string.format('Placed %s at original (%dg %ds %dz %dd) at (%.0f, %.0f)',
            row.name, #rec.groups, #rec.statics, #rec.zones, #rec.drawings, wa.x, wa.y))
        log.write('sms.me.prefab', log.INFO, 'placed ' .. row.name .. ' at original')
    else
        set_status('Place failed: ' .. tostring(err))
        log.write('sms.me.prefab', log.ERROR, 'place at original failed: ' .. tostring(err))
    end
end
```

- [ ] **Step 3: Add Esc-key cancel**

Inside `M.show()`, AFTER the section that constructs `W.window`, AFTER `W.window:setZOrder(190)` line, add:

```lua
        -- Esc cancels place-pending if window has focus.
        if W.window.addKeyDownCallback then
            W.window:addKeyDownCallback(function(_, key)
                pcall(function()
                    if not W.place_pending then return end
                    -- Lua dxgui doesn't have a cross-version key constant we
                    -- can rely on; match by key name string OR by numeric
                    -- code 27 (ASCII Esc).
                    if key == 27 or key == 'KEY_ESCAPE' or key == 'Escape' then
                        set_status('Place cancelled.')
                        exit_place_pending()
                    end
                end)
            end)
        end
```

- [ ] **Step 4: Re-run the smoke load**

```pwsh
cd D:/git/dcs-sms
$preload = @'
local function widget_factory()
    return setmetatable({new=function() return setmetatable({}, {__index=function() return function() end end}) end}, {__index=function() return function() end end})
end
package.preload['lfs']=function() return {writedir=function() return '' end, mkdir=function() return true end, dir=function() return function() return nil end end} end
package.preload['Window']  = widget_factory
package.preload['Static']  = widget_factory
package.preload['Button']  = widget_factory
package.preload['TextBox'] = widget_factory
package.preload['ListBox'] = widget_factory
package.preload['Skin']    = function() return {windowSkin=function() return {} end} end
package.preload['dxgui']   = function() return {GetWindowSize=function() return 1920,1080 end} end
log = { write=function() end, ERROR=1, WARNING=2, INFO=3 }
package.preload['dcs_sms_me.selection'] = function() return {snapshot=function() return {ok=true, groups={}, statics={}, zones={}, drawings={}} end} end
package.preload['me_map_window']=function() return {addClickHandler=function() end, removeClickHandler=function() end, screenToWorld=function() return 0,0 end} end
package.path = 'tools/me-mod/lua/dcs_sms_me/?.lua;' .. package.path
local w = require('window')
w.show()
print('place handlers smoke ok')
'@
$preload | lua -
```

Expected: prints `place handlers smoke ok`.

- [ ] **Step 5: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): wire Place at click + Place at original

Place-pending state machine: title + button text update, map-click
hook installed (with Esc cancel), exits cleanly on click, Esc, or
Cancel. Place at original uses meta.world_anchor directly. Both flows
record an undo slot via undo.record on success.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 13: Rename + Delete modals

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua` (real `on_rename_click` + `on_delete_click`)

**Background:** Rename writes a new file with rewritten `meta.name` then deletes the old; delete is `os.remove` after a confirmation modal. Both refresh the list afterwards.

For rename input, build a small dedicated overlay (similar to `show_overlay` from Task 11) but with a TextBox in addition to the buttons. Lifted helper.

- [ ] **Step 1: Replace `on_rename_click` and `on_delete_click` in `tools/me-mod/lua/dcs_sms_me/window.lua`**

```lua
-- Show a rename overlay: prompt + text input + OK/Cancel.
-- on_ok receives the new name string; on_cancel takes no args.
local function show_rename_overlay(prompt, current_name, on_ok, on_cancel)
    local screen_w, screen_h = Gui.GetWindowSize()
    local w, h = 460, 150
    local x = (screen_w - w) / 2
    local y = (screen_h - h) / 2
    local overlay, input = nil, nil
    local function close()
        pcall(function() if overlay and overlay.setVisible then overlay:setVisible(false) end end)
    end
    local ok, err = pcall(function()
        overlay = Window.new(x, y, w, h, 'Rename')
        overlay:setSkin(Skin.windowSkin())
        overlay:setVisible(true)
        overlay:setDraggable(true)
        overlay:setResizable(false)
        overlay:setZOrder(220)

        local lbl = Static.new()
        lbl:setBounds(10, 10, w - 20, 20)
        lbl:setText(tostring(prompt or 'New name:'))
        overlay:insertWidget(lbl)

        input = TextBox.new()
        input:setBounds(10, 36, w - 20, 22)
        if input.setText then input:setText(tostring(current_name or '')) end
        if input.setFocused then input:setFocused(true) end
        overlay:insertWidget(input)

        local ok_btn = Button.new()
        ok_btn:setBounds(w - 200, h - 36, 90, 22)
        ok_btn:setText('OK')
        ok_btn:addChangeCallback(function()
            local new_name = (input.getText and input:getText()) or ''
            close()
            pcall(function() (on_ok or function() end)(new_name) end)
        end)
        overlay:insertWidget(ok_btn)

        local cancel_btn = Button.new()
        cancel_btn:setBounds(w - 100, h - 36, 90, 22)
        cancel_btn:setText('Cancel')
        cancel_btn:addChangeCallback(function()
            close()
            pcall(on_cancel or function() end)
        end)
        overlay:insertWidget(cancel_btn)
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'rename overlay failed: ' .. tostring(err))
        pcall(on_cancel or function() end)
    end
end

local function rename_file(old_path, old_name, new_name)
    local prefab, lerr = prefab_ops.load(old_path)
    if not prefab then return false, 'load failed: ' .. tostring(lerr) end
    prefab.meta = prefab.meta or {}
    prefab.meta.name = new_name

    local serializer = require('dcs_sms_me.serializer')
    local serialized = serializer.serialize(prefab)
    local paths = require('dcs_sms_me.paths')
    local new_path = paths.PREFABS_DIR .. new_name .. '.lua'
    if old_path == new_path then return true, old_path end  -- no-op rename
    if prefab_ops.exists(new_name) then return false, 'target name already exists' end

    local f, oerr = io.open(new_path, 'w')
    if not f then return false, 'open failed: ' .. tostring(oerr) end
    f:write(serialized)
    f:close()

    local rok = os.remove(old_path)
    if not rok then
        -- Roll back: delete the new file, keep old.
        os.remove(new_path)
        return false, 'could not delete old file (rolled back)'
    end
    return true, new_path
end

local function on_rename_click()
    local row = require_selection('rename')
    if not row then return end
    show_rename_overlay('Rename "' .. row.name .. '" to:', row.name,
        function(new_name)
            new_name = (new_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
            if new_name == '' then set_status('Rename cancelled (empty name).'); return end
            if new_name == row.name then set_status('Rename cancelled (same name).'); return end
            local ok, msg = rename_file(row.path, row.name, new_name)
            if ok then
                set_status('Renamed ' .. row.name .. ' → ' .. new_name)
                log.write('sms.me.prefab', log.INFO, 'renamed ' .. row.name .. ' → ' .. new_name)
                refresh_list()
            else
                set_status('Rename failed: ' .. tostring(msg))
                log.write('sms.me.prefab', log.ERROR, 'rename failed: ' .. tostring(msg))
            end
        end,
        function() set_status('Rename cancelled.') end)
end

local function on_delete_click()
    local row = require_selection('delete')
    if not row then return end
    show_overlay(
        'Delete "' .. row.name .. '"?\n\nThis cannot be undone.',
        {
            { label = 'Delete', on_click = function()
                local ok, oerr = os.remove(row.path)
                if ok then
                    set_status('Deleted ' .. row.name)
                    log.write('sms.me.prefab', log.INFO, 'deleted ' .. row.name)
                else
                    set_status('Delete failed: ' .. tostring(oerr))
                    log.write('sms.me.prefab', log.ERROR, 'delete failed for ' .. row.path .. ': ' .. tostring(oerr))
                end
                W.selected_idx = nil
                refresh_list()
            end },
            { label = 'Cancel', on_click = function() set_status('Delete cancelled.') end },
        })
end
```

- [ ] **Step 2: Re-run the smoke load**

```pwsh
cd D:/git/dcs-sms
$preload = @'
local function widget_factory()
    return setmetatable({new=function() return setmetatable({}, {__index=function() return function() end end}) end}, {__index=function() return function() end end})
end
package.preload['lfs']=function() return {writedir=function() return '' end, mkdir=function() return true end, dir=function() return function() return nil end end} end
package.preload['Window']  = widget_factory
package.preload['Static']  = widget_factory
package.preload['Button']  = widget_factory
package.preload['TextBox'] = widget_factory
package.preload['ListBox'] = widget_factory
package.preload['Skin']    = function() return {windowSkin=function() return {} end} end
package.preload['dxgui']   = function() return {GetWindowSize=function() return 1920,1080 end} end
log = { write=function() end, ERROR=1, WARNING=2, INFO=3 }
package.preload['dcs_sms_me.selection'] = function() return {snapshot=function() return {ok=true, groups={}, statics={}, zones={}, drawings={}} end} end
package.preload['me_map_window']=function() return {addClickHandler=function() end, removeClickHandler=function() end, screenToWorld=function() return 0,0 end} end
package.path = 'tools/me-mod/lua/dcs_sms_me/?.lua;' .. package.path
local w = require('window')
w.show()
print('rename/delete smoke ok')
'@
$preload | lua -
```

Expected: prints `rename/delete smoke ok`.

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): wire Rename + Delete with confirmation modals

Rename uses a small overlay with a TextBox; rewrites meta.name + moves
the file (with rollback on partial failure). Delete uses the existing
overlay helper with Delete/Cancel buttons. Both refresh the library
afterwards.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 14: Ctrl-Z keyboard hook for Undo

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/window.lua` (extend the keyboard hook in M.show)

**Background:** Task 9 wired the Undo button. This task adds the keyboard shortcut. Hook the same `addKeyDownCallback` we added in Task 12 for Esc, and route Ctrl-Z to `on_undo_click`. dxgui exposes a "modifier" arg on key callbacks in some versions — if not, we accept "Z key with Ctrl held" by checking a key-state helper if available, otherwise just accept "Z" alone (acceptable; the window must be focused for the hook to fire at all).

- [ ] **Step 1: Extend the existing key callback inside `M.show()` in `tools/me-mod/lua/dcs_sms_me/window.lua`**

Find the `addKeyDownCallback` block from Task 12. Replace it with:

```lua
        if W.window.addKeyDownCallback then
            W.window:addKeyDownCallback(function(_, key, modifiers)
                pcall(function()
                    -- Esc cancels place-pending.
                    if W.place_pending and (key == 27 or key == 'KEY_ESCAPE' or key == 'Escape') then
                        set_status('Place cancelled.')
                        exit_place_pending()
                        return
                    end

                    -- Ctrl-Z → undo. Modifier handling varies across dxgui
                    -- builds — accept either an explicit ctrl flag or just
                    -- the Z key (window must be focused for the hook to
                    -- fire, which is our scope guard).
                    local is_z = (key == 'Z' or key == 'z' or key == 90 or key == 'KEY_Z')
                    if is_z then
                        local ctrl = false
                        if type(modifiers) == 'table' then ctrl = modifiers.ctrl or modifiers.control end
                        if type(modifiers) == 'number' then ctrl = (modifiers % 8) >= 4 end  -- best-effort bitmask
                        if ctrl or modifiers == nil then
                            on_undo_click()
                        end
                    end
                end)
            end)
        end
```

- [ ] **Step 2: Re-run the smoke load**

```pwsh
cd D:/git/dcs-sms
$preload = @'
local function widget_factory()
    return setmetatable({new=function() return setmetatable({}, {__index=function() return function() end end}) end}, {__index=function() return function() end end})
end
package.preload['lfs']=function() return {writedir=function() return '' end, mkdir=function() return true end, dir=function() return function() return nil end end} end
package.preload['Window']  = widget_factory
package.preload['Static']  = widget_factory
package.preload['Button']  = widget_factory
package.preload['TextBox'] = widget_factory
package.preload['ListBox'] = widget_factory
package.preload['Skin']    = function() return {windowSkin=function() return {} end} end
package.preload['dxgui']   = function() return {GetWindowSize=function() return 1920,1080 end} end
log = { write=function() end, ERROR=1, WARNING=2, INFO=3 }
package.preload['dcs_sms_me.selection'] = function() return {snapshot=function() return {ok=true, groups={}, statics={}, zones={}, drawings={}} end} end
package.preload['me_map_window']=function() return {addClickHandler=function() end, removeClickHandler=function() end, screenToWorld=function() return 0,0 end} end
package.path = 'tools/me-mod/lua/dcs_sms_me/?.lua;' .. package.path
local w = require('window')
w.show()
print('Ctrl-Z hook smoke ok')
'@
$preload | lua -
```

Expected: prints `Ctrl-Z hook smoke ok`.

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/window.lua
git commit -m "feat(me-mod): Ctrl-Z keyboard shortcut for Undo last place

Hooks dxgui's addKeyDownCallback when the Prefab Manager window is
focused. Modifier detection is best-effort across dxgui builds — falls
back to Z-alone when modifiers are nil (window-focus is the scope guard
anyway).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase D — Wiring

### Task 15: `init.lua` — switch from auto-show to menu install

**Files:**
- Modify: `tools/me-mod/lua/dcs_sms_me/init.lua`

- [ ] **Step 1: Replace `tools/me-mod/lua/dcs_sms_me/init.lua` content**

```lua
-- init.lua — loaded by the require() line patched into MissionEditor.lua.
--
-- Sub-project 3: registers a Tools-menu entry (with floating-button
-- fallback) instead of auto-showing the Prefab Manager window. The
-- window is constructed lazily on first toggle.
--
-- Outer pcall is the last-line defense: even if our require chain
-- breaks, the ME continues loading normally.

local ok, err = pcall(function()
    local menu = require('dcs_sms_me.menu')
    menu.install()
end)
if not ok then
    log.write('sms.me', log.ERROR, 'init failed: ' .. tostring(err))
end
```

- [ ] **Step 2: Verify the test suite still passes**

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
./run-tests.ps1
```

Expected: seven test files all pass (none touch init.lua, but this confirms nothing in the chain regressed).

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/lua/dcs_sms_me/init.lua
git commit -m "feat(me-mod): replace auto-show with Tools-menu install

init.lua now calls menu.install() instead of constructing the
hello-world window eagerly. The Prefab Manager window appears on the
first menu-entry click (or floating-button click if menu API is
unavailable).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase E — Docs

### Task 16: Update `tools/me-mod/README.md` smoke checklist

**Files:**
- Modify: `tools/me-mod/README.md`

- [ ] **Step 1: Read the current README**

```pwsh
cat D:/git/dcs-sms/tools/me-mod/README.md
```

Note the existing structure — install/uninstall instructions stay; only the manual smoke checklist (the part that exercises hello-world's "Print selection" button) gets replaced with the Sub-project 3 checklist.

- [ ] **Step 2: Replace the manual smoke section in `tools/me-mod/README.md`**

Find the section header that introduces the smoke checklist (likely `## Manual smoke checklist` or `## Smoke testing` — read the existing content). Replace that section's body (everything between that heading and the next `##` heading or end of file) with:

```markdown
## Manual smoke checklist (Sub-project 3 — Prefab Manager)

CI runs the parity + unit tests under `tools/me-mod/test/run-tests.ps1`. This checklist is the release gate; run by hand against a fresh DCS install before merging significant changes to the mod.

### Setup

1. Run `tools/dcs-sms.exe install-me-mod`. Open the ME. Verify the Tools menu has a "DCS-SMS Prefab Manager" entry. Verify the window does NOT appear automatically.
   - If the floating-button fallback fires instead (visible in `dcs.log` as `Tools menu API unavailable; using floating-button fallback`), that's expected on builds where the menu API isn't exposed — verify the floating button appears at top-right and clicking it opens the Manager.
2. Open Tools → "DCS-SMS Prefab Manager". Window appears with all panels (Save / Library / Action / Status).

### Save flow

3. Place one A-10C in the ME. Select it. Type `test_jet` in the name field. Click **Save**. Verify file at `Saved Games\DCS\dcs-sms\prefabs\test_jet.lua` and the library refreshes to show it.
4. With nothing selected, click **Save** with name `empty`. Status: `No selection — nothing to save`. No file written.
5. With selection, click **Save** with name `test_jet` (collision). Modal appears with **Overwrite / Rename / Cancel**. Pick Cancel — no change. Pick Overwrite — file overwritten.
6. Multi-selection: select two groups + one trigger zone + one drawing. Save as `complex_test`. Open the saved file and verify all four sections are populated.

### Place flow — at click

7. Library shows `test_jet` sorted A-Z. Select it, set rotation 0, click **Place at click**. Verify the title bar text changes to `Click on map to place test_jet (Esc to cancel)` and the button text becomes `Cancel`.
8. Click somewhere on the map. Verify the A-10C appears at that location, status confirms placement, **Ctrl-Z** removes it (group disappears from the ME).
9. Re-place `test_jet`. Save the `.miz`, close the ME, reopen the `.miz`. Verify the placed group survived (no dcs-sms-specific state needed at runtime).
10. Place at click with rotation 90. Verify the group is rotated 90° from how it was saved.
11. Place at click then press **Esc**. Verify exit from place-pending, no entity injected.

### Place flow — at original

12. Save a prefab that includes a group near a specific map building. Click **Place at original**. Verify it lands at the original `meta.world_anchor`, not at any clicked location.

### Best-effort partial-failure

13. Manually corrupt a prefab file to have one valid group + one group with a bogus DCS type. Place it. Verify status: `Placed N of M entities — see dcs.log`. The valid group is in the mission; the corrupt one is logged.

### Library

14. Save 3 prefabs with names `a`, `m`, `z`. Verify list is sorted A-Z.
15. Rename `m` to `middle`. Verify the file is renamed AND `meta.name` is updated inside (open the file).
16. Delete `middle`. Confirmation modal. Confirm. Verify file gone, list refreshed.
17. Manually drop a malformed `.lua` file into the prefabs dir. Click **Reload**. Verify it appears in the list with `[ERROR: ...]` rather than breaking the list.

### Undo

18. Place a prefab. Press **Ctrl-Z** (window focused). Verify removal.
19. Press **Ctrl-Z** again. Status: `Nothing to undo.`
20. Place. Click somewhere outside the Prefab Manager window to remove its focus. Press **Ctrl-Z**. Verify nothing happens (window not focused — broad ME-wide undo is [issue #25](https://github.com/nielsvaes/dcs-sms/issues/25)).

### Cleanup

21. Run `tools/dcs-sms.exe uninstall-me-mod`. Verify everything removed (modules dir gone, `MissionEditor.lua` patch reverted from backup).
```

- [ ] **Step 3: Commit**

```pwsh
cd D:/git/dcs-sms
git add tools/me-mod/README.md
git commit -m "docs(me-mod): smoke checklist for Prefab Manager

Replaces hello-world Print Selection checklist with the full Save / Place
/ Library / Undo flow. Setup + cleanup steps unchanged from sub-project
2; everything between is new.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Final verification

After Task 16, run the full test suite once more from a clean state:

```pwsh
cd D:/git/dcs-sms/tools/me-mod/test
./run-tests.ps1
cd D:/git/dcs-sms/framework/test
./run_distill_tests.ps1
```

Expected: all me-mod tests pass; all framework tests pass.

```pwsh
cd D:/git/dcs-sms
git log --oneline main..HEAD
```

Expected: ~16 commits on `feat/me-prefab-manager`, in roughly the task order above (one commit per task; some tasks have multiple sub-commits if the implementer chose to commit between TDD steps — that's fine).

The implementation is now ready for the user's manual test pass. Surface to the user with a hand-off summary; do NOT merge or open a PR.
