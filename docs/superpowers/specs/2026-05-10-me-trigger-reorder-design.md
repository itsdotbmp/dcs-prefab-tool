# `me trigger reorder*` verbs — design

**Status**: design (ready for implementation plan)
**Date**: 2026-05-10
**Branch**: `feat/me-execution-bridge`
**Predecessor**: [`2026-05-09-me-trigger-verbs-design.md`](2026-05-09-me-trigger-verbs-design.md) — adds the rest of the trigger surface

## Goal

Fill the one obvious gap in the `me trigger` verb family: reordering. The composable builder shipped in the v1 trigger work is append-only — once a trigger / condition / action exists, there's no programmatic way to move it. ED's UI has Up/Down buttons for all three lists; we don't.

The trigger order matters because mission scripts run trigger conditions in `mission.trig.func[idx]` order on every tick — reorder changes evaluation order. Order also matters cosmetically (sorting by topic in the panel). Encountered in practice when an agent tried to insert a new trigger before an existing one and had no way to do it.

## Scope

### In

- `me trigger reorder` — move a trigger by name within `mission.trigrules`
- `me trigger reorder-condition` — move a condition by index within `t.rules`
- `me trigger reorder-action` — move an action by index within `t.actions`
- Five mutually-exclusive position flags: `--to-index N`, `--before X`, `--after X`, `--to-start`, `--to-end`
- Best-effort panel refresh after each move (matches every other mutating trigger verb)

### Out

- Cross-trigger moves (e.g. moving an action from trigger A to trigger B). Out of scope; `remove-action` + `add-action` covers it. Cross-trigger semantics also raise questions ED's UI sidesteps (does the agent want a copy or a true move? what if the source action references trigger-local state?).
- Bulk reorder (sort by predicate name, etc.). YAGNI for v1.
- Reorder-via-drag UI helpers. CLI-only.

## API

### `me trigger reorder`

Move a trigger to a new position in `mission.trigrules`.

```
me trigger reorder --name <T> { --before <X> | --after <X> | --to-index <N>
                              | --to-start | --to-end }
```

- `--name T` (required) — the trigger to move (matched against `t.comment`).
- Exactly one position flag must be provided.
  - `--before X` / `--after X` — `X` is another trigger's name. Errors if `X` not found. If `X == T` (referencing the source itself), no-op.
  - `--to-index N` — 1-based final position in the resulting list. Errors if N < 1 or N > `#trigrules`.
  - `--to-start` — sugar for `--to-index 1`.
  - `--to-end` — sugar for `--to-index #trigrules`.

Returns `{ ok = true, moved = bool, from = N, to = M }`. `moved = false` is a no-op (source already at target); not an error.

### `me trigger reorder-condition`

Move a condition within a single trigger's `rules` list.

```
me trigger reorder-condition --trigger <T> --index <N>
                             { --before <M> | --after <M> | --to-index <M>
                             | --to-start | --to-end }
```

- `--trigger T` (required) — the parent trigger's name.
- `--index N` (required) — the source condition's 1-based index in `t.rules`.
- Position flags identical to `reorder` above; `--before M` / `--after M` reference an index, not a name.

Returns `{ ok = true, moved = bool, trigger = "T", from = N, to = M }`.

### `me trigger reorder-action`

Same as `reorder-condition` but operates on `t.actions`. Identical flag shape and return shape (with `actions` list bounds instead of `rules`).

## Behavior

- Pure list manipulation: `table.remove(list, from)` → `table.insert(list, target, item)`. Same mechanism ED's UI uses (`me_trigrules.lua:3449-3544`).
- No descriptor validation, no dict-key fiddling, no reference re-resolution. The entry is well-formed before the move and stays well-formed after.
- **Position semantics**: `--to-index N` is the **final** 1-based position in the resulting list. Range: `1..#list` (same length before and after, since we remove-then-insert one item).
- **Mechanics**: `table.remove(list, from_idx)` (yielding a list of `#list - 1` items), then `table.insert(list, target_idx, item)` where `target_idx` is in `1..#list_before_removal`. Lua's `table.insert` with `pos = #t + 1` appends, which is exactly what we want for `--to-end` (target = `#list_before_removal`).
- **`--before X` / `--after X` resolution**: find X's index in the original list (call it `X_idx`). If `X_idx > from_idx`, X shifts down by 1 after removal, so its post-removal index is `X_idx - 1`; otherwise X is unaffected. `--before X` target = X's post-removal index. `--after X` target = X's post-removal index + 1. (Mathematically: `--to-index` semantics derived from "before" and "after" land at the right final position.)
- **Self-target → no-op** (`moved = false`). Includes:
  - `--to-index N` where N is the source's current 1-based position
  - `--before T` / `--after T` where T resolves to the source itself
  Cleaner for scripts than an error and aligns with how ED's UI handles "Up at index 1" (silently does nothing).
- Calls `_trigger_panel_refresh()` after each move (only when `moved = true`, no point refreshing on no-ops). If the panel is open and showing the trigger being mutated, the user's selection in the outer triggers list is rebuilt by `predicates.rulesToList`.

## Errors

| Condition | Error |
|---|---|
| `--name` / `--trigger` not found | `no trigger named "T"` |
| `--index` out of bounds | `trigger has only N conditions; cannot reorder index M` |
| `--before X` / `--after X` reference not found | `no trigger named "X"` (or `index out of bounds`) |
| Zero or multiple position flags | `exactly one of --to-index / --before / --after / --to-start / --to-end is required` |
| `--to-index 0` or negative | `--to-index must be ≥ 1` |

