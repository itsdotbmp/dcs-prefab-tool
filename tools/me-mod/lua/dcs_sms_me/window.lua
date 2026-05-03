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
-- Grid + GridHeaderCell are the multi-column equivalents of ListBox. We use
-- Grid for the prefab library so each prefab's metadata gets its own column
-- (Name / Theatre / G / S / Z / D) instead of being stuffed into a single
-- formatted line. pcall-guarded so the module still loads in environments
-- where these widgets aren't bound (e.g. test VMs or older dxgui builds).
local Grid;            do local ok, mod = pcall(require, 'Grid');            if ok then Grid            = mod end end
local GridHeaderCell;  do local ok, mod = pcall(require, 'GridHeaderCell');  if ok then GridHeaderCell  = mod end end

local prefab_ops = require('dcs_sms_me.prefab_ops')
local undo       = require('dcs_sms_me.undo')
local dtc_skins  = require('dcs_sms_me.dtc_skins')

-- Apply a skin by name. Resolves in this order:
--   * 'dtc_button' / 'dtc_grid' / 'dtc_grid_header' → DTC-dialog-style skins
--     built at runtime in dtc_skins.lua. These give the small dark-blue
--     ADD/EDIT button look + the navy grid look from me_DTCnew.dlg.
--   * any other name → looked up in the Skin module, which auto-generates
--     one function per entry in dxgui/skins/skinME/skin_names.lua (e.g.
--     Skin.staticSkin_ME, Skin.editBoxSkin_ME).
-- Failures (missing skin builder, widget without setSkin, runtime error)
-- degrade silently so the widget keeps its default skin.
local function try_skin(widget, skin_name)
    pcall(function()
        if not (widget and widget.setSkin) then return end
        local s
        if     skin_name == 'dtc_button'      then s = dtc_skins.button()
        elseif skin_name == 'dtc_grid'        then s = dtc_skins.grid()
        elseif skin_name == 'dtc_grid_header' then s = dtc_skins.grid_header()
        else
            local fn = Skin[skin_name]
            if not fn then return end
            s = fn()
        end
        if s then widget:setSkin(s) end
    end)
end

local M = {}

