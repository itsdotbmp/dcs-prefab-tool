# `me trigger` verb family — design

**Status**: design (ready for implementation plan)
**Date**: 2026-05-09
**Branch**: `feat/me-execution-bridge`
**Reference mission**: `D:\git\honu\claude_example.miz` — kitchen-sink trigger exercising every predicate

## Goal

Add a `me trigger` verb family to the dcs-sms ME bridge so users (humans and AI agents) can read, build, and modify mission triggers from outside the ME panel. Existing surface as of branch HEAD: 66 verbs across `file` / `group` / `unit` / `zone` / `drawing`. Triggers are the largest unmodeled subsystem.

## User value

Today: building / inspecting triggers requires opening the ME's Trigger Rules panel and clicking through dropdowns and field-by-field inputs. There's no programmatic path for either humans (who have to remember exact `c_*` / `a_*` names and field schemas) or AI agents (who have to read ED's Lua to learn the vocabulary). After this feature: a single discoverable CLI surface lets you list every predicate ED knows about, read existing triggers in human-readable form, and build new triggers from a script or one-liner. The composable shape works equally well for shell pipelines and AI-driven mission construction.

## Scope

### In

- Read verbs: `list`, `get`, `list-predicates`, `describe-predicate` (the last two backed by ED's runtime descriptor tables — no hardcoded vocabulary)
- Mutate verbs: `create` (with optional bundled `--condition` / `--action` repeatable strings), `remove`, `set-name`, `set-eventlist`, `add-condition`, `add-action`, `remove-condition`, `remove-action`
- Friendly kebab-case alias resolution (`flag-is-true` ↔ `c_flag_is_true`; `continuous` ↔ `triggerContinious`)
- Reference resolution: groups, units, zones accept either id or name; coalition strings pass through
- Dictionary-key handling: text fields accept literals on write, return literals on read
- Best-effort trigger-panel refresh after mutations (so the panel reflects external edits without manual close/reopen)

### Out

- Pre-canned trigger templates / shortcuts (e.g. `create-time-message`). The composable builder covers them.
- Reordering conditions or actions in place. v1 is append-only.
- Per-trigger enable/disable flag. ED's runtime `mission.trig.flag[i]` is regenerated from `trigrules` on save and tracks presence; there's no separate enable/disable concept at the editor level.
- A repo-committed predicate dump (would drift; runtime verbs cover the use case).
- `//go:embed` of predicate metadata into the Go binary (YAGNI for v1; runtime + repo-readable spec covers all known consumers).

## Constraints

- **Save-survival**: every mutation must leave `mission.trigrules` in a state that ED's `unload()` codegen at `me_mission.lua:4592–4598` can serialize. Verb-time validation guarantees this — predicate must exist in `predicates.descrs`, fields validated against schema, references resolved.
- **No ED Lua patches**: the mod is dropped into a vanilla DCS install. We can call exported functions from `me_trigrules.lua` and `me_mission.lua` but not modify them.
- **AGENTS.md §11 versioning**: this is public-surface change → bump `tools/me-mod/lua/dcs_sms_me/version.lua` and add a CHANGELOG entry in the same change-set as code. No `AGENTS.md` §7 update — that section indexes framework `sms.*` modules, not ME-mod verbs.
- **Loose coupling to ED internals**: the descriptor walker and friendly-alias map are derived from ED's tables at runtime, so a future DCS version that adds predicates is automatically supported. We don't hardcode any predicate name.

## Decisions

The following choices were made during brainstorming. Each is recorded so a future agent reading this spec without conversation context can understand the rationale.

1. **Composable builder over curated subset or generic JSON-spec.** Full ~175-predicate surface is supported via descriptor-driven validation (zero hardcoded predicate list). `me trigger create` returns a name; `me trigger add-condition` / `add-action` extend it. A bundled-create form (`--condition`/`--action` repeatable strings) is sugar for the composable sequence, useful for one-shot scripts.

2. **Triggers identified by `comment` field, surfaced as `--name`.** ED already uses `comment` as the trigger's display name in its panel. Auto-suffix on collision (`-2`, `-3`, …) like the existing `me group create-*` verbs. No `--id` flag; positional indices in `trigrules[]` aren't stable across removes / saves.

3. **All ~175 predicates accepted, validated against ED's `predicates.descrs` at runtime.** Discoverability via two read verbs (`list-predicates`, `describe-predicate`) that surface the descriptor tables as JSON. No curated subset; no hand-tuned per-predicate flag schemas. Trade: error messages are slightly more generic ("unknown field 'foo' for predicate c_unit_dead") but the surface scales automatically with ED updates.

4. **Friendly kebab-case aliases accepted alongside canonical names.** Algorithm: strip `c_`/`a_`/`trigger` prefix → underscore-to-dash, lowercase. Special-case: `continuous` is the alias for ED's `triggerContinious` (typo intentional in DCS — we do not propagate). If a future ED version introduces `c_foo` and `a_foo` simultaneously, the bare alias `foo` becomes ambiguous and is rejected with an error listing both canonicals.

5. **Discoverability is runtime-only — no repo-committed dump.** The runtime verbs `list-predicates` / `describe-predicate` query ED at call time, always current to the user's installed DCS version (incl. modded predicates). A committed JSON would drift on DCS updates. No `//go:embed` either — solving an offline-without-DCS case nobody is asking about.

6. **Field values passed as positional `key=value` pairs after known flags.** `me trigger add-condition --trigger T --predicate unit-in-zone unit=5 zone=120`. Go's `flag` package parses `--trigger` / `--predicate`, the rest is walked as `<k>=<v>` pairs. Type coercion happens in Lua against the descriptor (number / string / bool). Array values use comma-separated form: `typebomb=4,5,9,285`. Bundled `--condition "..."` / `--action "..."` forms parse the same syntax inside a single quoted argv slot; values with literal spaces need shell quoting (`text='Hello World'`) or fall back to the composable form.

7. **References (group / unit / zone) accept either int-id or name-string.** Detection in Lua: descriptor's `comboFunc` slot identifies the reference type (`groupsLister` / `unitsLister` / `zoneLister` / `coalitionLister` / etc.). If the value parses as an integer, treat as id; else look up by name. Coalition fields take strings verbatim (`red`/`blue`/`neutrals`/`all`). Other reference types (airdrome, helipad) — id-only for v1; `list-predicates` documents this.

8. **Dictionary-key text fields: literal-in, literal-out.** Action fields like `text` on `a_out_text_delay` store a `DictKey_*` reference in `trigrules` with a `KeyDict_<fieldname>` companion. The Lua side detects them via the companion-field convention; on write, allocates a fresh dict key (via the ED helper, exact name confirmed at code time); on read (`get`), resolves the key back to the literal so users see real text. `get --raw` returns the on-disk shape verbatim for debugging.

9. **Trigger panel refresh: option B (best-effort `show(false)` + `show(true)`).** ED's panel rebinds the listbox via `setupCallbacks` whenever `Trigger.show(true)` is called. After a mutation, if the panel is visible, force a re-bind. Visibility detection probes `Trigger.triggersWindow:isVisible()` if reachable; falls back to a no-op if the field is module-local-scope (consistent with v1 limitation that other panels in the codebase share).

10. **12 flat (noun, verb) pairs; 13 Go files including one shared parsing helper.** Mirrors the dominant precedent (`me_zone_set_*.go`, `me_drawing_set_*.go`). No sub-dispatch (the `me unit payload` shape is a known-bad outlier — see issue #42).

11. **Lua surface stays in `verbs.lua`.** Consistent with the existing 66-verb pattern (zones / drawings / groups / units / payloads all colocated). If the trigger-helpers section grows past ~300 lines, the implementation plan can extract a private helper module (`dcs_sms_me/triggers.lua`); decision deferred until we see the actual line count.

## Open questions

(none — implementation can proceed; small unknowns are deferred to the plan, see "Open implementation details" below)

## Non-goals

- Pre-canned trigger templates (e.g. "create-time-message"). The composable builder covers them; templating is a follow-up if patterns emerge.
- Reordering conditions / actions in place. v1 is append-only; reordering = remove + add.
- Trigger enable/disable. Triggers exist or don't; ED's runtime `mission.trig.flag[i]` is regenerated from `trigrules` at save and tracks presence, not user-facing enabled state.
- A pre-generated, repo-committed predicate dump. Discoverability is runtime-only via verbs.

## Data shape (recap)

`mission.trigrules` is the editor source-of-truth. Each entry:

```lua
{
  predicate = "triggerOnce" | "triggerContinious" | "triggerStart" | "triggerFront",
  comment   = "<user-facing name>",
  eventlist = "" | <event id>,
  rules     = { { predicate = "c_*", ...field args... }, ... },
  actions   = { { predicate = "a_*", ...field args... }, ... },
}
```

At save, `me_mission.unload` regenerates `mission.trig.{conditions,actions,func,events,funcStartup}` from `trigrules` (`me_mission.lua:4592–4598`). So mutating `trigrules` is sufficient — we never touch `mission.trig.*` directly.

Vocabulary scale: 4 trigger types, ~75 condition predicates (`c_*`), ~100 action predicates (`a_*`). Each has a per-predicate field schema in `me_trigrules.predicates.descrs` and `triggersDescr`.

## Verb surface

12 verbs, flat (noun, verb) pairs (matching the dominant CLI convention; no sub-dispatch):

```
me trigger list
me trigger get  --name X  [--raw]
me trigger list-predicates       [--kind condition|action|trigger] [--search <substr>]
me trigger describe-predicate    --name <c_*|a_*|alias>

me trigger create  --type once|continuous|start|front --name N
                   [--condition "<predicate> k=v..."]   (repeatable)
                   [--action    "<predicate> k=v..."]   (repeatable)
me trigger remove  --name N
me trigger set-name      --name X --to Y
me trigger set-eventlist --name X --event E

me trigger add-condition    --trigger T --predicate P [k=v ...]
me trigger add-action       --trigger T --predicate P [k=v ...]
me trigger remove-condition --trigger T --index N
me trigger remove-action    --trigger T --index N
```

### Identification

Triggers are addressed by their `comment` field, surfaced as `--name` everywhere. Names must be unique per mission; on `create` collision, auto-suffix `-2`, `-3`, … (matches `me group create-*` collision behavior). The default name when `--name` is omitted matches ED's: `Trigger <epoch-seconds>`.

### Predicate names — canonical and alias

Both forms accepted anywhere a predicate is required:

| Canonical | Alias |
|---|---|
| `c_flag_is_true` | `flag-is-true` |
| `a_set_flag` | `set-flag` |
| `triggerOnce` | `once` |
| `triggerContinious` | `continuous` |

Algorithm: strip `c_` / `a_` / `trigger` prefix → underscore-to-dash, lowercase. The `triggerContinious` typo gets a fixed alias (`continuous`) — we don't propagate ED's misspelling to users. If a future ED release introduces `c_foo` and `a_foo` simultaneously, `foo` becomes ambiguous and is rejected with an error listing both canonicals; this can't happen today (no overlaps).

### Field passing — positional `key=value`

```sh
me trigger add-condition --trigger T --predicate unit-in-zone unit=5 zone=120
me trigger add-action    --trigger T --predicate set-flag flag=F2 value=true
```

Known flags (`--trigger`, `--predicate`, etc.) are parsed by Go's `flag` package. Remaining args are walked as `<key>=<value>` pairs and passed to Lua as a `fields` table. Type coercion happens in Lua against the descriptor (number / string / bool / array). Array values use comma-separated form: `typebomb=4,5,9,285`.

The bundled-create form (`--condition "..."` / `--action "..."`) accepts the same `<predicate> <k>=<v>...` tokens as a single string, parsed by the same shared helper. Limitation: values containing literal spaces (e.g. message text "Hello World") need shell quoting (`text='Hello World'`) or fall back to the composable form, where each verb invocation gets its own argv slot.

### Reference resolution (group / unit / zone / coalition)

ED's descriptor table tags each field's referent type via the `comboFunc` slot (`groupsLister`, `unitsLister`, `zoneLister`, `coalitionLister`, `airdromeAndHeliportLister`, …). The Lua side detects type from there:

```
group / unit / zone field:
   value parses as integer  → use as id
   value is string          → look up by name (groupId / unitId / zoneId)
   neither resolves         → error

coalition field:
   "red" / "blue" / "neutrals" / "all" verbatim

dictionary text field (companion KeyDict_<fieldname>):
   on add — allocate via Mission.addDictKey(text), store key in trigrules
   on get — resolve key back to literal text

other (flag / value / percent / time / etc.):
   pass through with descriptor-driven coercion
```

So both `unit=5` and `unit=DemoPayload-1` work.

### Read verbs

`me trigger list` — compact one-row-per-trigger:

```json
{
  "ok": true,
  "count": 2,
  "triggers": [
    {"name": "Trigger 1717123456", "type": "once",       "conditions": 73, "actions": 41, "eventlist": ""},
    {"name": "MyTrig",             "type": "continuous", "conditions": 2,  "actions": 2,  "eventlist": ""}
  ]
}
```

`me trigger get --name MyTrig` — full expansion with reference enrichment and dict-key resolution:

```json
{
  "ok": true,
  "name": "MyTrig",
  "type": "continuous",
  "eventlist": "",
  "conditions": [
    {"index": 1, "predicate": "c_flag_is_true",    "alias": "flag-is-true",
     "fields": {"flag": "F1"}},
    {"index": 2, "predicate": "c_unit_in_zone",    "alias": "unit-in-zone",
     "fields": {"unit": 5, "unit_name": "DemoPayload-1",
                "zone": 120, "zone_name": "MyZone"}}
  ],
  "actions": [
    {"index": 1, "predicate": "a_set_flag",        "alias": "set-flag",
     "fields": {"flag": "F2", "value": true}},
    {"index": 2, "predicate": "a_out_text_delay",  "alias": "out-text-delay",
     "fields": {"text": "Hello", "displayTime": 10, "clearview": false, "start_delay": 0}}
  ]
}
```

`--raw` returns the trigrules entry verbatim (DictKey strings, no name enrichment) for debugging on-disk state.

`me trigger list-predicates` — dumps every predicate ED knows about, complete with field schema and a generated CLI usage example:

```json
{
  "ok": true,
  "predicates": [
    {
      "name": "c_flag_is_true",
      "alias": "flag-is-true",
      "kind": "condition",
      "display": "FLAG TRUE",
      "fields": [{"id": "flag", "type": "edit", "default": ""}],
      "example": "me trigger add-condition --trigger T --predicate flag-is-true flag=F1"
    },
    ...
  ]
}
```

`me trigger describe-predicate --name <P>` returns a single entry in the same shape — for when an agent has narrowed to one predicate.

## Implementation

### Lua side — `tools/me-mod/lua/dcs_sms_me/verbs.lua`

Extends the existing module. Adds:

- A "Trigger helpers" block at the top of a new section (~150 lines): descriptor walker, friendly-alias map (lazy-cached), field type coercion, `_resolve_trigger_ref(field, value, kind)` for group/unit/zone/coalition, dict-key allocator wrapper, panel-refresh kick.
- 13 public `M.trigger_*` verbs delegating to those helpers.

The descriptor walker reads ED's `predicates.descrs` and `triggersDescr` once per session and merges them into a single `{predicate_name → field_schema, kind}` map. The friendly alias map (`{flag-is-true → c_flag_is_true, ...}`) is built from the same source.

Trigger creation reuses ED's `Trigger.createTrigger(descr)` and `Trigger.createAction(descr)` / `Trigger.createRule(descr)` constructors directly — no reimplementation of field default population. Argument validation happens before the constructors run; reference resolution and dict-key allocation happen after the field set is validated.

### Go side — `tools/cmd/dcs-sms/`

12 verb files, one per verb, mirroring `me_zone_set_*.go` / `me_drawing_set_*.go` precedent. Plus one shared helper file `me_trigger_args.go` for the positional `key=value` parse used by `add-condition`, `add-action`, and the bundled forms on `create` (13 files total).

```
me_trigger_args.go              shared helpers (parse, escape, build Lua expr)
me_trigger_list.go
me_trigger_get.go
me_trigger_list_predicates.go
me_trigger_describe_predicate.go
me_trigger_create.go
me_trigger_remove.go
me_trigger_set_name.go
me_trigger_set_eventlist.go
me_trigger_add_condition.go
me_trigger_add_action.go
me_trigger_remove_condition.go
me_trigger_remove_action.go
```

### Data flow (one verb invocation)

```
CLI: me trigger add-condition --trigger MyTrig --predicate flag-is-true flag=F1
    │
    ├─ Go parses known flags, walks remaining args as k=v pairs
    │  → builds Lua expr: { trigger="MyTrig", predicate="flag-is-true", fields={flag="F1"} }
    │
    ├─ runMeVerb dispatches via gui bridge to verbs.trigger_add_condition(args)
    │
verbs.trigger_add_condition:
    1. Resolve "flag-is-true" → "c_flag_is_true" (friendly-alias map)
    2. Walk descrs["c_flag_is_true"].fields — validate {flag} is allowed, no required missing
    3. Coerce values per descriptor type; resolve group/unit/zone names if any; allocate dict keys for text fields
    4. Find trigger by comment field; refuse if not unique
    5. table.insert(trigger.rules, {predicate="c_flag_is_true", flag="F1"})
    6. Best-effort panel refresh kick (see "UI panel refresh" below)
    7. Return { ok=true, trigger="MyTrig", index=N, predicate="c_flag_is_true" }
```

## Edge cases

### Dictionary-key allocation

Action predicates with text fields — `a_out_text_delay`, `a_mark_to_all`, `a_end_mission`, etc. — store a `DictKey_*` reference in trigrules with a `KeyDict_<fieldname>` companion. The user passes literal text; the Lua side allocates via ED's `Mission.addDictKey` (or equivalent — exact name to be confirmed at code time) and writes both `<field>` and `KeyDict_<field>` to the trigrules entry. On `get`, dict keys are resolved back to literals so the output is human-readable.

### Save survival

Trigrules → `mission.trig.*` codegen happens unconditionally inside `unload()` at `me_mission.lua:4592–4598`. Verb-time validation guarantees we only insert well-formed entries (known predicate, valid fields, resolved references), so save can never crash on our additions. The `--reopen=false` escape hatch for save crashes is unaffected.

### UI panel refresh

When a verb mutates `trigrules` while the trigger panel is open, the panel's listbox bindings go stale. ED's `me_trigrules.show(b)` rebinds the listbox to current trigrules via `setupCallbacks` whenever called with `true`.

Best-effort refresh: after the mutation, if the panel is currently visible, call `Trigger.show(false); Trigger.show(true)` to force a re-bind. Visibility detection: probe `Trigger.triggersWindow:isVisible()` if exposed at module level; if the field is local-scope and unreachable, fall back to a no-op (consistent with v1 limitation that other panels in the codebase share). The exact probing mechanism is an implementation detail — confirmed at code time by trying both reachable-state probes and unconditional close-reopen.

### Descriptor cache

`predicates.descrs` and `triggersDescr` are loaded once per ME launch and don't change. The Lua-side helper module caches the merged friendly-alias map and field schema on first call. Cache invalidation is not needed (table references are stable across mission load/save).

### Concurrency

The bridge polls one verb at a time. No intra-verb concurrency to worry about.

## Testing

Manual end-to-end against the live bridge (consistent with how the existing 66 verbs were validated):

1. Load `claude_example.miz` (or run against the live ME with the demo groups still in place).
2. `me trigger list` — confirm the existing 2 triggers show up with the right counts.
3. `me trigger get --name "<existing trigger name>"` — confirm the rendered output is sane and dict keys resolve.
4. `me trigger create --type continuous --name TestT` followed by `me trigger get` — verify a fresh empty trigger.
5. `me trigger add-condition --trigger TestT --predicate flag-is-true flag=F1` and `add-action --trigger TestT --predicate set-flag flag=F2 value=true`.
6. Save-as round-trip with `--reopen=true` — confirm the trigger persists and reloads cleanly.
7. Remove the test trigger; confirm `list` count goes back to baseline.
8. `list-predicates --kind condition --search flag` and `--kind action --search flag` — verify discoverability.

No automated tests in CI (consistent with the rest of the ME-mod surface — CI doesn't have a DCS install).

## Out of scope (explicit non-goals — repeated)

- Pre-canned trigger templates / shortcuts.
- Reordering conditions or actions in place.
- Enable/disable per trigger.
- Repo-committed predicate dump.

## Versioning impact

Per `AGENTS.md` §11, public-surface changes bump `tools/me-mod/lua/dcs_sms_me/version.lua` and add a CHANGELOG entry in the same commit-set as the code change. The implementation plan must include this as a concrete task, not a follow-up.

No `AGENTS.md` §7 update — that section indexes the framework `sms.*` modules, not ME-mod verbs. Triggers are ME-mod surface; CHANGELOG and version bump are the only doc touchpoints.

## Open implementation details (deferred to plan)

- Exact ED API name for dictionary-key allocation (`Mission.addDictKey` is the working assumption; confirm at code time).
- Trigger panel visibility-detection mechanism (probe `triggersWindow:isVisible()` if reachable; fallback strategy if not).
- Whether the trigger-helpers block in `verbs.lua` should be factored to a separate `dcs_sms_me/triggers.lua` module if the line count justifies it (decide post-implementation by file size).
