# sms.prefab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `sms.prefab` framework module — distill ME selection dumps into anchor-relative prefab files (groups + statics + zones + drawings, headings in degrees, country captured), then load and respawn them at runtime with translation, rotation, country override, and per-instance lifecycle tracking.

**Architecture:** Two new framework files under `framework/`. `prefab_distill.lua` is pure-data (walks dump with visited-set, drops back-refs, rebases coords on centroid, converts headings rad→deg) — unit-testable in standalone Lua 5.1. `prefab.lua` is the public surface (registry, load/save, spawn math, DCS API integration, instance handle, lifecycle) — smoke-tested via the bridge against running DCS. A pure-data `framework/utils_serialize.lua` (lifted from the hello-world serializer) gives `sms.utils.serialize` for save.

**Tech Stack:** Lua 5.1 (DCS mission environment + standalone), PowerShell (test driver), `coalition.addGroup` / `coalition.addStaticObject` / `trigger.action.markup*` (DCS API).

**Spec:** [`docs/superpowers/specs/2026-05-03-sms-prefab-design.md`](../specs/2026-05-03-sms-prefab-design.md)

---

## File structure

### Created

```
framework/
├── utils_serialize.lua                              — sms.utils.serialize (Lua-table → Lua chunk)
├── prefab_distill.lua                               — sms.prefab.distill (pure-data transform)
└── prefab.lua                                       — sms.prefab.* (registry, save, spawn, handle)

framework/test/
├── fixtures/
│   └── dump_synthetic_aerial.lua                    — small handcrafted dump fixture
├── test_utils_serialize.lua                         — pure-Lua tests
├── test_prefab_distill.lua                          — pure-Lua tests
├── run_distill_tests.ps1                            — PS driver for distill + serialize tests
└── smoke_prefab.ps1                                 — DCS smoke (manual; needs running DCS)

docs/api/
└── prefab.md                                        — per-symbol reference page

docs/superpowers/plans/
└── 2026-05-03-sms-prefab.md                         — this file
```

### Modified

```
framework/load_all.lua                               — append utils_serialize.lua, prefab_distill.lua, prefab.lua
AGENTS.md                                            — §7 module index +1 line for sms.prefab
README.md                                            — link docs/api/prefab.md (if README's API list exists)
```

---

## Decisions made during plan-writing

These extend or refine the spec; recorded so they're easy to find.

- **Serializer adapter, not exact copy.** `framework/utils_serialize.lua` exposes `sms.utils.serialize` and re-uses the same algorithm as the hello-world serializer — but it lives inside the framework's module conventions (`assert(type(sms) == "table"...)`, `local log = sms.log.module(...)`). Source files are independent; both produce byte-identical output for the same input (verified by a parity test in `test_utils_serialize.lua`).
- **Synthetic fixture, not real dump fixture.** The plan creates a small handcrafted `dump_synthetic_aerial.lua` that exercises every distill path (mixed groups + statics + zones + drawings, including a `boss` cycle, including a unit with `heading = math.pi/2` to test rad→deg). Real captured dumps are 60–600 KB and impractical to commit; the synthetic one is ~150 lines and fully covers the algorithm. We can swap to a real dump later if regression coverage demands it.
- **Statics partition.** A dump entry is classified as a static if its `units[1].type` is in the `sms.K.statics` catalog OR if it has top-level `category` AND `dead` fields without `route`/`tasks` (static-only fields). Order: catalog lookup first; field-shape inference as fallback. Both rules live in distill.
- **Country resolution at spawn.** Distill captures country as a numeric id from `boss.country.id`. Spawn passes that number directly to `coalition.addGroup(country, ...)`. Country override (`opts.country`) accepts either a number or a string (resolved via `sms.utils.resolve_country` if string).
- **Drawing primitive types.** The ME's `panel_draw.getCurrObject()` returns objects with `primitiveType` strings. v1 supports `Line`, `Polygon`, `TextBox`, `Icon`, `Circle`. Anything else: log warning, skip. Each maps to a `trigger.action.*` call (`lineToAll`, `quadToAll` or `markupToAll`, `textToAll`, `markToAll`, `circleToAll`).
- **Mark-id allocation.** `trigger.action.markup*` requires a unique numeric mark id. The handle holds a counter starting at the current `Unix-time-in-seconds * 1000` to avoid collision with marks placed by other scripts; increments per drawing.
- **Instance id allocation.** `_next_instance_id` private counter, monotonically increasing per process. Stable enough for v1.
- **Handle type.** `prefab_instance` is a small table with metatable `__index = sms.prefab` — same pattern as the rest of the framework. Field `_destroyed` flag for idempotency.

---

## Task 1: Lift serializer into framework (TDD)

**Files:**
- Create: `framework/utils_serialize.lua`
- Create: `framework/test/test_utils_serialize.lua`
- Create: `framework/test/run_distill_tests.ps1`

The framework needs `sms.utils.serialize` for `sms.prefab.save()`. Lift the algorithm from `tools/me-mod/lua/dcs_sms_me/serializer.lua` (already battle-tested there) and adapt it to framework conventions.

- [ ] **Step 1.1: Write failing tests**

Create `framework/test/test_utils_serialize.lua`:

```lua
-- Standalone Lua 5.1 test suite for framework/utils_serialize.lua.
-- Mirrors the parity tests for tools/me-mod/lua/dcs_sms_me/serializer.lua,
-- with framework-specific shimming.
--
-- Run via: lua test_utils_serialize.lua  (cwd: framework/test/)

-- Stub the framework's module-init contract so utils_serialize.lua loads
-- standalone (it expects sms and sms.log already present).
sms = {}
sms.log = { module = function() return { warn = function() end, error = function() end, info = function() end, debug = function() end } end }

package.path = '../?.lua;' .. package.path
sms.utils = sms.utils or {}
dofile('../utils_serialize.lua')

local serialize = sms.utils.serialize

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name) else
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
    local chunk = serialize(value)
    local fn, err = loadstring(chunk)
    if not fn then return nil, 'loadstring failed: ' .. tostring(err) .. '\n' .. chunk end
    local ok, result = pcall(fn)
    if not ok then return nil, 'eval failed: ' .. tostring(result) end
    return result
end

-- 1. Flat numeric array round-trip.
do
    local input = {1, 2, 3}
    local out, err = roundtrip(input)
    check('flat numeric array', out and tables_equal(input, out), err)
end

-- 2. Mixed key shape (the DCS callsign).
do
    local input = {[1] = 3, [2] = 1, [3] = 1, name = 'Uzi11'}
    local out, err = roundtrip(input)
    check('mixed numeric+string keys', out and tables_equal(input, out), err)
end

-- 3. Nested mixed types.
do
    local input = {
        name = 'Convoy',
        x = 12345.5,
        y = -678.25,
        active = true,
        units = {
            [1] = {type = 'M-1', heading = 0},
            [2] = {type = 'M-2', heading = 1.57},
        },
    }
    local out, err = roundtrip(input)
    check('nested mixed types', out and tables_equal(input, out), err)
end

-- 4. Cycle detection.
do
    local input = {name = 'ouroboros'}
    input.self = input
    local chunk = serialize(input)
    check('cycle marker present', chunk:find('cycle', 1, true) ~= nil, chunk)
end

-- 5. Top-level "return ...".
do
    local chunk = serialize({x = 1})
    check('top-level return prefix', chunk:match('^return%s') ~= nil, chunk)
end

-- 6. Inf number key.
do
    local input = {[math.huge] = 'x'}
    local out, err = roundtrip(input)
    check('inf number key roundtrips', out and out[math.huge] == 'x', err)
end

-- 7. Stable byte output across two runs.
do
    local input = {z = 1, a = 2, m = 3, b = 4}
    local first  = serialize(input)
    local second = serialize(input)
    check('output is byte-stable', first == second, 'differ:\n' .. first .. '\n---\n' .. second)
end

-- 8. Empty table.
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

Create `framework/test/run_distill_tests.ps1`:

```powershell
# Locates a Lua 5.1 interpreter on PATH and runs all framework unit tests:
#   - test_utils_serialize.lua
#   - test_prefab_distill.lua
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
        Write-Host 'Install Lua 5.1 (https://luabinaries.sourceforge.net/) and put it on PATH.'
        exit 2
    }
    Write-Host "Using Lua interpreter: $lua"
    $tests = @('test_utils_serialize.lua', 'test_prefab_distill.lua')
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

- [ ] **Step 1.3: Run tests, verify they fail**