local W = {
    -- dxgui handles
    window     = nil,
    name_input = nil,
    save_btn   = nil,
    reload_btn = nil,
    grid       = nil,
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

-- Build a Static cell widget for a Grid cell. Inline helper so the cell
-- skin and the optional tooltip are applied consistently.
local function make_cell(text, tooltip)
    local s = Static.new(tostring(text or ''))
    try_skin(s, 'staticSkin_ME')
    if tooltip and s.setTooltipText then
        pcall(function() s:setTooltipText(tostring(tooltip)) end)
    end
    return s
end

local function refresh_list()
    W.rows = prefab_ops.scan_dir() or {}
    pcall(function()
        if W.list_label and W.list_label.setText then
            W.list_label:setText(string.format('Prefabs (%d)', #W.rows))
        end
    end)
    pcall(function()
        if not W.grid then return end
        -- removeAllRows wipes both row structures and any cell widgets we
        -- inserted in the previous refresh — equivalent to ListBox's
        -- removeAllItems for our purposes.
        if W.grid.removeAllRows then W.grid:removeAllRows() end

        for i, r in ipairs(W.rows) do
            -- Grid is 0-indexed for both columns and rows.
            W.grid:insertRow(nil)  -- nil → use rowHeight from gridSkin_ME (30px)
            local row = i - 1

            if r.error then
                local err_text = tostring(r.error)
                W.grid:setCell(0, row, make_cell('[ERROR] ' .. r.name, err_text))
                W.grid:setCell(1, row, make_cell(err_text:sub(1, 40), err_text))
                W.grid:setCell(2, row, make_cell(''))
                W.grid:setCell(3, row, make_cell(''))
                W.grid:setCell(4, row, make_cell(''))
                W.grid:setCell(5, row, make_cell(''))
            else
                W.grid:setCell(0, row, make_cell(r.name, r.name))
                W.grid:setCell(1, row, make_cell(r.theatre or '?'))
                W.grid:setCell(2, row, make_cell(r.group_count   or 0))
                W.grid:setCell(3, row, make_cell(r.static_count  or 0))
                W.grid:setCell(4, row, make_cell(r.zone_count    or 0))
                W.grid:setCell(5, row, make_cell(r.drawing_count or 0))
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
    -- h grew 130 → 170 so the buttons sit clear of the skin's bottom
    -- border. The ~26px title bar at the top + ~14px bottom border
    -- means content area is roughly h - 40 = 130; buttons at y=128
    -- (h - 42) leave 22px above the bottom border.
    local w, h = 420, 170
    local x = (screen_w - w) / 2
    local y = (screen_h - h) / 2

    local overlay = nil
    local function close()
        pcall(function() if overlay and overlay.setVisible then overlay:setVisible(false) end end)
    end

    local ok, err = pcall(function()
        overlay = Window.new(x, y, w, h, '')
        overlay:setSkin((Skin.windowSkinME and Skin.windowSkinME()) or Skin.windowSkin())
        overlay:setVisible(true)
        overlay:setDraggable(true)
        overlay:setResizable(false)
        overlay:setZOrder(220)

        local msg = Static.new()
        msg:setBounds(10, 14, w - 20, h - 70)
        msg:setText(tostring(message or ''))
        try_skin(msg, 'staticSkin_ME')
        overlay:insertWidget(msg)

        local n = #buttons
        local bw = math.floor((w - 20 - (n - 1) * 10) / n)
        for i, b in ipairs(buttons) do
            local btn = Button.new()
            btn:setBounds(10 + (i - 1) * (bw + 10), h - 42, bw, 22)
            btn:setText(b.label or '?')
            try_skin(btn, 'dtc_button')
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

-- Grid-row select callback.
-- Grid:getSelectedRow() returns the 0-based row index, or -1 if nothing is
-- selected. Map to W.rows[idx+1]. The callback is wired both via
-- addSelectRowCallback (fires on keyboard arrow-key changes) and via an
-- onMouseDown override that calls grid:selectRow(row) — Grid's built-in
-- mouse handler does not auto-select on click; see me_openfile.lua's
-- setupCallbacksAddGrid for the pattern we mirror.
local function on_list_select(...)
    pcall(function()
        if not (W.grid and W.grid.getSelectedRow) then
            W.selected_idx = nil
            return
        end
        local idx = W.grid:getSelectedRow()
        if type(idx) ~= 'number' or idx < 0 then
            W.selected_idx = nil
            return
        end
        W.selected_idx = idx + 1
        local row = selected_row()
        if row then
            set_status('Selected: ' .. tostring(row.name))
        end
        log.write('sms.me', log.INFO,
            'on_list_select grid row=' .. tostring(idx)
            .. ' (' .. tostring(row and row.name or '?') .. ')')
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
        if W.window and W.window.setText then
            -- ALL-CAPS + arrow markers to make place-pending unmistakable
            -- without needing color (dxgui Static has no setColor API).
            W.window:setText('▶▶▶ PLACING "' .. prefab_name .. '" — CLICK MAP (Esc cancels) ◀◀◀')
        end
    end)
    pcall(function()
        if W.place_click_btn and W.place_click_btn.setText then W.place_click_btn:setText('Cancel') end
    end)
    set_status('▶▶▶ PLACING "' .. prefab_name .. '" — CLICK ON THE MAP (Esc cancels) ◀◀◀')

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
                    -- record.statics doesn't exist in Task 6's shape (statics
                    -- ride inside record.groups since DCS treats them as
                    -- groups with type='static'). Sum errors instead.
                    set_status(string.format(
                        'Placed %s (%dg %dz %dd, %d errors) at (%.0f, %.0f)',
                        prefab_name,
                        #(rec.groups or {}),
                        #(rec.zones or {}),
                        #(rec.drawings or {}),
                        #(rec.errors or {}),
                        wx, wy))
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
        set_status(string.format(
            'Placed %s at original (%dg %dz %dd, %d errors) at (%.0f, %.0f)',
            row.name,
            #(rec.groups or {}),
            #(rec.zones or {}),
            #(rec.drawings or {}),
            #(rec.errors or {}),
            wa.x, wa.y))
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
    -- Same skin-bottom-border accommodation as show_overlay above.
    local w, h = 460, 180
    local x = (screen_w - w) / 2
    local y = (screen_h - h) / 2
    local overlay, input = nil, nil
    local function close()
        pcall(function() if overlay and overlay.setVisible then overlay:setVisible(false) end end)
    end
    local ok, err = pcall(function()
        overlay = Window.new(x, y, w, h, 'Rename')
        overlay:setSkin((Skin.windowSkinME and Skin.windowSkinME()) or Skin.windowSkin())
        overlay:setVisible(true)
        overlay:setDraggable(true)
        overlay:setResizable(false)
        overlay:setZOrder(220)

        local lbl = Static.new()
        lbl:setBounds(10, 14, w - 20, 20)
        lbl:setText(tostring(prompt or 'New name:'))
        try_skin(lbl, 'staticSkin_ME')
        overlay:insertWidget(lbl)

        input = TextBox.new()
        input:setBounds(10, 40, w - 20, 22)
        if input.setText then input:setText(tostring(current_name or '')) end
        if input.setFocused then input:setFocused(true) end
        try_skin(input, 'editBoxSkin_ME')
        overlay:insertWidget(input)

        local ok_btn = Button.new()
        ok_btn:setBounds(w - 200, h - 42, 90, 22)
        ok_btn:setText('OK')
        try_skin(ok_btn, 'dtc_button')
        ok_btn:addChangeCallback(function()
            local new_name = (input.getText and input:getText()) or ''
            close()
            pcall(function() (on_ok or function() end)(new_name) end)
        end)
        overlay:insertWidget(ok_btn)

        local cancel_btn = Button.new()
        cancel_btn:setBounds(w - 100, h - 42, 90, 22)
        cancel_btn:setText('Cancel')
        try_skin(cancel_btn, 'dtc_button')
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
        -- Title bar (~30px) + bottom border (~12px) sit outside the content
        -- layout, so total height = content y-extent + ~42. Grid block ends
        -- at y=260 (h=180 → 6 rows at gridSkin_ME's rowHeight=30); status
        -- label ends at ~362; +~42 → 410.
        local w, h = 440, 410
        local x = screen_w - w - 20
        local y = 80

        W.window = Window.new(x, y, w, h, 'dcs-sms — Prefab Manager')
        W.window:setSkin((Skin.windowSkinME and Skin.windowSkinME()) or Skin.windowSkin())
        W.window:setVisible(true)
        W.window:setDraggable(true)
        W.window:setResizable(false)
        W.window:setZOrder(190)

        -- Esc cancels place-pending; Ctrl-Z undoes the last place.
        -- DCS Window exposes addHotKeyCallback (key-name strings like
        -- "escape", "Ctrl+Z") — addKeyDownCallback exists only on
        -- input widgets like EditBox, not on Window. Same pattern as
        -- me_menubar uses for Ctrl+S, delete, etc.
        if W.window.addHotKeyCallback then
            pcall(function()
                W.window:addHotKeyCallback('escape', function()
                    if not W.place_pending then return end
                    set_status('Place cancelled.')
                    exit_place_pending()
                end)
            end)
            pcall(function()
                W.window:addHotKeyCallback('Ctrl+Z', function()
                    on_undo_click()
                end)
            end)
            -- Dev reload: drop all dcs_sms_me modules from package.loaded
            -- and re-bootstrap. Saves a full DCS restart while iterating.
            pcall(function()
                W.window:addHotKeyCallback('Ctrl+Shift+R', function()
                    M.reload()
                end)
            end)
        end

        -- Save panel (top): "Name: [______] [Save]"
        local section_label_save = Static.new()
        section_label_save:setBounds(10, 6, w - 20, 16)
        section_label_save:setText('Save current selection')
        try_skin(section_label_save, 'staticSkin_ME')
        W.window:insertWidget(section_label_save)

        local name_label = Static.new()
        name_label:setBounds(10, 26, 50, 22)
        name_label:setText('Name:')
        try_skin(name_label, 'staticSkin_ME')
        W.window:insertWidget(name_label)

        if TextBox then
            W.name_input = TextBox.new()
        else
            W.name_input = Static.new()
            W.name_input.setText = W.name_input.setText  -- API parity stub
        end
        W.name_input:setBounds(64, 26, w - 64 - 80 - 16, 22)
        if W.name_input.setText then W.name_input:setText('') end
        try_skin(W.name_input, 'editBoxSkin_ME')
        W.window:insertWidget(W.name_input)

        W.save_btn = Button.new()
        W.save_btn:setBounds(w - 90, 26, 80, 22)
        W.save_btn:setText('Save')
        try_skin(W.save_btn, 'dtc_button')
        W.save_btn:addChangeCallback(on_save_click)
        W.window:insertWidget(W.save_btn)

        -- Library section
        W.list_label = Static.new()
        W.list_label:setBounds(10, 60, w - 20 - 80, 16)
        W.list_label:setText('Prefabs (0)')
        try_skin(W.list_label, 'staticSkin_ME')
        W.window:insertWidget(W.list_label)

        W.reload_btn = Button.new()
        W.reload_btn:setBounds(w - 90, 56, 80, 22)
        W.reload_btn:setText('Reload')
        try_skin(W.reload_btn, 'dtc_button')
        W.reload_btn:addChangeCallback(on_reload_click)
        W.window:insertWidget(W.reload_btn)

        if Grid and GridHeaderCell then
            W.grid = Grid.new()
            try_skin(W.grid, 'dtc_grid')

            -- Six columns, sized for the 420px content area (440 - 20px padding).
            -- Numeric counter columns are tight (35px) since they hold one or
            -- two digits; Name gets the lion's share.
            local cols = {
                { name = 'Name',     width = 190 },
                { name = 'Theatre',  width = 90  },
                { name = 'G',        width = 35  },
                { name = 'S',        width = 35  },
                { name = 'Z',        width = 35  },
                { name = 'D',        width = 35  },
            }
            for _, c in ipairs(cols) do
                local hc = GridHeaderCell.new()
                try_skin(hc, 'dtc_grid_header')
                if hc.setText then hc:setText(c.name) end
                W.grid:insertColumn(c.width, hc)
            end

            -- Mirror me_openfile.lua: Grid's default onMouseDown is empty, so
            -- mouse clicks don't change the selected row. Override it to call
            -- selectRow(row) for the clicked row, which then triggers
            -- addSelectRowCallback.
            W.grid.onMouseDown = function(self, x, y, button)
                if button ~= 1 then return end
                pcall(function()
                    local _, row = self:getMouseCursorColumnRow(x, y)
                    if row and row >= 0 then
                        self:selectRow(row)
                        on_list_select()
                    end
                end)
            end
            if W.grid.addSelectRowCallback then
                pcall(function()
                    W.grid:addSelectRowCallback(function(_grid, _curr, _prev)
                        on_list_select()
                    end)
                end)
            end
        else
            -- Fallback: minimal Static so the window still constructs in
            -- environments missing Grid (older dxgui builds, test VMs).
            W.grid = Static.new()
            if W.grid.setText then W.grid:setText('Grid widget not available') end
        end
        W.grid:setBounds(10, 80, w - 20, 180)
        W.window:insertWidget(W.grid)

        -- Action panel (y-offsets shifted down 50px because the grid above
        -- is now h=180 instead of the ListBox's h=130).
        local rotation_label = Static.new()
        rotation_label:setBounds(10, 268, 60, 22)
        rotation_label:setText('Rotation:')
        try_skin(rotation_label, 'staticSkin_ME')
        W.window:insertWidget(rotation_label)

        if TextBox then
            W.rotation_input = TextBox.new()
        else
            W.rotation_input = Static.new()
            W.rotation_input.setText = W.rotation_input.setText  -- API parity stub
        end
        W.rotation_input:setBounds(70, 268, 50, 22)
        if W.rotation_input.setText then W.rotation_input:setText('0') end
        try_skin(W.rotation_input, 'editBoxSkin_ME')
        W.window:insertWidget(W.rotation_input)

        local rotation_unit = Static.new()
        rotation_unit:setBounds(122, 268, 20, 22)
        rotation_unit:setText('°')
        try_skin(rotation_unit, 'staticSkin_ME')
        W.window:insertWidget(rotation_unit)

        local btn_y_1 = 294
        W.place_click_btn = Button.new()
        W.place_click_btn:setBounds(10, btn_y_1, 130, 22)
        W.place_click_btn:setText('Place at click')
        try_skin(W.place_click_btn, 'dtc_button')
        W.place_click_btn:addChangeCallback(on_place_click)
        W.window:insertWidget(W.place_click_btn)

        W.place_origin_btn = Button.new()
        W.place_origin_btn:setBounds(146, btn_y_1, 130, 22)
        W.place_origin_btn:setText('Place at original')
        try_skin(W.place_origin_btn, 'dtc_button')
        W.place_origin_btn:addChangeCallback(on_place_origin_click)
        W.window:insertWidget(W.place_origin_btn)

        local btn_y_2 = 320
        W.rename_btn = Button.new()
        W.rename_btn:setBounds(10, btn_y_2, 80, 22)
        W.rename_btn:setText('Rename')
        try_skin(W.rename_btn, 'dtc_button')
        W.rename_btn:addChangeCallback(on_rename_click)
        W.window:insertWidget(W.rename_btn)

        W.delete_btn = Button.new()
        W.delete_btn:setBounds(96, btn_y_2, 80, 22)
        W.delete_btn:setText('Delete')
        try_skin(W.delete_btn, 'dtc_button')
        W.delete_btn:addChangeCallback(on_delete_click)
        W.window:insertWidget(W.delete_btn)

        W.undo_btn = Button.new()
        W.undo_btn:setBounds(182, btn_y_2, 130, 22)
        W.undo_btn:setText('Undo last place')
        try_skin(W.undo_btn, 'dtc_button')
        W.undo_btn:addChangeCallback(on_undo_click)
        W.window:insertWidget(W.undo_btn)

        -- Status
        W.status = Static.new()
        W.status:setBounds(10, 346, w - 20, 16)
        W.status:setText('Ready.')
        try_skin(W.status, 'staticSkin_ME')
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

-- Tear down the visible window. Used by the dev reload before clearing
-- package.loaded — the dxgui Lua bind has no explicit destroy(), but
-- hiding + dropping our reference removes the window from the visible
-- scene graph and lets the next module instance start from scratch.
-- The OLD W table goes away with the module when package.loaded clears.
function M.dispose()
    pcall(function()
        if W.window and W.window.setVisible then W.window:setVisible(false) end
    end)
end

-- Dev-loop helper: dispose, clear package.loaded for our modules, then
-- re-require the bootstrap. Lets you iterate on Lua without restarting
-- DCS. Works cleanly because the Customize-menu item's click callback
-- (set in menu.lua) does `require('dcs_sms_me.window')` AT CLICK TIME,
-- not at registration — so once package.loaded is cleared, the menu
-- entry naturally picks up the new code on the next click. Same for
-- the floating-button fallback. The menu widget itself is in the dxgui
-- scene and outlives the require, and add_menu_entry's `_dcs_sms_prefab_added`
-- idempotency flag prevents a duplicate entry on the re-bootstrap.
function M.reload()
    log.write('sms.me', log.INFO, 'dev reload triggered')
    pcall(M.dispose)

    local cleared = {}
    for k in pairs(package.loaded) do
        if type(k) == 'string' and k:find('^dcs_sms_me') then
            cleared[#cleared + 1] = k
        end
    end
    for _, k in ipairs(cleared) do package.loaded[k] = nil end
    log.write('sms.me', log.INFO, 'cleared ' .. #cleared .. ' modules from package.loaded')

    -- Re-require the bootstrap. Any error surfaces in dcs.log; the old
    -- window is already gone so a failed reload leaves the user with
    -- "no Prefab Manager" rather than a half-broken one.
    local ok, err = pcall(require, 'dcs_sms_me.init')
    if not ok then
        log.write('sms.me', log.ERROR, 'reload failed: ' .. tostring(err))
        return false, tostring(err)
    end
    log.write('sms.me', log.INFO, 'dev reload completed')

    -- Show the freshly reloaded window. We have to go through the new
    -- module — our M is the OLD one; the just-required init.lua already
    -- reset package.loaded['dcs_sms_me.window'], so a fresh require picks
    -- up the new code.
    pcall(function()
        local fresh = require('dcs_sms_me.window')
        if fresh and fresh.show then fresh.show() end
    end)
    return true
end

return M
