-- menu.lua — Tools-menu entry registration with floating-button fallback.
--
-- ME-API investigation result (2026-05-03):
--   me_menubar.lua uses module('me_menubar') and keeps its menuBar variable
--   module-local — no getToolsMenu(), getMenu(), or any menu accessor is
--   exported.  The setModMEMenu() plugin hook requires being registered in
--   base.plugins[*].callbacksME, which is only available to compiled DCS
--   modules, not to Lua mod injections.  There is also no 'tools' top-level
--   menu in the menubar at all (keys: file, view, edit, flight, campaign,
--   customize, generator, help, dymMission).
--
-- Therefore try_install_menu() always returns false, and the guaranteed
-- fallback — a small floating toggle button — is the v1 UI entry point.
-- Either way, clicking the entry/button calls window.toggle().

local M = {}

local function get_window()
    return require('dcs_sms_me.window')
end

-- try_install_menu --------------------------------------------------------
-- Attempts to register an entry in the ME's Tools menu using whatever
-- menu API is available.  Returns true on success, false if nothing works.
-- All access is pcall-guarded so a missing/wrong API is a silent no-op.

local function try_install_menu()
    -- me_menubar does not export any menu accessor, and there is no
    -- 'me_main_window' module in DCS World (confirmed by file search).
    -- The setModMEMenu() plugin hook requires base.plugins registration
    -- (compiled DCS module path), which is not available here.
    -- Return false unconditionally so the floating-button fallback runs.
    local ok, menubar = pcall(require, 'me_menubar')
    if not ok or not menubar then return false end

    -- me_menubar is a module() style module; its menuBar table is local.
    -- None of the exported symbols expose a menu item factory.
    -- If a future DCS version adds an accessor, add the attempt here:
    --   if menubar.getToolsMenu then ... end

    return false
end

-- install_floating_fallback -----------------------------------------------
-- Creates a small draggable button at the top-right of the ME screen.
-- Clicking it calls window.toggle().  Errors are logged but never thrown.

local function install_floating_fallback()
    local ok, err = pcall(function()
        local Window = require('Window')
        local Button = require('Button')
        local Skin   = require('Skin')
        local Gui    = require('dxgui')

        local screen_w, _ = Gui.GetWindowSize()
        local w, h = 200, 36
        local x = screen_w - w - 20
        local y = 8

        local fb = Window.new(x, y, w, h, '')
        fb:setSkin(Skin.windowSkin())
        fb:setVisible(true)
        fb:setDraggable(true)
        fb:setResizable(false)
        fb:setZOrder(195)

        local btn = Button.new()
        btn:setBounds(0, 0, w, h)
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
-- Public entry point.  Call once during ME startup.
-- Returns true if a native menu entry was installed, false if the
-- floating-button fallback was used instead.

function M.install()
    if try_install_menu() then
        log.write('sms.me', log.INFO, 'Tools menu entry installed')
        return true
    end
    log.write('sms.me', log.WARNING,
        'Tools menu API unavailable; using floating-button fallback')
    install_floating_fallback()
    return false
end

return M
