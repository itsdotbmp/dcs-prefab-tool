-- menu.lua — Customize-menu entry registration with floating-button fallback.
--
-- ME-API path (discovered 2026-05-03 by re-reading me_menubar.lua):
--   me_menubar's `menuBar` table IS module-public — set without `local` at
--   line 467: `menuBar = window.menuBar`. So `require('me_menubar').menuBar`
--   resolves once me_menubar.create_() has run (which it does when
--   me_menubar.show() is first called).
--
--   The Customize menu has a public-stable shape:
--     menuBar.customize.menu  -- a Menu widget with :newItem(label, pos)
--     existing items (missionOptions, mapOptions, setPosition, logbook)
--     can be queried via :getSkin() to skin our new item consistently.
--
--   me_menubar's setCustomizeMenu() already wires `menu:onChange` to call
--   `item.func` for any clicked item — so we just set our item's `.func`
--   and it fires on click.
--
-- Strategy:
--   1. At install time, try to add the menu entry immediately (in case the
--      menubar is already constructed).
--   2. If menuBar isn't ready yet, monkey-patch me_menubar.show so the
--      entry is added the next time ME shows the menubar.
--   3. If me_menubar isn't accessible at all, fall back to a floating
--      toggle window.

local M = {}

local function get_window()
    return require('dcs_sms_me.window')
end

-- Add our entry to me_menubar.menuBar.customize.menu. Idempotent.
-- Returns true if the entry exists in the menu after this call.
local function add_menu_entry()
    local ok, mb = pcall(require, 'me_menubar')
    if not ok or not mb or not mb.menuBar then return false end
    local customize = mb.menuBar.customize
    if not customize or not customize.menu then return false end
    local menu = customize.menu
    if menu._dcs_sms_prefab_added then return true end  -- idempotency

    local item
    local ok_new, err = pcall(function()
        item = menu:newItem('PREFAB MANAGER')
    end)
    if not ok_new or not item then
        log.write('sms.me', log.ERROR, 'menu:newItem failed: ' .. tostring(err))
        return false
    end

    -- Copy the skin from an existing item so our entry visually matches.
    pcall(function()
        local sibling = menu.missionOptions or menu.mapOptions
                     or menu.setPosition  or menu.logbook
        if sibling and sibling.getSkin then
            local skin = sibling:getSkin()
            if skin and item.setSkin then item:setSkin(skin) end
        end
    end)

    -- The Customize menu's onChange already calls item.func on click
    -- (set up by me_menubar.setMenuCallback / setCustomizeMenu).
    -- Log explicitly so failures during require/toggle don't get
    -- swallowed by the caller's protection.
    item.func = function()
        log.write('sms.me', log.INFO, 'Prefab Manager menu item clicked')
        local ok, err = pcall(function()
            local win = require('dcs_sms_me.window')
            win.toggle()
        end)
        if not ok then
            log.write('sms.me', log.ERROR,
                'Prefab Manager toggle failed: ' .. tostring(err))
        end
    end

    menu._dcs_sms_prefab_added = true
    return true
end

-- Monkey-patch me_menubar.show so add_menu_entry runs after the menubar
-- is constructed. Idempotent — only patches once.
local function patch_menubar_show()
    local ok, mb = pcall(require, 'me_menubar')
    if not ok or not mb or type(mb.show) ~= 'function' then return false end
    if mb._dcs_sms_show_patched then return true end

    local orig_show = mb.show
    mb.show = function(...)
        local result = orig_show(...)
        pcall(add_menu_entry)
        return result
    end
    mb._dcs_sms_show_patched = true
    return true
end

-- install_floating_fallback ------------------------------------------------
-- Last-resort floating window with a Prefab Manager toggle button.
-- Sized to fit the title bar + a button below it. The earlier 36-tall
-- window had its content clipped under the title bar, which is why the
-- previous build looked half-cut-off.

local function install_floating_fallback()
    local ok, err = pcall(function()
        local Window = require('Window')
        local Button = require('Button')
        local Skin   = require('Skin')
        local Gui    = require('dxgui')

        local screen_w, _ = Gui.GetWindowSize()
        local w, h = 220, 64        -- enough for the title bar + button below
        local x = screen_w - w - 20
        local y = 8

        local fb = Window.new(x, y, w, h, 'dcs-sms')
        fb:setSkin(Skin.windowSkin())
        fb:setVisible(true)
        fb:setDraggable(true)
        fb:setResizable(false)
        fb:setZOrder(195)

        local btn = Button.new()
        btn:setBounds(8, 26, w - 16, 30)   -- y=26 leaves room for the title bar
        btn:setText('Prefab Manager')
        btn:addChangeCallback(function()
            pcall(function() get_window().toggle() end)
        end)
        fb:insertWidget(btn)
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'menu fallback failed: ' .. tostring(err))
    end
end

-- M.install ---------------------------------------------------------------
-- Public entry point. Returns:
--   "menu"     — added entry to Customize menu (immediately or via patch)
--   "fallback" — me_menubar wasn't accessible; floating button installed
function M.install()
    -- Try to add immediately. If menubar already exists we're done.
    if add_menu_entry() then
        log.write('sms.me', log.INFO, 'Prefab Manager added to Customize menu')
        return 'menu'
    end

    -- Otherwise, schedule via show-patch — entry will appear the next time
    -- the menubar is shown (usually right after init, on first ME paint).
    if patch_menubar_show() then
        log.write('sms.me', log.INFO,
            'Prefab Manager will be added to Customize menu when menubar shows')
        return 'menu'
    end

    log.write('sms.me', log.WARNING,
        'me_menubar inaccessible; using floating-button fallback')
    install_floating_fallback()
    return 'fallback'
end

return M