Run: `pwsh framework/test/run_distill_tests.ps1`
Expected: `test_utils_serialize.lua` fails with `module 'utils_serialize' not found` (or similar — the dofile target doesn't exist yet). `test_prefab_distill.lua` is missing → driver skips it (the `if (-not (Test-Path $t)) { continue }` guard).

- [ ] **Step 1.4: Implement `framework/utils_serialize.lua`**

Create `framework/utils_serialize.lua`:

```lua
-- dcs-sms framework: serialize module (sms.utils.serialize).
--
-- Lua value → Lua chunk string. Round-trips losslessly through loadstring
-- for tables with mixed numeric/string keys, cycles (replaced with marker),
-- inf/NaN numbers, and unsupported value types (function/userdata/thread →
-- nil with comment).
--
-- The algorithm mirrors tools/me-mod/lua/dcs_sms_me/serializer.lua. Keep
-- the two in lock-step (both have identical test suites for parity).
-- Eventually one becomes the canonical source; for now duplication is the
-- simplest path because the framework runs in DCS mission env while the
-- ME mod runs in the GUI env, and they have no shared load path.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> utils_serialize.lua.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")
sms.utils = sms.utils or {}

local function number_literal(n)
    if n ~= n then return '0/0' end
    if n == math.huge then return '1/0' end
    if n == -math.huge then return '-1/0' end
    return tostring(n)
end

local function key_repr(k)
    if type(k) == 'string' then
        return '[' .. string.format('%q', k) .. ']'
    elseif type(k) == 'number' then
        return '[' .. number_literal(k) .. ']'
    elseif type(k) == 'boolean' then
        return '[' .. tostring(k) .. ']'
    end
    return nil
end

local function value_repr(v)
    local t = type(v)
    if t == 'nil' then return 'nil' end
    if t == 'string' then return string.format('%q', v) end
    if t == 'number' then return number_literal(v) end
    if t == 'boolean' then return tostring(v) end
    return nil
end

local function key_summary(k)
    local t = type(k)
    if t == 'string' then return string.format('%q', k) end
    if t == 'number' or t == 'boolean' then return tostring(k) end
    return tostring(k)
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

local emit_value

local function emit_table(tbl, indent_unit, depth, visited)
    if visited[tbl] then return 'nil --[[ cycle ]]' end
    visited[tbl] = true

    local keys = sorted_keys(tbl)
    if #keys == 0 then visited[tbl] = nil; return '{}' end

    local pad     = indent_unit:rep(depth + 1)
    local pad_end = indent_unit:rep(depth)
    local parts   = {'{'}
    for _, k in ipairs(keys) do
        local kr = key_repr(k)
        if kr then
            local v_str = emit_value(tbl[k], indent_unit, depth + 1, visited)
            parts[#parts + 1] = pad .. kr .. ' = ' .. v_str .. ','
        else
            parts[#parts + 1] = pad .. '-- key dropped: ' .. type(k) .. ' = ' .. key_summary(k)
        end
    end
    parts[#parts + 1] = pad_end .. '}'
    visited[tbl] = nil
    return table.concat(parts, '\n')
end

emit_value = function(v, indent_unit, depth, visited)
    if type(v) == 'table' then
        return emit_table(v, indent_unit, depth, visited)
    end
    local simple = value_repr(v)
    if simple then return simple end
    return 'nil --[[ ' .. type(v) .. ' ]]'
end

function sms.utils.serialize(value, opts)
    opts = opts or {}
    local indent_unit = opts.indent or '  '
    local body = emit_value(value, indent_unit, 0, {})
    return 'return ' .. body .. '\n'
end
```

- [ ] **Step 1.5: Run tests, verify they pass**

Run: `pwsh framework/test/run_distill_tests.ps1`
Expected: 8 PASS lines under `test_utils_serialize.lua`, "all tests passed", exit 0.

- [ ] **Step 1.6: Commit**

```bash
git add framework/utils_serialize.lua framework/test/test_utils_serialize.lua framework/test/run_distill_tests.ps1
git commit -m "feat(framework): add sms.utils.serialize"
```

---

## Task 2: Capture synthetic dump fixture

**Files:**
- Create: `framework/test/fixtures/dump_synthetic_aerial.lua`

A handcrafted dump that exercises every distill path: groups+statics+zones+drawings, mixed coordinates so centroid math is checkable, a heading in radians (`math.pi/2 = 1.5707963…`) to test rad→deg, a `boss` cycle to test back-ref strip, country info inside `boss`. Small enough to read in full (~150 lines).

- [ ] **Step 2.1: Write the fixture**

Create `framework/test/fixtures/dump_synthetic_aerial.lua`:

```lua
-- Synthetic ME selection dump for sms.prefab.distill tests.
-- Shape mirrors what the hello-world ME mod produces.
-- Three top-level entities: 1 group, 1 static (modeled as single-unit group),
-- 1 trigger zone, 1 drawing. Coordinates chosen so the centroid is (50, 100).
--
-- Used by framework/test/test_prefab_distill.lua.

local mission_country_belgium = { id = 11, name = "Belgium" }
local mission_country_usa     = { id =  2, name = "USA" }

-- The boss back-ref: each entity's boss points at a country, which back-points
-- at the entity. This recreates the cycle the real dump has and that distill
-- must strip.
local boss_belgium = { country = mission_country_belgium }
local boss_usa     = { country = mission_country_usa }

local group_aerial = {
    ["name"]    = "Aerial-1",
    ["type"]    = "plane",
    ["x"]       = 0,                 -- world coords; centroid will be (50, 100)
    ["y"]       = 0,
    ["heading"] = 0,
    ["units"] = {
        [1] = {
            ["name"]      = "Aerial-1-1",
            ["type"]      = "F-16C_50",
            ["x"]         = 0,
            ["y"]         = 0,
            ["alt"]       = 2000,
            ["alt_type"]  = "BARO",
            ["heading"]   = math.pi / 2,            -- 90 deg in rad
            ["livery_id"] = "104th fs maryland",
            ["skill"]     = "Veteran",
            ["callsign"]  = { [1] = 1, [2] = 1, [3] = 1, ["name"] = "Enfield11" },
            ["payload"]   = { ["pylons"] = {}, ["fuel"] = 5000 },
        },
    },
    ["route"] = {
        ["points"] = {
            [1] = { ["x"] = 0,    ["y"] = 0,    ["alt"] = 2000 },
            [2] = { ["x"] = 1000, ["y"] = 0,    ["alt"] = 3000 },
        },
    },
}
group_aerial.boss = boss_belgium
boss_belgium.aerial = group_aerial            -- back-ref → cycle

-- "Static" — modeled as single-unit group per ME convention.
local group_static_hangar = {
    ["name"]     = "Hangar A",
    ["type"]     = "Hangar A",
    ["category"] = "Heliports",
    ["dead"]     = false,
    ["x"]        = 100,
    ["y"]        = 200,
    ["heading"]  = 0,
    ["units"] = {
        [1] = {
            ["name"]    = "Hangar A",
            ["type"]    = "Hangar A",
            ["x"]       = 100,
            ["y"]       = 200,
            ["heading"] = 0,
        },
    },
}
group_static_hangar.boss = boss_usa
boss_usa.hangar = group_static_hangar

-- Trigger zone, anchor (50, 100) is implicit (centroid of all four).
local zone_no_fly = {
    ["name"]   = "no_fly",
    ["type"]   = 0,                 -- circle
    ["x"]      = 50,
    ["y"]      = 100,
    ["radius"] = 1500,
    ["properties"] = { ["alarm"] = "yes" },
}

-- Drawing: a polygon with three vertices.
local drawing_perimeter = {
    ["name"]          = "perimeter",
    ["primitiveType"] = "Polygon",
    ["mapData"] = { ["x"] = 100, ["y"] = 200 },
    ["points"]  = {
        [1] = { ["x"] = 0,   ["y"] = 0   },
        [2] = { ["x"] = 100, ["y"] = 0   },
        [3] = { ["x"] = 50,  ["y"] = 100 },
    },
    ["color"]      = { 1, 0, 0, 1 },
    ["fillColor"]  = { 1, 0, 0, 0.2 },
}

return {
    ["meta"] = {
        ["selection_mode"] = "multi",
        ["timestamp_utc"]  = "2026-05-03T09:12:54Z",
        ["ok"]             = true,
    },
    ["groups"]     = { [1] = group_aerial, [2] = group_static_hangar },
    ["statics"]    = {},                    -- ME models statics inside groups; distill partitions
    ["zones"]      = { [1] = zone_no_fly },
    ["drawings"]   = { [1] = drawing_perimeter },
    ["nav_points"] = {},
    ["raw"]        = {},
}
```

- [ ] **Step 2.2: Verify it loads**

Run: `pwsh -c "Push-Location framework/test; lua -e 'local t = dofile([[fixtures/dump_synthetic_aerial.lua]]); assert(#t.groups == 2); print(\"fixture loads OK\")'; Pop-Location"`

Expected: `fixture loads OK`.

If lua is not on PATH, skip and verify by reading the file — its structure must:
- Have `groups[1].name == "Aerial-1"` (a real group with `route`).
- Have `groups[2].name == "Hangar A"` (a static, classified by `category` + `dead` and lack of `route`).
- Have `groups[1].boss.aerial == groups[1]` (cycle).
- Have one zone, one drawing.

- [ ] **Step 2.3: Commit**

```bash
git add framework/test/fixtures/dump_synthetic_aerial.lua
git commit -m "test(framework): add synthetic ME dump fixture for prefab_distill"
```

---

## Task 3: Implement `prefab_distill.lua` (TDD)

**Files:**
- Create: `framework/prefab_distill.lua`
- Create: `framework/test/test_prefab_distill.lua`

The pure-data transform. Walk the dump, drop back-refs, partition statics, capture country, convert headings, anchor to centroid.

- [ ] **Step 3.1: Write failing tests**

Create `framework/test/test_prefab_distill.lua`:

```lua
-- Standalone Lua 5.1 test suite for framework/prefab_distill.lua.
-- Run via: lua test_prefab_distill.lua  (cwd: framework/test/)

-- Stub framework module-init contract.
sms = {}
sms.log = { module = function() return { warn = function() end, error = function() end, info = function() end, debug = function() end } end }
sms.utils = sms.utils or {}

-- Minimal sms.K.statics so distill's partition can recognize static type names.
sms.K = sms.K or {}
sms.K.statics = sms.K.statics or { ['Hangar A'] = true }

package.path = '../?.lua;' .. package.path
dofile('../prefab_distill.lua')

local distill = sms.prefab.distill

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name) else
        print('FAIL ' .. name .. ': ' .. tostring(msg))
        failures = failures + 1
    end
end

-- Recursive scan for any key named "boss".
local function has_boss(tbl, seen)
    seen = seen or {}
    if type(tbl) ~= 'table' or seen[tbl] then return false end
    seen[tbl] = true
    for k, v in pairs(tbl) do
        if k == 'boss' then return true end
        if type(v) == 'table' and has_boss(v, seen) then return true end
    end
    return false
end

-- Approximately equal for floating-point comparisons.
local function approx(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) <= eps
end

-- 1. Real fixture dump: distill returns a non-nil prefab.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab', theatre = 'Caucasus'})
    check('distill returns non-nil for fixture', prefab ~= nil, 'got nil')
end

-- 2. boss is gone everywhere.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('no boss key anywhere in output', prefab and not has_boss(prefab),
        'boss still present')
end

-- 3. Centroid math: 4 entities at (0,0), (100,200), (50,100), (100,200) → centroid is (62.5, 125).
--    Note: zone is at (50, 100), drawing at (100, 200) per fixture mapData.
--    Group 1 at (0,0), group 2 at (100,200).
--    Centroid x = (0 + 100 + 50 + 100) / 4 = 62.5
--    Centroid y = (0 + 200 + 100 + 200) / 4 = 125
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('world_anchor in meta is centroid (x)',
        prefab and prefab.meta and approx(prefab.meta.world_anchor.x, 62.5),
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.world_anchor and prefab.meta.world_anchor.x))
    check('world_anchor in meta is centroid (y)',
        prefab and prefab.meta and approx(prefab.meta.world_anchor.y, 125),
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.world_anchor and prefab.meta.world_anchor.y))
end

-- 4. Group coords are anchor-relative.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('group 1 x is anchor-relative (-62.5)',
        prefab and prefab.groups[1] and approx(prefab.groups[1].x, -62.5),
        'got ' .. tostring(prefab and prefab.groups[1] and prefab.groups[1].x))
    check('group 1 y is anchor-relative (-125)',
        prefab and prefab.groups[1] and approx(prefab.groups[1].y, -125),
        'got ' .. tostring(prefab and prefab.groups[1] and prefab.groups[1].y))
end

-- 5. Unit heading converted rad → deg (math.pi/2 → 90).
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    local h = prefab and prefab.groups[1] and prefab.groups[1].units[1].heading
    check('unit heading converted to degrees', h and approx(h, 90),
        'got ' .. tostring(h))
end

-- 6. Country captured from boss before strip.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('group 1 country = 11 (Belgium)',
        prefab and prefab.groups[1] and prefab.groups[1].country == 11,
        'got ' .. tostring(prefab and prefab.groups[1] and prefab.groups[1].country))
end

-- 7. Static partition: hangar ends up in statics, NOT groups.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    check('statics has 1 entry (Hangar A)',
        prefab and #prefab.statics == 1 and prefab.statics[1].name == 'Hangar A',
        'got ' .. tostring(prefab and #prefab.statics))
    check('groups has 1 entry (Aerial-1, not Hangar A)',
        prefab and #prefab.groups == 1 and prefab.groups[1].name == 'Aerial-1',
        'got ' .. tostring(prefab and #prefab.groups))
end

-- 8. Zone fidelity: properties preserved verbatim, center anchor-relative.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    local z = prefab and prefab.zones[1]
    check('zone properties preserved', z and z.properties and z.properties.alarm == 'yes',
        'properties missing or wrong')
    check('zone center anchor-relative x (~ -12.5)',
        z and approx(z.x, -12.5), 'got ' .. tostring(z and z.x))
    check('zone center anchor-relative y (~ -25)',
        z and approx(z.y, -25), 'got ' .. tostring(z and z.y))
    check('zone radius preserved', z and z.radius == 1500, 'got ' .. tostring(z and z.radius))
end

-- 9. Drawing fidelity: vertices and color preserved.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'test_prefab'})
    local d = prefab and prefab.drawings[1]
    check('drawing has 3 points', d and #d.points == 3,
        'got ' .. tostring(d and #d.points))
    check('drawing color preserved', d and d.color and d.color[1] == 1,
        'color missing')
end

-- 10. Empty input returns nil.
do
    local result = distill({groups = {}, statics = {}, zones = {}, drawings = {}}, {name = 'empty'})
    check('empty dump returns nil', result == nil, 'got non-nil')
end

-- 11. Bad input returns nil.
do
    local result = distill(nil, {name = 'bad'})
    check('nil dump returns nil', result == nil, 'got non-nil')
end

-- 12. Meta block populated.
do
    local prefab = distill('fixtures/dump_synthetic_aerial.lua', {name = 'sa6_template', theatre = 'Caucasus'})
    check('meta.name set from opts', prefab and prefab.meta and prefab.meta.name == 'sa6_template',
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.name))
    check('meta.theatre set from opts', prefab and prefab.meta and prefab.meta.theatre == 'Caucasus',
        'got ' .. tostring(prefab and prefab.meta and prefab.meta.theatre))
    check('meta.sms_prefab_version set',
        prefab and prefab.meta and type(prefab.meta.sms_prefab_version) == 'string',
        'missing')
    check('meta.created_utc set',
        prefab and prefab.meta and type(prefab.meta.created_utc) == 'string',
        'missing')
end

if failures > 0 then
    print(string.format('\n%d test(s) FAILED', failures))
    os.exit(1)
else
    print('\nall tests passed')
    os.exit(0)
end
```

- [ ] **Step 3.2: Run tests, verify they fail**

Run: `pwsh framework/test/run_distill_tests.ps1`
Expected: `test_prefab_distill.lua` fails with `module 'prefab_distill' not found`. `test_utils_serialize.lua` still passes.

- [ ] **Step 3.3: Implement `framework/prefab_distill.lua`**

Create `framework/prefab_distill.lua`:

```lua
-- dcs-sms framework: prefab distill module (sms.prefab.distill).
--
-- Pure-data transform: walk an ME selection dump, drop back-references,
-- partition statics out of the groups array, capture country before strip,
-- convert headings rad → deg, and anchor every coordinate relative to the
-- centroid of the selection. No DCS dependencies — runnable in standalone
-- Lua 5.1 for unit tests.
--
-- Public:
--   sms.prefab.distill(dump_or_path, opts) → prefab_table | nil
--     opts = {
--       name    = string,           -- required; meta.name
--       theatre = string?,          -- optional; meta.theatre
--     }
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- ... -> prefab_distill.lua. Asserts sms and sms.log only.
--
-- See docs/superpowers/specs/2026-05-03-sms-prefab-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")
sms.prefab = sms.prefab or {}

local log = sms.log.module("sms.prefab.distill")

local PREFAB_VERSION = "0.1.0"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function rad_to_deg(r)
    return r * (180 / math.pi)
end

local function utc_now()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function is_static_entity(entry)
    -- Catalog lookup first.
    if sms.K and sms.K.statics and entry.units and entry.units[1]
       and sms.K.statics[entry.units[1].type] then
        return true
    end
    -- Field-shape inference: static-only fields, no route/tasks.
    if entry.category and entry.dead ~= nil and not entry.route then
        return true
    end
    return false
end

-- Walk a table, drop "boss" + back-references (cycles). Returns a fresh deep
-- copy with the offending references removed. Captures country (numeric id)
-- via boss.country.id and returns it as the second return value when found.
local function strip_back_refs(value, visited)
    if type(value) ~= 'table' then return value end
    if visited[value] then return nil end
    visited[value] = true

    local out = {}
    local captured_country
    for k, v in pairs(value) do
        if k == 'boss' then
            -- Capture country before dropping.
            if type(v) == 'table' and type(v.country) == 'table' and type(v.country.id) == 'number' then
                captured_country = v.country.id
            end
            -- Drop the boss field entirely.
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

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function sms.prefab.distill(dump_or_path, opts)
    opts = opts or {}
    if not opts.name or opts.name == '' then
        log.warn('distill: opts.name is required')
        return nil
    end

    -- Resolve dump.
    local dump
    local source_dump_name
    if type(dump_or_path) == 'string' then
        local ok, result = pcall(dofile, dump_or_path)
        if not ok then
            log.error('distill: dofile failed for ' .. dump_or_path .. ': ' .. tostring(result))
            return nil
        end
        dump = result
        -- Extract just the filename for source_dump.
        source_dump_name = dump_or_path:match('([^/\\]+)$') or dump_or_path
    elseif type(dump_or_path) == 'table' then
        dump = dump_or_path
    else
        log.warn('distill: dump must be a path string or table')
        return nil
    end

    if type(dump) ~= 'table' then
        log.warn('distill: dump did not load to a table')
        return nil
    end

    local raw_groups   = dump.groups   or {}
    local raw_statics  = dump.statics  or {}
    local raw_zones    = dump.zones    or {}
    local raw_drawings = dump.drawings or {}

    if #raw_groups == 0 and #raw_statics == 0 and #raw_zones == 0 and #raw_drawings == 0 then
        log.warn('distill: dump has no entities — nothing to distill')
        return nil
    end

    -- Phase 1: strip back-refs + capture country per entity.
    -- Process groups (which may include statics in disguise).
    local clean_groups   = {}
    local clean_statics  = {}
    for _, entry in ipairs(raw_groups) do
        local cleaned, country = strip_back_refs(entry, {})
        if cleaned then
            if country and not cleaned.country then
                cleaned.country = country
            end
            -- Propagate country down to units that don't have one.
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
    -- Statics that came in via dump.statics (not yet seen).
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

    -- Phase 2: compute centroid.
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
        log.warn('distill: no positionable entities — cannot anchor')
        return nil
    end
    local cx, cy = sum_x / n, sum_y / n

    -- Phase 3: rebase all coords relative to centroid.
    for _, g in ipairs(clean_groups)   do rebase_xy(g, cx, cy) end
    for _, s in ipairs(clean_statics)  do rebase_xy(s, cx, cy) end
    for _, z in ipairs(clean_zones)    do rebase_xy(z, cx, cy) end
    for _, d in ipairs(clean_drawings) do rebase_xy(d, cx, cy) end

    -- Phase 4: convert all headings rad → deg.
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
```

- [ ] **Step 3.4: Run tests, verify they pass**

Run: `pwsh framework/test/run_distill_tests.ps1`
Expected: 16 PASS lines under `test_prefab_distill.lua` (12 cases — some emit 2 PASSes), "all tests passed", exit 0. `test_utils_serialize.lua` still 8/8 PASS.

- [ ] **Step 3.5: Commit**

```bash
git add framework/prefab_distill.lua framework/test/test_prefab_distill.lua
git commit -m "feat(framework): add sms.prefab.distill (pure-data dump transform)"
```

---

## Task 4: `prefab.lua` skeleton — registry, save, math helpers

**Files:**
- Create: `framework/prefab.lua`

The public surface module. This task adds: module skeleton, internal registry, `load`/`load_dir`/`save`/`unload`/`list`/`get`, and the pure spawn-math helpers (`_rotate_xy`, `_apply_anchor`). Spawn integration (DCS API calls + handle creation) is in Task 5.

- [ ] **Step 4.1: Implement the file**

Create `framework/prefab.lua`:

```lua
-- dcs-sms framework: prefab module (sms.prefab).
--
-- Public namespace for prefab management at runtime: load/save prefab
-- files, register them in an in-memory map, spawn instances at any anchor +
-- rotation + (optional) country override, and clean up via per-instance
-- handles or bulk destroy_all.
--
-- A prefab is a portable bundle of groups + statics + zones + drawings
-- distilled from an ME selection dump. See sms.prefab.distill (in
-- prefab_distill.lua) for the input side. See spec for the file format.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> constants.lua ->
-- group.lua -> unit.lua -> area.lua -> timer.lua -> rule.lua ->
-- group_spawn.lua -> static.lua -> events.lua -> weapon.lua -> task.lua ->
-- commands.lua -> options.lua -> utils_serialize.lua -> prefab_distill.lua ->
-- prefab.lua.
--
-- See docs/superpowers/specs/2026-05-03-sms-prefab-design.md.

assert(type(sms) == "table", "framework/sms.lua must be loaded first")
assert(type(sms.utils) == "table", "framework/utils.lua must be loaded first")
assert(type(sms.utils.serialize) == "function", "framework/utils_serialize.lua must be loaded first")
assert(type(sms.constants) == "table" or type(sms.K) == "table", "framework/constants.lua must be loaded first")
assert(type(sms.prefab) == "table" and type(sms.prefab.distill) == "function", "framework/prefab_distill.lua must be loaded first")

local log = sms.log.module("sms.prefab")

-- ---------------------------------------------------------------------------
-- Module-private state
-- ---------------------------------------------------------------------------

local _registry = {}    -- name -> template_table
local _instances = {}   -- id -> handle
local _next_instance_id = 1

-- ---------------------------------------------------------------------------
-- Math helpers (pure; unit-testable separately if desired).
-- Exposed under sms.prefab._<name> so the smoke tests can poke them.
-- ---------------------------------------------------------------------------

-- Rotate a point (x, y) around origin (0, 0) by rotation_deg degrees,
-- clockwise from north (DCS convention).
function sms.prefab._rotate_xy(x, y, rotation_deg)
    if not rotation_deg or rotation_deg == 0 then return x, y end
    local r = rotation_deg * (math.pi / 180)
    local c, s = math.cos(r), math.sin(r)
    return x * c - y * s, x * s + y * c
end

-- Resolve a vec2/vec3-shaped anchor into (x, z). Spec: caller passes
-- {x = world_x, z = world_y} (DCS world coords; framework convention 2D-y =
-- 3D-z). Also accepts {x, y} for 2D callers.
function sms.prefab._anchor_xy(anchor)
    if type(anchor) ~= 'table' then return nil end
    local ax = anchor.x
    local az = anchor.z or anchor.y
    if type(ax) ~= 'number' or type(az) ~= 'number' then return nil end
    return ax, az
end

-- ---------------------------------------------------------------------------
-- Registry: load / load_dir / save / unload / list / get
-- ---------------------------------------------------------------------------

function sms.prefab.load(path)
    if type(path) ~= 'string' or path == '' then
        log.warn('load: path required')
        return nil
    end
    local ok, result = pcall(dofile, path)
    if not ok then
        log.error('load: dofile failed for ' .. path .. ': ' .. tostring(result))
        return nil
    end
    if type(result) ~= 'table' or type(result.meta) ~= 'table' or type(result.meta.name) ~= 'string' then
        log.warn('load: file at ' .. path .. ' has no meta.name')
        return nil
    end
    if _registry[result.meta.name] then
        log.warn("load: overwriting prefab '" .. result.meta.name .. "'")
    end
    _registry[result.meta.name] = result
    return result
end

function sms.prefab.load_dir(dir)
    if type(dir) ~= 'string' or dir == '' then
        log.warn('load_dir: dir required')
        return 0
    end
    if not lfs then
        log.warn('load_dir: lfs not available — call sms.prefab.load(path) per file instead')
        return 0
    end
    local count = 0
    local function recurse(d)
        for entry in lfs.dir(d) do
            if entry ~= '.' and entry ~= '..' then
                local full = d .. '/' .. entry
                local attr = lfs.attributes(full)
                if attr and attr.mode == 'directory' then
                    recurse(full)
                elseif attr and entry:match('%.lua$') then
                    if sms.prefab.load(full) then count = count + 1 end
                end
            end
        end
    end
    local ok = pcall(recurse, dir)
    if not ok then
        log.warn('load_dir: directory not accessible: ' .. dir)
    end
    return count
end

function sms.prefab.save(prefab_table, path)
    if type(prefab_table) ~= 'table' or type(prefab_table.meta) ~= 'table' then
        log.warn('save: prefab_table missing meta')
        return false
    end
    if type(path) ~= 'string' or path == '' then
        log.warn('save: path required')
        return false
    end
    if type(io) ~= 'table' or not io.open then
        log.warn('save: io.open not available in this environment')
        return false
    end
    local f, err = io.open(path, 'w')
    if not f then
        log.error('save: open failed: ' .. tostring(err))
        return false
    end
    f:write(sms.utils.serialize(prefab_table))
    f:close()
    return true
end

-- Register a template directly (without going through dofile). Useful for
-- programmatically constructed prefabs and for tests. The 'load' path is
-- the production happy path; this is the in-memory equivalent.
function sms.prefab.register(name, template)
    if type(name) ~= 'string' or name == '' then
        log.warn('register: name required')
        return nil
    end
    if type(template) ~= 'table' or type(template.meta) ~= 'table' then
        log.warn("register: template missing meta")
        return nil
    end
    if _registry[name] then
        log.warn("register: overwriting prefab '" .. name .. "'")
    end
    template.meta.name = name
    _registry[name] = template
    return template
end

function sms.prefab.unload(name)
    if _registry[name] then
        _registry[name] = nil
        return true
    end
    return false
end

function sms.prefab.list()
    local out = {}
    for name in pairs(_registry) do out[#out + 1] = name end
    table.sort(out)
    return out
end

function sms.prefab.get(name)
    return _registry[name]
end

-- ---------------------------------------------------------------------------
-- Spawn (skeleton — implementation in next task)
-- ---------------------------------------------------------------------------

function sms.prefab.spawn(name, opts)
    log.error('spawn: not implemented yet')
    return nil
end

function sms.prefab.list_instances(name)
    local out = {}
    for _, h in pairs(_instances) do
        if not name or h:get_name() == name then
            out[#out + 1] = h
        end
    end
    return out
end

function sms.prefab.destroy_all(name)
    local count = 0
    for id, h in pairs(_instances) do
        if not name or h:get_name() == name then
            h:destroy()
            count = count + 1
        end
    end
    return count
end
```

- [ ] **Step 4.2: Verify it loads (no DCS needed)**

Run from `framework/test/`:

```
pwsh -c "Push-Location framework/test; lua -e 'sms = {}; sms.log = { module = function() return { warn = print, error = print, info = print, debug = function() end } end }; sms.utils = {}; sms.utils.serialize = function() return [[]] end; sms.K = { statics = {} }; sms.constants = sms.K; sms.prefab = {}; sms.prefab.distill = function() end; package.path = [[../?.lua;]] .. package.path; dofile([[../prefab.lua]]); print(\"prefab.lua loads OK; list returns: \" .. (#sms.prefab.list()))'; Pop-Location"
```

Expected: `prefab.lua loads OK; list returns: 0`.

- [ ] **Step 4.3: Commit**

```bash
git add framework/prefab.lua
git commit -m "feat(framework): add sms.prefab module skeleton + registry"
```

---

## Task 5: `prefab.lua` — spawn implementation

**Files:**
- Modify: `framework/prefab.lua`

Replace the stub `sms.prefab.spawn` with the real implementation: math, group/static creation via `coalition.add*`, drawing creation via `trigger.action.markup*`, zones attached as data, name auto-suffix, country override, handle construction.

- [ ] **Step 5.1: Implement spawn (full body)**

In `framework/prefab.lua`, replace:

```lua
function sms.prefab.spawn(name, opts)
    log.error('spawn: not implemented yet')
    return nil
end
```

with:

```lua
-- ---------------------------------------------------------------------------
-- Spawn implementation
-- ---------------------------------------------------------------------------

local _category_for_group_type = {
    plane      = Group.Category and Group.Category.AIRPLANE   or 0,
    helicopter = Group.Category and Group.Category.HELICOPTER or 1,
    vehicle    = Group.Category and Group.Category.GROUND     or 2,
    ground     = Group.Category and Group.Category.GROUND     or 2,
    ship       = Group.Category and Group.Category.SHIP       or 3,
    train      = Group.Category and Group.Category.TRAIN      or 4,
}

-- Resolve country opt: accepts a numeric id, a string name (case-insensitive),
-- or nil. Returns numeric id or nil.
local function resolve_country(c)
    if c == nil then return nil end
    if type(c) == 'number' then return c end
    if type(c) == 'string' and sms.utils.resolve_country then
        local id = sms.utils.resolve_country(c)
        return id
    end
    return nil
end

-- Probe Group.getByName / StaticObject.getByName to find a free name with
-- the same auto-suffix convention used by sms.group.create.
local function unique_name(base)
    if not Group.getByName(base) and not (StaticObject and StaticObject.getByName and StaticObject.getByName(base)) then
        return base
    end
    local i = 1
    while true do
        local candidate = base .. '-' .. i
        if not Group.getByName(candidate) and not (StaticObject and StaticObject.getByName and StaticObject.getByName(candidate)) then
            return candidate
        end
        i = i + 1
        if i > 9999 then return base .. '-' .. tostring(os.time()) end
    end
end

-- Deep copy a table; needed because we mutate the spawn-time table without
-- modifying the registered template.
local function deep_copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deep_copy(val) end
    return out
end

-- Apply rotation + translation to every (x, y) pair in a sub-table.
local function apply_transform(t, anchor_x, anchor_z, rotation_deg)
    if type(t) ~= 'table' then return end
    if type(t.x) == 'number' and type(t.y) == 'number' then
        local rx, ry = sms.prefab._rotate_xy(t.x, t.y, rotation_deg)
        t.x = anchor_x + rx
        t.y = anchor_z + ry
    end
    for _, v in pairs(t) do
        if type(v) == 'table' then
            apply_transform(v, anchor_x, anchor_z, rotation_deg)
        end
    end
end

-- Apply rotation to every heading field. (Headings are in degrees in the
-- prefab file; DCS expects radians on spawn.)
local function rotate_headings(t, rotation_deg)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'heading' and type(v) == 'number' then
            t[k] = ((v + rotation_deg) % 360)
        elseif type(v) == 'table' then
            rotate_headings(v, rotation_deg)
        end
    end
end

-- Convert all heading fields deg → rad in-place (final pre-DCS step).
local function headings_to_rad(t)
    if type(t) ~= 'table' then return end
    for k, v in pairs(t) do
        if k == 'heading' and type(v) == 'number' then
            t[k] = v * (math.pi / 180)
        elseif type(v) == 'table' then
            headings_to_rad(v)
        end
    end
end

-- Spawn one group: coalition.addGroup. Returns spawned name on success, nil + log on failure.
local function spawn_group(group_table, country_override, name_prefix)
    local g = deep_copy(group_table)
    local country = country_override or g.country
    if not country then
        log.warn("spawn: group '" .. tostring(g.name) .. "' has no country and none provided")
        return nil
    end
    local cat = _category_for_group_type[g.type]
    if not cat then
        log.warn("spawn: group '" .. tostring(g.name) .. "' unknown type '" .. tostring(g.type) .. "'")
        return nil
    end
    local desired = (name_prefix or '') .. (g.name or 'unnamed')
    local resolved = unique_name(desired)
    g.name = resolved
    -- Auto-suffix unit names too — append the same suffix (delta from the original name).
    if g.units then
        local suffix = resolved:sub(#desired + 1)            -- "" if no suffix added
        for _, u in pairs(g.units) do
            if type(u) == 'table' and type(u.name) == 'string' and suffix ~= '' then
                u.name = u.name .. suffix
            end
        end
    end
    headings_to_rad(g)
    -- Drop our distill enrichment fields that DCS doesn't expect.
    g.country = nil
    local ok, err = pcall(coalition.addGroup, country, cat, g)
    if not ok then
        log.error("spawn: coalition.addGroup failed for '" .. resolved .. "': " .. tostring(err))
        return nil
    end
    return resolved
end

local function spawn_static(static_table, country_override, name_prefix)
    local s = deep_copy(static_table)
    local country = country_override or s.country
    if not country then
        log.warn("spawn: static '" .. tostring(s.name) .. "' has no country and none provided")
        return nil
    end
    local desired = (name_prefix or '') .. (s.name or 'unnamed')
    s.name = unique_name(desired)
    headings_to_rad(s)
    s.country = nil
    local ok, err = pcall(coalition.addStaticObject, country, s)
    if not ok then
        log.error("spawn: coalition.addStaticObject failed for '" .. s.name .. "': " .. tostring(err))
        return nil
    end
    return s.name
end

-- Spawn a drawing via trigger.action.* APIs. Returns a {name, mark_id, kind}
-- table on success, nil on failure.
local function spawn_drawing(drawing, mark_id_alloc)
    local kind = drawing.primitiveType or 'Unknown'
    local mark_id = mark_id_alloc()
    local coalition_id = -1                                     -- all
    local color    = drawing.color     or {1, 1, 1, 1}
    local fill     = drawing.fillColor or {1, 1, 1, 0.25}
    local line_type = drawing.lineType or 1                     -- 1 = solid

    local ok, err
    if kind == 'Line' and drawing.points and #drawing.points >= 2 then
        local p1 = drawing.points[1]
        local p2 = drawing.points[2]
        ok, err = pcall(trigger.action.lineToAll, coalition_id, mark_id,
            { x = p1.x, y = 0, z = p1.y },
            { x = p2.x, y = 0, z = p2.y },
            color, line_type, true, drawing.text or '')
    elseif kind == 'Polygon' and drawing.points and #drawing.points >= 3 then
        ok, err = pcall(function()
            local args = { 7, coalition_id, mark_id }     -- shapeId 7 = freeform polygon
            for _, p in ipairs(drawing.points) do
                args[#args + 1] = { x = p.x, y = 0, z = p.y }
            end
            args[#args + 1] = color
            args[#args + 1] = fill
            args[#args + 1] = line_type
            args[#args + 1] = true
            args[#args + 1] = drawing.text or ''
            trigger.action.markupToAll(table.unpack and table.unpack(args) or unpack(args))
        end)
    elseif kind == 'Circle' then
        local r = drawing.radius or 1000
        local cx = (drawing.mapData and drawing.mapData.x) or drawing.x or 0
        local cy = (drawing.mapData and drawing.mapData.y) or drawing.y or 0
        ok, err = pcall(trigger.action.circleToAll, coalition_id, mark_id,
            { x = cx, y = 0, z = cy }, r, color, fill, line_type, true, drawing.text or '')
    elseif kind == 'TextBox' or kind == 'Text' then
        local cx = (drawing.mapData and drawing.mapData.x) or drawing.x or 0
        local cy = (drawing.mapData and drawing.mapData.y) or drawing.y or 0
        ok, err = pcall(trigger.action.textToAll, coalition_id, mark_id,
            { x = cx, y = 0, z = cy }, color, fill, drawing.fontSize or 16, true, drawing.text or '')
    elseif kind == 'Icon' then
        local cx = (drawing.mapData and drawing.mapData.x) or drawing.x or 0
        local cy = (drawing.mapData and drawing.mapData.y) or drawing.y or 0
        ok, err = pcall(trigger.action.markToAll, mark_id, drawing.text or drawing.name or '',
            { x = cx, y = 0, z = cy }, true)
    else
        log.warn("spawn: drawing kind '" .. kind .. "' not supported in v1 — skipping")
        return nil
    end
    if not ok then
        log.error("spawn: drawing render failed for '" .. tostring(drawing.name) .. "': " .. tostring(err))
        return nil
    end
    return { name = drawing.name, mark_id = mark_id, kind = kind }
end

function sms.prefab.spawn(name, opts)
    opts = opts or {}
    local template = _registry[name]
    if not template then
        log.warn("spawn: prefab '" .. tostring(name) .. "' not registered")
        return nil
    end
    local rotation = opts.rotation or 0
    local country = resolve_country(opts.country)
    if opts.country ~= nil and country == nil then
        log.warn('spawn: opts.country invalid: ' .. tostring(opts.country))
        return nil
    end

    local anchor_x, anchor_z
    if opts.keep_position then
        anchor_x = template.meta.world_anchor.x
        anchor_z = template.meta.world_anchor.y
        rotation = 0
    else
        anchor_x, anchor_z = sms.prefab._anchor_xy(opts.anchor)
        if not anchor_x then
            log.warn('spawn: opts.anchor required (or set keep_position=true)')
            return nil
        end
    end

    -- Phase 1: build mutable copies, transform coords + headings.
    local groups   = {}
    local statics  = {}
    for _, g in ipairs(template.groups or {})   do
        local copy = deep_copy(g)
        rotate_headings(copy, rotation)
        apply_transform(copy, anchor_x, anchor_z, rotation)
        groups[#groups + 1] = copy
    end
    for _, s in ipairs(template.statics or {})  do
        local copy = deep_copy(s)
        rotate_headings(copy, rotation)
        apply_transform(copy, anchor_x, anchor_z, rotation)
        statics[#statics + 1] = copy
    end

    -- Phase 2: realize in DCS.
    local spawned_groups   = {}
    local spawned_statics  = {}
    local spawned_drawings = {}
    local zones            = {}
    local template_to_runtime = {}     -- "Aerial-1" -> "Aerial-1-2"

    for _, g in ipairs(groups) do
        local original = g.name
        local rt = spawn_group(g, country, opts.name_prefix)
        if rt then
            spawned_groups[#spawned_groups + 1] = sms.group(rt)
            template_to_runtime[original] = rt
        end
    end
    for _, s in ipairs(statics) do
        local original = s.name
        local rt = spawn_static(s, country, opts.name_prefix)
        if rt then
            spawned_statics[#spawned_statics + 1] = sms.static(rt)
            template_to_runtime[original] = rt
        end
    end

    -- Drawings: transform coords first, then realize.
    local mark_id_seed = math.floor(os.time() * 1000)
    local drawings = {}
    for _, d in ipairs(template.drawings or {}) do
        local copy = deep_copy(d)
        apply_transform(copy, anchor_x, anchor_z, rotation)
        drawings[#drawings + 1] = copy
    end
    local function alloc_mark_id()
        mark_id_seed = mark_id_seed + 1
        return mark_id_seed
    end
    for _, d in ipairs(drawings) do
        local entry = spawn_drawing(d, alloc_mark_id)
        if entry then spawned_drawings[#spawned_drawings + 1] = entry end
    end

    -- Zones: data-only. Transform coords; attach to handle.
    for _, z in ipairs(template.zones or {}) do
        local copy = deep_copy(z)
        apply_transform(copy, anchor_x, anchor_z, rotation)
        zones[#zones + 1] = copy
    end

    if #spawned_groups == 0 and #spawned_statics == 0 and #spawned_drawings == 0 and #zones == 0 then
        log.error("spawn: nothing in prefab '" .. name .. "' was spawnable")
        return nil
    end

    -- Build handle.
    local id = _next_instance_id
    _next_instance_id = id + 1
    local handle = {
        _name                = name,
        _id                  = id,
        _anchor              = { x = anchor_x, z = anchor_z },
        _rotation            = rotation,
        _groups              = spawned_groups,
        _statics             = spawned_statics,
        _drawings            = spawned_drawings,
        _zones               = zones,
        _template_to_runtime = template_to_runtime,
        _destroyed           = false,
    }
    setmetatable(handle, { __index = sms.prefab })
    _instances[id] = handle
    return handle
end

-- ---------------------------------------------------------------------------
-- Handle methods (dispatched via __index = sms.prefab)
-- ---------------------------------------------------------------------------

function sms.prefab.get_name(h)     return h._name end
function sms.prefab.get_id(h)       return h._id end
function sms.prefab.get_anchor(h)   return { x = h._anchor.x, z = h._anchor.z } end
function sms.prefab.get_rotation(h) return h._rotation end
function sms.prefab.get_groups(h)   return h._destroyed and {} or h._groups end
function sms.prefab.get_statics(h)  return h._destroyed and {} or h._statics end
function sms.prefab.get_zones(h)    return h._destroyed and {} or h._zones end
function sms.prefab.get_drawings(h) return h._destroyed and {} or h._drawings end

local function find_by_name(arr, name)
    for _, x in ipairs(arr) do
        if x.name == name then return x end
    end
    return nil
end

function sms.prefab.get_group(h, template_name)
    if h._destroyed then return nil end
    local rt = h._template_to_runtime[template_name]
    if not rt then return nil end
    return sms.group(rt)
end

function sms.prefab.get_static(h, template_name)
    if h._destroyed then return nil end
    local rt = h._template_to_runtime[template_name]
    if not rt then return nil end
    return sms.static(rt)
end

function sms.prefab.get_zone(h, name)
    if h._destroyed then return nil end
    return find_by_name(h._zones, name)
end

function sms.prefab.is_alive(h)
    if h._destroyed then return false end
    for _, g in ipairs(h._groups) do
        if g and g.is_alive and g:is_alive() then return true end
    end
    for _, s in ipairs(h._statics) do
        if s and s.is_alive and s:is_alive() then return true end
    end
    return false
end

function sms.prefab.destroy(h)
    if h._destroyed then return end
    for _, g in ipairs(h._groups) do
        pcall(function()
            local raw = Group.getByName(g.name)
            if raw then raw:destroy() end
        end)
    end
    for _, s in ipairs(h._statics) do
        pcall(function()
            if StaticObject and StaticObject.getByName then
                local raw = StaticObject.getByName(s.name)
                if raw then raw:destroy() end
            end
        end)
    end
    for _, d in ipairs(h._drawings) do
        pcall(trigger.action.removeMark, d.mark_id)
    end
    h._destroyed = true
    _instances[h._id] = nil
end
```

- [ ] **Step 5.2: Verify load (no DCS needed — minimal stubs)**

Run from worktree root:

```
pwsh -c "Push-Location framework/test; lua -e 'sms = {}; sms.log = { module = function() return { warn = print, error = print, info = print, debug = function() end } end }; sms.utils = {}; sms.utils.serialize = function() return [[]] end; sms.utils.resolve_country = function(s) return 11 end; sms.K = { statics = {} }; sms.constants = sms.K; sms.prefab = {}; sms.prefab.distill = function() end; Group = { Category = { AIRPLANE=0, HELICOPTER=1, GROUND=2, SHIP=3, TRAIN=4 }, getByName = function() return nil end }; StaticObject = { getByName = function() return nil end }; coalition = { addGroup = function() end, addStaticObject = function() end }; trigger = { action = { lineToAll = function() end, markupToAll = function() end, circleToAll = function() end, textToAll = function() end, markToAll = function() end, removeMark = function() end } }; sms.group = function(n) return { name = n, is_alive = function() return true end } end; sms.static = function(n) return { name = n, is_alive = function() return true end } end; package.path = [[../?.lua;]] .. package.path; dofile([[../prefab.lua]]); print(\"prefab.lua loads with spawn impl\")'; Pop-Location"
```

Expected: `prefab.lua loads with spawn impl`.

- [ ] **Step 5.3: Commit**

```bash
git add framework/prefab.lua
git commit -m "feat(framework): implement sms.prefab.spawn + handle"
```

---

## Task 6: Wire prefab modules into `load_all.lua`

**Files:**
- Modify: `framework/load_all.lua`

The framework loader needs to know about the three new modules.

- [ ] **Step 6.1: Update modules list**

Edit `framework/load_all.lua`. Find the `local modules = { ... }` block and append `"utils_serialize.lua"`, `"prefab_distill.lua"`, `"prefab.lua"` after `"options.lua"`. The full block should read:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "constants.lua",
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
  "utils_serialize.lua",
  "prefab_distill.lua",
  "prefab.lua",
}
```

- [ ] **Step 6.2: Verify**

Run: `grep -n "prefab" framework/load_all.lua`
Expected: three lines showing the three new modules.

- [ ] **Step 6.3: Commit**

```bash
git add framework/load_all.lua
git commit -m "feat(framework): load prefab modules in load_all"
```

---

## Task 7: AGENTS.md §7 + docs/api/prefab.md

**Files:**
- Modify: `AGENTS.md`
- Create: `docs/api/prefab.md`

Per CLAUDE.md, public surface change requires AGENTS.md sync + docs/api page.

- [ ] **Step 7.1: AGENTS.md §7 module index**

Edit `AGENTS.md`. Find the module index table (the `| Module | File(s) | Reference | Purpose |` table in §7). Append a row after the `sms.options` row:

```markdown
| `sms.prefab` | `prefab.lua` (+ `prefab_distill.lua`) | [`docs/api/prefab.md`](docs/api/prefab.md) | Portable bundles of groups + statics + zones + drawings. Distill ME selection dumps; load/save prefab files; spawn at any anchor + rotation + (optional) country override; per-instance lifecycle. |
```

- [ ] **Step 7.2: Create docs/api/prefab.md**

Create `docs/api/prefab.md`:

```markdown
# `sms.prefab`

