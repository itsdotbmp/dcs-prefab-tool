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
-- ComboList renders the selected item with its OWN skin in the closed
-- display (so the coalition dot survives), unlike ComboBox which just
-- shows raw text. The ME's airplane-group c_country uses ComboList for
-- exactly this reason.
local ComboList;       do local ok, mod = pcall(require, 'ComboList');       if ok then ComboList       = mod end end
local ListBoxItem;     do local ok, mod = pcall(require, 'ListBoxItem');     if ok then ListBoxItem     = mod end end
local ToggleButton;    do local ok, mod = pcall(require, 'ToggleButton');    if ok then ToggleButton    = mod end end
local Dial;            do local ok, mod = pcall(require, 'Dial');            if ok then Dial            = mod end end
local SpinBox;         do local ok, mod = pcall(require, 'SpinBox');         if ok then SpinBox         = mod end end

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
        elseif skin_name == 'icon_warning'    then s = dtc_skins.icon_static('warning')
        elseif skin_name == 'icon_question'   then s = dtc_skins.icon_static('question')
        elseif skin_name == 'dtc_dial'        then s = dtc_skins.dial()
        elseif skin_name == 'dtc_separator'   then s = dtc_skins.separator()
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
    name_label     = nil,
    search_label   = nil,
    country_label  = nil,
    rotation_label = nil,
    rotation_unit  = nil,        -- fallback "°" Static (no Dial/SpinBox path)
    sep1           = nil,
    sep2           = nil,
    sep3           = nil,
    rotation_input = nil,        -- legacy TextBox; only used when Dial/SpinBox unavailable
    rotation_dial  = nil,
    rotation_spin  = nil,
    rotation_deg   = 0,          -- single source of truth for the place-time rotation
    country_combo      = nil,
    country_filter_btn = nil,
    place_click_btn   = nil,
    place_origin_btn  = nil,
    rename_btn = nil,
    delete_btn = nil,
    undo_btn   = nil,
    status     = nil,

    -- runtime state
    rows           = {},        -- last scan_dir result (post-sort), source of truth
    visible_rows   = {},        -- filtered subset of rows; what the grid shows
    selected_idx   = nil,        -- index into visible_rows of currently selected row
    place_pending  = false,      -- in place-pending mode (Task 12)
    place_pending_name = nil,    -- name of prefab being placed
    sort_key       = 'name',     -- column key to sort rows by
    sort_dir       = 'asc',      -- 'asc' or 'desc'
    grid_headers   = {},         -- parallel to COLS; lets us re-text headers on sort change
    filter_text    = '',         -- live filter applied to rows → visible_rows
    filter_input   = nil,        -- TextBox widget for the filter
}

-- Column definitions for the prefab grid. Module-level so refresh_list and the
-- header-click handlers can share key + numeric-flag metadata.
local COLS = {
    { key = 'name',          label = 'Name',    width = 190, numeric = false },
    { key = 'theatre',       label = 'Theatre', width = 90,  numeric = false },
    { key = 'group_count',   label = 'G',       width = 35,  numeric = true  },
    { key = 'static_count',  label = 'S',       width = 35,  numeric = true  },
    { key = 'zone_count',    label = 'Z',       width = 35,  numeric = true  },
    { key = 'drawing_count', label = 'D',       width = 35,  numeric = true  },
}

local function find_col(key)
    for i, c in ipairs(COLS) do if c.key == key then return c, i end end
end

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

-- Stable in-place sort. Lua's table.sort isn't stable by default, so we tag
-- each row with its pre-sort index and use that as the tiebreaker.
local function sort_rows(rows, key, dir)
    local col = find_col(key)
    local numeric = col and col.numeric
    local asc = (dir ~= 'desc')
    for i, r in ipairs(rows) do r._stable_idx = i end
    table.sort(rows, function(a, b)
        -- Error rows sink to the bottom regardless of direction so they
        -- don't get scattered through the list.
        if a.error and not b.error then return false end
        if b.error and not a.error then return true end
        local av, bv = a[key], b[key]
        if numeric then
            av, bv = tonumber(av) or 0, tonumber(bv) or 0
        else
            av, bv = tostring(av or ''):lower(), tostring(bv or ''):lower()
        end
        if av == bv then return a._stable_idx < b._stable_idx end
        if asc then return av < bv else return av > bv end
    end)
    for _, r in ipairs(rows) do r._stable_idx = nil end
