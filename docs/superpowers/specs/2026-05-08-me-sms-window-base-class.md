## ME `SMSWindow` Base Class — Design

**Date:** 2026-05-08
**Status:** Approved (brainstorm phase)
**Scope:** Extract a reusable base class for ME-mod tool windows. The Prefab Manager and the (in-flight, on a separate branch) Group Tools window already duplicate ~150 lines each of titlebar / footer / Ctrl-Z / new-mission-hook plumbing. This spec defines `SMSWindow`, refactors `prefab_manager.lua` (renamed from `window.lua`) onto it, and leaves Group Tools to migrate later.

## Goal

Every future ME-mod tool window — Group Tools, a future Trigger Inspector, a future Spawn-Point Library, etc. — should "feel" like the same product: matching titlebar branding, matching footer status bar, matching close / on-top / resize / undo behaviour. Today, those behaviours are copy-pasted between `window.lua` (Prefab Manager) and `group_tools.lua`. The next window we add will copy them again, and divergence is already starting (e.g. the bulk-rename branch had to add a defensive `setBounds` after `Window.new` that the Prefab Manager doesn't have).

This spec turns the shared chrome into a single `SMSWindow` Lua class. Concrete windows extend it and override `:build_body()` / `:relayout()`.

## User value

Two audiences:

- **End user (mission maker, in DCS):** Tool windows look and feel like one cohesive product instead of two near-but-not-quite-identical floating panels. Bug fixes to the chrome (e.g. the persisted-size workaround) propagate everywhere at once. Status messages have one consistent severity-color vocabulary.

- **Developer / agent (writing the next tool window):** Adding a new ME-mod tool window becomes a small, focused file: declare a subclass, override two methods, done. No re-deriving the right `setZOrder` value, the right `windowSkinME` setup, the right `addSizeCallback` clamp logic.

## Non-goals

- **Group Tools migration.** Group Tools currently lives on the `worktree-me-mod-group-tools-bulk-rename` branch which has not merged. Migrating it is deferred until that branch ships (or is reconciled). Group Tools stays unchanged on its own branch.
- **Window position/size persistence across editor sessions.** dxgui has implicit persistence we currently fight (the bulk-rename branch needed `setBounds` to override stale restored sizes). Doing it *right* is a separate design — out of scope for v1.
- **A `Frame` / `Panel` widget abstraction.** Subclasses still talk to the underlying dxgui widgets directly; the base only owns the title bar (via the dxgui `Window` it wraps), the footer band (separator + status), and the resize-clamp plumbing.
- **Modal dialogs / message boxes.** `MsgWindow` (the native ME message-box factory) covers that already and isn't changing.
- **Framework (`sms.*`) consumers.** This is purely ME-mod. The `sms.*` framework rule "lightweight handles, never inheritance" does not apply here — this is mod-side tooling and inheritance is permitted.

## Architecture

### File layout

```
tools/me-mod/lua/dcs_sms_me/
    sms_window.lua          NEW — base class SMSWindow (~250 lines)
    prefab_manager.lua      RENAMED from window.lua — subclasses SMSWindow
    group_tools.lua         UNCHANGED on this branch (deferred migration)
    menu.lua                UPDATED — require('dcs_sms_me.prefab_manager')
    init.lua                UPDATED if it requires the old path
    dtc_skins.lua           UNCHANGED — already provides the colored Static skins
    new_mission_hook.lua    UNCHANGED — base subscribes to it
    undo.lua                UNCHANGED — base calls undo.undo() on Ctrl+Z
```

The rename of `window.lua` → `prefab_manager.lua` is a `git mv` so blame is preserved.

### Inheritance model

Lua metatable chain. Idiomatic, no framework needed:

```lua
-- sms_window.lua
local SMSWindow = {}
SMSWindow.__index = SMSWindow

function SMSWindow.new(opts) ... end          -- creates dxgui Window, footer, hooks
function SMSWindow:show() / :hide() / :toggle()
function SMSWindow:set_status(text, severity) / :flash_status(text, severity, [t])
function SMSWindow:get_content_bounds() -> x, y, w, h
function SMSWindow:build_body()                -- abstract; subclass overrides
function SMSWindow:relayout(x, y, w, h)        -- default no-op; subclass overrides
function SMSWindow:raw() -> dxgui Window       -- escape hatch

return SMSWindow
```

```lua
-- prefab_manager.lua
local SMSWindow = require('dcs_sms_me.sms_window')

local PrefabManager = setmetatable({}, { __index = SMSWindow })
PrefabManager.__index = PrefabManager

function PrefabManager.new()
    local self = SMSWindow.new({
        title    = 'Prefab Manager',
        size     = { w = 480, h = 600 },
        min_size = { w = 360, h = 400 },
    })
    if not self then return nil end
    setmetatable(self, PrefabManager)
    self:build_body()
    return self
end

function PrefabManager:build_body() ... end       -- existing widget construction
function PrefabManager:relayout(x, y, w, h) ... end -- existing resize repositioning

-- Module-level wrapper: keeps the same public surface as today
-- (menu.lua calls M.show / M.hide / M.toggle). Internally manages a
-- lazily-constructed singleton of the PrefabManager class.
local M = {}
local instance = nil

local function ensure()
    if not instance then instance = PrefabManager.new() end
    return instance
end

function M.show()    local s = ensure(); if s then s:show()   end end
function M.hide()    if instance then instance:hide() end end
function M.toggle()  local s = ensure(); if s then s:toggle() end end

return M
```

A new tool window is the same shape with different overrides. The module-level `M.show / M.hide / M.toggle` wrapper is the same idiom both `window.lua` and `group_tools.lua` use today — so `menu.lua` and `init.lua` don't have to change beyond the require path. No `BASE`-style root class, no deeper hierarchy than one level.

### Layout model — the three-band window

```
┌─────────────────────────────────────────────────┐
│  Coconut Cockpit · DCS-SMS — Foo v1.2     [X]   │ ← title bar (dxgui Window)
├─────────────────────────────────────────────────┤
│                                                 │
│   ← content area: subclass widgets →            │  ← `get_content_bounds()` returns this rect
│                                                 │
├─────────────────────────────────────────────────┤ ← separator (dtc_skins.separator(), 1px)
│ Status text                                     │ ← status Static, colored by severity
└─────────────────────────────────────────────────┘
```

Constants in `sms_window.lua`:

| Constant | Value | Source |
|---|---|---|
| `TITLEBAR_H` | 26 | empirical; dxgui doesn't expose a getter |
| `FOOTER_H` | 22 | 1px separator + 20px status static + 1px breathing room |
| `EDGE_PAD` | 8 | gap between window edge and content rect |

`get_content_bounds()` returns `(EDGE_PAD, TITLEBAR_H, win_w - 2*EDGE_PAD, win_h - TITLEBAR_H - FOOTER_H)`.

### Resize plumbing

`SMSWindow.new` wires `addSizeCallback`. On every fire:

1. **Clamp.** If user shrunk past `opts.min_size`, call `setBounds(x, y, max(w, min_w), max(h, min_h))` — re-fires the callback at the clamped size.
2. **Reposition footer.** Move separator to `(0, win_h - FOOTER_H)` and status Static to `(EDGE_PAD, win_h - FOOTER_H + 1)`. Subclass never touches these.
3. **Delegate.** Call `self:relayout(content_x, content_y, content_w, content_h)` so the subclass repositions its own widgets within the content rect.

A defensive `win:setBounds(x, y, w, h)` runs once after `Window.new` returns, before `setVisible(true)`. This overrides any dxgui-restored persisted size from a prior session — same fix the bulk-rename branch had to bake into Group Tools, now centralized.

## Public API of `SMSWindow`

### Construction

```
SMSWindow.new(opts) -> self | nil
    opts.title       (required)  string — base wraps as
                                  'Coconut Cockpit · DCS-SMS — ' .. title .. ' v' .. version
                                  (version is read from dcs_sms_me.version)
    opts.size        (required)  { w = N, h = N }    -- initial size in pixels
    opts.min_size    (optional)  { w = N, h = N }    -- defaults to opts.size
    opts.position    (optional)  { x = N, y = N }    -- defaults to top-right:
                                                       x = max(20, screen_w - w - 20), y = 80
    opts.persist_across_new_mission  (default false)
        -- when false, base subscribes to new_mission_hook and calls :hide()
    opts.disable_undo_hotkey         (default false)
        -- when false, base wires Ctrl+Z → self:on_undo()
        -- Default on_undo() implementation calls undo.undo() and
        -- flashes a status message. Subclasses can override to add
        -- post-undo refresh while still calling SMSWindow.on_undo(self)
        -- for the base behavior.
```

Returns `nil` if `Window.new` failed (logged); subclass `new` should propagate the nil.

### Lifecycle

```
self:show()      -- idempotent. setVisible(true), setEnabled(true).
self:hide()      -- idempotent. setVisible(false).
self:toggle()    -- show if hidden, hide if shown.
```

### Layout

```
self:get_content_bounds() -> x, y, w, h
    -- the content rect inside the chrome. Re-call after every resize
    -- (or use the rect passed to your relayout()).
```

### Status bar

```
self:set_status(text, severity)
    -- Replaces footer text + skin. Sticks until next set_status call.
    -- Severity ∈ 'info' | 'warning' | 'error' | 'success'.
    -- 'info' = gray (default skin); others use dtc_skins.static_*.
    -- Updates `self.last_sticky_text` / `self.last_sticky_severity`.

self:flash_status(text, severity, [timeout_sec])
    -- Same stamp as set_status, but reverts after timeout (default 5s)
    -- to whatever was last set via set_status.
    -- Calling set_status during a flash cancels the flash.
    -- Calling flash_status during a flash replaces it (latest wins).
```

### Hooks for subclasses

```
self:build_body()
    -- Subclass override. Called once by the subclass after SMSWindow.new
    -- returns. Builds the subclass's widgets into the dxgui Window
    -- (use self.window:insertWidget(w) and self:get_content_bounds()).
    -- Default: no-op.

self:relayout(x, y, w, h)
    -- Subclass override. Called by the base on every size change with the
    -- current content rect. Subclass repositions its widgets.
    -- Default: no-op.

self:on_undo()
    -- Subclass override. Called by the Ctrl+Z hotkey (unless
    -- disable_undo_hotkey is set). Default: calls undo.undo() and
    -- flashes a 'success' / 'error' / 'warning' status. Subclasses
    -- override to add post-undo refresh; call SMSWindow.on_undo(self)
    -- to invoke the base behavior first.
```

### Escape hatch

```
self:raw() -> dxgui Window
    -- Returns the underlying dxgui Window for cases the API doesn't cover.
    -- Use rarely; prefer adding to the base if you need it twice.
```

## Status bar mechanics

The base owns the severity → skin map (centralized; replaces the `SEVERITY_SKIN` table currently duplicated in `window.lua` and `group_tools.lua`):

```lua
local SEVERITY_SKIN = {
    info     = 'staticSkin_ME',         -- gray, default skin
    success  = 'dtc_status_green',
    warning  = 'dtc_status_yellow',
    error    = 'dtc_status_red',
}
```

The base owns its own internal `try_skin` helper that handles only the four severity skins above. The two existing `try_skin` copies in `window.lua` (now `prefab_manager.lua`) and `group_tools.lua` keep their full skin vocabulary for non-status uses (buttons, separators in the body, dial, grid, etc.).

`set_status(text, severity)` stamps the Static, applies the skin, records the sticky baseline. Synchronous; no timer.

`flash_status(text, severity, timeout)` stamps the Static, applies the skin, sets `self.flash_expires_at = os.time() + (timeout or 5)`. A single `UpdateManager` callback (registered lazily on first `flash_status` call, never deregistered) ticks every frame: if `os.time() >= flash_expires_at`, it re-applies `last_sticky_text` / `last_sticky_severity` and clears the expiry. 1-second granularity is fine for a status bar.

Initial state before any `set_status` call: empty Static with the default `info` skin (gray). Reads as a clean unused status bar.

## Lifecycle wiring

| Behavior | Default | Opt-out |
|---|---|---|
| Close `[X]` button → `:hide()` (not destroy) | bake in (re-creating widgets on reopen is wasteful) | n/a |
| File > New / File > Open closes the window | bake in: subscribe to `new_mission_hook` with a closure that calls `self:hide()` | `opts.persist_across_new_mission = true` |
| `Ctrl+Z` calls `self:on_undo()` (default impl calls `undo.undo()` + flashes status) | bake in: project has a single global undo bus; both existing windows already wire to it. Routing through a method gives subclasses an override hook for post-undo refresh. | `opts.disable_undo_hotkey = true` |
| Position/size persistence across editor sessions | **defer to v2** (see Non-goals) | n/a |
| `setZOrder(190)` so map clicks don't repaint over the window | bake in (every window today does this; no foreseeable opt-out) | n/a |
| `setSkin(Skin.windowSkinME)` for native ME chrome | bake in | n/a |
| `setDraggable(true)` and `setResizable(true)` | bake in | n/a |

The `new_mission_hook` subscription is *additive* (matches the bulk-rename branch's fix). Multiple windows subscribing simultaneously must coexist — the hook supports multiple subscribers; the base just registers its own and never resets.

## Error handling

Project rule: log + return nil/false, never throw. Every dxgui call inside `SMSWindow` is wrapped in `pcall`. Specific failure modes:

| Failure | Behavior |
|---|---|
| `Window.new` returns nil or throws | log error, return nil from `SMSWindow.new`. Subclass `.new` should propagate the nil. Menu wiring already handles a nil return from `M.show()` gracefully. |
| `setSkin` / `setBounds` / `addSizeCallback` failure | log once, continue. Window stays usable, just unstyled or unreflowing. |
| `set_status` called before `Window.new` succeeded | silent no-op (status Static is nil). |
| Severity not in the map | falls back to `info` (gray), logs a warning. |
| `flash_status` UpdateManager registration fails | log warning. `flash_status` degrades to behaving like `set_status` (no timer; sticks). |
| Subclass's `build_body` / `relayout` throws | base wraps the call in `pcall`. Logs the error. Window stays usable. |

## Testing

Tests live in `tools/me-mod/test/` and run via `run-tests.ps1` like every other ME-mod test.

What can be tested without a real dxgui environment:

| Test | What it covers |
|---|---|
| `validate_severity(s) -> skin_name` | pure function. Verifies every severity maps to the right skin name and unknown severity falls back to `info`. |
| `flash_status` state transitions | extracted state machine that takes a fake clock. Verifies: (a) flash overwrites flash, (b) set_status during flash cancels it, (c) revert text equals last sticky baseline, (d) timeout=0 behaves the same as timeout=default. |
| Title-string composition | `compose_title('Foo', '0.5.0')` returns `'Coconut Cockpit · DCS-SMS — Foo v0.5.0'`. |

`validate_severity`, the flash state-machine helper, and `compose_title` are internal helpers exposed on the module table (e.g. `SMSWindow._validate_severity`, `SMSWindow._compose_title`) only so the test file can require them. They are not part of the public API; the leading underscore signals that.

Out of scope for unit tests (covered by manual smoke):

- Actual dxgui Window lifecycle.
- Resize-clamp behavior under user drag.
- Ctrl+Z hotkey firing.
- File>New closing the window.

A new `tools/me-mod/test/test_sms_window.lua` covers the unit-testable parts. Registered in `run-tests.ps1` like `test_bulk_rename.lua` was.

The `docs/release-gate/me-mod-smoke.md` checklist gets a new section: **SMSWindow + Prefab Manager refactor**. Items: open the window (size/position match), resize (footer stays at the bottom), close button hides, File>New closes, Ctrl+Z fires undo, gray/green/yellow/red status text colors render correctly, transient flash reverts to sticky baseline.

## Migration of `prefab_manager.lua`

The rename of `window.lua` → `prefab_manager.lua` is a `git mv` (preserves blame). Inside the file, the following plumbing is **deleted** because the base now owns it:

| Removed from `prefab_manager.lua` | Replaced by |
|---|---|
| local `WINDOW_TITLE` string composition | `opts.title = 'Prefab Manager'` (base composes the brand + version) |
| local `try_skin` cases for `dtc_status_*` (the local `try_skin` keeps the rest — buttons, separators in the body, dial, grid) | `self:set_status(...)` / `self:flash_status(...)` |
| local `SEVERITY_SKIN` map | gone — base owns it |
| local separator + status Static construction | base creates them in `SMSWindow.new` |
| explicit `Window.new(...)` + `setSkin` + `setZOrder` + `setDraggable` + `setResizable` + `setVisible(true)` block | base's constructor |
| explicit `addSizeCallback` clamp + relayout dispatch | base owns it; subclass just implements `:relayout(x, y, w, h)` |
| explicit `addHotKeyCallback('Ctrl+Z', undo.undo)` + post-undo refresh | base wires Ctrl+Z to `self:on_undo()`. Default impl handles `undo.undo()` + status. Prefab Manager overrides to add grid refresh. |
| explicit `new_mission_hook.subscribe(M.hide)` | base wires it (opt-out via `persist_across_new_mission`) |
| top-level `M.show / M.hide / M.toggle` thin wrappers | **kept**, but each forwards to a class-singleton instance (see the prefab_manager.lua skeleton above). External callers (menu.lua, init.lua) don't change. |

Estimated delta in `prefab_manager.lua`: ~100-150 lines removed, ~5-10 lines added (the subclass declaration and metatable wiring). The file shrinks from ~1958 to ~1800.

## Versioning

ME-mod is at **0.4.2** on `main` (the bulk-rename branch's 0.5.0 has not merged). This work bumps `0.4.2 → 0.5.0` on the new branch. The version string change goes in the same commit as the public-surface-affecting code change (per project versioning rule).

When the bulk-rename branch eventually merges, its 0.5.0 entry reconciles with this one — both land under the same release line. The reconciliation is a follow-up; not in scope for this spec.

`CHANGELOG.md` gets a 0.5.0 entry with bullets for: SMSWindow base class introduced, Prefab Manager refactored onto it, footer status bar gains `flash_status` semantics.

`tools/me-mod/README.md` gets a new "## SMSWindow" section — short, points at this spec for the design doc and at the API summary above for the contract.

## Documentation rule (per CLAUDE.md)

ME-mod changes do NOT trigger an `AGENTS.md §7` update — that rule is framework-only (`sms.*` modules). The doc updates that DO land in this change-set:

- `tools/me-mod/README.md` — new SMSWindow section, brief.
- `CHANGELOG.md` — 0.5.0 entry (ME-mod track).
- `docs/release-gate/me-mod-smoke.md` — new "SMSWindow + Prefab Manager refactor" smoke checklist section.

Per CLAUDE.md, these updates land in the same commit-set as the code, not as a follow-up.

## Open follow-ups (deferred)

These are explicitly out of scope for this spec but worth tracking for later:

1. **Group Tools migration onto SMSWindow.** Wait for the bulk-rename branch to ship or be reconciled, then migrate. Should be a small follow-up patch (delete the same plumbing the Prefab Manager just lost; add a `setmetatable(self, GroupTools)` line; override `build_body` and `relayout`).
2. **Position/size persistence (v2).** Save bounds on `:hide()` to a per-window slot (e.g. in `paths.lua`'s registry); restore on `:show()`. Replaces the defensive `setBounds` workaround with a real persistence layer.
3. **`min_size` enforcement at the dxgui level.** Currently the base clamps via callback after the user drags past the minimum. dxgui has no `setMinSize`; if a future build does, switch to it.
4. **Footer height query.** `TITLEBAR_H = 26` is empirical. If dxgui ever exposes a getter, switch.

## Implementation order (preview, full plan in implementation-plan doc)

1. Create `sms_window.lua` with the public API and tests for the pure pieces (severity map, flash state machine, title composition).
2. `git mv window.lua prefab_manager.lua`. Don't change content yet.
3. Refactor `prefab_manager.lua` to subclass `SMSWindow`. Delete the duplicated plumbing.
4. Update `menu.lua` and `init.lua` for the new path.
5. Run full ME-mod test suite (existing tests must still pass; new tests must pass).
6. Bump version to 0.5.0; update `CHANGELOG.md`, `README.md`, `me-mod-smoke.md`.
7. Manual DCS smoke: open Prefab Manager, exercise it, confirm the chrome looks identical to before.