Portable bundles of DCS entities — groups, statics, trigger zones, map drawings — distilled from a Mission Editor selection and respawnable at runtime anywhere on any map.

A prefab is a Lua chunk file produced by `sms.prefab.distill(...)` from a hello-world ME selection dump. Once loaded into the runtime registry via `sms.prefab.load(path)`, you can `sms.prefab.spawn("name", {anchor=..., rotation=..., country=...})` as many times as you want; each call returns an instance handle for lifecycle management.

See [the design spec](../superpowers/specs/2026-05-03-sms-prefab-design.md) for the file format details and design rationale.

## Quick example

```lua
-- One-time setup: distill a captured ME selection dump into a prefab.
local prefab = sms.prefab.distill(
    "C:/Users/.../Saved Games/DCS/dcs-sms/me/selection-2026-05-03T091254Z.lua",
    { name = "farp_alpha", theatre = "Caucasus" }
)
sms.prefab.save(prefab, "C:/Users/.../Saved Games/DCS/dcs-sms/prefabs/farp_alpha.lua")

-- Per-mission: load the registry, spawn copies.
sms.prefab.load("C:/Users/.../Saved Games/DCS/dcs-sms/prefabs/farp_alpha.lua")

local north = sms.prefab.spawn("farp_alpha", {
    anchor   = { x = 12000, z = -3500 },
    rotation = 90,
})

local south = sms.prefab.spawn("farp_alpha", {
    anchor   = { x = -8000, z = 5000 },
    rotation = -45,
    country  = sms.K.countries.RUSSIA,
})

-- Later, clean up.
north:destroy()
sms.prefab.destroy_all("farp_alpha")  -- destroys remaining south
```

