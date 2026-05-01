# `sms.countries` enum — design spec

**Status:** approved (auto-approved via `/write-it`, 2026-05-01)
**Branch:** `feat/sms-countries`
**Worktree:** `.worktrees/sms-countries`

## Goal

Add an `sms.countries` enum table with one entry per DCS `country.id` key, so mission code can write `country = sms.countries.USA` instead of the magic string `country = "USA"`. Mirrors the editor-ergonomics value of `sms.units` for the spawn-config `country` field.

## User value

Today, `sms.group.create({country = "USA", ...})` and `sms.static.create({country = "RUSSIA", ...})` accept any string and pass it through `sms.utils.resolve_country` (case-insensitive, space-to-underscore). That works at runtime but gives:

- **No autocomplete.** Authors don't know what countries exist without grepping DCS docs.
- **Silent typos at the framework boundary.** `country = "USAa"` reaches `resolve_country`, which returns `nil`, which `sms.group.create` reports — but only at runtime, only after the spawn attempt.
- **No editor type-checking.** A LuaCATS-aware editor cannot warn on a misspelled string.

After this work:

- `sms.countries.USA` resolves to `"USA"`. Autocomplete in any LuaCATS-aware editor lists every supported country.
- `sms.countries.UNITED_KINGDOM` resolves to `"UNITED_KINGDOM"` (the upper-snake form `country.id` itself uses).
- A LuaCATS `---@alias sms.Country` makes raw string literals on the `country` spawn-config field typo-checkable too — the enum isn't the only path that gets editor protection.
- `examples.md` and `README.md` quick-start use the enum, so users learn the recommended form by reading docs.

## Scope

### In scope

1. New module `framework/countries.lua` exposing `sms.countries.<KEY> = "<KEY>"` for every well-known DCS `country.id` key.
2. Runtime drift check at the bottom of `countries.lua`: walk `country.id` keys, log a `warn` for any key not in `sms.countries`, and add it to the table at runtime so spawn calls still work even if a future DCS update introduces a country we haven't catalogued.
3. LuaCATS `---@class sms.countries` field annotations + `---@alias sms.Country` listing every key, so editors give autocomplete for both `sms.countries.<KEY>` and `country = "..."` literal usage.
4. Update `framework/load_all.lua` to load `countries.lua` (after `utils.lua`, so the runtime drift check runs after `log` is available).
5. Update `framework/group_spawn.lua` and `framework/static.lua` so the `country` field on `create` configs is annotated with the new `sms.Country` alias.
6. Update `framework/test/smoke.sh` to verify a representative subset of `sms.countries.<KEY>` values resolve correctly via `sms.utils.resolve_country` and that the table is populated.
7. New API doc page `docs/api/countries.md`.
8. Update `docs/api/README.md` module-index table to add the `countries.md` row.
9. Update `AGENTS.md` §7 module-index table to add `sms.countries`.
10. Update `README.md` "Repo layout" framework module list to mention `sms.countries`.
11. Sweep `docs/api/examples.md` to replace `country = "USA"` / `country = "RUSSIA"` literals with `sms.countries.USA` / `sms.countries.RUSSIA`.
12. Sweep `README.md` quick-start snippet (the F-18 CAP example) to use `sms.countries.USA`.

### Out of scope

- A code generator (`gen-countries`) parallel to `gen-units`. The country list is bounded (~90 entries) and stable across DCS releases. Hand-maintenance plus a runtime drift warning is sufficient.
- Numeric ID exposure (`sms.countries.USA_ID = 2`). Mission code uses strings; the integer is an internal DCS concept and `sms.utils.resolve_country` already exposes it for callers who need it.
- A reverse lookup helper (`sms.countries.from_int(2) → "USA"`). Trivial follow-up if a use case appears; YAGNI now.
- Display-name forms (`"United Kingdom"`). `sms.utils.resolve_country` already accepts that form via the space-to-underscore fold; no need to expose two forms in the enum.
- Sweep of `docs/api/<other modules>.md` example snippets where `country = "USA"` appears (group.md, static.md). Those pages document the spawn-config schema, not idiomatic use, so leaving them as raw strings is fine; their `country` row already cross-links to `resolve_country`. **Decision D5** addresses this.

## Constraints