end

-- Re-text every header so the active column gets an arrow glyph and the rest
-- are reset back to their plain label.
local function update_header_labels()
    pcall(function()
        for i, c in ipairs(COLS) do
            local hc = W.grid_headers[i]
            if hc and hc.setText then
                local label = c.label
                if c.key == W.sort_key then
                    label = label .. (W.sort_dir == 'desc' and ' ▼' or ' ▲')
                end
                hc:setText(label)
            end
        end
    end)
end

-- Pure filter: returns a new array of rows whose name OR theatre contains
-- filter_text (case-insensitive substring). Empty filter → shallow copy of
-- the input. Plain-text find (4th arg = true) avoids regex surprises.
-- Exposed via M._filter_rows for unit testing.
local function filter_rows(rows, filter_text)
    local f = (filter_text or ''):lower()
    if f == '' then
        local copy = {}
        for i, r in ipairs(rows) do copy[i] = r end
        return copy
    end
    local out = {}
    for _, r in ipairs(rows) do
        local name_l    = tostring(r.name    or ''):lower()
        local theatre_l = tostring(r.theatre or ''):lower()
        if name_l:find(f, 1, true) or theatre_l:find(f, 1, true) then
            out[#out + 1] = r
        end
    end
    return out
end
M._filter_rows = filter_rows

local function apply_filter()
    W.visible_rows = filter_rows(W.rows, W.filter_text)
end

-- Restore selection by row name in the current visible_rows. Returns the
-- new W.selected_idx (1-based) or nil if the previously-selected row is no
-- longer visible.
local function restore_selection_by_name(prev_name)
    W.selected_idx = nil
    if not prev_name then return end
    for i, r in ipairs(W.visible_rows) do
        if r.name == prev_name then W.selected_idx = i; return i end
    end
end

-- The prefab count lives in the filter input's placeholder text now ("Search
-- 27 prefabs"). Hint text only renders when the input is empty — once the
-- user types, the typed text takes over, which is the right UX.
local function update_count_label()
    pcall(function()
        if not (W.filter_input and W.filter_input.setHintText) then return end
        local total = #W.rows
        local label = (total == 1) and 'Search 1 prefab' or string.format('Search %d prefabs', total)
        W.filter_input:setHintText(label)
    end)
end

-- Repopulate the grid from W.visible_rows. Caller is responsible for setting
-- W.visible_rows + W.selected_idx beforehand. Used by both refresh_list
-- (after disk rescan + sort) and on_filter_change (just after filter).
local function render_grid()
    pcall(function()
        if not W.grid then return end
        -- removeAllRows wipes both row structures and any cell widgets we
        -- inserted in the previous refresh — equivalent to ListBox's
        -- removeAllItems for our purposes.
        if W.grid.removeAllRows then W.grid:removeAllRows() end

        for i, r in ipairs(W.visible_rows) do
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

        if W.selected_idx and W.grid.selectRow then
            pcall(function() W.grid:selectRow(W.selected_idx - 1) end)
        end
    end)
end

local function refresh_list()
    -- Remember the selected row by name so we can restore selection across
    -- the re-sort + re-filter that scan_dir + sort_rows + apply_filter
    -- produces.
    local prev_name = nil
    if W.selected_idx and W.visible_rows[W.selected_idx] then
        prev_name = W.visible_rows[W.selected_idx].name
    end

    W.rows = prefab_ops.scan_dir() or {}
    sort_rows(W.rows, W.sort_key, W.sort_dir)
    apply_filter()
    restore_selection_by_name(prev_name)
    update_count_label()
    update_header_labels()
    render_grid()
end

-- Re-filter and re-render in response to filter_input keystrokes. Doesn't
-- rescan the disk — that's refresh_list's job.
local function on_filter_change()
    pcall(function()
        if not (W.filter_input and W.filter_input.getText) then return end
        local txt = W.filter_input:getText() or ''
        if txt == W.filter_text then return end
        local prev_name = nil
        if W.selected_idx and W.visible_rows[W.selected_idx] then
            prev_name = W.visible_rows[W.selected_idx].name
        end
        W.filter_text = txt
        apply_filter()
        restore_selection_by_name(prev_name)
        update_count_label()
        render_grid()
    end)
end
M._refresh_list = refresh_list  -- exposed for later tasks

local function selected_row()
    if not W.selected_idx then return nil end
    return W.visible_rows[W.selected_idx]
end
M._selected_row = selected_row

-- ---------------------------------------------------------------------------
-- Modal overlay helper. Shows a small centered window with a message and
-- up to 3 buttons. Each button calls the supplied callback then closes the
-- overlay. Buttons:
--   { {label='OK',  on_click=function() ... end}, ... }
-- ---------------------------------------------------------------------------

local function show_overlay(message, buttons, icon)
    local screen_w, screen_h = Gui.GetWindowSize()
    -- windowSkinME's title bar + bottom border consume more than the bare
    -- arithmetic suggests, so h is sized to leave ~30px between the
    -- buttons (y = h - 52) and the window's bottom edge after the skin
    -- frame is drawn. Icon, if any, is a 64x64 ME glyph at (10, 14).
    local w, h = 420, 210
    local x = (screen_w - w) / 2
    local y = (screen_h - h) / 2
    local msg_x = icon and 68 or 10
    local msg_w = w - msg_x - 10
    local btn_y = h - 92

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

        if icon then
            local ico = Static.new()
            ico:setBounds(10, 14, 48, 48)
            try_skin(ico, 'icon_' .. icon)
            overlay:insertWidget(ico)
        end

        local msg = Static.new()
        msg:setBounds(msg_x, 14, msg_w, btn_y - 24)
        msg:setText(tostring(message or ''))
        try_skin(msg, 'staticSkin_ME')
        overlay:insertWidget(msg)

        local n = #buttons
        local bw = math.floor((w - 20 - (n - 1) * 10) / n)
        for i, b in ipairs(buttons) do
            local btn = Button.new()
            btn:setBounds(10 + (i - 1) * (bw + 10), btn_y, bw, 22)
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
        pcall(function()
            if W.name_input and W.name_input.setText then W.name_input:setText('') end
        end)
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
                },
                'question')
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
-- selected. Map to W.visible_rows[idx+1]. The callback is wired both via
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

