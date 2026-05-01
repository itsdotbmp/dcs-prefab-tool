# `sms.countries` enum implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `sms.countries` enum table mirroring the static autocomplete-friendly shape of `sms.units`, so mission code can write `country = sms.countries.USA` instead of `country = "USA"`.

**Architecture:** Single hand-maintained file `framework/countries.lua` exposing `sms.countries.<KEY> = "<KEY>"` for ~94 well-known DCS `country.id` keys, plus a load-time drift check that walks `country.id` and `log.warn`s (and adds at runtime) any keys missing from the static list. LuaCATS `---@class sms.countries` field annotations and `---@alias sms.Country` cover both `sms.countries.<KEY>` access and `country = "..."` literal-string usage on spawn configs.

**Tech Stack:** Lua 5.1 (DCS mission environment), `sms.log` (tagged logger). Smoke-tested via bash + `tools/dcs-sms.exe exec` against a live DCS mission.

**Spec:** `docs/superpowers/specs/2026-05-01-sms-countries.md`

---

## Conventions used in this plan

- **Working directory:** `D:/git/dcs-sms/.worktrees/sms-countries/`. All shell commands run from there unless otherwise noted.
- **Lua syntax check:** the framework has no LSP / linter wired in; trust the smoke test as the contract.
- **Commit style:** conventional commits, scopes follow the repo (`feat(framework)`, `docs(framework)`, etc.). One commit per task.
- **Smoke tests need DCS:** any new check added to `framework/test/smoke.sh` requires DCS running with a mission loaded. CI does NOT run it. The plan still requires the smoke checks be written and committed; the user runs them as part of `/bring-it-home`.
- **Tasks 2–6 are independent** of each other and only depend on Task 1. The driver may run them in parallel.

---

## File structure

| File | Status | Purpose |
|---|---|---|
| `framework/countries.lua` | Create | The new module: `sms.countries.<KEY> = "<KEY>"` table, `---@class sms.countries` field block, `---@alias sms.Country` literal alias, runtime drift check against `country.id`. |
| `framework/load_all.lua` | Modify | Insert `"countries.lua"` in the loader list, after `"utils.lua"` and before `"units.lua"`. |
| `framework/group_spawn.lua` | Modify | Update the LuaCATS annotation on the `country` field of the spawn-config type alias to reference `sms.Country`. |
| `framework/static.lua` | Modify | Same — update the `country` field annotation on the static spawn-config type alias to reference `sms.Country`. |
| `framework/test/smoke.sh` | Modify | Add a small "sms.countries" section verifying the table loads, key/value identity holds, and representative entries round-trip through `sms.utils.resolve_country`. |
| `docs/api/countries.md` | Create | Per-symbol reference page with worked examples; describes the table, the `sms.Country` alias, the drift check, and why values are upper-snake. |
| `docs/api/README.md` | Modify | Add `countries.md` row to the module-index table (between `statics.md` and `targets.md`). |
| `docs/api/examples.md` | Modify | Replace `country = "USA"` and `country = "RUSSIA"` literals in recipes 1, 4, and 5 with `sms.countries.USA` / `sms.countries.RUSSIA`. |
| `AGENTS.md` | Modify | Add `sms.countries` row to §7 module-index table (between `sms.statics` and `sms.targets`). |
| `README.md` | Modify | Add `sms.countries` to the framework module list under "Repo layout"; sweep the quick-start snippet to use `sms.countries.USA`. |

---

## Task 1: Implement `framework/countries.lua` and wire `load_all.lua`

**Files:**
- Create: `framework/countries.lua`
- Modify: `framework/load_all.lua` — insert `"countries.lua"` after `"utils.lua"` and before `"units.lua"` in the `modules` list.

**Background for the implementer:**

- The framework loads modules in dependency order via `framework/load_all.lua`. `sms.lua` defines the global namespace; `log.lua` provides tagged loggers; `utils.lua` is loaded before any consumer of `sms.utils.*`. `countries.lua` only depends on `sms` and `sms.log` — no `utils` dependency — but loading it after `utils.lua` keeps the "utility-ish constants" cluster (`utils → countries → units → statics → targets → designations`) together.
- The module exposes a flat table: `sms.countries.<KEY> = "<KEY>"`. The value being equal to the key itself gives the invariant `sms.countries.X == "X"`, which is easy to reason about and matches what `country.id` keys look like (`country.id.USA`, `country.id.UNITED_KINGDOM`).
- LuaCATS double-form: the `---@class sms.countries` field block drives autocomplete on `sms.countries.<KEY>` access; the `---@alias sms.Country` drives autocomplete on raw string literals (`country = "USA"`). Both must list the same keys; the explicit assignment block below populates both.
- Runtime drift check: at the end of the file, iterate `country.id` keys; for any key not in `sms.countries`, add it at runtime AND `log.warn` once per missing key. This makes the framework forward-compatible if DCS adds a country between regenerations of the static list. The check must be defensive — `country` may not exist in some test contexts (running outside DCS) — guarded by a `type(country) == "table"` check.
- Failure model: no public function on this module logs at error or returns nil for caller misuse. There are no public functions, only the table. The drift warning is `log.warn`, exactly once per missing key at load time.

