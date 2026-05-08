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

-- ---------- Live class (dxgui-bound) ----------
--
-- Below this point the module talks to the dxgui module-table widgets
-- (Window, Static, Skin, UpdateManager) and the project's hooks
-- (new_mission_hook, undo). These are pcall-guarded so the module still
-- loads in environments missing them (test VMs, older dxgui builds).

local Window;        do local ok, mod = pcall(require, 'Window');        if ok then Window        = mod end end
local Static;        do local ok, mod = pcall(require, 'Static');        if ok then Static        = mod end end
local Skin;          do local ok, mod = pcall(require, 'Skin');          if ok then Skin          = mod end end
local Gui;           do local ok, mod = pcall(require, 'dxgui');         if ok then Gui           = mod end end
local UpdateManager; do local ok, mod = pcall(require, 'UpdateManager'); if ok then UpdateManager = mod end end

local dtc_skins;        do local ok, mod = pcall(require, 'dcs_sms_me.dtc_skins');        if ok then dtc_skins        = mod end end
local version          = require('dcs_sms_me.version')
local undo;             do local ok, mod = pcall(require, 'dcs_sms_me.undo');             if ok then undo             = mod end end
local new_mission_hook; do local ok, mod = pcall(require, 'dcs_sms_me.new_mission_hook'); if ok then new_mission_hook = mod end end

-- Layout constants (see spec — Layout model section).
local TOP_PAD   = 8    -- breathing room at the top of the content area
local FOOTER_H  = 22   -- separator (1px) + status static (20px) + 1px breathing room
local EDGE_PAD  = 8    -- left/right gap between window edge and content rect

-- Resolve a skin by short name. Handles only the four severity skins +
-- the footer separator — every other skin name is delegated to the Skin
-- module's auto-generated factories (Skin.staticSkin_ME, etc).
local function try_skin(widget, skin_name)
    pcall(function()
        if not (widget and widget.setSkin) then return end
        local s
        if     skin_name == 'dtc_status_green'  then s = dtc_skins.static_green()
        elseif skin_name == 'dtc_status_yellow' then s = dtc_skins.static_yellow()
        elseif skin_name == 'dtc_status_red'    then s = dtc_skins.static_red()
        elseif skin_name == 'dtc_separator'     then s = dtc_skins.separator()
        else
            local fn = Skin and Skin[skin_name]
            if not fn then return end
            s = fn()
        end
        if s then widget:setSkin(s) end
    end)
end

local SMSWindow = {}
SMSWindow.__index = SMSWindow

-- Default position: top-right of the screen, 20px in from the right edge,
-- 80px down from the top. Falls back to 1920px screen width if dxgui
-- doesn't expose Gui.GetWindowSize.
local function default_position(w)
    local screen_w = 1920
    pcall(function()
        if Gui and Gui.GetWindowSize then
            local sw = Gui.GetWindowSize()
            if type(sw) == 'number' and sw > 0 then screen_w = sw end
        end
    end)
    return math.max(20, screen_w - w - 20), 80
end