-- Read the currently-selected country from the dropdown. Returns nil when
-- the combo isn't built (test VM, dxgui without ComboBox) or no item is
-- selected — caller falls back to the prefab's stored country.
local function get_country_name()
    local name
    pcall(function()
        if not (W.country_combo and W.country_combo.getSelectedItem) then return end
        local item = W.country_combo:getSelectedItem()
        if item and item.getText then
            local txt = item:getText()
            if type(txt) == 'string' and txt ~= '' then name = txt end
        end
    end)
    return name
end

-- Read the mission-defined coalition for a country name. Returns 'red',
-- 'blue', 'neutral', or nil. Mission.countryCoalition[name] is the
-- coalition *object* whose .name field carries the string ('red', 'blue',
-- 'neutrals' — note plural). The .color field is a MapColor table for
-- map rendering, NOT the coalition string, so don't read .color here.
local function country_coalition(Mission, name)
    if not (Mission and type(Mission.countryCoalition) == 'table') then return nil end
    local entry = Mission.countryCoalition[name]
    if type(entry) ~= 'table' then return nil end
    local cn = entry.name
    if cn == 'red' or cn == 'blue' then return cn end
    if cn == 'neutrals' or cn == 'neutral' then return 'neutral' end
    return nil
end

-- Map a coalition string to the canonical ME ListBoxItem skin name.
local COALITION_SKIN = {
    red     = 'listBoxItemCoalRedSkin',
    blue    = 'listBoxItemCoalBlueSkin',
    neutral = 'listBoxItemCoalNeutralSkin',
}

-- Is the Combat/All toggle currently in "All" mode? (state=true ⇒ All;
-- state=false / no widget ⇒ Combat). Mirrors me_aircraft.lua's tbFilter.
local function is_filter_all()
    local on = false
    pcall(function()
        if W.country_filter_btn and W.country_filter_btn.getState then
            on = W.country_filter_btn:getState() == true
        end
    end)
    return on
end