- [ ] **Step 1.1: Create `framework/countries.lua`**

Write this file verbatim:

```lua
-- dcs-sms framework: countries module (sms.countries).
--
-- Hand-maintained enum of DCS country.id keys. Mission code uses
-- sms.countries.<KEY> instead of magic strings:
--
--     sms.group.create({country = sms.countries.USA, ...})
--     sms.static.create({country = sms.countries.RUSSIA, ...})
--
-- Values are the upper-snake form that country.id itself uses, which
-- gives the invariant sms.countries.X == "X". sms.utils.resolve_country
-- accepts either the upper-snake form or display variants ("USA",
-- "usa", "United Kingdom"); the enum picks the canonical form.
--
-- Runtime drift check (bottom of this file): walks country.id at load
-- time and log.warns + adds at runtime any keys missing from the static
-- list. This keeps spawn calls working even if a future DCS update
-- introduces a country we haven't catalogued — and surfaces the gap so
-- the static list can be updated to keep editor autocomplete in sync.
--
-- Loading order: sms.lua -> log.lua -> utils.lua -> countries.lua.
--
-- See docs/superpowers/specs/2026-05-01-sms-countries.md.

assert(type(sms) == "table",     "framework/sms.lua must be loaded first")
assert(type(sms.log) == "table", "framework/log.lua must be loaded first")

local log = sms.log.module("sms.countries")

---@class sms.countries
---@field RUSSIA                  "RUSSIA"
---@field UKRAINE                 "UKRAINE"
---@field USA                     "USA"
---@field TURKEY                  "TURKEY"
---@field UK                      "UK"
---@field FRANCE                  "FRANCE"
---@field GERMANY                 "GERMANY"
---@field USAF_AGGRESSORS         "USAF_AGGRESSORS"
---@field CANADA                  "CANADA"
---@field SPAIN                   "SPAIN"
---@field THE_NETHERLANDS         "THE_NETHERLANDS"
---@field BELGIUM                 "BELGIUM"
---@field NORWAY                  "NORWAY"
---@field DENMARK                 "DENMARK"
---@field ISRAEL                  "ISRAEL"
---@field GEORGIA                 "GEORGIA"
---@field INSURGENTS              "INSURGENTS"
---@field ABKHAZIA                "ABKHAZIA"
---@field SOUTH_OSETIA            "SOUTH_OSETIA"
---@field ITALY                   "ITALY"
---@field AUSTRALIA               "AUSTRALIA"
---@field SWITZERLAND             "SWITZERLAND"
---@field AUSTRIA                 "AUSTRIA"
---@field BELARUS                 "BELARUS"
---@field BULGARIA                "BULGARIA"
---@field CHEZH_REPUBLIC          "CHEZH_REPUBLIC"
---@field CHINA                   "CHINA"
---@field CROATIA                 "CROATIA"
---@field EGYPT                   "EGYPT"
---@field FINLAND                 "FINLAND"
---@field GREECE                  "GREECE"
---@field HUNGARY                 "HUNGARY"
---@field INDIA                   "INDIA"
---@field IRAN                    "IRAN"
---@field IRAQ                    "IRAQ"
---@field JAPAN                   "JAPAN"
---@field KAZAKHSTAN              "KAZAKHSTAN"
---@field NORTH_KOREA             "NORTH_KOREA"
---@field PAKISTAN                "PAKISTAN"
---@field POLAND                  "POLAND"
---@field ROMANIA                 "ROMANIA"
---@field SAUDI_ARABIA            "SAUDI_ARABIA"
---@field SERBIA                  "SERBIA"
---@field SLOVAKIA                "SLOVAKIA"
---@field SOUTH_KOREA             "SOUTH_KOREA"
---@field SWEDEN                  "SWEDEN"
---@field SYRIA                   "SYRIA"
---@field YEMEN                   "YEMEN"
---@field VIETNAM                 "VIETNAM"
---@field VENEZUELA               "VENEZUELA"
---@field TUNISIA                 "TUNISIA"
---@field THAILAND                "THAILAND"
---@field SUDAN                   "SUDAN"
---@field PHILIPPINES             "PHILIPPINES"
---@field MOROCCO                 "MOROCCO"
---@field MEXICO                  "MEXICO"
---@field MALAYSIA                "MALAYSIA"
---@field LIBYA                   "LIBYA"
---@field JORDAN                  "JORDAN"
---@field INDONESIA               "INDONESIA"
---@field HONDURAS                "HONDURAS"
---@field ETHIOPIA                "ETHIOPIA"
---@field CHILE                   "CHILE"
---@field BRAZIL                  "BRAZIL"
---@field BAHRAIN                 "BAHRAIN"
---@field THIRDREICH              "THIRDREICH"
---@field YUGOSLAVIA              "YUGOSLAVIA"
---@field USSR                    "USSR"
---@field ITALIAN_SOCIAL_REPUBLIC "ITALIAN_SOCIAL_REPUBLIC"
---@field ALGERIA                 "ALGERIA"
---@field KUWAIT                  "KUWAIT"
---@field QATAR                   "QATAR"
---@field OMAN                    "OMAN"
---@field UAE                     "UAE"
---@field SOUTH_AFRICA            "SOUTH_AFRICA"
---@field CUBA                    "CUBA"
---@field PORTUGAL                "PORTUGAL"
---@field GDR                     "GDR"
---@field LEBANON                 "LEBANON"
---@field CJTF_BLUE                "CJTF_BLUE"
---@field CJTF_RED                 "CJTF_RED"
---@field UN_PEACEKEEPERS         "UN_PEACEKEEPERS"
---@field ARGENTINA               "ARGENTINA"
---@field CYPRUS                  "CYPRUS"
---@field SLOVENIA                "SLOVENIA"
---@field BOLIVIA                 "BOLIVIA"
---@field GHANA                   "GHANA"
---@field NIGERIA                 "NIGERIA"
---@field PERU                    "PERU"
---@field ECUADOR                 "ECUADOR"
---@field ESTONIA                 "ESTONIA"
---@field LATVIA                  "LATVIA"
---@field LITHUANIA               "LITHUANIA"
---@field URUGUAY                 "URUGUAY"
sms.countries = sms.countries or {}

---@alias sms.Country
---| "RUSSIA"
---| "UKRAINE"
---| "USA"
---| "TURKEY"
---| "UK"
---| "FRANCE"
---| "GERMANY"
---| "USAF_AGGRESSORS"
---| "CANADA"
---| "SPAIN"
---| "THE_NETHERLANDS"
---| "BELGIUM"
---| "NORWAY"
---| "DENMARK"
---| "ISRAEL"
---| "GEORGIA"
---| "INSURGENTS"
---| "ABKHAZIA"
---| "SOUTH_OSETIA"
---| "ITALY"
---| "AUSTRALIA"
---| "SWITZERLAND"
---| "AUSTRIA"
---| "BELARUS"
---| "BULGARIA"
---| "CHEZH_REPUBLIC"
---| "CHINA"
---| "CROATIA"
---| "EGYPT"
---| "FINLAND"
---| "GREECE"
---| "HUNGARY"
---| "INDIA"
---| "IRAN"
---| "IRAQ"
---| "JAPAN"
---| "KAZAKHSTAN"
---| "NORTH_KOREA"
---| "PAKISTAN"
---| "POLAND"
---| "ROMANIA"
---| "SAUDI_ARABIA"
---| "SERBIA"
---| "SLOVAKIA"
---| "SOUTH_KOREA"
---| "SWEDEN"
---| "SYRIA"
---| "YEMEN"
---| "VIETNAM"
---| "VENEZUELA"
---| "TUNISIA"
---| "THAILAND"
---| "SUDAN"
---| "PHILIPPINES"
---| "MOROCCO"
---| "MEXICO"
---| "MALAYSIA"
---| "LIBYA"
---| "JORDAN"
---| "INDONESIA"
---| "HONDURAS"
---| "ETHIOPIA"
---| "CHILE"
---| "BRAZIL"
---| "BAHRAIN"
---| "THIRDREICH"
---| "YUGOSLAVIA"
---| "USSR"
---| "ITALIAN_SOCIAL_REPUBLIC"
---| "ALGERIA"
---| "KUWAIT"
---| "QATAR"
---| "OMAN"
---| "UAE"
---| "SOUTH_AFRICA"
---| "CUBA"
---| "PORTUGAL"
---| "GDR"
---| "LEBANON"
---| "CJTF_BLUE"
---| "CJTF_RED"
---| "UN_PEACEKEEPERS"
---| "ARGENTINA"
---| "CYPRUS"
---| "SLOVENIA"
---| "BOLIVIA"
---| "GHANA"
---| "NIGERIA"
---| "PERU"
---| "ECUADOR"
---| "ESTONIA"
---| "LATVIA"
---| "LITHUANIA"
---| "URUGUAY"

-- Static enum: every key's value is the key itself, so
-- sms.countries.X == "X" holds for every entry.
sms.countries.RUSSIA                  = "RUSSIA"
sms.countries.UKRAINE                 = "UKRAINE"
sms.countries.USA                     = "USA"
sms.countries.TURKEY                  = "TURKEY"
sms.countries.UK                      = "UK"
sms.countries.FRANCE                  = "FRANCE"
sms.countries.GERMANY                 = "GERMANY"
sms.countries.USAF_AGGRESSORS         = "USAF_AGGRESSORS"
sms.countries.CANADA                  = "CANADA"
sms.countries.SPAIN                   = "SPAIN"
sms.countries.THE_NETHERLANDS         = "THE_NETHERLANDS"
sms.countries.BELGIUM                 = "BELGIUM"
sms.countries.NORWAY                  = "NORWAY"
sms.countries.DENMARK                 = "DENMARK"
sms.countries.ISRAEL                  = "ISRAEL"
sms.countries.GEORGIA                 = "GEORGIA"
sms.countries.INSURGENTS              = "INSURGENTS"
sms.countries.ABKHAZIA                = "ABKHAZIA"
sms.countries.SOUTH_OSETIA            = "SOUTH_OSETIA"
sms.countries.ITALY                   = "ITALY"
sms.countries.AUSTRALIA               = "AUSTRALIA"
sms.countries.SWITZERLAND             = "SWITZERLAND"
sms.countries.AUSTRIA                 = "AUSTRIA"
sms.countries.BELARUS                 = "BELARUS"
sms.countries.BULGARIA                = "BULGARIA"
sms.countries.CHEZH_REPUBLIC          = "CHEZH_REPUBLIC"
sms.countries.CHINA                   = "CHINA"
sms.countries.CROATIA                 = "CROATIA"
sms.countries.EGYPT                   = "EGYPT"
sms.countries.FINLAND                 = "FINLAND"
sms.countries.GREECE                  = "GREECE"
sms.countries.HUNGARY                 = "HUNGARY"
sms.countries.INDIA                   = "INDIA"
sms.countries.IRAN                    = "IRAN"
sms.countries.IRAQ                    = "IRAQ"
sms.countries.JAPAN                   = "JAPAN"
sms.countries.KAZAKHSTAN              = "KAZAKHSTAN"
sms.countries.NORTH_KOREA             = "NORTH_KOREA"
sms.countries.PAKISTAN                = "PAKISTAN"
sms.countries.POLAND                  = "POLAND"
sms.countries.ROMANIA                 = "ROMANIA"
sms.countries.SAUDI_ARABIA            = "SAUDI_ARABIA"
sms.countries.SERBIA                  = "SERBIA"
sms.countries.SLOVAKIA                = "SLOVAKIA"
sms.countries.SOUTH_KOREA             = "SOUTH_KOREA"
sms.countries.SWEDEN                  = "SWEDEN"
sms.countries.SYRIA                   = "SYRIA"
sms.countries.YEMEN                   = "YEMEN"
sms.countries.VIETNAM                 = "VIETNAM"
sms.countries.VENEZUELA               = "VENEZUELA"
sms.countries.TUNISIA                 = "TUNISIA"
sms.countries.THAILAND                = "THAILAND"
sms.countries.SUDAN                   = "SUDAN"
sms.countries.PHILIPPINES             = "PHILIPPINES"
sms.countries.MOROCCO                 = "MOROCCO"
sms.countries.MEXICO                  = "MEXICO"
sms.countries.MALAYSIA                = "MALAYSIA"
sms.countries.LIBYA                   = "LIBYA"
sms.countries.JORDAN                  = "JORDAN"
sms.countries.INDONESIA               = "INDONESIA"
sms.countries.HONDURAS                = "HONDURAS"
sms.countries.ETHIOPIA                = "ETHIOPIA"
sms.countries.CHILE                   = "CHILE"
sms.countries.BRAZIL                  = "BRAZIL"
sms.countries.BAHRAIN                 = "BAHRAIN"
sms.countries.THIRDREICH              = "THIRDREICH"
sms.countries.YUGOSLAVIA              = "YUGOSLAVIA"
sms.countries.USSR                    = "USSR"
sms.countries.ITALIAN_SOCIAL_REPUBLIC = "ITALIAN_SOCIAL_REPUBLIC"
sms.countries.ALGERIA                 = "ALGERIA"
sms.countries.KUWAIT                  = "KUWAIT"
sms.countries.QATAR                   = "QATAR"
sms.countries.OMAN                    = "OMAN"
sms.countries.UAE                     = "UAE"
sms.countries.SOUTH_AFRICA            = "SOUTH_AFRICA"
sms.countries.CUBA                    = "CUBA"
sms.countries.PORTUGAL                = "PORTUGAL"
sms.countries.GDR                     = "GDR"
sms.countries.LEBANON                 = "LEBANON"
sms.countries.CJTF_BLUE               = "CJTF_BLUE"
sms.countries.CJTF_RED                = "CJTF_RED"
sms.countries.UN_PEACEKEEPERS         = "UN_PEACEKEEPERS"
sms.countries.ARGENTINA               = "ARGENTINA"
sms.countries.CYPRUS                  = "CYPRUS"
sms.countries.SLOVENIA                = "SLOVENIA"
sms.countries.BOLIVIA                 = "BOLIVIA"
sms.countries.GHANA                   = "GHANA"
sms.countries.NIGERIA                 = "NIGERIA"
sms.countries.PERU                    = "PERU"
sms.countries.ECUADOR                 = "ECUADOR"
sms.countries.ESTONIA                 = "ESTONIA"
sms.countries.LATVIA                  = "LATVIA"
sms.countries.LITHUANIA               = "LITHUANIA"
sms.countries.URUGUAY                 = "URUGUAY"

-- Runtime drift check. country is the DCS global; country.id is a
-- {KEY = int} hash of every country DCS knows about. If a key is in
-- country.id but not in the static list above, add it at runtime so
-- spawn calls keep working, and log a one-shot warn so the gap is
-- visible. Guarded so this file is loadable outside DCS (e.g. host-side
-- tests that don't have the country global).
if type(country) == "table" and type(country.id) == "table" then
  for key in pairs(country.id) do
    if type(key) == "string" and sms.countries[key] == nil then
      sms.countries[key] = key
      log.warn("country.id key '" .. key .. "' not in static list — added at runtime; update framework/countries.lua to keep autocomplete in sync")
    end
  end
end
```