## Decisions

1. **Three sibling verbs over one polymorphic verb.** `reorder-condition --trigger T --index N` is unambiguous; a single `reorder --kind condition --trigger T --index N` would need a kind flag and would muddy the source identifier (name for trigger, index pair for condition/action). Mirrors `add-condition` / `remove-condition` naming.
2. **`reorder` not `move`.** `move` could imply moving across triggers (which we don't support); `reorder` is unambiguous.
3. **Five position flags including the two sugar ones.** `--to-start` and `--to-end` cost nothing in implementation (one extra branch in the resolver) and remove a foot-gun: writing `--to-index 1` requires you know it's 1-based; `--to-end` requires you know `#list`. Including them makes the verb friendlier to one-liner agents.
4. **No-op on self-target instead of error, including self-reference.** Aligns with ED's UI ("Up" at index 1 silently does nothing) and is friendlier in scripts (idempotent re-runs). `me trigger reorder --name T --before T` is a no-op, not an error — same as `--to-index <where-T-already-is>`.
5. **`--before X` / `--after X` accept the same identifier shape as the source.** Triggers: name. Conditions/actions: 1-based index. Don't mix shapes within a single verb.

## Implementation

Two private Lua helpers shared across the three verbs:

```lua
-- _reorder_resolve_target — turn the position flags into a final 1-based
-- target index in the post-removal list. Returns target_idx, err.
--
-- find_ref_idx: function(list, ref) → idx | nil
--   triggers     → ref is a name; resolves via _trigger_find_by_name
--   cond/action  → ref is already a 1-based index; bounds-checked
--
-- Validates exactly-one-position-flag. Maps:
--   --to-index N    → N
--   --to-start      → 1
--   --to-end        → #list
--   --before X      → X_post_removal_idx
--   --after X       → X_post_removal_idx + 1
-- where X_post_removal_idx = (X_orig_idx > from_idx) and X_orig_idx-1
--                                                    or  X_orig_idx
local function _reorder_resolve_target(list, from_idx, args, find_ref_idx)
    -- ...
end

-- _reorder_apply — table.remove + table.insert. Caller has already
-- short-circuited from_idx == target_idx via the resolver / no-op path.
local function _reorder_apply(list, from_idx, target_idx)
    local item = table.remove(list, from_idx)
    table.insert(list, target_idx, item)
end
```

The no-op short-circuit lives in the verb functions: after resolving, if `from_idx == target_idx`, return `{ ok = true, moved = false, from = N, to = N }` without calling `_reorder_apply` or refreshing the panel.

Three public verbs:

```lua
function M.trigger_reorder(args)            -- list = mission.trigrules, source = args.name
function M.trigger_reorder_condition(args)  -- list = t.rules,    source = args.index
function M.trigger_reorder_action(args)     -- list = t.actions,  source = args.index
```

Each verb is ~25 lines: validate args, resolve source index, call `_reorder_resolve_target`, call `_reorder_apply`, refresh panel, return result.

### Go side

Three new files: `tools/cmd/dcs-sms/me_trigger_reorder.go`, `me_trigger_reorder_condition.go`, `me_trigger_reorder_action.go`. Each registers its verb in `dispatch.go` and forwards the parsed flags through `emitMeResponse`. Position-flag mutual exclusion enforced Go-side (count the set flags); the inner-vs-outer-OK gap (issue #44) doesn't apply here because the bundled-create flow isn't involved.

### File touches

- `tools/me-mod/lua/dcs_sms_me/verbs.lua` — 2 helpers + 3 verbs (~120 LoC added)
- `tools/cmd/dcs-sms/dispatch.go` — 3 verb registrations
- `tools/cmd/dcs-sms/me_trigger_reorder.go` — new
- `tools/cmd/dcs-sms/me_trigger_reorder_condition.go` — new
- `tools/cmd/dcs-sms/me_trigger_reorder_action.go` — new
- `tools/me-mod/lua/dcs_sms_me/version.lua` — bumped in the same commit per AGENTS.md §11 ("Bump the version string in the same commit that lands the change"). `/ship-it` later creates the annotated tag.
- `CHANGELOG.md` — under the unreleased ME-mod section
- (No `docs/api/` update — that tree is for framework `sms.*` modules; ME-mod verbs are self-documented via `me trigger list-predicates` / `describe-predicate` and the per-verb CLI help.)

### Test plan

- Live verification mirrors the issue #45 fix style: create a 3-trigger mission, exercise each position flag, dump `mission.trigrules` order, assert.
- Each error path (out-of-bounds, ambiguous flags, missing-ref) tested via a one-liner that expects `ok: false` with a specific error substring.
- Self-reference cases (`--before T --name T`, `--to-index <where-source-is>`) tested for `moved: false` no-op, not error.
- A panel-refresh round-trip (open panel, reorder via CLI, re-select trigger, verify the visual order matches `trigrules`).

## Versioning

ME-mod version bump from current `0.5.0` to `0.6.0` (new public verbs = minor bump per AGENTS.md §11). CHANGELOG entry under the unreleased ME-mod section. The framework version is unaffected.

No `AGENTS.md` §7 update (that section indexes framework `sms.*` modules, not ME-mod verbs).

## Surface impact

Trigger verb count: 12 → 15 (+3). Total bridge surface: 78 → 81.