- **Lua 5.1.** The generated file runs inside the DCS mission environment.
- **Idempotent load.** `sms.countries = sms.countries or {}` so reloading the module doesn't clobber any consumer's local references.
- **No throws.** The runtime drift check must not raise. If `country` global is somehow missing or `country.id` isn't a table (running outside DCS), the check is a silent no-op.
- **Failure model.** Per [`AGENTS.md` §3](../../../AGENTS.md#3-failure-model-log--nil-never-throw): no public function on this module logs at error or returns nil for caller misuse — there are no public functions, just the table. The drift warning is `log.warn` exactly once at load time.
- **Drop-in.** Existing call sites (`country = "USA"`) continue to work. The framework's `resolve_country` accepts both forms.

## Decisions

### D1 — Module name: `sms.countries` (plural)

Matches the conventions of `sms.targets`, `sms.designations`, `sms.statics`, `sms.units` — every existing dcs-sms enum/catalog module is plural-noun-named.

### D2 — Enum layout: flat single-level

`sms.countries.USA = "USA"` — no sub-categorization. Countries don't have an obvious mission-relevant hierarchy (NATO/Warsaw/etc. is a coalition concept, not a country one), and a flat namespace matches `sms.targets`. The two-level structure of `sms.units.armor.tanks` is justified by hundreds of unit types per top-level bucket; for ~90 countries flat is fine.

### D3 — Value strings are upper-snake (`"USA"`, `"UNITED_KINGDOM"`)

`sms.utils.resolve_country` accepts `"USA"`, `"usa"`, and `"United Kingdom"` — all three round-trip. The canonical form that round-trips losslessly **and** matches `country.id`'s own keys is upper-snake. Using that form gives the invariant `sms.countries.X == "X"`, which is easy to reason about and matches `sms.targets` (`sms.targets.AIR == "Air"` — wait, `targets` uses Title Case because that's the form DCS expects; for countries the canonical is upper-snake).

### D4 — Hand-maintained file with runtime drift check

No `gen-countries` tool. The list is small and stable. The runtime drift check at the end of `countries.lua` walks `country.id` keys; if any are missing from `sms.countries`, it (a) adds them to the table at runtime so spawn calls still work, and (b) logs a single `warn` per missing key naming the keys so future-us / agents see the gap and update the static list.

### D5 — Sweep scope: `examples.md` and `README.md` only

The `docs/api/examples.md` cookbook and the `README.md` quick-start are the canonical "this is how mission code looks" surfaces, so they switch to `sms.countries.X`. The per-module reference pages (`docs/api/group.md`, `docs/api/static.md`) document the spawn-config schema and intentionally show the raw-string form so the cross-link to `sms.utils.resolve_country` makes sense; leaving those alone is consistent with how those pages already treat `country`.

### D6 — LuaCATS double form: `---@class sms.countries` field list **and** `---@alias sms.Country`

The `sms.countries` class fields drive autocomplete on `sms.countries.<KEY>` access. The `sms.Country` alias drives autocomplete and literal-string typo-checking on the `country` field of spawn configs. Both forms are populated from the same hand-list and stay in sync because they live in the same file under the same `_known` array.

### D7 — Country list source

The hand-list is seeded from the well-known DCS `country.id` enumeration as documented in:
- DCS Eagle Dynamics Lua scripting reference (`country.id` table).
- Hoggit DCS World wiki (`DCS_enum_country` page) — the most-cited public mirror of the enum.

The list as of 2026-05-01 (94 entries):

```
RUSSIA, UKRAINE, USA, TURKEY, UK, FRANCE, GERMANY, USAF_AGGRESSORS,
CANADA, SPAIN, THE_NETHERLANDS, BELGIUM, NORWAY, DENMARK, ISRAEL,
GEORGIA, INSURGENTS, ABKHAZIA, SOUTH_OSETIA, ITALY, AUSTRALIA,
SWITZERLAND, AUSTRIA, BELARUS, BULGARIA, CHEZH_REPUBLIC, CHINA,
CROATIA, EGYPT, FINLAND, GREECE, HUNGARY, INDIA, IRAN, IRAQ,
JAPAN, KAZAKHSTAN, NORTH_KOREA, PAKISTAN, POLAND, ROMANIA,
SAUDI_ARABIA, SERBIA, SLOVAKIA, SOUTH_KOREA, SWEDEN, SYRIA,
YEMEN, VIETNAM, VENEZUELA, TUNISIA, THAILAND, SUDAN, PHILIPPINES,
MOROCCO, MEXICO, MALAYSIA, LIBYA, JORDAN, INDONESIA, HONDURAS,
ETHIOPIA, CHILE, BRAZIL, BAHRAIN, THIRDREICH, YUGOSLAVIA, USSR,
ITALIAN_SOCIAL_REPUBLIC, ALGERIA, KUWAIT, QATAR, OMAN, UAE,
SOUTH_AFRICA, CUBA, PORTUGAL, GDR, LEBANON, CJTF_BLUE, CJTF_RED,
UN_PEACEKEEPERS, ARGENTINA, CYPRUS, SLOVENIA, BOLIVIA, GHANA,
NIGERIA, PERU, ECUADOR, ESTONIA, LATVIA, LITHUANIA, URUGUAY
```

Some keys use DCS's own (occasionally-misspelled) form — `CHEZH_REPUBLIC` rather than `CZECH_REPUBLIC`, `THIRDREICH` rather than `THIRD_REICH`. The framework mirrors what `country.id` actually exposes; correcting DCS's spelling would defeat the round-trip invariant. Keys the runtime drift check finds at load time and the user adds to the static list later are equally welcome.

### D8 — Drift warning format

Single `log.warn` line per missing key:

```
[sms.countries] country.id key '<KEY>' not in static list — added at runtime; update framework/countries.lua to keep autocomplete in sync
```

This is loud enough to surface in a normal `dcs.log` scan, quiet enough to not flood when DCS introduces multiple new countries in one update.

## Open questions

(none)