-- Construct an SMSWindow. Returns nil (logged) if the dxgui Window can't
-- be created. Builds the title bar, footer separator + status Static.
-- The body (content area) is left empty — subclass populates via
-- :build_body() or the consumer inserts widgets imperatively after .new
-- returns.
--
-- opts (see spec for the full table):
--   title      string  required — branded with version
--   size       {w,h}   required — initial size in pixels
--   min_size   {w,h}   optional — defaults to opts.size
--   position   {x,y}   optional — defaults to top-right
--   persist_across_new_mission  boolean (default false)
--   disable_undo_hotkey         boolean (default false)
--   on_undo    function(self)                  optional override
--   on_resize  function(self, x, y, w, h)      optional override
--   on_close   function(self)                  optional cleanup hook
function SMSWindow.new(opts)
    if type(opts) ~= 'table' then
        log.write('sms.me', log.ERROR, 'SMSWindow.new: opts must be a table')
        return nil
    end
    if type(opts.title) ~= 'string' or opts.title == '' then
        log.write('sms.me', log.ERROR, 'SMSWindow.new: opts.title is required')
        return nil
    end
    if type(opts.size) ~= 'table' or type(opts.size.w) ~= 'number' or type(opts.size.h) ~= 'number' then
        log.write('sms.me', log.ERROR, 'SMSWindow.new: opts.size = {w, h} is required')
        return nil
    end

    local self = setmetatable({}, SMSWindow)
    self._opts        = opts
    self._size        = { w = opts.size.w, h = opts.size.h }
    self._min_size    = { w = (opts.min_size and opts.min_size.w) or opts.size.w,
                          h = (opts.min_size and opts.min_size.h) or opts.size.h }
    self._flash_state = M._new_flash_state()
    self._tick_registered          = false
    self._new_mission_subscribed   = false

    -- Construct the dxgui Window.
    if not Window or not Static then
        log.write('sms.me', log.ERROR, 'SMSWindow.new: Window/Static module unavailable')
        return nil
    end

    local x, y
    if opts.position and type(opts.position.x) == 'number' and type(opts.position.y) == 'number' then
        x, y = opts.position.x, opts.position.y
    else
        x, y = default_position(self._size.w)
    end

    local title_string = M._compose_title(opts.title, version)
    local win
    local ok, err = pcall(function()
        win = Window.new(x, y, self._size.w, self._size.h, title_string)
    end)
    if not ok or not win then
        log.write('sms.me', log.ERROR, 'SMSWindow.new: Window.new failed: ' .. tostring(err))
        return nil
    end
    self.window = win

    -- Apply the native ME chrome.
    pcall(function()
        win:setSkin((Skin and Skin.windowSkinME and Skin.windowSkinME()) or (Skin and Skin.windowSkin and Skin.windowSkin()) or nil)
    end)
    -- Force-set bounds AFTER setSkin to override any dxgui-restored
    -- persisted size from a prior session — the bulk-rename branch
    -- needed this fix; centralising it here means every window gets it.
    pcall(function() if win.setBounds then win:setBounds(x, y, self._size.w, self._size.h) end end)
    pcall(function() if win.setDraggable then win:setDraggable(true) end end)
    pcall(function() if win.setResizable then win:setResizable(true) end end)
    pcall(function() if win.setZOrder    then win:setZOrder(190)   end end)

    -- Footer band: separator + status Static. Geometry is set by relayout
    -- in Task 4. Both inserted into the window before the body so the
    -- subclass's widgets render on top in case of overlap (defensive;
    -- the layout doesn't actually overlap).
    local sep = Static.new()
    pcall(function() if win.insertWidget then win:insertWidget(sep) end end)
    try_skin(sep, 'dtc_separator')
    self._sep = sep

    local status = Static.new('')
    pcall(function() if win.insertWidget then win:insertWidget(status) end end)
    try_skin(status, 'staticSkin_ME')
    self._status = status

    pcall(function() if win.setVisible then win:setVisible(true) end end)

    -- Initial layout pass + resize callback. _install_resize_callback uses
    -- get_content_bounds and relayout, both defined later — Lua resolves
    -- method lookups at call time, so the forward reference is fine.
    self:_initial_layout()
    self:_install_resize_callback()

    return self
end

-- ---------- Lifecycle ----------

-- show / hide / toggle are idempotent — multiple calls are no-ops past
-- the first. setEnabled(true) on show is defensive: some dxgui builds
-- leave a hidden Window in a disabled state.
function SMSWindow:show()
    pcall(function()
        if self.window and self.window.setVisible then self.window:setVisible(true) end
        if self.window and self.window.setEnabled then self.window:setEnabled(true) end
    end)
end

