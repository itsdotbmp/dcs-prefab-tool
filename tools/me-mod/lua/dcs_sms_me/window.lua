-- window.lua — Prefab Manager.
--
-- Single window, all panels visible. Constructed lazily on first show().
-- All callbacks are pcall-guarded so dxgui or DCS-API failures degrade to
-- a status-label message rather than crashing the editor.
--
-- Public:
--   M.show()    — idempotent
--   M.hide()    — idempotent
--   M.toggle()  — show if hidden, hide if shown

local Window  = require('Window')
local Static  = require('Static')
local Button  = require('Button')
local Gui     = require('dxgui')
local Skin    = require('Skin')

-- TextBox and ListBox may not be exposed in every DCS ME GUI build.
-- Loaded via pcall and falling back to Static placeholders so module
-- load never fails on a missing widget.
local TextBox; do local ok, mod = pcall(require, 'TextBox'); if ok then TextBox = mod end end
local ListBox; do local ok, mod = pcall(require, 'ListBox'); if ok then ListBox = mod end end

local prefab_ops = require('dcs_sms_me.prefab_ops')
local undo       = require('dcs_sms_me.undo')

local M = {}

local W = {
    -- dxgui handles
    window     = nil,
    name_input = nil,
    save_btn   = nil,
    reload_btn = nil,
    list_box   = nil,
    list_label = nil,
    rotation_input = nil,
    place_click_btn   = nil,
    place_origin_btn  = nil,
    rename_btn = nil,
    delete_btn = nil,
    undo_btn   = nil,
    status     = nil,

    -- runtime state
    rows           = {},        -- last scan_dir result
    selected_idx   = nil,        -- index into rows of currently selected library row
    place_pending  = false,      -- in place-pending mode (Task 12)
    place_pending_name = nil,    -- name of prefab being placed
}

local function set_status(text)
    pcall(function()
        if W.status and W.status.setText then W.status:setText(tostring(text or '')) end
    end)
end
M._set_status = set_status  -- exposed for later tasks