-- (Re-)populate the country combobox from Mission.missionCountry. Called
-- on first build, on every M.show, and on Combat/All toggle. Per-item
-- skin shows a colored dot for the country's mission coalition (red /
-- blue / neutral). In Combat mode neutral countries are hidden — same
-- convention as the ME's airplane group panel (tbFilter).
local function populate_country_combo()
    pcall(function()
        if not (W.country_combo and ListBoxItem) then return end
        local ok_req, Mission = pcall(require, 'me_mission')
        if not ok_req or type(Mission.missionCountry) ~= 'table' then
            log.write('sms.me', log.WARNING, 'Mission.missionCountry unavailable — country dropdown empty')
            return
        end

        local show_all = is_filter_all()
        local prev = get_country_name()

        if W.country_combo.removeAllItems then W.country_combo:removeAllItems() end

        local names = {}
        for name in pairs(Mission.missionCountry) do
            if type(name) == 'string' then names[#names + 1] = name end
        end
        table.sort(names)

        local first_item, prev_item
        for _, name in ipairs(names) do
            local coalition = country_coalition(Mission, name)
            -- Combat mode: red/blue only. All mode: include neutral (and
            -- countries with no mission coalition assignment).
            local include = show_all or coalition == 'red' or coalition == 'blue'
            if include then
                local item = ListBoxItem.new(name)
                local skin_name = COALITION_SKIN[coalition or 'neutral']
                if skin_name then try_skin(item, skin_name) end
                W.country_combo:insertItem(item)
                if not first_item then first_item = item end
                if name == prev then prev_item = item end
            end
        end

        local pick = prev_item or first_item
        if pick and W.country_combo.selectItem then
            pcall(function() W.country_combo:selectItem(pick) end)
        end
    end)
end

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
                local country_name = get_country_name()
                if not country_name then
                    log.write('sms.me.prefab', log.WARNING, 'place: country dropdown empty — using prefab-stored countries')
                end
                local rec, err = prefab_ops.place(prefab_table, {
                    anchor       = { x = wx, y = wy },
                    rotation     = rotation_deg,
                    country_name = country_name,
                })
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
    -- Dial+SpinBox path keeps W.rotation_deg authoritative; the legacy
    -- TextBox fallback writes its own value here too via on_rotation_text_change.
    return W.rotation_deg or 0
end

-- Re-entrance guard so spin→dial→spin (or vice versa) doesn't recurse when
-- one widget's setValue fires the other's onChange. Mirrors the implicit
-- guard me_static.lua relies on (where setValue with the same value is a
-- no-op); we make it explicit because our normalization can change the
-- value we write back, which would otherwise re-trigger.
local rotation_syncing = false

-- Normalize an arbitrary numeric input to 0..359 integer degrees. Matches
-- the convention me_static.lua's onChange_e_heading uses (-1 → 359,
-- 360 → 0), but generalized for any over/underflow.
local function normalize_deg(v)
    v = tonumber(v) or 0
    v = math.floor(v + 0.5)
    v = v % 360
    if v < 0 then v = v + 360 end
    return v
end

local function on_rotation_spin_change(self)
    if rotation_syncing then return end
    rotation_syncing = true
    pcall(function()
        local raw = (self.getValue and self:getValue()) or 0
        local v = normalize_deg(raw)
        W.rotation_deg = v
        if v ~= raw and self.setValue then self:setValue(v) end
        if W.rotation_dial and W.rotation_dial.setValue then W.rotation_dial:setValue(v) end
    end)
    rotation_syncing = false
end

local function on_rotation_dial_change(self)
    if rotation_syncing then return end
    rotation_syncing = true
    pcall(function()
        local v = normalize_deg((self.getValue and self:getValue()) or 0)
        W.rotation_deg = v
        if W.rotation_spin and W.rotation_spin.setValue then W.rotation_spin:setValue(v) end
    end)
    rotation_syncing = false
end

-- Read the currently-selected country from the dropdown. Returns nil when
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
    local country_name = get_country_name()
    if not country_name then
        log.write('sms.me.prefab', log.WARNING, 'place at original: country dropdown empty — using prefab-stored countries')
    end
    local rec, err = prefab_ops.place(prefab, {
        keep_position = true,
        rotation      = rotation_deg,
        country_name  = country_name,
    })
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
    -- Slightly taller than show_overlay because rename has prompt + input
    -- stacked. Same icon convention: 64x64 question glyph at (10, 14),
    -- prompt + input shifted to x=84.
    local w, h = 460, 220
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

        local ico = Static.new()
        ico:setBounds(10, 14, 48, 48)
        try_skin(ico, 'icon_question')
        overlay:insertWidget(ico)

        local lbl = Static.new()
        lbl:setBounds(68, 14, w - 78, 20)
        lbl:setText(tostring(prompt or 'New name:'))
        try_skin(lbl, 'staticSkin_ME')
        overlay:insertWidget(lbl)

        input = TextBox.new()
        input:setBounds(68, 40, w - 78, 22)
        if input.setText then input:setText(tostring(current_name or '')) end
        if input.setFocused then input:setFocused(true) end
        try_skin(input, 'editBoxSkin_ME')
        overlay:insertWidget(input)

        local ok_btn = Button.new()
        ok_btn:setBounds(w - 200, h - 92, 90, 22)
        ok_btn:setText('OK')
        try_skin(ok_btn, 'dtc_button')
        ok_btn:addChangeCallback(function()
            local new_name = (input.getText and input:getText()) or ''
            close()
            pcall(function() (on_ok or function() end)(new_name) end)
        end)
        overlay:insertWidget(ok_btn)

        local cancel_btn = Button.new()
        cancel_btn:setBounds(w - 100, h - 92, 90, 22)
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
        },
        'warning')
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