- [ ] **Step 1.2: Modify `framework/load_all.lua`**

The current `modules` list (around lines 30–50) reads:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "units.lua",
  "statics.lua",
  ...
}
```

Insert `"countries.lua"` between `"utils.lua"` and `"units.lua"`. The post-edit list reads:

```lua
local modules = {
  "sms.lua",
  "log.lua",
  "utils.lua",
  "countries.lua",
  "units.lua",
  "statics.lua",
  "targets.lua",
  "designations.lua",
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
}
```

- [ ] **Step 1.3: Quick local sanity check**

Verify the file is syntactically valid by running it through `luac -p` if a Lua compiler is available, otherwise skip. Most agents will not have luac on Windows; the smoke test in Task 3 is the real contract.

```bash
which luac && luac -p framework/countries.lua && echo "OK" || echo "luac not available; will rely on smoke test"
```

- [ ] **Step 1.4: Commit**

```bash
git add framework/countries.lua framework/load_all.lua docs/superpowers/specs/2026-05-01-sms-countries.md docs/superpowers/plans/2026-05-01-sms-countries.md
git commit -m "$(printf 'feat(framework): add sms.countries enum module\n\nHand-listed table of ~94 DCS country.id keys with sms.countries.X == "X"\ninvariant; LuaCATS class+alias for autocomplete; runtime drift check\nthat warns and adds keys missing from the static list.\n')"
```

---

## Task 2: Annotate `country` field in spawn configs with `sms.Country`

**Files:**
- Modify: `framework/group_spawn.lua` — find the `---@field country` line on the spawn-config type alias and update its annotation.
- Modify: `framework/static.lua` — same on the static spawn-config type alias.

**Background for the implementer:**

- Both `group_spawn.lua` and `static.lua` define a LuaCATS `---@class` for their spawn-config table. The `country` field is currently typed as `string` with a comment pointing at `sms.utils.resolve_country`.
- The new `sms.Country` alias declared in `framework/countries.lua` is defined ahead of these files in load order (countries → group_spawn → static), so referencing it is safe.
- The framework still accepts any case-folded string at runtime via `resolve_country` — annotating with `sms.Country` is purely an editor hint. Mission code passing `country = "USA"` keeps working.

- [ ] **Step 2.1: Update `framework/group_spawn.lua`**

Find the existing field annotation:

```lua
---@field country string  # country name (resolved via sms.utils.resolve_country)
```

Replace it with:

```lua
---@field country sms.Country|string  # country name (resolved via sms.utils.resolve_country); pass sms.countries.<KEY> for autocomplete or any case-folded string
```

The `|string` keeps any non-enumerated string accepted by the type checker — `resolve_country` is case-and-space-tolerant, and the runtime drift check covers DCS-additions, so users who write `country = "United Kingdom"` or `country = "usa"` should not get a red squiggle.

- [ ] **Step 2.2: Update `framework/static.lua`**

`static.lua` has the same `---@field country` line on its own static-spawn-config alias (search for `---@field country`). Replace identically:

```lua
---@field country sms.Country|string  # country name (resolved via sms.utils.resolve_country); pass sms.countries.<KEY> for autocomplete or any case-folded string
```

- [ ] **Step 2.3: Commit**

```bash
git add framework/group_spawn.lua framework/static.lua
git commit -m "$(printf 'feat(framework): annotate spawn config country field with sms.Country\n\nLuaCATS hint only; runtime resolve_country still accepts case-folded\nstrings and display variants.\n')"
```

---

## Task 3: Smoke checks for `sms.countries` in `framework/test/smoke.sh`

**Files:**
- Modify: `framework/test/smoke.sh` — append a new `## sms.countries enum` section after the existing `sms.utils.resolve_country` checks.

