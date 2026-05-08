-- sms_window.lua — Base class for ME-mod tool windows.
--
-- Owns the shared chrome that every ME-mod window needs:
--   * Branded title bar     ('Coconut Cockpit · DCS-SMS — <title> v<version>')
--   * Footer separator + colored status Static, with set_status (sticky)
--     and flash_status (auto-revert) semantics.
--   * Close button → :hide() (idempotent).
--   * File > New / File > Open closes the window (additive subscriber).
--   * Ctrl+Z hotkey → :on_undo() (default impl calls undo.undo() + flashes).
--   * Resize clamp + footer reposition + delegate to subclass relayout.
--
-- New windows extend SMSWindow via Lua metatable inheritance and override
-- :build_body() / :relayout() / :on_undo(). Existing windows that already
-- have a procedural module-with-W-table structure (prefab_manager.lua) can
-- alternatively pass opts.on_undo / opts.on_resize callbacks for a
-- minimal-diff retrofit — see "Composition path" in the spec.
--
-- Public:
--   SMSWindow.new(opts) → self | nil
--   self:show() / :hide() / :toggle()
--   self:get_content_bounds() → x, y, w, h
--   self:set_status(text, severity)
--   self:flash_status(text, severity, [timeout_sec])
--   self:raw() → underlying dxgui Window
--
-- Hooks for subclasses to override (default impls live in this file):
--   self:build_body()     — build widgets after construction
--   self:relayout(x,y,w,h) — reposition widgets on resize
--   self:on_undo()        — Ctrl+Z handler

-- Pure helpers exposed for testing — leading underscore signals "internal".
local M = {}

-- Severity → skin name. Centralised; replaces the SEVERITY_SKIN tables
-- previously duplicated in window.lua and group_tools.lua.
local SEVERITY_SKIN = {
    info     = 'staticSkin_ME',
    success  = 'dtc_status_green',
    warning  = 'dtc_status_yellow',
    error    = 'dtc_status_red',
}

-- Map a severity string to its skin name. Unknown / nil severities fall
-- back to 'info'. Returned skin name is consumed by try_skin (live
-- module) or the test (pure assertion).
function M._validate_severity(severity)
    return SEVERITY_SKIN[severity] or SEVERITY_SKIN.info
end

-- Compose the branded title string. Single source of truth so every
-- window's title bar reads the same.
function M._compose_title(title, version)
    return 'Coconut Cockpit · DCS-SMS — ' .. tostring(title) .. ' v' .. tostring(version)
end

-- ---------- Flash state machine ----------
--
-- Pure helpers that the live class uses by composition. Decoupling the
-- state machine from the dxgui Static lets us unit-test the transitions
-- without a real window.
--
-- State shape:
--   sticky_text      : string  -- last set_status text (rendered when flash expires)
--   sticky_severity  : string  -- last set_status severity
--   flash_expires_at : number  -- os.time when an active flash should revert; nil = no flash

function M._new_flash_state()
    return {
        sticky_text      = nil,
        sticky_severity  = nil,
        flash_expires_at = nil,
    }
end

-- Record a sticky status update + cancel any in-flight flash. Returns the
-- (text, severity) that should be rendered now.
function M._on_set_status(state, text, severity)
    state.sticky_text      = text
    state.sticky_severity  = severity
    state.flash_expires_at = nil
    return text, severity
end

-- Start a flash. Sticky baseline is left untouched; the flash overlays for
-- `timeout` seconds (default 5) starting from `now`. Returns the (text,
-- severity) that should be rendered now.
function M._on_flash_status(state, text, severity, timeout, now)
    state.flash_expires_at = now + (timeout or 5)
    return text, severity
end

-- Per-frame tick. If a flash has expired, returns the (text, severity) we
-- should revert to (the sticky baseline, defaulting to empty/info if none
-- was set). If no flash or not yet expired, returns nil.
function M._on_tick(state, now)
    if state.flash_expires_at == nil then return nil end
    if now < state.flash_expires_at then return nil end
    state.flash_expires_at = nil
    local text = state.sticky_text or ''
    local sev  = state.sticky_severity or 'info'
    return text, sev
end

return M