-- Minimum window size below which the layout starts overlapping. Acts as a
-- floor for #32's resize support (no setMinSize() in dxgui — the size
-- callback re-sets bounds if the user shrinks past this).
local MIN_W, MIN_H = 440, 460

-- Single source of truth for child geometry. Called once at construction and
-- from the Window:addSizeCallback. Top band (Name + Search) sticks to the
-- top, status sticks to the bottom, action panel anchors to the bottom too,
-- the grid in the middle stretches with both dimensions.
local function relayout(w, h)
    if not W.window then return end
    local function set(widget, x, y, ww, hh)
        if widget and widget.setBounds then
            pcall(function() widget:setBounds(x, y, ww, hh) end)
        end
    end

    -- Row 0: Name row at top.
    set(W.name_label, 10, 8, 50, 22)
    set(W.name_input, 60, 8, w - 60 - 90 - 6, 22)
    set(W.save_btn,   w - 90, 8, 80, 22)

    -- Separator + Row 1: Search.
    set(W.sep1, 10, 36, w - 20, 1)
    set(W.search_label, 10, 42, 50, 22)
    set(W.filter_input, 60, 42, w - 60 - 10, 22)

    -- Bottom band offsets relative to h. Locked to the bottom so resizing
    -- the window grows the grid, not the action panel.
    local row3_y   = h - 184
    local sep2_y   = h - 158
    local row4_y   = h - 154
    local row5_y   = h - 124
    local sep3_y   = h - 77
    local status_y = h - 73

    -- Grid stretches between the top band and row 3.
    local grid_y = 68
    local grid_h = math.max(60, row3_y - grid_y - 8)
    local grid_w = w - 20
    set(W.grid, 10, grid_y, grid_w, grid_h)
    -- Name column absorbs the leftover horizontal space; numeric/Theatre
    -- columns stay at their COLS-defined widths. Resizing the window
    -- widens just the Name column.
    if W.grid and W.grid.setColumnWidth then
        local fixed_w = 0
        for i, c in ipairs(COLS) do
            if i > 1 then fixed_w = fixed_w + c.width end
        end
        local name_w = math.max(80, grid_w - fixed_w)
        pcall(function() W.grid:setColumnWidth(0, name_w) end)
    end

    -- Row 3: Reload | Undo (left) | gap | Rename | Delete (right).
    set(W.reload_btn, 10,                row3_y, 70,  22)
    set(W.undo_btn,   84,                row3_y, 110, 22)
    set(W.rename_btn, w - 90 - 80 - 4,   row3_y, 80,  22)
    set(W.delete_btn, w - 90,            row3_y, 80,  22)

    set(W.sep2, 10, sep2_y, w - 20, 1)

    -- Row 4: Country picker.
    set(W.country_label, 10, row4_y, 100, 22)
    local combo_x = 114
    local combo_w = (W.country_filter_btn) and (w - combo_x - 90 - 6) or (w - combo_x - 10)
    set(W.country_combo, combo_x, row4_y, combo_w, 22)
    set(W.country_filter_btn, w - 90, row4_y, 80, 22)

    -- Row 5: Rotation gizmo + place buttons. Row is 43px tall (dial); the
    -- spinbox/label/place-buttons are vertically centered against it.
    set(W.rotation_label, 10, row5_y + 10, 60, 22)
    set(W.rotation_spin,  70, row5_y + 10, 50, 22)
    set(W.rotation_dial,  122, row5_y, 47, 43)
    set(W.rotation_input, 70, row5_y + 10, 50, 22)   -- fallback path
    set(W.rotation_unit,  122, row5_y + 10, 20, 22)  -- fallback path
    -- place_click_btn right-edge at w-10 (122 wide), place_origin_btn 4px
    -- to its left (130 wide). Both stay anchored to the right edge.
    set(W.place_origin_btn, w - 266, row5_y + 10, 130, 22)
    set(W.place_click_btn,  w - 132, row5_y + 10, 122, 22)

    set(W.sep3, 10, sep3_y, w - 20, 1)
    set(W.status, 10, status_y, w - 20, 16)