**Background for the implementer:**

- The smoke harness loads framework files individually via `${DCSSMS} exec --file <file>` and runs assertions via `${DCSSMS} exec --code <lua>`. The pattern is established at the top of `smoke.sh` (load `sms.lua`, `log.lua`, `utils.lua`).
- For this task, after the existing `resolve_country` checks (around line 76), load `countries.lua` then run a few representative checks: identity invariant, well-known key resolution through `resolve_country`, and the size of the table.
- Loose-bridge note: `${DCSSMS} exec --code` returns Lua values JSON-encoded. Numeric returns appear as `"return_value":<n>`, strings as `"return_value":"<s>"`. The existing tests use `grep -q '"return_value":...'` to assert.

- [ ] **Step 3.1: Locate the insertion point in `framework/test/smoke.sh`**

Find the existing line:

```bash
echo "==> sms.utils.resolve_country('united kingdom') case-insensitive + space->underscore"
result=$("${DCSSMS}" exec --code "return sms.utils.resolve_country('united kingdom') == sms.utils.resolve_country('UNITED_KINGDOM')")
echo "${result}" | grep -q '"return_value":true' \
  || { echo "FAIL: expected return_value:true, got: ${result}"; exit 1; }
```

The new block goes immediately after this, before the next `coalition_int_to_str` block.