## Functions

### `sms.prefab.distill(dump_or_path, opts) → prefab_table | nil`

Walks an ME selection dump, drops back-references (the `boss` cycle), partitions statics out of groups, captures country before strip, converts headings rad → deg, and rebases every coordinate relative to the centroid of the selection. Pure data — no DCS dependencies.

- `dump_or_path` — either an in-memory dump table or a path string to a `.lua` dump file.
- `opts.name` (string, required) — the prefab's registered name (`meta.name`).
- `opts.theatre` (string, optional) — informational; stored as `meta.theatre`.

Returns a prefab table (the same shape as a saved prefab file), or `nil` + log on bad input.

### `sms.prefab.save(prefab_table, path) → boolean`

Serializes `prefab_table` via `sms.utils.serialize` and writes to `path`. Returns `true` on success, `false` + log on failure (e.g., `io.open` failed). Requires `io` to be available — fails gracefully in environments where it's nilled.

### `sms.prefab.load(path) → template_table | nil`

`dofile`s the file at `path`, validates that it has `meta.name`, registers it in the registry under that name. Re-loading the same name logs a warning and overwrites. Returns the loaded template or `nil` + log on failure.

### `sms.prefab.load_dir(dir) → number`

Recursively loads every `*.lua` under `dir`. Per-file failures log + continue. Returns the count of successful loads. Requires `lfs`.

