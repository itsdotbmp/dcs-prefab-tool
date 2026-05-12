# `me resources set` + weapon name lookup — design

**Status**: design (ready for implementation plan)
**Date**: 2026-05-10
**Branch**: `feat/me-execution-bridge`
**Predecessors**:
- [`2026-05-10-me-airbase-query-design.md`](#) — wasn't written; the `me airbase list/get` and `me resources get` verbs were built directly from conversation. Their commits: `3a3d11d` (query verbs), `70bbf18` (set-coalition + resources get).

## Goal

Land the third leg of the airbase / ship inventory triad: write access to the warehouse table (`mission.AirportsEquipment.airports[N]` for airbases, `mission.AirportsEquipment.warehouses[unitId]` for ships and structures). The `get` and `set-coalition` verbs already cover read + coalition; `set` is the remaining piece for full inventory control — toggling unlimited flags, clearing categories, setting per-fuel / per-aircraft / per-weapon counts.

The biggest sub-problem is **weapon name resolution**: the warehouse table indexes weapons by `wsType` (a 4-tuple of integers, e.g. `{4, 7, 33, 146}`), not by name. A user-friendly CLI needs to accept human strings (`"AIM-120C-7"`, `"GBU-12"`) and map them to wsType tuples. ED's `DB.weapon_by_CLSID` (2161 entries on a typical install) carries the mapping.

## Scope

### In

- `me resources set { --airbase N | --unit ID } [...mods...]` — single verb, applies one or more inventory modifications and writes back.
- New module `dcs_sms_me/weapons_db.lua` — lazy index over `DB.weapon_by_CLSID`, exposes `find_by_name(needle)` returning either a hit, an ambiguous-result with candidates, or nil. Reused by future verbs (e.g. unit loadout queries).
- Live verification on Syria: round-trip a sample airbase (Hama) and a sample ship-with-warehouse, exercise every flag class.

### Out

- `me resources set --coalition` — already covered by `me airbase set-coalition`. Don't overlap.
- Ship coalition setting — that's group-level, not warehouse-level. Different code path.
- A `me weapon list` discovery verb. Users can `me resources get --airbase X` and inspect `weapons[N]` to see what's enumerated. Add later if it turns out to be needed in practice.
- The `linkDynTempl` field on per-aircraft entries (dynamic spawn template binding) — leave at whatever value it already has on read-modify-write. Out of scope for v1.
- The `suppliers`, `dynamicCargo`, `dynamicSpawn`, `allowHotStart`, `speed`, `periodicity`, `size` top-level fields. They're rarely useful from CLI; if needed, expose later. Read-modify-write preserves their current values.

## Verb shape

```
me resources set { --airbase NAME | --unit NAME-OR-ID }
                 [--clear] [--unlimited]
                 [--clear-aircrafts] [--clear-fuel] [--clear-munitions]
                 [--unlimited-aircrafts] [--unlimited-fuel] [--unlimited-munitions]
                 [--operating-level-air N]
                 [--operating-level-fuel N]
                 [--operating-level-eqp N]
                 [--fuel TYPE=N ...]
                 [--aircraft "DISPLAY NAME"=N ...]
                 [--weapon "FRAGMENT"=N ...]
                 [--pretty]
```

All mod flags are optional. With no mod flags, the verb is a no-op (returns the current entry — equivalent to `me resources get` but exits 0). Useful for "verify nothing changes" diff-tests.

## Mods, applied in order

Order matters because later mods can override earlier ones (e.g. `--clear --aircraft "F-16C bl.50"=100` clears everything, then sets just the F-16 to 100).

1. **Top-level resets**
   - `--clear` — set `unlimitedFuel/Aircrafts/Munitions` to false, set every existing entry in `aircrafts.planes`, `aircrafts.helicopters`, and `weapons[N]` to `initialAmount = 0`, set every fuel sub-table's `InitFuel = 0`. Mirrors the ME's "Clear" button (which clears the inventory but doesn't touch the unlimited checkboxes — we go further by also unchecking those, since `--clear` reads as "fully empty" semantically).
   - `--unlimited` — set `unlimitedFuel/Aircrafts/Munitions` to true. Doesn't touch the per-entry numbers (they're moot when unlimited is on, and a future `--clear-unlimited` toggle would restore them).

2. **Per-category resets**
   - `--clear-aircrafts` — zero every `aircrafts.{planes,helicopters}[NAME].initialAmount`. Don't touch unlimitedAircrafts.
   - `--clear-fuel` — set every fuel sub-table's `InitFuel = 0`. Don't touch unlimitedFuel.
   - `--clear-munitions` — zero every `weapons[N].initialAmount`. Don't touch unlimitedMunitions.
   - `--unlimited-aircrafts` / `--unlimited-fuel` / `--unlimited-munitions` — set the matching flag to true.

   **Unsetting unlimited per category**: use Go's standard bool-flag `=false` syntax —
   `--unlimited-aircrafts=false`. Same applies to the top-level `--unlimited=false` (turns
   off all three) and to `--clear=false` (which is a no-op, since `--clear` is just the
   trigger to apply the reset; passing it false means "don't apply"). This matrix gives
   complete coverage of every checkbox state ED's Resource Manager exposes:

   | Goal | Flag |
   |---|---|
   | Inventory → 0, all unlimited → off | `--clear` |
   | Inventory → 0, leave unlimited alone | `--clear-aircrafts` `--clear-fuel` `--clear-munitions` (any combination) |
   | All unlimited → on | `--unlimited` |
   | Per-category unlimited on | `--unlimited-aircrafts` (etc.) |
   | Per-category unlimited off (without clearing inventory) | `--unlimited-aircrafts=false` (etc.) |
   | All unlimited → off (without clearing inventory) | `--unlimited=false` |

3. **Operating levels** (replenishment minimum stock, 0–100 integer percent)
   - `--operating-level-air N`
   - `--operating-level-fuel N`
   - `--operating-level-eqp N`
   - Range validated CLI-side. Out-of-range → exit 2.

4. **Specific values**
   - `--fuel TYPE=N` (repeatable) — TYPE in `{jet_fuel, gasoline, diesel, methanol_mixture}`, N is 0..100. Sets `entry[TYPE].InitFuel = N`. Unknown TYPE → error.
   - `--aircraft "DISPLAY NAME"=N` (repeatable) — exact match against the warehouse table key (which is a display name, e.g. `"F-16C bl.50"`). The key search walks both `aircrafts.planes` and `aircrafts.helicopters`. Unknown name → error with the closest matches as candidates.
   - `--weapon "FRAGMENT"=N` (repeatable) — substring match (case-insensitive) against `displayName` from `DB.weapon_by_CLSID`. See "Weapon resolution" below.

### Weapon resolution

Inputs are display-name fragments. The lookup module (new file `dcs_sms_me/weapons_db.lua`) builds an index lazily on first access:

```
{
  by_displayname_lower = { ["aim-120c-7 (amraam)"] = entry, ... },
  all_entries = [{ clsid, name, display_name, ws_type = {4, 7, 33, 146}, category }, ...]
}
```

`find_by_name(needle)` algorithm:
1. Lowercase the needle.
2. Exact-match against `by_displayname_lower`. If exactly one hit → return it.
3. Otherwise scan `all_entries` for substring matches on `display_name` (case-insensitive). 
   - 0 hits → `{ found = false }`
   - Exactly 1 hit → return it
   - 2+ hits → `{ ambiguous = true, candidates = [first 5 display_names] }`
4. As a last-resort escape hatch, `find_by_clsid(clsid)` accepts the raw CLSID (e.g. `"{LAU-68 FFAR Mk5 HEAT_TER_2_L}"`). The `--weapon` flag detects values starting with `"{"` and routes through this path.

When `--weapon FRAGMENT=N` finds a match:
- Walk `entry.weapons[1..#weapons]`, find an existing entry whose `wsType` equals the resolved 4-tuple.
- If found: set its `initialAmount = N`.
- If not found: append a new entry `{ wsType = <tuple>, initialAmount = N }`.

When ambiguous, the whole `set` call fails atomically — no other mods are applied — and returns the candidate list so the user can refine. Pre-validate before any mutation.

### Atomicity

All mods validate first (parse all flag values, resolve all weapon names, find all aircraft keys), then apply on a deep copy of the warehouse entry, then write back. If any validation fails, no mutation happens and the live data is untouched. This matters because partial application would leave the warehouse in a state the user can't easily reason about.

## Targeting

Identical to `me resources get`:

- `--airbase N` — name resolved via `_airbase_find_by_name` (case-insensitive exact preferred, substring fallback). Errors if no match.
- `--unit NAME-OR-ID` — name via `mission.unit_by_name`, or numeric `unitId`. Only resolves if the unit has a warehouse entry (ships, structures with cargo). Errors if no warehouse for the resolved id.

Exactly one of `--airbase` / `--unit` is required. Mutual-exclusion enforced CLI-side.

## Returns

Same shape as `me resources get`:

```
{ ok: true,
  target: "airbase" | "unit",
  name: ...,
  airdrome_number / unit_id: ...,
  warehouse: { ...full updated entry... } }
```

On error: `{ ok: false, error: "..." }` with optional `candidates: [...]` for weapon ambiguity.

## Errors

| Condition | Response |
|---|---|
| Both / neither of `--airbase` / `--unit` | CLI exit 2 |
| Unknown airbase / unit | `ok: false, error: 'no <kind> matching "X"'` |
| No warehouse entry for resolved unitId | `ok: false, error: 'no warehouse entry for unit X (id=N)'` |
| Unknown fuel type | `ok: false, error: 'unknown fuel type "X" (must be jet_fuel/gasoline/diesel/methanol_mixture)'` |
| Out-of-range operating level / fuel value | CLI exit 2 with usage message |
| Unknown aircraft key | `ok: false, error: 'no aircraft "X" in warehouse', candidates: [...]` (closest matches) |
| Ambiguous weapon fragment | `ok: false, error: 'weapon "FRAG" is ambiguous', candidates: [...]` |
| Weapon fragment matches nothing | `ok: false, error: 'no weapon matching "X"'` |
| Mission not loaded | `ok: false, error: 'mission not loaded — open one in the Mission Editor first'` |

## Implementation

### Lua

**New file**: `tools/me-mod/lua/dcs_sms_me/weapons_db.lua` (~80 LoC)

```lua
local M = {}
local _index   -- nil until first build

local function build()
    local DB_ok, DB = pcall(require, 'me_db_api')
    if not DB_ok or not DB or type(DB.weapon_by_CLSID) ~= 'table' then return nil end
    local idx = { by_displayname_lower = {}, by_clsid = {}, all_entries = {} }
    for clsid, w in pairs(DB.weapon_by_CLSID) do
        if type(w) == 'table' and type(w.displayName) == 'string' and type(w.wsTypeOfWeapon) == 'table' then
            local entry = {
                clsid        = clsid,
                name         = w.name,
                display_name = w.displayName,
                ws_type      = { w.wsTypeOfWeapon[1], w.wsTypeOfWeapon[2], w.wsTypeOfWeapon[3], w.wsTypeOfWeapon[4] },
                category     = w.category,
            }
            local key_lower = w.displayName:lower()
            -- Multiple CLSIDs CAN share a displayName (rare). Last-wins for the
            -- map; substring search still walks the full list to find them all.
            idx.by_displayname_lower[key_lower] = entry
            idx.by_clsid[clsid] = entry
            idx.all_entries[#idx.all_entries + 1] = entry
        end
    end
    return idx
end

function M.find_by_name(needle)
    if type(needle) ~= 'string' or needle == '' then return { found = false } end
    if needle:sub(1, 1) == '{' then
        return M.find_by_clsid(needle)
    end
    _index = _index or build()
    if not _index then return { found = false, error = 'weapon DB not available' } end
    local n_low = needle:lower()
    local exact = _index.by_displayname_lower[n_low]
    if exact then return { found = true, entry = exact } end
    local hits = {}
    for _, e in ipairs(_index.all_entries) do
        if e.display_name:lower():find(n_low, 1, true) then
            hits[#hits + 1] = e
            if #hits > 5 then break end  -- bound the candidate list
        end
    end
    if #hits == 0 then return { found = false } end
    if #hits == 1 then return { found = true, entry = hits[1] } end
    local cands = {}
    for _, e in ipairs(hits) do cands[#cands + 1] = e.display_name end
    return { ambiguous = true, candidates = cands }
end

function M.find_by_clsid(clsid)
    _index = _index or build()
    if not _index then return { found = false, error = 'weapon DB not available' } end
    local e = _index.by_clsid[clsid]
    if e then return { found = true, entry = e } end
    return { found = false }
end

return M
```

**New verb in `verbs.lua`**: `M.resources_set(args)` (~150 LoC)

```lua
function M.resources_set(args)
    args = args or {}
    -- 1. Resolve target (airbase or unit) — same logic as resources_get
    -- 2. Read warehouse entry, deep copy it
    -- 3. Pre-validate ALL mods. Build:
    --    - resolved fuel overrides table { jet_fuel = 80, gasoline = 50 }
    --    - resolved aircraft overrides table { ["F-16C bl.50"] = 100 }
    --    - resolved weapon overrides list [{ ws_type = {...}, count = 400 }, ...]
    --    Any failure here returns { ok = false, error = ..., candidates = ... }
    --    BEFORE any mutation.
    -- 4. Apply mods on the copy in canonical order (top resets → category resets
    --    → operating levels → specific values).
    -- 5. Write back via warehouse_ops.apply (airbase) or direct splice
    --    (unit; mission.AirportsEquipment.warehouses[unit_id] = copy).
    -- 6. Return { ok = true, target = ..., name = ..., warehouse = copy }
end
```

The `--clear` and `--unlimited` interactions are simple enough that we don't need a bitfield: each top-level / per-category mod is applied if its flag is set in `args`. Order is fixed by the function code, not by arg-array order.

For ship warehouses, no AirdromeController push is needed — coalition stays at whatever the ship had (and we don't accept `--coalition` here, so it's preserved).

### Go

**New file**: `tools/cmd/dcs-sms/me_resources_set.go` (~180 LoC)

Repeatable flags use `flag.Func`:

```go
var (
    fuels     []string  // "TYPE=N" raw
    aircrafts []string  // "NAME=N" raw
    weapons   []string  // "FRAGMENT=N" raw
)
fs.Func("fuel", "...", func(v string) error { fuels = append(fuels, v); return nil })
fs.Func("aircraft", "...", func(v string) error { aircrafts = append(aircrafts, v); return nil })
fs.Func("weapon", "...", func(v string) error { weapons = append(weapons, v); return nil })
```

Parse `K=V` Go-side, validate K is non-empty and V parses as a number. Build a Lua expression with structured sub-tables:

```
{
    airbase = "Hama",  -- or unit = "..."
    clear = true, unlimited = false,
    clear_aircrafts = false, clear_fuel = false, clear_munitions = false,
    unlimited_aircrafts = false, unlimited_fuel = false, unlimited_munitions = false,
    operating_level_air = 80, operating_level_fuel = 80, operating_level_eqp = 80,
    fuel_overrides = { jet_fuel = 80, gasoline = 50 },
    aircraft_overrides = { ["F-16C bl.50"] = 100 },
    weapon_overrides = { { name = "AIM-120C-7", count = 400 }, { name = "GBU-12", count = 200 } },
}
```

Note: `weapon_overrides` is an array, not a map, so duplicate fragments are visible (and Lua-side we either reject or last-wins; reject is cleaner).

### File touches

- `tools/me-mod/lua/dcs_sms_me/weapons_db.lua` — new
- `tools/me-mod/lua/dcs_sms_me/verbs.lua` — add `M.resources_set` (~150 LoC)
- `tools/cmd/dcs-sms/me_resources_set.go` — new (~180 LoC)
- `CHANGELOG.md` — extend the in-flight 0.6.0 entry under ME-mod
- (No `AGENTS.md` change — that section is for framework `sms.*`)

### Test plan

Live verification on Syria. No Lua unit tests (project convention); some Go-side unit tests for the K=V parsing / range-checking logic if it gets non-trivial.

Round-trip test against Hama:
1. `me resources get --airbase Hama` → snapshot
2. `me resources set --airbase Hama --clear` → diff: all unlimited flags off, all counts zero
3. `me resources set --airbase Hama --unlimited` → diff: all unlimited flags on
4. `me resources set --airbase Hama --aircraft "F-16C bl.50"=100 --fuel jet_fuel=80 --weapon "GBU-12"=400`
   - Visible in `me resources get` output: F-16 count, jet_fuel value, GBU-12 wsType-keyed entry
5. Restore from snapshot to verify revertibility

Error paths:
- `--weapon "AIM"=100` — should be ambiguous (likely matches AIM-7, AIM-9, AIM-120 variants); response should list candidates
- `--weapon "GBU-12"=400` — likely unique; should succeed
- `--weapon "{LAU-68 FFAR Mk5 HEAT_TER_2_L}"=100` — CLSID escape hatch; should succeed
- `--fuel kerosene=50` — unknown fuel type; clean error
- `--operating-level-air 150` — out of range; CLI exit 2

Ship test (carrier in mission, if available):
- Same round-trip on a ship's warehouse via `--unit "CVN-71"`.
- Verifies the lowercase coalition is preserved and the splice goes to `warehouses[unitId]` not `airports[N]`.

## Decisions

1. **Repeatable flags via `flag.Func`** rather than custom `flag.Value` slice types. Less code, clear intent. Loses the `String()` / `IsBoolFlag()` features but we don't need them.
2. **Substring + ambiguity error for weapons**, not exact-only. Display names are too long to type in full (`"GBU-12 - 500 lb LGB"`); fragments are the natural CLI input. Ambiguity is rare in practice (most weapon families have one canonical entry plus variants with disambiguating words like `(AMRAAM)`).
3. **CLSID escape hatch** when fragment matching fails or is ambiguous. Recognised by leading `{`. Lets agents script around the rare ambiguous cases without us having to ship a full disambiguation UI.
4. **`--clear` clears AND unchecks unlimited**. Stricter than the ME's "Clear" button, which only zeroes the inventory. Reasoning: from CLI, `--clear` reads as "make this warehouse fully empty". A user who wants the ME's behaviour can `--clear --unlimited-fuel --unlimited-aircrafts --unlimited-munitions` (composable).
5. **Atomic apply**: validate all mods first, then mutate. No partial application. Single round-trip from caller's perspective.
6. **No `--coalition` here**. `me airbase set-coalition` already covers it; doubling up would mean two code paths to maintain (one with the AirdromeController push, one without). For ships, coalition is on the unit, not the warehouse — different verb entirely (out of scope).
7. **No `me weapon list` discovery verb in v1**. `me resources get` already exposes the full weapons list with wsTypes; users can grep for fragments. If real users find this awkward, add later — YAGNI now.
8. **Aircraft keys exact-match, not substring**. Display names there are short and stable (`"F-16C bl.50"`, `"Su-27"`), unlike weapons. Substring would invite false positives (`"F-16C"` matching multiple variants).

## Versioning

ME-mod 0.6.0 is in flight, not yet tagged. This work folds in. CHANGELOG entry under the existing 0.6.0 Added block.

## Surface impact

`me`-namespace verbs: 87 → 88 (+1). Bridge total stays in lockstep — `screenshot` is a top-level CLI verb, not under `me`.

`me resources` verbs: 1 (`get`) → 2 (`get`, `set`).

New shared module: `dcs_sms_me/weapons_db.lua` (lazy weapon-name index). Designed for reuse by future verbs that need wsType ↔ display-name mapping (e.g. unit loadout queries).

## Open questions

None at design time — all design questions resolved in conversation prior to this spec.