- [ ] **Step 3.2: Insert the `sms.countries` smoke block**

Insert verbatim:

```bash
echo "==> load framework/countries.lua"
"${DCSSMS}" exec --file countries.lua >/dev/null

echo "==> sms.countries.USA == 'USA' (key/value identity)"
result=$("${DCSSMS}" exec --code "return sms.countries.USA")
echo "${result}" | grep -q '"return_value":"USA"' \
  || { echo "FAIL: expected USA, got: ${result}"; exit 1; }

echo "==> sms.countries.RUSSIA == 'RUSSIA'"
result=$("${DCSSMS}" exec --code "return sms.countries.RUSSIA")
echo "${result}" | grep -q '"return_value":"RUSSIA"' \
  || { echo "FAIL: expected RUSSIA, got: ${result}"; exit 1; }

echo "==> sms.countries.THE_NETHERLANDS round-trips through resolve_country"
result=$("${DCSSMS}" exec --code "return type(sms.utils.resolve_country(sms.countries.THE_NETHERLANDS))")
echo "${result}" | grep -q '"return_value":"number"' \
  || { echo "FAIL: expected number, got: ${result}"; exit 1; }

echo "==> sms.countries.UNKNOWN_COUNTRY is nil (typo guard)"
result=$("${DCSSMS}" exec --code "return tostring(sms.countries.UNKNOWN_COUNTRY)")
echo "${result}" | grep -q '"return_value":"nil"' \
  || { echo "FAIL: expected nil, got: ${result}"; exit 1; }

echo "==> sms.countries has at least 80 entries (sanity)"
result=$("${DCSSMS}" exec --code "local n = 0; for _ in pairs(sms.countries) do n = n + 1 end; return n")
n=$(echo "${result}" | sed -n 's/.*"return_value":\([0-9]*\).*/\1/p')
[ -n "${n}" ] && [ "${n}" -ge 80 ] \
  || { echo "FAIL: expected >=80 entries, got: ${result}"; exit 1; }
```