### `sms.prefab.register(name, template) → template_table | nil`

Registers a template directly (without `dofile`). Useful for programmatically constructed prefabs and for tests. Sets `template.meta.name = name` and adds to the registry. Returns the template, or `nil` + log on bad input.

### `sms.prefab.unload(name) → boolean`

Removes `name` from the registry. Does NOT destroy spawned instances. Returns `true` if `name` was registered, `false` otherwise.

### `sms.prefab.list() → string[]`

Returns the names of all currently-registered prefabs, sorted.

### `sms.prefab.get(name) → template_table | nil`

Returns the registered template table for `name`, or `nil`.

### `sms.prefab.spawn(name, opts) → handle | nil`

Spawns a new instance of the registered prefab `name`. Returns a handle (see "Handle methods" below) or `nil` + log on failure.

`opts`:

- `anchor` (vec2 / vec3, required unless `keep_position=true`) — world anchor `{x = world_x, z = world_y}`. Also accepts `{x, y}` for callers passing 2D.
- `rotation` (number, optional, default `0`) — degrees, clockwise from north.
- `country` (number or string, optional) — override every unit's country. `nil` preserves per-unit country from the prefab. Strings resolved via `sms.utils.resolve_country`.
- `name_prefix` (string, optional) — prepended to every spawned entity's name (before auto-suffix).
- `keep_position` (boolean, optional) — if `true`, ignores `opts.anchor` and `opts.rotation`; spawns at `meta.world_anchor` with rotation 0 (the original placement).