end

function M.show()
    log.write('sms.me', log.INFO, 'window.show() called (W.window present=' .. tostring(W.window ~= nil) .. ')')
    if W.window then
        -- Re-populate so a mission-change between hides surfaces the new
        -- country list; existing selection is preserved if still valid.
        populate_country_combo()
        pcall(function() W.window:setVisible(true) end)
        return
    end
    local ok, err = pcall(function()
        local screen_w, _ = Gui.GetWindowSize()
        -- Layout (top → bottom):
        --   y=8   Name row:    "Name:" + name_input + Save
        --   y=38  Search row:  filter_input full-width (count → hint text)
        --   y=68  Grid:        h=200, ends y=268
        --   y=276 Action row:  Reload | Undo | gap | Rename | Delete
        --   y=306 Country row: "Place as country:" + combo + Combat toggle
        --   y=336 Rotation:    spin+dial gizmo + Place-at-original + Place-at-click (43px tall)
        --   y=387 Status
        -- Title bar (~30) + bottom border (~12) sit outside, so window
        -- total height = content y-extent + ~42 → 460.
        local w, h = 440, 460
        local x = screen_w - w - 20
        local y = 80

        W.window = Window.new(x, y, w, h, 'dcs-sms — Prefab Manager')
        W.window:setSkin((Skin.windowSkinME and Skin.windowSkinME()) or Skin.windowSkin())
        W.window:setVisible(true)
        W.window:setDraggable(true)
        W.window:setResizable(true)
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

        -- Row 0: Name + Save. Bounds for every widget below are set by
        -- relayout(w, h) at the end of build (and on every Window resize).
        W.name_label = Static.new()
        W.name_label:setText('Name:')
        try_skin(W.name_label, 'staticSkin_ME')
        W.window:insertWidget(W.name_label)

        if TextBox then
            W.name_input = TextBox.new()
        else
            W.name_input = Static.new()
            W.name_input.setText = W.name_input.setText  -- API parity stub
        end
        if W.name_input.setText then W.name_input:setText('') end
        try_skin(W.name_input, 'editBoxSkin_ME')
        W.window:insertWidget(W.name_input)

        W.save_btn = Button.new()
        W.save_btn:setText('Save')
        try_skin(W.save_btn, 'dtc_button')
        W.save_btn:addChangeCallback(on_save_click)
        W.window:insertWidget(W.save_btn)

        W.sep1 = Static.new()
        try_skin(W.sep1, 'dtc_separator')
        W.window:insertWidget(W.sep1)

        -- Row 1: "Search:" label + filter input. Count of prefabs lives in
        -- the hint/placeholder text — but if the dxgui build doesn't
        -- render hints, the label keeps the row labelled.
        W.search_label = Static.new()
        W.search_label:setText('Search:')
        try_skin(W.search_label, 'staticSkin_ME')
        W.window:insertWidget(W.search_label)

        if TextBox then
            W.filter_input = TextBox.new()
        else
            W.filter_input = Static.new()
        end
        if W.filter_input.setText then W.filter_input:setText('') end
        try_skin(W.filter_input, 'editBoxSkin_ME')
        if W.filter_input.addChangeCallback then
            pcall(function() W.filter_input:addChangeCallback(on_filter_change) end)
        end
        if W.filter_input.addKeyDownCallback then
            pcall(function()
                W.filter_input:addKeyDownCallback(function(_self, keyName)
                    -- Escape clears the filter and re-shows all rows.
                    if keyName == 'escape' or keyName == 'Escape' then
                        pcall(function() W.filter_input:setText('') end)
                        on_filter_change()
                    end
                end)
            end)
        end
        W.window:insertWidget(W.filter_input)

        if Grid and GridHeaderCell then
            W.grid = Grid.new()
            try_skin(W.grid, 'dtc_grid')

            -- Columns sized for the 420px content area (440 - 20px padding).
            -- Numeric counter columns are tight (35px); Name gets the lion's
            -- share. Definitions live module-level in COLS so refresh_list
            -- and the header-click handlers share key/numeric metadata.
            W.grid_headers = {}
            for i, c in ipairs(COLS) do
                local hc = GridHeaderCell.new()
                try_skin(hc, 'dtc_grid_header')
                if hc.setText then hc:setText(c.label) end
                if hc.addChangeCallback then
                    local idx = i
                    pcall(function()
                        hc:addChangeCallback(function()
                            local key = COLS[idx].key
                            if W.sort_key == key then
                                W.sort_dir = (W.sort_dir == 'asc') and 'desc' or 'asc'
                            else
                                W.sort_key = key
                                W.sort_dir = 'asc'
                            end
                            refresh_list()
                        end)
                    end)
                end
                W.grid_headers[i] = hc
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
        W.window:insertWidget(W.grid)

        -- Row 3: library/selection actions. Reload + Undo on the left
        -- (library-wide), Rename + Delete on the right (per-selection).
        W.reload_btn = Button.new()
        W.reload_btn:setText('Reload')
        try_skin(W.reload_btn, 'dtc_button')
        W.reload_btn:addChangeCallback(on_reload_click)
        W.window:insertWidget(W.reload_btn)

        W.undo_btn = Button.new()
        W.undo_btn:setText('Undo last place')
        try_skin(W.undo_btn, 'dtc_button')
        W.undo_btn:addChangeCallback(on_undo_click)
        W.window:insertWidget(W.undo_btn)

        W.rename_btn = Button.new()
        W.rename_btn:setText('Rename')
        try_skin(W.rename_btn, 'dtc_button')
        W.rename_btn:addChangeCallback(on_rename_click)
        W.window:insertWidget(W.rename_btn)

        W.delete_btn = Button.new()
        W.delete_btn:setText('Delete')
        try_skin(W.delete_btn, 'dtc_button')
        W.delete_btn:addChangeCallback(on_delete_click)
        W.window:insertWidget(W.delete_btn)

        W.sep2 = Static.new()
        try_skin(W.sep2, 'dtc_separator')
        W.window:insertWidget(W.sep2)

        -- Row 4: Country picker.
        W.country_label = Static.new()
        W.country_label:setText('Place as country:')
        try_skin(W.country_label, 'staticSkin_ME')
        W.window:insertWidget(W.country_label)

        -- Combat/All toggle on the right edge of the row, mirroring the
        -- ME's airplane-group panel (tbFilter). State=false → "Combat"
        -- (only red+blue countries shown). State=true → "All" (everything,
        -- including neutrals).
        if ToggleButton then
            W.country_filter_btn = ToggleButton.new()
            W.country_filter_btn:setText('Combat')
            try_skin(W.country_filter_btn, 'dtc_button')
            if W.country_filter_btn.addChangeCallback then
                pcall(function()
                    W.country_filter_btn:addChangeCallback(function(self)
                        local on = self.getState and self:getState() or false
                        pcall(function() self:setText(on and 'All' or 'Combat') end)
                        populate_country_combo()
                    end)
                end)
            end
            W.window:insertWidget(W.country_filter_btn)
        end

        if ComboList then
            W.country_combo = ComboList.new()
            try_skin(W.country_combo, 'comboListSkinNew_')
            W.window:insertWidget(W.country_combo)
        else
            -- Fallback: a Static so the row still renders. populate is a
            -- no-op without ComboList; place falls back to stored country.
            W.country_combo = Static.new()
            W.country_combo:setText('(ComboList unavailable)')
            try_skin(W.country_combo, 'staticSkin_ME')
            W.window:insertWidget(W.country_combo)
        end

        -- Row 5: Rotation gizmo + place buttons. Row is 43px tall (dial
        -- height). Spinbox + label are vertically centered against the
        -- dial. Dial + SpinBox wired via W.rotation_deg, mirroring
        -- me_static.lua's d_heading / e_heading; TextBox fallback when
        -- Dial / SpinBox aren't available (test VMs).
        W.rotation_label = Static.new()
        W.rotation_label:setText('Rotation:')
        try_skin(W.rotation_label, 'staticSkin_ME')
        W.window:insertWidget(W.rotation_label)

        if SpinBox and Dial then
            W.rotation_spin = SpinBox.new()
            try_skin(W.rotation_spin, 'spinBoxSkin_MENew')
            pcall(function() W.rotation_spin:setRange(-1, 360) end)
            pcall(function() W.rotation_spin:setStep(1) end)
            pcall(function() W.rotation_spin:setPageStep(10) end)
            pcall(function() W.rotation_spin:setCheckRange(true) end)
            pcall(function() W.rotation_spin:setAcceptDecimalPoint(false) end)
            pcall(function() W.rotation_spin:setValue(0) end)
            pcall(function() W.rotation_spin:setTooltipText('Placement rotation (°, clockwise)') end)
            if W.rotation_spin.addChangeCallback then
                pcall(function() W.rotation_spin:addChangeCallback(on_rotation_spin_change) end)
            end
            W.window:insertWidget(W.rotation_spin)

            W.rotation_dial = Dial.new()
            try_skin(W.rotation_dial, 'dtc_dial')
            pcall(function() W.rotation_dial:setRange(0, 359) end)
            pcall(function() W.rotation_dial:setStep(1) end)
            pcall(function() W.rotation_dial:setPageStep(10) end)
            pcall(function() W.rotation_dial:setCyclic(true) end)
            pcall(function() W.rotation_dial:setValue(0) end)
            pcall(function() W.rotation_dial:setTooltipText('Placement rotation (°, clockwise)') end)
            if W.rotation_dial.addChangeCallback then
                pcall(function() W.rotation_dial:addChangeCallback(on_rotation_dial_change) end)
            end
            W.window:insertWidget(W.rotation_dial)
        else
            -- Fallback path: legacy TextBox + ° label, same as before the
            -- Dial/SpinBox upgrade. Writes into W.rotation_deg via the
            -- change callback so get_rotation_deg() works uniformly.
            if TextBox then
                W.rotation_input = TextBox.new()
            else
                W.rotation_input = Static.new()
            end
            if W.rotation_input.setText then W.rotation_input:setText('0') end
            try_skin(W.rotation_input, 'editBoxSkin_ME')
            if W.rotation_input.addChangeCallback then
                pcall(function()
                    W.rotation_input:addChangeCallback(function(self)
                        W.rotation_deg = normalize_deg((self.getText and self:getText()) or '0')
                    end)
                end)
            end
            W.window:insertWidget(W.rotation_input)

            W.rotation_unit = Static.new()
            W.rotation_unit:setText('°')
            try_skin(W.rotation_unit, 'staticSkin_ME')
            W.window:insertWidget(W.rotation_unit)
        end

        W.place_origin_btn = Button.new()
        W.place_origin_btn:setText('Place at original')
        try_skin(W.place_origin_btn, 'dtc_button')
        W.place_origin_btn:addChangeCallback(on_place_origin_click)
        W.window:insertWidget(W.place_origin_btn)

        W.place_click_btn = Button.new()
        W.place_click_btn:setText('Place at click')
        try_skin(W.place_click_btn, 'dtc_button')
        W.place_click_btn:addChangeCallback(on_place_click)
        W.window:insertWidget(W.place_click_btn)

        W.sep3 = Static.new()
        try_skin(W.sep3, 'dtc_separator')
        W.window:insertWidget(W.sep3)

        W.status = Static.new()
        W.status:setText('Ready.')
        try_skin(W.status, 'staticSkin_ME')
        W.window:insertWidget(W.status)

        -- Initial layout pass + size callback for resize support. dxgui has
        -- no setMinSize, so the callback clamps via setBounds when the user
        -- shrinks past MIN_W/MIN_H — that re-fires the callback with the
        -- clamped size, which is fine.
        relayout(w, h)
        if W.window.addSizeCallback then
            pcall(function()
                W.window:addSizeCallback(function()
                    pcall(function()
                        local cw, ch = W.window:getSize()
                        if cw < MIN_W or ch < MIN_H then
                            local px, py = W.window:getBounds()
                            W.window:setBounds(px, py, math.max(cw, MIN_W), math.max(ch, MIN_H))
                            return
                        end
                        relayout(cw, ch)
                        -- Grid cells sometimes render at stale positions
                        -- after a column-width change; render_grid is cheap
                        -- (in-memory only, no disk rescan) and fixes that.
                        render_grid()
                    end)
                end)
            end)
        end

        refresh_list()
        populate_country_combo()
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