- [ ] **Step 3.3: Commit**

```bash
git add framework/test/smoke.sh
git commit -m "$(printf 'test(framework): add sms.countries smoke checks\n\nIdentity invariant, round-trip through resolve_country, table size.\n')"
```

---

## Task 4: API reference page `docs/api/countries.md` and module-index update

**Files:**
- Create: `docs/api/countries.md`
- Modify: `docs/api/README.md` — add `countries.md` row to the module-index table.

**Background for the implementer:**

- `docs/api/` follows a tight template described in `docs/api/README.md` ("Page template" section). The countries page is short — there are no functions, just a constant table — so it deviates slightly: section headings cover the table, the alias, the drift check, and a worked example, but the per-function arguments/returns scaffolding is omitted.
- The page must follow the API style conventions in `docs/api/README.md` — examples assume `sms` is loaded; cross-links use relative paths; the failure model link points to AGENTS.md §3.

- [ ] **Step 4.1: Create `docs/api/countries.md`**

Write verbatim:

```markdown
# `sms.countries` — DCS country enum

Hand-maintained table of every well-known DCS `country.id` key, exposed as `sms.countries.<KEY>`. Mission code uses these constants instead of magic-string `country = "USA"` literals — autocomplete in any LuaCATS-aware editor lists every supported country, and a typo (`sms.countries.USAa`) becomes a static type error instead of a runtime resolve failure.

The framework's `country` spawn-config field is annotated with the `sms.Country` alias, so `country = "USA"` literals are typo-checkable in LuaCATS-aware editors too.

All entries follow the invariant `sms.countries.X == "X"` — values are the upper-snake form `country.id` itself uses. `sms.utils.resolve_country` is case-insensitive and folds spaces to underscores, so `country = sms.countries.UNITED_KINGDOM`, `country = "United Kingdom"`, and `country = "united kingdom"` all resolve to the same DCS country int.

## Loading

Requires `sms.lua` and `log.lua`. Loaded automatically by `framework/load_all.lua` after `utils.lua`.

## Usage

```lua
local cap = sms.group.create({
  name     = "blue-cap",
  position = {x = 0, y = 0, z = 0},
  country  = sms.countries.USA,
  category = "airplane",
  units    = { {type = sms.units.planes.FA_18C_hornet, alt = 6000, heading = 90} },
})