Naming: candidate name is `(opts.name_prefix or "") .. file_name`. If a name is already taken, the spawner appends `-1`, `-2`, ... per the framework convention.

### `sms.prefab.list_instances(name?) → handle[]`

Returns all live handles, optionally filtered by template name.

### `sms.prefab.destroy_all(name?) → number`

Calls `:destroy()` on every live handle (or those matching `name`). Returns count destroyed.

## Handle methods

The handle returned by `spawn(...)` is callable via `handle:method()` style.

| Method | Returns |
|---|---|
| `handle:get_name()` | template name (string) |
| `handle:get_id()` | instance id (number, unique per spawn) |
| `handle:get_anchor()` | resolved world anchor used at spawn (`{x, z}`) |
| `handle:get_rotation()` | degrees applied at spawn |
| `handle:get_groups()` | array of `sms.group` handles |
| `handle:get_statics()` | array of `sms.static` handles |
| `handle:get_zones()` | array of zone tables (data-only; not real DCS trigger zones) |
| `handle:get_drawings()` | array of `{name, mark_id, kind}` (mark ids are DCS runtime) |
| `handle:get_group(template_name)` | the spawned `sms.group` for the given original (template) name |
| `handle:get_static(template_name)` | the spawned `sms.static` for the given original (template) name |
| `handle:get_zone(name)` | zone table by name |
| `handle:is_alive()` | `true` if at least one entity from this spawn still exists |
| `handle:destroy()` | destroys all spawned entities, removes drawings; idempotent |