function SMSWindow:hide()
    pcall(function()
        if self.window and self.window.setVisible then self.window:setVisible(false) end
    end)
    if self._opts and type(self._opts.on_close) == 'function' then
        pcall(self._opts.on_close, self)
    end
end

function SMSWindow:toggle()
    if not self.window then return end
    local visible = false
    pcall(function()
        if self.window.getVisible then visible = self.window:getVisible() end
    end)
    if visible then self:hide() else self:show() end
end

-- Escape hatch: returns the underlying dxgui Window. Used by retrofits
-- that need to attach extra hotkeys (Escape, Ctrl+Shift+R) or callbacks
-- the base doesn't anticipate.
function SMSWindow:raw() return self.window end

-- ---------- Layout ----------

-- Returns the content rect (x, y, w, h) inside the chrome — the area
-- between the title bar (handled by dxgui Window) and the footer
-- (separator + status, owned by this class). Subclasses position their
-- own widgets within this rect.
function SMSWindow:get_content_bounds()
    local sw, sh = self._size.w, self._size.h
    pcall(function()
        if self.window and self.window.getSize then
            local cw, ch = self.window:getSize()
            if cw and ch then sw, sh = cw, ch end
        end
    end)
    return EDGE_PAD, TOP_PAD, sw - 2 * EDGE_PAD, sh - TOP_PAD - FOOTER_H
end

-- Reposition footer widgets to the bottom of the window. Called from
-- the size callback on every resize.
function SMSWindow:_relayout_footer(w, h)
    local sep_y    = h - FOOTER_H
    local status_y = h - FOOTER_H + 1
    pcall(function() if self._sep    and self._sep.setBounds    then self._sep:setBounds(0, sep_y, w, 1) end end)
    pcall(function() if self._status and self._status.setBounds then self._status:setBounds(EDGE_PAD, status_y, w - 2 * EDGE_PAD, 20) end end)
end

-- Default override hooks. Subclasses (or composition consumers via opts)
-- replace these.
function SMSWindow:build_body() end
function SMSWindow:relayout(x, y, w, h) end

-- Wire the dxgui resize callback. Clamps via setBounds when the user
-- shrinks past min_size (re-fires the callback at the clamped size,
-- which is fine), repositions the footer, then dispatches to the
-- subclass's relayout method or the opts.on_resize callback.
function SMSWindow:_install_resize_callback()
    if not (self.window and self.window.addSizeCallback) then return end
    local me = self
    pcall(function()
        self.window:addSizeCallback(function()
            pcall(function()
                local cw, ch = me.window:getSize()
                if cw < me._min_size.w or ch < me._min_size.h then
                    local px, py = me.window:getBounds()
                    me.window:setBounds(px, py, math.max(cw, me._min_size.w), math.max(ch, me._min_size.h))
                    return
                end
                me._size.w, me._size.h = cw, ch
                me:_relayout_footer(cw, ch)
                local x, y, w, h = me:get_content_bounds()
                if me._opts and type(me._opts.on_resize) == 'function' then
                    pcall(me._opts.on_resize, me, x, y, w, h)
                else
                    pcall(SMSWindow.relayout, me, x, y, w, h)
                end
            end)
        end)
    end)
end

-- Initial geometry pass — call once after construction + body build.
-- Replays exactly what the size callback does, so the first paint
-- matches subsequent resizes.
function SMSWindow:_initial_layout()
    self:_relayout_footer(self._size.w, self._size.h)
    local x, y, w, h = self:get_content_bounds()
    if self._opts and type(self._opts.on_resize) == 'function' then
        pcall(self._opts.on_resize, self, x, y, w, h)
    else
        pcall(SMSWindow.relayout, self, x, y, w, h)
    end
end

-- Expose the live class table for inheritance + access to the helpers.
M.SMSWindow = SMSWindow

-- Expose try_skin for reuse by subclasses if they want to reuse the
-- severity-skin resolver. Most won't need it (they go through
-- :set_status / :flash_status).
M._try_skin = try_skin

return M