local convoy = sms.group.create({
  name     = "red-convoy",
  position = {x = 50000, y = 0, z = 0},
  country  = sms.countries.RUSSIA,
  category = "ground",
  units    = { {type = sms.units.unarmed.Ural_4320T, heading = 270} },
})
```

## The `sms.Country` alias

`sms.Country` is a LuaCATS string alias listing every key in `sms.countries`. The `country` field on `sms.group.create` and `sms.static.create` configs is annotated `sms.Country|string`, so:

- `country = sms.countries.USA` — autocompleted, type-safe.
- `country = "USA"` — accepted, autocompleted from the alias.
- `country = "United Kingdom"` — accepted as `string` (the alias doesn't enumerate display variants); resolves at runtime.
- `country = "USAa"` — accepted as `string` by the type checker, but `resolve_country` returns nil and the spawn fails with a `log.warn` per the [framework failure model](../../AGENTS.md#3-failure-model-log--nil-never-throw).

The `|string` half of the union exists because `resolve_country` is case-and-space-tolerant and we don't want LSP red squiggles on `"united kingdom"`.

## Runtime drift check

DCS occasionally adds new countries (`country.id` keys) between releases. `framework/countries.lua` runs a one-time check at load time:

1. Walk `country.id` keys.
2. For each key not in the static `sms.countries` table, add it to the table at runtime AND log a single `warn` line:

   ```
   [sms.countries] country.id key 'NEW_COUNTRY' not in static list — added at runtime; update framework/countries.lua to keep autocomplete in sync
   ```

This means spawn calls keep working forever — the framework never blocks on a stale country list — but the missing key is visible in `dcs.log` so the static list (and the autocomplete) gets updated when someone notices.

## Why upper-snake?

`country.id` itself is a hash keyed by upper-snake names (`country.id.USA`, `country.id.UNITED_KINGDOM`). Mirroring those keys gives:

- The `sms.countries.X == "X"` invariant — easy to reason about.
- `sms.utils.resolve_country(sms.countries.X)` is identical to `sms.utils.resolve_country("X")` — no surprises.
- Round-trip with `country.id` is trivial; no string-form translation needed.

Display variants like `"United Kingdom"` aren't first-class — `resolve_country` accepts them, but the enum picks the one canonical form.

## Handling unknown countries

There is no `sms.countries.from_int(n)` reverse lookup. If a unit handle gives you a country int and you need a human-readable name, walk `country.id` directly:

```lua
local function name_from_int(n)
  for k, v in pairs(country.id) do
    if v == n then return k end
  end
end
```

This is intentionally not framework code — the use case is rare, the helper is three lines, and inlining keeps the framework surface small.

**See also** — [`sms.utils.resolve_country`](utils.md#smsutilsresolve_countrys--integer--nil) for the runtime resolution helper, [`sms.units`](units.md) for the parallel unit-type catalog, [`sms.group.create`](group.md) for the spawn config that consumes `country`.
```

- [ ] **Step 4.2: Modify `docs/api/README.md`**

Find the module-index table row for `sms.statics`:

```markdown
| [`statics.md`](statics.md) | `sms.statics` | Generated catalog of every static-spawnable DCS type, parallel to `sms.units`. |
```

Insert a new row immediately after it:

```markdown
| [`countries.md`](countries.md) | `sms.countries` | Hand-maintained enum of DCS `country.id` keys; provides autocomplete on `country = sms.countries.<KEY>` spawn configs. |
```

- [ ] **Step 4.3: Commit**

```bash
git add docs/api/countries.md docs/api/README.md
git commit -m "$(printf 'docs(api): add reference page for sms.countries\n\nDescribes the enum table, the sms.Country alias, the runtime drift\ncheck, and the upper-snake naming rationale.\n')"
```

---

## Task 5: AGENTS.md §7 module-index entry and README.md updates

**Files:**
- Modify: `AGENTS.md` — §7 module-index table.
- Modify: `README.md` — "Repo layout" framework module list and the quick-start snippet.

**Background for the implementer:**

- `AGENTS.md` §7 is the single-line module index for cross-cutting reference. Per `CLAUDE.md`, every change that adds a public `sms.*` module must update this table in the same change-set.
- `README.md` "Repo layout" section has a one-line list of every `sms.*` module name; it must include `sms.countries`.
- `README.md` quick-start snippet shows a CAP spawn with `country = "USA"` and `type = "FA-18C_hornet"`. Switch to `country = sms.countries.USA` to demonstrate idiomatic usage. The `type = "FA-18C_hornet"` literal stays — it's already shown as `sms.units.planes.<...>` style elsewhere, but switching it here too would mix two changes in one task.

- [ ] **Step 5.1: Update `AGENTS.md` §7**

Find the row for `sms.statics`:

```markdown
| `sms.statics` | `statics.lua` | [`docs/api/statics.md`](docs/api/statics.md) | Generated catalog of every static-spawnable DCS type, parallel to `sms.units`. |
```

Insert a new row immediately after it:

```markdown
| `sms.countries` | `countries.lua` | [`docs/api/countries.md`](docs/api/countries.md) | Hand-maintained enum of DCS `country.id` keys; provides autocomplete on `country = sms.countries.<KEY>` spawn configs and a `sms.Country` LuaCATS alias for raw-string usage. |
```

- [ ] **Step 5.2: Update `README.md` framework module list**

In the "Repo layout" section, find:

```markdown
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.targets`, `sms.designations`, `sms.group` (+ `sms.spawn` factories), `sms.unit`, `sms.area`, `sms.timer`, `sms.rule`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`, `sms.commands`, `sms.options`. See [`AGENTS.md`](AGENTS.md) for cross-cutting rules and conventions, or [`docs/api/`](docs/api/) for per-function detail.
```

Add `sms.countries`, `sms.units`, and `sms.statics` if they're not already in the list. Note that `sms.units` and `sms.statics` exist in §7 of AGENTS but may be missing from the README short list; check before editing. The post-edit line:

```markdown
- `framework/` — in-DCS Lua framework. Modules: `sms`, `sms.log`, `sms.utils`, `sms.countries`, `sms.units`, `sms.statics`, `sms.targets`, `sms.designations`, `sms.group` (+ `sms.spawn` factories), `sms.unit`, `sms.area`, `sms.timer`, `sms.rule`, `sms.static`, `sms.events`, `sms.weapon`, `sms.task`, `sms.commands`, `sms.options`. See [`AGENTS.md`](AGENTS.md) for cross-cutting rules and conventions, or [`docs/api/`](docs/api/) for per-function detail.
```

If `sms.units` and `sms.statics` are already there, leave them and just add `sms.countries` between `sms.utils` and the others.

- [ ] **Step 5.3: Sweep the `README.md` quick-start snippet**

Find the quick-start CAP example (around lines 36–48):

```lua
local cap = sms.group.create({
  name = "f18-cap",
  position = {x = 0, y = 0, z = 0},
  country = "USA",
  category = "airplane",
  units = { {type = "FA-18C_hornet", alt = 6000, heading = 90} },
})
```

Replace `country = "USA"` with `country = sms.countries.USA`. Leave the rest alone:

```lua
local cap = sms.group.create({
  name = "f18-cap",
  position = {x = 0, y = 0, z = 0},
  country = sms.countries.USA,
  category = "airplane",
  units = { {type = "FA-18C_hornet", alt = 6000, heading = 90} },
})
```

- [ ] **Step 5.4: Commit**

```bash
git add AGENTS.md README.md
git commit -m "$(printf 'docs(framework): add sms.countries to AGENTS.md module index and README\n\nAlso sweep README quick-start to use sms.countries.USA.\n')"
```

---

## Task 6: Sweep `docs/api/examples.md` to use `sms.countries.*`

**Files:**
- Modify: `docs/api/examples.md` — replace `country = "USA"` and `country = "RUSSIA"` literals across all recipes that contain them.

**Background for the implementer:**

- `docs/api/examples.md` is the cross-module recipe cookbook. Recipes 1, 4, 5 contain `country = "USA"` / `country = "RUSSIA"` literals. (Recipes 6, 7, 8 don't spawn aircraft and have no country fields.)
- Per spec **Decision D5**, the per-module reference pages (`group.md`, `static.md`) intentionally keep raw-string examples to anchor the cross-link to `resolve_country`. Don't touch those.
- All `country` references in `examples.md` are inside `sms.group.create({...})` blocks. There are five total: two `"USA"` and one `"RUSSIA"` in recipe 1, one `"USA"` in recipe 4, two `"USA"` in recipe 5 (one for AWACS, one for tanker).

- [ ] **Step 6.1: Replace `country = "USA"` instances in examples.md**

In `docs/api/examples.md`, replace every line of the form:

```
  country  = "USA",
```

with:

```
  country  = sms.countries.USA,
```

Use a single `replace_all` edit since the indentation and spacing are uniform across recipes.

- [ ] **Step 6.2: Replace `country = "RUSSIA"` instance in examples.md**

Replace:

```
  country  = "RUSSIA",
```

with:

```
  country  = sms.countries.RUSSIA,
```

Single occurrence (recipe 1, red CAP).

- [ ] **Step 6.3: Verify no other country literals remain in examples.md**

Run a grep to confirm no `country = "..."` literals survived:

```bash
grep -n 'country\s*=\s*"' docs/api/examples.md && echo "FOUND LITERALS — investigate" || echo "clean"
```

Expected: `clean`.

- [ ] **Step 6.4: Commit**

```bash
git add docs/api/examples.md
git commit -m "$(printf 'docs(api): use sms.countries enums in examples.md spawn configs\n\nRecipes 1, 4, 5 — country = "USA" / "RUSSIA" literals replaced with\nsms.countries.USA / sms.countries.RUSSIA. Per-module reference pages\n(group.md, static.md) intentionally keep raw-string forms.\n')"
```

---

## Self-review

**Spec coverage check:**

| Spec scope item | Plan task |
|---|---|
| 1. New module `framework/countries.lua` | Task 1 |
| 2. Runtime drift check | Task 1 |
| 3. LuaCATS class + alias | Task 1 |
| 4. `framework/load_all.lua` wiring | Task 1 |
| 5. `country` field annotation on group_spawn / static | Task 2 |
| 6. Smoke checks | Task 3 |
| 7. `docs/api/countries.md` | Task 4 |
| 8. `docs/api/README.md` row | Task 4 |
| 9. AGENTS.md §7 row | Task 5 |
| 10. README.md module list | Task 5 |
| 11. Sweep `examples.md` | Task 6 |
| 12. Sweep README quick-start | Task 5 |

All 12 spec scope items map to a task.

**Placeholder scan:**

No "TBD" / "TODO" / "implement later" / "fill in details" / "similar to Task N" / vague "add error handling" / "write tests for the above" without code.

**Type / signature consistency:**

- `sms.countries` is a flat table with `<KEY> = "<KEY>"` entries — used identically across Tasks 1, 3, 4, 6.
- `sms.Country` LuaCATS alias defined once in Task 1, referenced consistently in Tasks 2 and 4.
- Module load order — countries.lua loaded after utils.lua and before units.lua / group_spawn.lua — applied consistently in Task 1 and assumed in Task 2.

No drift.