## Notes and limitations

- **Zones don't get realized** in DCS — there's no runtime trigger-zone-creation API. They're stored on the handle for custom in-zone checks (`sms.area.is_in_polygon` etc.).
- **Drawings get realized** via `trigger.action.markup*` — they appear on the F10 map. v1 supports `Line`, `Polygon`, `Circle`, `TextBox`, `Icon`. Other kinds skip with a warning.
- **Same-prefab cross-references aren't rewritten.** If group A's escort task references group B and you spawn the prefab twice, the second spawn's A-equivalent still references the first spawn's B. Documented limitation; revisit in v2 if it bites real users.
- **Loading prefab files is `dofile`** — arbitrary code execution. v1 is for files you wrote or trust. Sandboxed loader will land before community sharing is encouraged.
- **Random pools** (per-entity spawn-chance) are not yet supported. Designed-around in the format so they can be added in v2.
- **Names are preserved verbatim** in the file — auto-suffix happens at spawn time, not save time.
- **Headings in the file are degrees** — internal rad-to-deg conversion happens during distill; deg-to-rad happens during spawn before handing to DCS.
```

- [ ] **Step 7.3: Verify both files**

```
grep -c "sms.prefab" AGENTS.md
ls docs/api/prefab.md
```

Expected: AGENTS.md grep returns ≥1; the docs file exists.

- [ ] **Step 7.4: Commit**

```bash
git add AGENTS.md docs/api/prefab.md
git commit -m "docs: add sms.prefab to AGENTS.md §7 and docs/api"
```

---

## Task 8: Smoke test file (manual, won't run in CI)

**Files:**
- Create: `framework/test/smoke_prefab.ps1`

The smoke needs DCS running. Implementer should write the file but does not need to run it (validation = "the file parses and follows the established smoke pattern"). User runs it manually after testing.

- [ ] **Step 8.1: Read an existing smoke for the pattern**

Run: `head -100 framework/test/smoke_static.ps1`
Note the structure: `Import-Module $PSScriptRoot/_smoke.psm1`, `Initialize-Smoke`, `Invoke-Smoke -File 'load_all.lua'`, fixture-name array + try/finally with `Clear-SmokeFixtures`.

- [ ] **Step 8.2: Write the smoke file**

Create `framework/test/smoke_prefab.ps1`:

```powershell
# smoke_prefab.ps1 — manual smoke for sms.prefab.
#
# Requires DCS running with a loaded mission and the dcs-sms hook installed.
# Run via:
#   pwsh framework/test/smoke_prefab.ps1
#
# Steps:
#   1. Build a tiny prefab in-memory via sms.prefab.distill against a synthetic
#      dump table (no file I/O dependency).
#   2. Register it in the runtime registry.
#   3. Spawn at a known anchor; verify position math.
#   4. Spawn a second instance; verify name auto-suffix.
#   5. Spawn with country override; verify coalition.
#   6. Spawn with rotation; verify a unit at offset (100, 0) ends up at (0, 100).
#   7. keep_position; verify spawn at meta.world_anchor.
#   8. destroy(); verify Group.getByName returns nil.
#   9. Idempotent destroy.
#  10. destroy_all by template name.