local function refresh_list()
    W.rows = prefab_ops.scan_dir() or {}
    pcall(function()
        if W.list_label and W.list_label.setText then
            W.list_label:setText(string.format('Prefabs (%d)', #W.rows))
        end
    end)
    pcall(function()
        if W.list_box and W.list_box.removeItems then W.list_box:removeItems() end
        for _, r in ipairs(W.rows) do
            local label
            if r.error then
                label = string.format('%s    [ERROR: %s]', r.name, tostring(r.error):sub(1, 40))
            else
                label = string.format('%s    %s · %dg %ds %dz %dd',
                    r.name,
                    r.theatre or '?',
                    r.group_count or 0,
                    r.static_count or 0,
                    r.zone_count or 0,
                    r.drawing_count or 0)
            end
            if W.list_box and W.list_box.insertItem then
                W.list_box:insertItem(label)
            end
        end
    end)
end
M._refresh_list = refresh_list  -- exposed for later tasks

local function selected_row()
    if not W.selected_idx then return nil end
    return W.rows[W.selected_idx]
end
M._selected_row = selected_row

-- ---------------------------------------------------------------------------
-- Modal overlay helper. Shows a small centered window with a message and
-- up to 3 buttons. Each button calls the supplied callback then closes the
-- overlay. Buttons:
--   { {label='OK',  on_click=function() ... end}, ... }
-- ---------------------------------------------------------------------------

local function show_overlay(message, buttons)
    local screen_w, screen_h = Gui.GetWindowSize()
    local w, h = 420, 130
    local x = (screen_w - w) / 2
    local y = (screen_h - h) / 2

    local overlay = nil
    local function close()
        pcall(function() if overlay and overlay.setVisible then overlay:setVisible(false) end end)
    end

    local ok, err = pcall(function()
        overlay = Window.new(x, y, w, h, '')
        overlay:setSkin(Skin.windowSkin())
        overlay:setVisible(true)
        overlay:setDraggable(true)
        overlay:setResizable(false)
        overlay:setZOrder(220)

        local msg = Static.new()
        msg:setBounds(10, 10, w - 20, h - 60)
        msg:setText(tostring(message or ''))
        overlay:insertWidget(msg)

        local n = #buttons
        local bw = math.floor((w - 20 - (n - 1) * 10) / n)
        for i, b in ipairs(buttons) do
            local btn = Button.new()
            btn:setBounds(10 + (i - 1) * (bw + 10), h - 36, bw, 22)
            btn:setText(b.label or '?')
            btn:addChangeCallback(function()
                pcall(b.on_click or function() end)
                close()
            end)
            overlay:insertWidget(btn)
        end
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'overlay construction failed: ' .. tostring(err))
        -- Best-effort: just call the first (default) button to keep flow.
        if buttons[1] and buttons[1].on_click then pcall(buttons[1].on_click) end
    end
end
M._show_overlay = show_overlay  -- exposed for later tasks

local function focus_name_input()
    pcall(function()
        if W.name_input and W.name_input.setFocused then W.name_input:setFocused(true) end
    end)
end

local function do_save(name)
    local ok, path_or_err = prefab_ops.save_selection(name)
    if ok then
        set_status('Saved ' .. name .. ' → ' .. tostring(path_or_err))
        log.write('sms.me.prefab', log.INFO, 'saved ' .. name)
        refresh_list()
    else
        set_status('Save failed: ' .. tostring(path_or_err))
        log.write('sms.me.prefab', log.ERROR, 'save failed: ' .. tostring(path_or_err))
    end
end

local function on_save_click()
    pcall(function()
        local name = ''
        if W.name_input and W.name_input.getText then name = W.name_input:getText() or '' end
        if name == '' then
            set_status('Empty name — using timestamped fallback. See dcs.log.')
            name = 'prefab-' .. os.date('!%Y%m%dT%H%M%SZ')
            log.write('sms.me.prefab', log.WARNING, 'save with empty name → ' .. name)
            do_save(name)
            return
        end

        if prefab_ops.exists(name) then
            show_overlay(
                'Prefab "' .. name .. '" already exists.\n\nOverwrite, rename, or cancel?',
                {
                    { label = 'Overwrite', on_click = function() do_save(name) end },
                    { label = 'Rename',    on_click = function() focus_name_input(); set_status('Type a new name and click Save.') end },
                    { label = 'Cancel',    on_click = function() set_status('Save cancelled.') end },
                })
            return
        end

        do_save(name)
    end)
end

local function on_reload_click()
    pcall(function() refresh_list(); set_status('Library reloaded.') end)
end

local function require_selection(action_label)
    local row = selected_row()
    if not row then
        set_status('Select a prefab in the list first (' .. action_label .. ').')
        return nil
    end
    if row.error then
        set_status('Cannot ' .. action_label .. ' — file has load error.')
        return nil
    end
    return row
end

-- List-row select callback.
local function on_list_select(_, idx)
    pcall(function()
        if type(idx) == 'number' then
            W.selected_idx = idx
            local row = selected_row()
            if row then
                set_status('Selected: ' .. tostring(row.name))
            end
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Place-pending state machine
-- ---------------------------------------------------------------------------

local exit_place_pending  -- forward declaration; assigned below

local function enter_place_pending(prefab_name, prefab_table, rotation_deg)
    W.place_pending = true
    W.place_pending_name = prefab_name
    pcall(function()
        if W.window and W.window.setText then W.window:setText('Click on map to place ' .. prefab_name .. ' (Esc to cancel)') end
    end)
    pcall(function()
        if W.place_click_btn and W.place_click_btn.setText then W.place_click_btn:setText('Cancel') end
    end)
    set_status('Click on the map to place ' .. prefab_name .. '...')

    -- Map-click hook via me_map_window state machine.
    -- We create a plain table that satisfies the NewMapView state interface
    -- (onMouseDown / onMouseUp / onMouseDrag / onMouseMove / onMouseWheel).
    -- me_map_window.setState() installs it; exit_place_pending restores panState.
    -- Coord conversion: me_map_window.getMapPoint(screen_x, screen_y) → world x, y.
    local ok = pcall(function()
        local MapWindow = require('me_map_window')
        if not (MapWindow and MapWindow.setState and MapWindow.getPanState and MapWindow.getMapPoint) then
            error('me_map_window missing required symbols')
        end

        local place_state = {}

        function place_state:onMouseDown(x, y, button)
            pcall(function()
                if not W.place_pending then return end
                if button ~= 1 then return end  -- only left-click places
                local wx, wy = MapWindow.getMapPoint(x, y)
                if not (wx and wy) then
                    set_status('Place failed: getMapPoint returned nil')
                    log.write('sms.me.prefab', log.ERROR, 'place: getMapPoint returned nil')
                    exit_place_pending()
                    return
                end
                local rec, err = prefab_ops.place(prefab_table, { anchor = { x = wx, y = wy }, rotation = rotation_deg })
                if rec then
                    undo.record(rec)
                    set_status(string.format('Placed %s (%dg %ds %dz %dd) at (%.0f, %.0f)',
                        prefab_name, #rec.groups, #rec.statics, #rec.zones, #rec.drawings, wx, wy))
                    log.write('sms.me.prefab', log.INFO, 'placed ' .. prefab_name)
                else
                    set_status('Place failed: ' .. tostring(err))
                    log.write('sms.me.prefab', log.ERROR, 'place failed: ' .. tostring(err))
                end
                exit_place_pending()
            end)
        end

        function place_state:onMouseUp(x, y, button) end
        function place_state:onMouseDrag(dx, dy, button, x, y) end
        function place_state:onMouseMove(x, y) end
        function place_state:onMouseWheel(x, y, clicks) end

        MapWindow.setState(place_state)
    end)
    if not ok then
        set_status('Place at click unavailable — try Place at original. See dcs.log.')
        log.write('sms.me.prefab', log.ERROR, 'map-click hook unavailable')
        exit_place_pending()
    end
end

exit_place_pending = function()
    W.place_pending = false
    W.place_pending_name = nil
    pcall(function()
        if W.window and W.window.setText then W.window:setText('dcs-sms — Prefab Manager') end
    end)
    pcall(function()
        if W.place_click_btn and W.place_click_btn.setText then W.place_click_btn:setText('Place at click') end
    end)
    pcall(function()
        local MapWindow = require('me_map_window')
        if MapWindow and MapWindow.setState and MapWindow.getPanState then
            MapWindow.setState(MapWindow.getPanState())
        end
    end)
end

local function get_rotation_deg()
    local s = '0'
    pcall(function()
        if W.rotation_input and W.rotation_input.getText then s = W.rotation_input:getText() or '0' end
    end)
    local n = tonumber(s)
    if not n then return 0 end
    return n
end

local function on_place_click()
    if W.place_pending then
        -- Acting as Cancel.
        set_status('Place cancelled.')
        exit_place_pending()
        return
    end
    local row = require_selection('place')
    if not row then return end
    local prefab, lerr = prefab_ops.load(row.path)
    if not prefab then
        set_status('Load failed: ' .. tostring(lerr))
        log.write('sms.me.prefab', log.ERROR, 'load failed for ' .. row.path .. ': ' .. tostring(lerr))
        return
    end
    enter_place_pending(row.name, prefab, get_rotation_deg())
end

local function on_place_origin_click()
    local row = require_selection('place at original')
    if not row then return end
    local prefab, lerr = prefab_ops.load(row.path)
    if not prefab then
        set_status('Load failed: ' .. tostring(lerr))
        log.write('sms.me.prefab', log.ERROR, 'load failed for ' .. row.path .. ': ' .. tostring(lerr))
        return
    end
    local rotation_deg = get_rotation_deg()
    local rec, err = prefab_ops.place(prefab, { keep_position = true, rotation = rotation_deg })
    if rec then
        undo.record(rec)
        local wa = prefab.meta and prefab.meta.world_anchor or { x = 0, y = 0 }
        set_status(string.format('Placed %s at original (%dg %ds %dz %dd) at (%.0f, %.0f)',
            row.name, #rec.groups, #rec.statics, #rec.zones, #rec.drawings, wa.x, wa.y))
        log.write('sms.me.prefab', log.INFO, 'placed ' .. row.name .. ' at original')
    else
        set_status('Place failed: ' .. tostring(err))
        log.write('sms.me.prefab', log.ERROR, 'place at original failed: ' .. tostring(err))
    end
end

local function on_rename_click()
    if not require_selection('rename') then return end
    set_status('Rename — wired in Task 13')
end

local function on_delete_click()
    if not require_selection('delete') then return end
    set_status('Delete — wired in Task 13')
end
local function on_undo_click()
    pcall(function()
        if not undo.has_record() then set_status('Nothing to undo.'); return end
        local ok, err = undo.undo()
        if ok then
            set_status('Undid last place' .. (err and (' (' .. err .. ')') or ''))
        else
            set_status('Undo failed: ' .. tostring(err))
        end
    end)
end

function M.show()
    if W.window then
        pcall(function() W.window:setVisible(true) end)
        return
    end
    local ok, err = pcall(function()
        local screen_w, _ = Gui.GetWindowSize()
        local w, h = 420, 320
        local x = screen_w - w - 20
        local y = 80

        W.window = Window.new(x, y, w, h, 'dcs-sms — Prefab Manager')
        W.window:setSkin(Skin.windowSkin())
        W.window:setVisible(true)
        W.window:setDraggable(true)
        W.window:setResizable(false)
        W.window:setZOrder(190)

        -- Esc cancels place-pending if window has focus.
        if W.window.addKeyDownCallback then
            W.window:addKeyDownCallback(function(_, key)
                pcall(function()
                    if not W.place_pending then return end
                    -- Match by numeric code 27 (ASCII Esc) or by key name string —
                    -- dxgui doesn't expose a stable cross-version key constant.
                    if key == 27 or key == 'KEY_ESCAPE' or key == 'Escape' then
                        set_status('Place cancelled.')
                        exit_place_pending()
                    end
                end)
            end)
        end

        -- Save panel (top): "Name: [______] [Save]"
        local section_label_save = Static.new()
        section_label_save:setBounds(10, 6, w - 20, 16)
        section_label_save:setText('Save current selection')
        W.window:insertWidget(section_label_save)

        local name_label = Static.new()
        name_label:setBounds(10, 26, 50, 22)
        name_label:setText('Name:')
        W.window:insertWidget(name_label)

        if TextBox then
            W.name_input = TextBox.new()
        else
            W.name_input = Static.new()
            W.name_input.setText = W.name_input.setText  -- API parity stub
        end
        W.name_input:setBounds(64, 26, w - 64 - 80 - 16, 22)
        if W.name_input.setText then W.name_input:setText('') end
        W.window:insertWidget(W.name_input)

        W.save_btn = Button.new()
        W.save_btn:setBounds(w - 90, 26, 80, 22)
        W.save_btn:setText('Save')
        W.save_btn:addChangeCallback(on_save_click)
        W.window:insertWidget(W.save_btn)

        -- Library section
        W.list_label = Static.new()
        W.list_label:setBounds(10, 60, w - 20 - 80, 16)
        W.list_label:setText('Prefabs (0)')
        W.window:insertWidget(W.list_label)

        W.reload_btn = Button.new()
        W.reload_btn:setBounds(w - 90, 56, 80, 22)
        W.reload_btn:setText('Reload')
        W.reload_btn:addChangeCallback(on_reload_click)
        W.window:insertWidget(W.reload_btn)

        if ListBox then
            W.list_box = ListBox.new()
        else
            W.list_box = Static.new()
            if W.list_box.setText then W.list_box:setText('ListBox not available') end
        end
        W.list_box:setBounds(10, 80, w - 20, 130)
        if W.list_box.addChangeCallback then
            W.list_box:addChangeCallback(on_list_select)
        end
        W.window:insertWidget(W.list_box)

        -- Action panel
        local rotation_label = Static.new()
        rotation_label:setBounds(10, 218, 60, 22)
        rotation_label:setText('Rotation:')
        W.window:insertWidget(rotation_label)

        if TextBox then
            W.rotation_input = TextBox.new()
        else
            W.rotation_input = Static.new()
            W.rotation_input.setText = W.rotation_input.setText  -- API parity stub
        end
        W.rotation_input:setBounds(70, 218, 50, 22)
        if W.rotation_input.setText then W.rotation_input:setText('0') end
        W.window:insertWidget(W.rotation_input)

        local rotation_unit = Static.new()
        rotation_unit:setBounds(122, 218, 20, 22)
        rotation_unit:setText('°')
        W.window:insertWidget(rotation_unit)

        local btn_y_1 = 244
        W.place_click_btn = Button.new()
        W.place_click_btn:setBounds(10, btn_y_1, 130, 22)
        W.place_click_btn:setText('Place at click')
        W.place_click_btn:addChangeCallback(on_place_click)
        W.window:insertWidget(W.place_click_btn)

        W.place_origin_btn = Button.new()
        W.place_origin_btn:setBounds(146, btn_y_1, 130, 22)
        W.place_origin_btn:setText('Place at original')
        W.place_origin_btn:addChangeCallback(on_place_origin_click)
        W.window:insertWidget(W.place_origin_btn)

        local btn_y_2 = 270
        W.rename_btn = Button.new()
        W.rename_btn:setBounds(10, btn_y_2, 80, 22)
        W.rename_btn:setText('Rename')
        W.rename_btn:addChangeCallback(on_rename_click)
        W.window:insertWidget(W.rename_btn)

        W.delete_btn = Button.new()
        W.delete_btn:setBounds(96, btn_y_2, 80, 22)
        W.delete_btn:setText('Delete')
        W.delete_btn:addChangeCallback(on_delete_click)
        W.window:insertWidget(W.delete_btn)

        W.undo_btn = Button.new()
        W.undo_btn:setBounds(182, btn_y_2, 130, 22)
        W.undo_btn:setText('Undo last place')
        W.undo_btn:addChangeCallback(on_undo_click)
        W.window:insertWidget(W.undo_btn)

        -- Status
        W.status = Static.new()
        W.status:setBounds(10, 296, w - 20, 16)
        W.status:setText('Ready.')
        W.window:insertWidget(W.status)

        refresh_list()
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'window construction failed: ' .. tostring(err))
        W.window = nil
        return
    end
    log.write('sms.me', log.INFO, 'Prefab Manager window opened')
end

function M.hide()
    pcall(function()
        if W.window and W.window.setVisible then W.window:setVisible(false) end
    end)
end

function M.toggle()
    if W.window then
        local visible = false
        pcall(function() if W.window.isVisible then visible = W.window:isVisible() end end)
        if visible then M.hide() else pcall(function() W.window:setVisible(true) end) end
    else
        M.show()
    end
end

return M
