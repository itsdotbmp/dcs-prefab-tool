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

-- Text-input + list widgets vary slightly across DCS dxgui builds.
-- Real installs ship `EditBox` and `ListBox` under dxgui/bind/. We try
-- both `EditBox` (the canonical) and `TextBox` (an older alias seen in
-- the plan) so the module loads either way; whichever resolves becomes
-- our text-input class.
local TextBox
do
    local ok, mod = pcall(require, 'EditBox')
    if ok then TextBox = mod
    else
        local ok2, mod2 = pcall(require, 'TextBox')
        if ok2 then TextBox = mod2 end
    end
end
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
    W.list_items = {}      -- index → ListBoxItem widget, parallel to W.rows
    pcall(function()
        if W.list_label and W.list_label.setText then
            W.list_label:setText(string.format('Prefabs (%d)', #W.rows))
        end
    end)
    pcall(function()
        if not W.list_box then return end
        -- Clear existing items: real ListBox API is removeAllItems / clear.
        if W.list_box.removeAllItems then W.list_box:removeAllItems()
        elseif W.list_box.clear then W.list_box:clear() end

        for i, r in ipairs(W.rows) do
            local label
            if r.error then
                label = string.format('%s    [ERROR: %s]', r.name, tostring(r.error):sub(1, 40))
            else
                label = string.format('%s    %s | %dg %ds %dz %dd',
                    r.name,
                    r.theatre or '?',
                    r.group_count or 0,
                    r.static_count or 0,
                    r.zone_count or 0,
                    r.drawing_count or 0)
            end
            -- Real ListBox API: newItem(text) creates and inserts a
            -- ListBoxItem; insertItem(text) (string arg) does NOT exist.
            if W.list_box.newItem then
                local item = W.list_box:newItem(label)
                W.list_items[i] = item
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
-- ListBox's selection-change callback fires with the ListBox widget itself
-- as `self`; the selected ListBoxItem is fetched via getSelectedItem().
-- Map back to the row index via the W.list_items parallel array (set in
-- refresh_list).
local function on_list_select(self_listbox)
    pcall(function()
        local picked
        if self_listbox and self_listbox.getSelectedItem then
            picked = self_listbox:getSelectedItem()
        elseif W.list_box and W.list_box.getSelectedItem then
            picked = W.list_box:getSelectedItem()
        end
        if not picked then return end
        for i, item in ipairs(W.list_items or {}) do
            if item == picked then
                W.selected_idx = i
                local row = selected_row()
                if row then
                    set_status('Selected: ' .. tostring(row.name))
                end
                return
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

-- Show a rename overlay: prompt + text input + OK/Cancel.
-- on_ok receives the new name string; on_cancel takes no args.
local function show_rename_overlay(prompt, current_name, on_ok, on_cancel)
    local screen_w, screen_h = Gui.GetWindowSize()
    local w, h = 460, 150
    local x = (screen_w - w) / 2
    local y = (screen_h - h) / 2
    local overlay, input = nil, nil
    local function close()
        pcall(function() if overlay and overlay.setVisible then overlay:setVisible(false) end end)
    end
    local ok, err = pcall(function()
        overlay = Window.new(x, y, w, h, 'Rename')
        overlay:setSkin(Skin.windowSkin())
        overlay:setVisible(true)
        overlay:setDraggable(true)
        overlay:setResizable(false)
        overlay:setZOrder(220)

        local lbl = Static.new()
        lbl:setBounds(10, 10, w - 20, 20)
        lbl:setText(tostring(prompt or 'New name:'))
        overlay:insertWidget(lbl)

        input = TextBox.new()
        input:setBounds(10, 36, w - 20, 22)
        if input.setText then input:setText(tostring(current_name or '')) end
        if input.setFocused then input:setFocused(true) end
        overlay:insertWidget(input)

        local ok_btn = Button.new()
        ok_btn:setBounds(w - 200, h - 36, 90, 22)
        ok_btn:setText('OK')
        ok_btn:addChangeCallback(function()
            local new_name = (input.getText and input:getText()) or ''
            close()
            pcall(function() (on_ok or function() end)(new_name) end)
        end)
        overlay:insertWidget(ok_btn)

        local cancel_btn = Button.new()
        cancel_btn:setBounds(w - 100, h - 36, 90, 22)
        cancel_btn:setText('Cancel')
        cancel_btn:addChangeCallback(function()
            close()
            pcall(on_cancel or function() end)
        end)
        overlay:insertWidget(cancel_btn)
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'rename overlay failed: ' .. tostring(err))
        pcall(on_cancel or function() end)
    end
end

local function rename_file(old_path, old_name, new_name)
    local prefab, lerr = prefab_ops.load(old_path)
    if not prefab then return false, 'load failed: ' .. tostring(lerr) end
    prefab.meta = prefab.meta or {}
    prefab.meta.name = new_name

    local serializer = require('dcs_sms_me.serializer')
    local serialized = serializer.serialize(prefab)
    local paths = require('dcs_sms_me.paths')
    local new_path = paths.PREFABS_DIR .. new_name .. '.lua'
    if old_path == new_path then return true, old_path end  -- no-op rename
    if prefab_ops.exists(new_name) then return false, 'target name already exists' end

    local f, oerr = io.open(new_path, 'w')
    if not f then return false, 'open failed: ' .. tostring(oerr) end
    f:write(serialized)
    f:close()

    local rok = os.remove(old_path)
    if not rok then
        -- Roll back: delete the new file, keep old.
        os.remove(new_path)
        return false, 'could not delete old file (rolled back)'
    end
    return true, new_path
end

local function on_rename_click()
    local row = require_selection('rename')
    if not row then return end
    show_rename_overlay('Rename "' .. row.name .. '" to:', row.name,
        function(new_name)
            new_name = (new_name or ''):gsub('^%s+', ''):gsub('%s+$', '')
            if new_name == '' then set_status('Rename cancelled (empty name).'); return end
            if new_name == row.name then set_status('Rename cancelled (same name).'); return end
            local ok, msg = rename_file(row.path, row.name, new_name)
            if ok then
                set_status('Renamed ' .. row.name .. ' → ' .. new_name)
                log.write('sms.me.prefab', log.INFO, 'renamed ' .. row.name .. ' → ' .. new_name)
                refresh_list()
            else
                set_status('Rename failed: ' .. tostring(msg))
                log.write('sms.me.prefab', log.ERROR, 'rename failed: ' .. tostring(msg))
            end
        end,
        function() set_status('Rename cancelled.') end)
end

local function on_delete_click()
    local row = require_selection('delete')
    if not row then return end
    show_overlay(
        'Delete "' .. row.name .. '"?\n\nThis cannot be undone.',
        {
            { label = 'Delete', on_click = function()
                local ok, oerr = os.remove(row.path)
                if ok then
                    set_status('Deleted ' .. row.name)
                    log.write('sms.me.prefab', log.INFO, 'deleted ' .. row.name)
                else
                    set_status('Delete failed: ' .. tostring(oerr))
                    log.write('sms.me.prefab', log.ERROR, 'delete failed for ' .. row.path .. ': ' .. tostring(oerr))
                end
                W.selected_idx = nil
                refresh_list()
            end },
            { label = 'Cancel', on_click = function() set_status('Delete cancelled.') end },
        })
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
    log.write('sms.me', log.INFO, 'window.show() called (W.window present=' .. tostring(W.window ~= nil) .. ')')
    if W.window then
        pcall(function() W.window:setVisible(true) end)
        return
    end
    local ok, err = pcall(function()
        local screen_w, _ = Gui.GetWindowSize()
        -- Height needs ~30px reserved for the title bar + ~12px for the
        -- bottom border under the status label, on top of the content
        -- layout. The previous 320 clipped the status bar.
        local w, h = 440, 360
        local x = screen_w - w - 20
        local y = 80

        W.window = Window.new(x, y, w, h, 'dcs-sms — Prefab Manager')
        W.window:setSkin(Skin.windowSkin())
        W.window:setVisible(true)
        W.window:setDraggable(true)
        W.window:setResizable(false)
        W.window:setZOrder(190)

        if W.window.addKeyDownCallback then
            W.window:addKeyDownCallback(function(_, key, modifiers)
                pcall(function()
                    -- Esc cancels place-pending.
                    if W.place_pending and (key == 27 or key == 'KEY_ESCAPE' or key == 'Escape') then
                        set_status('Place cancelled.')
                        exit_place_pending()
                        return
                    end

                    -- Ctrl-Z → undo. Modifier handling varies across dxgui
                    -- builds — accept either an explicit ctrl flag or just
                    -- the Z key (window must be focused for the hook to
                    -- fire, which is our scope guard).
                    local is_z = (key == 'Z' or key == 'z' or key == 90 or key == 'KEY_Z')
                    if is_z then
                        local ctrl = false
                        if type(modifiers) == 'table' then ctrl = modifiers.ctrl or modifiers.control end
                        if type(modifiers) == 'number' then ctrl = (modifiers % 8) >= 4 end  -- best-effort bitmask
                        if ctrl or modifiers == nil then
                            on_undo_click()
                        end
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
        -- Real ListBox API uses addSelectionChangeCallback. addChangeCallback
        -- exists on simpler widgets like Button but does not fire on ListBox
        -- selection. Try the real one first, fall back to the older alias.
        if W.list_box.addSelectionChangeCallback then
            W.list_box:addSelectionChangeCallback(on_list_select)
        elseif W.list_box.addChangeCallback then
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