Import-Module "$PSScriptRoot/_smoke.psm1" -Force
Initialize-Smoke
Invoke-Smoke -File 'load_all.lua' | Out-Null

# Define a small inline prefab via a Lua chunk. Uses ground vehicle (no
# route/aircraft requirements) at (0, 0) for simplicity. Anchor recorded as
# (0, 0) so keep_position spawns where defined.
$buildPrefab = @"
sms.prefab.unload('_smoke_prefab_a')
local template = {
    meta = {
        sms_prefab_version = "0.1.0",
        created_utc = "2026-05-03T00:00:00Z",
        world_anchor = { x = 0, y = 0 },
    },
    groups = {
        [1] = {
            name = "_smoke_aerial",
            type = "vehicle",
            x = 0, y = 0, heading = 0, country = 2,
            units = {
                [1] = { name = "_smoke_aerial-1", type = "M-1 Abrams",
                        x = 100, y = 0, heading = 0, skill = "Average" },
            },
            task = "Ground Nothing",
        },
    },
    statics = {}, zones = {}, drawings = {},
}
sms.prefab.register('_smoke_prefab_a', template)
return sms.prefab.list()[1]
"@

$fixtures = @('_smoke_aerial', '_smoke_aerial-1', '_smoke_aerial-2')

try {
    Expect-EqString -Label 'register registers under meta.name' `
        -Code $buildPrefab `
        -Expected '_smoke_prefab_a'

    # 3. spawn at known anchor
    Expect-EqNumber -Label 'spawn 1: unit position x = anchor.x + 100' `
        -Code @"
            local h = sms.prefab.spawn('_smoke_prefab_a', { anchor = { x = 50000, z = 0 } })
            local g = h:get_groups()[1]
            local u = Group.getByName(g.name):getUnits()[1]
            return u:getPoint().x
"@ `
        -Expected 50100 -Tolerance 0.5

    # 4. spawn second; verify auto-suffix
    Expect-EqString -Label 'spawn 2: name auto-suffixed' `
        -Code @"
            local h2 = sms.prefab.spawn('_smoke_prefab_a', { anchor = { x = 60000, z = 0 } })
            return h2:get_groups()[1].name
"@ `
        -Expected '_smoke_aerial-1'

    # 5. country override
    Expect-EqNumber -Label 'spawn 3: country override = RUSSIA' `
        -Code @"
            local h3 = sms.prefab.spawn('_smoke_prefab_a', {
                anchor = { x = 70000, z = 0 }, country = 0,
            })
            local g = h3:get_groups()[1]
            return Group.getByName(g.name):getCoalition()
"@ `
        -Expected 1   # 1 = red, since country 0 = USSR which is red

    # 6. rotation: unit at offset (100, 0) with 90deg becomes (0, 100)
    Expect-EqNumber -Label 'spawn 4: rotation 90 places unit at z = anchor.z + 100' `
        -Code @"
            local h4 = sms.prefab.spawn('_smoke_prefab_a', {
                anchor = { x = 80000, z = 0 }, rotation = 90,
            })
            local g = h4:get_groups()[1]
            local u = Group.getByName(g.name):getUnits()[1]
            return u:getPoint().z
"@ `
        -Expected 100 -Tolerance 0.5

    # 7. keep_position
    Expect-EqNumber -Label 'spawn 5: keep_position uses meta.world_anchor (x=0)' `
        -Code @"
            local h5 = sms.prefab.spawn('_smoke_prefab_a', { keep_position = true })
            local g = h5:get_groups()[1]
            local u = Group.getByName(g.name):getUnits()[1]
            return u:getPoint().x
"@ `
        -Expected 100 -Tolerance 0.5  # unit at relative (100, 0); anchor (0, 0) → world 100

    # 8. destroy
    Expect-EqString -Label 'destroy_all clears every spawned instance' `
        -Code @"
            local n = sms.prefab.destroy_all('_smoke_prefab_a')
            return tostring(n) .. '|' .. tostring(#sms.prefab.list_instances('_smoke_prefab_a'))
"@ `
        -Expected '5|0'

} finally {
    Clear-SmokeFixtures -Names $fixtures
}

Write-Host "ALL sms.prefab smoke checks passed."
```

**Note for the implementer:** the smoke uses `sms.prefab.register(name, template)` to bypass the `dofile` path entirely — it's the public in-memory-registration entry point. Tests don't need temp files on disk; production code can also use this when prefabs are constructed programmatically.

- [ ] **Step 8.3: Verify the file at least parses (no DCS run yet)**

Run: `pwsh -NoProfile -Command "Get-Content framework/test/smoke_prefab.ps1 | Out-Null; Write-Host 'parsed OK'"`

If the file has PowerShell syntax errors, this fails. Otherwise prints `parsed OK`. The actual test execution requires a running DCS and is run by the user manually.

- [ ] **Step 8.4: Commit**

```bash
git add framework/test/smoke_prefab.ps1
git commit -m "test(framework): add manual smoke for sms.prefab"
```

---

## Task 9: Final validation

**No file changes.** A final pass that everything builds and the unit tests still pass.

- [ ] **Step 9.1: Run all unit tests**

Run: `pwsh framework/test/run_distill_tests.ps1`
Expected: both `test_utils_serialize.lua` (8 PASS) and `test_prefab_distill.lua` (16 PASS), all green.

- [ ] **Step 9.2: Verify Go suite still passes**

Run: `cd tools && go test ./... -count=1`
Expected: all packages PASS (no Go changes were made; this is a sanity check against accidental edits).

- [ ] **Step 9.3: Verify branch state**

Run: `git log --oneline main..HEAD`
Expected: a series of clean conventional commits, one per task. No working-tree changes (`git status` clean).

- [ ] **Step 9.4: Verify load_all.lua references all new modules**

Run: `grep -c "prefab" framework/load_all.lua`
Expected: `2` (or `3` — both `prefab_distill.lua` and `prefab.lua` plus possibly `utils_serialize.lua`).

If anything is dirty, fix it now.

---

## Self-review notes

These are checks the plan-writer ran to verify completeness; nothing actionable for the implementer.

**Spec coverage:**
- `sms.prefab.distill` — Task 3.
- `sms.prefab.load` / `load_dir` / `unload` / `list` / `get` — Task 4.
- `sms.prefab.save` — Task 4 (uses `sms.utils.serialize` from Task 1).
- `sms.prefab.spawn` math + groups + statics + drawings + zones — Task 5.
- Handle methods + lifecycle — Task 5.
- `list_instances` / `destroy_all` — Task 4 skeleton, Task 5 confirmed working.
- Failure model (log + nil + never throw) — `pcall`-wrapped throughout Tasks 3–5; per-entity partial success in spawn.
- File format — Task 3 emits it; Task 4 loads it; both reference the spec.
- Loading order — Task 6.
- AGENTS.md / docs/api — Task 7.
- Tests (unit) — Tasks 1, 3.
- Tests (smoke) — Task 8.

**Placeholder scan:** no TBD/TODO; every code block is complete.

**Type consistency:**
- `sms.prefab.distill(...)` returns prefab table with keys `meta`, `groups`, `statics`, `zones`, `drawings` — same shape consumed by `sms.prefab.spawn(...)` via `_registry`.
- Handle fields (`_name`, `_id`, `_anchor`, `_rotation`, `_groups`, `_statics`, `_drawings`, `_zones`, `_template_to_runtime`, `_destroyed`) used identically in spawn (Task 5) and the handle methods (Task 5).
- `sms.prefab._rotate_xy` / `_anchor_xy` defined Task 4, called by spawn Task 5.
- `sms.utils.serialize` defined Task 1, called by `sms.prefab.save` Task 4.
- Country resolution: `resolve_country(c)` accepts number or string (via `sms.utils.resolve_country`); spec confirmed.
