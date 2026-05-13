## ME Prefab Manager — Folder Browser + Right-Click Context Menus — Design

**Date:** 2026-05-13
**Status:** Approved (brainstorm phase)
**Closes:** GH#50 (right-click context menu on prefab rows) — folded into this design
**Scope:** Split the Prefab Manager into a two-pane layout — folder tree on the left, prefab list on the right — backed by real filesystem subfolders. Add right-click context menus on both panes. The existing top/bottom bands (Name+Save, Country, Rotation, Place) are unchanged.

## Goal

Today the Prefab Manager shows every saved prefab as a flat list. As the library grows, finding a prefab requires either the filter input or scrolling. The user has worked on a similar tool (an animation browser) where a folder tree on the left + file view on the right was the well-received affordance. This spec brings that pattern into the Prefab Manager.

In the same change-set, GH#50 — right-click context menu on prefab rows (Copy file contents · Copy place snippet · Show in Explorer) — is folded in. We're building the context-menu infrastructure for the folder tree anyway; the file-row menu rides on the same module and ships in one release.

## User value

- **Organize at scale.** Users who currently end up with 50+ prefabs in one flat list can group them by mission role (CAP, SAM, FARP-kits) or by theatre, and find what they need by drilling into the tree.
- **No GUI gymnastics for common file ops.** "Where is this on disk?" and "give me the placement Lua" no longer require leaving DCS. (GH#50.)
- **No mandatory migration.** Existing flat prefabs at the root of `<SavedGames>\DCS\dcs-sms\prefabs\` continue to work; they show up when no folder is selected in the tree.

## Non-goals

- **Drag-and-drop reorganization.** dxgui drag-drop is fragile; right-click → Move to… covers the same workflow.
- **Folder/file-move undo.** Folder mutations and prefab moves are immediate. The existing `Ctrl+Z` undo bus stays scoped to prefab placement.
- **Tags / multi-folder membership.** A prefab is in exactly one folder (its filesystem location).
- **Persistence of expansion / selection state.** Across window hide/show, the tree resets to defaults. Persistence is a separate, easy follow-up if desired.
- **Auto-migration of flat prefabs.** They stay at root.
- **A `sms.prefab.place` framework function.** The placement snippet GH#50 specifies documents a future framework API. The status line acknowledges it isn't shipped yet.
- **New `me prefab` CLI verbs.** Folder-aware verbs are a plausible follow-up; this spec is GUI-only.

## Decisions

Choices made during brainstorming, with one-line rationale each. Anything we hit later that contradicts one of these should be raised, not silently changed.

- **Folder model = real filesystem subfolders** under `prefabs/`. Closest match to user's reference tool; visible to anything outside the manager.
- **Save target = currently selected folder.** Empty selection → root. Mirrors standard file-manager flow.
- **Folder creation = + New Folder button (below the tree) + right-click → New subfolder.** Button placement explicitly: below the tree, so search-bar + tree match the vertical heights of the file-list search + grid.
- **In-manager folder ops = New, Rename, Delete; file op = Move to….** No drag-and-drop.
- **Filter scope = current folder (direct children) when a folder is selected; recursive over all prefabs when nothing is selected.** Two independent filters: tree filter and file filter.
- **Tree widget = native `TreeView` first, hand-rolled `ListBox`-with-indent fallback** behind a `pcall(require, 'TreeView')` probe.
- **Splitter = fixed-width (200 px) tree pane.** No drag-resize in v1.
- **GH#50 folded in.** Same release adds the file-row right-click menu (Move to… · Copy file contents · Copy place snippet · Show in Explorer).
- **`prefab_ops.scan_dir` returns flat rows with a new `folder` field.** Tree-building is a UI-side concern, kept in `prefab_manager.lua`.
- **No `.prefab` schema change.** Folder is implicit in the file's path.
- **No persistence of expansion / selection state across hide/show.** Defaults each open.
- **No auto-migration of existing flat prefabs.** They stay at root, visible when nothing is selected.
- **Path separators:** `/` in memory (`row.folder`, `W.selected_folder`), `\` on disk. Single seam: `paths.folder_to_abs`.

## Open questions

None at brainstorm phase.

## Architecture

### File layout

```
tools/me-mod/lua/dcs_sms_me/
    prefab_manager.lua      UPDATED — two-pane layout, new selection state, context-menu hooks
    prefab_ops.lua          UPDATED — scan_dir recurses; new save_selection folder arg; new move/rename/delete helpers
    paths.lua               UPDATED — folder_to_abs(folder_rel) helper; PREFABS_DIR unchanged
    context_menu.lua        NEW (~150 lines) — wraps dxgui Menu, owns clipboard probe, exposes show_for_file_row / show_for_tree_node
```

No new top-level module. `context_menu` is a leaf consumed by `prefab_manager`.

### Data model

- **On disk:** `<SavedGames>\DCS\dcs-sms\prefabs\` becomes recursive. Subdirectories under it are real folders. Prefab path is `prefabs\<rel-path>\<name>.prefab`, where `<rel-path>` uses platform `\` and is empty for root.
- **In memory:** the `row.folder` field — forward-slash-joined relative path, `""` for root, `"CAP"` for top-level, `"Static defense/FARP-kits"` for nested. The `/` form is the canonical in-memory representation; `\` is filesystem-only.
- **No schema change** to the `.prefab` file. The folder is implicit in the file's location.

### `prefab_ops.scan_dir` recursion

Existing fields unchanged. New: every row carries `folder` (string).

```lua
function M.scan_dir()
    paths.ensure_prefabs()
    local rows = {}
    local function walk(abs_dir, rel_folder)
        local ok, err = pcall(function()
            for entry in lfs.dir(abs_dir) do
                if entry ~= '.' and entry ~= '..' then
                    local abs = abs_dir .. entry
                    local attr = lfs.attributes(abs)
                    if attr and attr.mode == 'directory' then
                        local sub = (rel_folder == '' and entry) or (rel_folder .. '/' .. entry)
                        walk(abs .. '\\', sub)
                    elseif attr and attr.mode == 'file' then
                        -- .prefab / .lua extension test + legacy migration: unchanged
                        local name, is_legacy = parse_prefab_filename(entry)
                        if name then
                            local path = abs
                            if is_legacy then path = migrate_legacy_to_prefab(path, name) end
                            local prefab, lerr = M.load(path)
                            local row = prefab and row_from_prefab(name, path, prefab)
                                                or { name = name, path = path, error = lerr }
                            row.folder = rel_folder
                            rows[#rows + 1] = row
                        end
                    end
                end
            end
        end)
        if not ok then
            log.write('sms.me.prefab', log.WARNING, 'scan_dir at ' .. tostring(rel_folder) .. ' failed: ' .. tostring(err))
        end
    end
    walk(paths.PREFABS_DIR, '')
    table.sort(rows, function(a, b)
        if a.folder ~= b.folder then return a.folder < b.folder end
        return a.name < b.name
    end)
    return rows
end
```

`pcall` per-directory means a broken sub-folder doesn't poison sibling walks. Legacy `.lua` → `.prefab` migration still runs at every level.

### Empty-folder discovery

`scan_dir` only emits rows for `.prefab` files; an empty folder is invisible to it. The Prefab Manager runs a *separate* `lfs.dir` walk on each tree refresh to collect the full set of folders (including empties). The two results — flat rows from `scan_dir` and the folder set — feed `build_tree(rows, folder_set)`, which produces the nested structure the `TreeView` consumes.

This keeps `scan_dir` a clean "what prefabs exist?" query — the tree-with-empties is purely a manager concern.

### UI structure

**Top band** (unchanged): Name input + Fixed-location checkbox + Save button, spanning full width.

**Two-column body** between the top band and the bottom bands. Constants:

```
TREE_W = 200    -- fixed left-pane width
SPLIT  = 6      -- gutter between panes
```

Left pane (`x ∈ [10, 10 + TREE_W]`):
- `W.folder_search_label` — Static, "Search folders:"
- `W.folder_search_input` — EditBox; substring-filters the tree
- `W.folder_tree` — `TreeView` + `TreeViewItem` (native) or `ListBox` (hand-rolled fallback)
- `W.new_folder_btn` — Button, "+ New folder"; sits in a 28 px strip *below* the tree, full pane width

Right pane (`x ∈ [10 + TREE_W + SPLIT, w - 10]`):
- `W.search_label` — Static, **renamed** from "Search:" to "Search files:"
- `W.filter_input` — EditBox; substring-filters file rows
- `W.grid` — `Grid` with the existing 8 columns. Unchanged.

The folder-search input and the file-search input share the same `y` (top of the body, currently `y = 51`). The tree top-edge and grid top-edge share the same `y` (`y = 77`). The "+ New folder" button sits at `y = (tree bottom) + 0`, in the 28 px strip carved from the tree's bottom. The grid extends to its existing bottom (above the bottom bands) without that 28 px strip — there's no equivalent button on the right side.

**Bottom bands** (unchanged): Reload/Undo (left) + Rename/Delete (right) · Country picker · Rotation + Place buttons · status. All span full width.

**Min size** bumps from `MIN_W = 540, MIN_H = 460` to `MIN_W = 760, MIN_H = 460`. The original 540 assumed one grid; the tree adds ~220 px of unavoidable width.

### TreeView fallback

`pcall(require, 'TreeView')` at module-load. If nil:
- Substitute a `ListBox` widget.
- Render each folder as a single row, indent two spaces per depth, prefix `▶ ` (collapsed) or `▼ ` (expanded).
- Single-click on a row sets `W.selected_folder = node.path`. Double-click on a row with children flips its collapse state and rebuilds the rendered rows. (dxgui `ListBox` doesn't reliably expose click-x for sub-cell hit-testing, so the two gestures stay distinct.)
- Same backing model as the native path (`W.folder_tree_collapse[path] = true` set).

We test both paths but ship the native one as the default. The fallback exists because no other code in the repo currently uses `TreeView` — if ED's binding has a wrinkle, we want a working alternative without a new release.

### Selection state and filter composition

New state on `W`:

```lua
W.selected_folder = ''         -- '' means "no selection / show recursively"
W.folder_filter_text = ''      -- substring filter for the tree
W.folder_tree_collapse = {}    -- map folder_path -> true if collapsed
```

`apply_filter()` composes two filters in order:

```
visible_rows = W.rows
    |> filter by W.selected_folder:
         '' → keep all rows
         '<path>' → keep rows where row.folder == '<path>'  (direct children only)
    |> filter by W.filter_text:
         '' → keep all
         non-empty → keep rows whose row.name contains W.filter_text (case-insensitive)
    |> sort_rows(W.sort_key, W.sort_dir)
```

Direct-children-only on folder selection matches Windows Explorer. Sub-folders are present in the tree as their own selectable nodes; clicking them drills in. Clicking empty space in the tree sets `W.selected_folder = ''` and shows everything recursively — that's what the user explicitly asked for during brainstorming.

`W.folder_filter_text` filters which tree nodes are *visible*, not which file rows are visible. The match is **case-insensitive** (matching the file-filter convention). A folder is shown if its own name matches the substring **or** any descendant matches (so users can find deep folders by typing the leaf name). Empty folders that don't match and have no matching descendant are hidden.

### Save target derivation

`prefab_ops.save_selection` gains an optional `folder` argument (default `""`).

```lua
function M.save_selection(name, place_at_origin, airbases, folder)
    folder = folder or ''
    paths.ensure_prefab_folder(folder)        -- mkdir each segment top-down
    local path = paths.folder_to_abs(folder) .. name .. '.prefab'
    -- ... rest unchanged ...
end
```

`paths.ensure_prefab_folder(folder)` walks the segments and `lfs.mkdir`s each. `paths.folder_to_abs(folder)` rewrites `/` → `\` and prepends `PREFABS_DIR`. Single seam between in-memory and on-disk separators.

The Prefab Manager's `on_save_click` passes `W.selected_folder` as the `folder` argument.

### Right-click selection-then-menu pattern (GH#50)

`W.grid.onMouseDown` currently ignores `button ~= 1`. Extend it to handle `button == 2`:
- `selectRow(row) + on_list_select()` — visually select the row, exactly as a left-click would.
- `context_menu.show_for_file_row(x, y, selected_row())` — popup at cursor.
- Right-click in empty grid area (no row under cursor): no menu.

The same pattern applies to the tree (left or fallback): right-click selects the node, then `context_menu.show_for_tree_node(x, y, node)`.

### `context_menu.lua` module

```lua
-- Public:
--   M.show_for_file_row(x, y, row)
--   M.show_for_tree_node(x, y, node)
--
-- Internal:
--   build_menu(entries) -> dxgui Menu with entries = { {label, enabled, on_click}, ... }
--   probe_clipboard() -> fn(string) | nil, resolved once at module load
--   open_in_explorer(path) -> os.execute('explorer /select,"<path>"')
```

**File-row menu entries:**

| Entry | When `row.error` | Action |
|---|---|---|
| Move to… | hidden | Opens folder-picker modal (own Window + TreeView + Move/Cancel) |
| *separator* | hidden | — |
| Copy file contents | hidden | Read `row.path`, clipboard, status: `Copied <name>.prefab contents (<N> bytes).` |
| Copy place snippet | hidden | `sms.prefab.place("<name>", {x = 0, y = 0})  -- rotation = 0, country = nil`, clipboard, status: `Copied placement snippet. (sms.prefab.place not yet shipped in framework.)` |
| Show in Explorer | enabled | `os.execute('explorer /select,"<row.path>"')` |

Per GH#50, error rows show only Show in Explorer.

**Tree-node menu entries:**

| Entry | When root | Action |
|---|---|---|
| New subfolder | enabled | Name-input overlay; `lfs.mkdir(parent + name)` |
| Rename | hidden | Name-input overlay pre-filled; `os.rename(old, new)` |
| Delete | hidden | Confirm if non-empty; depth-first `os.remove` + bottom-up `lfs.rmdir` |

The root node ("(root)" header) is non-renameable and non-deletable; the "New subfolder" entry on the root is the same as clicking the New Folder button with nothing selected.

### Clipboard probe (GH#50)

`probe_clipboard()` resolves once at module load. Tries in priority order, picks the first that works:

1. `_G.Gui and Gui.setClipboard`
2. `_G.dxgui and dxgui.setClipboard`
3. `pcall(require, 'Input').setClipboard`
4. `os.execute('echo <text> | clip')` — last resort, with escaping (`"` → `""`, control chars stripped)

If all four fail, returned function is `nil`. Calls to clipboard ops then status: `Clipboard unavailable on this build — see dcs.log.` and a `log.write` at WARNING level naming what was tried.

### Folder operations

**New folder.** Name-input overlay (MsgWindow + a TextBox; or `MsgWindow.text` with inline EditBox if the build supports it). Parent = `W.selected_folder` for the button click, or the right-clicked node's path for the context-menu path. Validates: no path separators (`/`, `\`), no Windows-reserved chars (`<>:"|?*`), trimmed, non-empty. Rejection → status line, no overlay. `lfs.mkdir(absolute_path)`. On success: refresh tree, select the new node, status: `Created folder "<parent>/<name>".`

**Rename folder.** Name-input overlay pre-filled. Same validation rules. `os.rename(old_abs, new_abs)`. If target exists: error, no overwrite. On success: refresh tree, refresh file list (rows' `folder` fields are stale), restore selection by path-rewrite.

**Delete folder.** Recursive count of `.prefab` files and sub-folders. Empty: delete without confirm. Non-empty: `show_overlay` warning with the count; Delete / Cancel buttons. On confirm: depth-first walk → `os.remove` each file → `lfs.rmdir` each dir bottom-up. Any failure aborts mid-walk and reports the offending path; the tree refresh then reflects the partial state.

**Move prefab to folder.** Opens a small modal Window with its own `TreeView` listing all folders + Move/Cancel buttons. Pre-selects the prefab's current folder (root if it's at the root). The Move button is disabled when the selected target equals the source folder (no-op). On Move: `os.rename(old_path, target_folder + name + '.prefab')`. If target file exists: status error, no overwrite. On success: refresh, re-select the prefab in its new folder.

### Failure modes

| Surface | Behavior |
|---|---|
| `TreeView` binding missing | Falls back to `ListBox` with hand-rolled indent / collapse rendering. Same model, same callbacks, less visual polish. |
| `scan_dir` errors mid-recursion | Per-directory `pcall` preserves sibling walks. Broken sub-folder logs WARNING, returns 0 rows for itself, continues. |
| Folder-name collision on create/rename | Checked *before* the syscall via `lfs.attributes(target)`. Rejection → status message; no overwrite. |
| Prefab-name collision on move | Checked via `io.open(target_path, 'r')`. Status: `Cannot move: "<name>" already exists in <target_folder>.` |
| Non-empty folder delete | `show_overlay` warning naming the prefab + subfolder count; user must confirm. |
| Path-separator normalization | `paths.folder_to_abs(folder_rel)` is the single seam between `/` (in-memory) and `\` (filesystem). |
| Clipboard probe failure (GH#50) | Status: `Clipboard unavailable on this build — see dcs.log.` plus `log.write` WARNING. No crash. |
| `explorer /select,...` failure (GH#50) | `os.execute` returns non-zero; logged. No status update — user already sees Windows didn't pop up. |
| Right-click on grid empty area | No menu, no selection change. |
| Right-click on tree empty area | No menu, no selection change. (Only left-click on empty area deselects.) |
| Move prefab into a folder that no longer exists | Re-check just before `os.rename`; if the destination was deleted between dialog-open and confirm, status error. |

### Testing

| Surface | Test approach |
|---|---|
| `prefab_ops.scan_dir` recursion + `row.folder` values + legacy `.lua` migration at every level | New Lua unit test under `tools/me-mod/test/`. Uses a temp directory tree built in the test setup; verifies row count, folder strings, migration. |
| Folder name validation (separators, reserved chars, trim) | Pure-Lua test on `prefab_manager._validate_folder_name` (exposed for tests). |
| `apply_filter` composition (folder × text) | Pure-Lua test on the function with hand-built `W.rows` fixtures. Folder=`''` shows all; folder=`'CAP'` shows only direct children; combined with text filter narrows further. |
| `paths.folder_to_abs` | Pure-Lua test, both empty and nested-with-`/`-input. |
| Clipboard probe ordering | Mocked globals; verify first available strategy is picked; verify nil-return on all-fail. |
| `prefab_ops.move` | Pure-Lua test using temp directories; success case, target-exists case, source-missing case. |
| `prefab_ops.delete_folder` recursive | Pure-Lua test using temp directories with nested files; verifies bottom-up rmdir. |
| Tree click / right-click flow, menu rendering, overlay confirmations | Manual smoke per the release-gate checklist — these aren't reasonably testable without a real DCS state. Add items to `docs/release-gate/me-mod-smoke.md`. |

### Versioning and doc-sync

- **Version bump.** `tools/me-mod/lua/dcs_sms_me/version.lua` — **minor** (new feature, no breaking change).
- **CHANGELOG entry.** Under the new version: "Prefab Manager folder browser + right-click context menus (closes GH#50)."
- **`tools/me-mod/AGENTS.md`.** No public Lua surface change. The §2.2 file-layout table gains a row for `context_menu.lua`. Update in the same commit.
- **`tools/me-mod/README.md`.** User-facing docs — update the Prefab Manager section with a screenshot of the new layout and a mention of the right-click menus.
- **`docs/cli/`.** Untouched. No new verbs.
- **`docs/release-gate/me-mod-smoke.md`.** Add smoke items for: tree expand/collapse, folder create/rename/delete, prefab move, right-click menu entries, clipboard ops.

## Implementation order

This is a brainstorm-phase document. Detailed sequencing belongs in the implementation plan (`writing-plans` skill output). At a glance the natural ordering is:

1. `paths.lua` — `folder_to_abs`, `ensure_prefab_folder`.
2. `prefab_ops.scan_dir` recursion + `row.folder`.
3. `prefab_ops.save_selection` folder arg + `prefab_ops.move` + `prefab_ops.delete_folder`.
4. `context_menu.lua` — module + clipboard probe + the two `show_for_*` functions.
5. `prefab_manager.lua` — split-pane layout, tree wiring, selection state, filter composition.
6. Tree fallback path.
7. Manual smoke + release-gate checklist updates.
8. Version bump, CHANGELOG, AGENTS.md edits.

## Cross-references

- **GH#50** — feat(me): Prefab Manager — right-click context menu on prefab rows. Folded in; will be referenced in the implementation PR and closed on merge.
- **2026-05-08-me-sms-window-base-class.md** — the `sms_window` chrome the manager already rides on. The folder-picker modal for Move-to is a new floating window and will use the same factory.
- **2026-05-03-me-prefab-manager.md** — original Prefab Manager design. This spec extends it.
- **2026-05-07-prefab-file-extension.md** — `.prefab` vs legacy `.lua`. The recursive `scan_dir` preserves the legacy-rename behavior at every depth.
