-- window.lua — dxgui window with a "Print selection" button + status label.
--
-- Imperative widget construction (Button.new, Static.new) for v1 — one
-- button + one label has no real layout. Sub-project 3 will switch to .dlg
-- files when there is real layout to describe.
--
-- Public:
--   M.show()    — construct and display the window. Idempotent.

local Static = require('Static')
local Button = require('Button')
local Gui    = require('dxgui')

local selection  = require('dcs_sms_me.selection')
local serializer = require('dcs_sms_me.serializer')
local paths      = require('dcs_sms_me.paths')

local M = {}

local window      = nil
local statusLabel = nil

local VERSION = '0.1.0'

local function utc_filename_stamp()
    -- e.g. "2026-05-03T141728Z" — no colons (Windows-safe).
    local stamp = os.date('!%Y-%m-%dT%H%M%SZ')
    return stamp
end

local function truncate(s, max)
    s = tostring(s or '')
    if #s <= max then return s end
    return s:sub(1, max - 1) .. '…'
end

local function is_empty(snap)
    return snap.ok
        and #snap.groups == 0
        and #snap.zones == 0
        and #snap.drawings == 0
        and #snap.nav_points == 0
end

local function envelope(snap)
    return {
        meta = {
            dcs_sms_me_version = VERSION,
            timestamp_utc      = snap.timestamp_utc,
            selection_mode     = snap.selection_mode,
            ok                 = snap.ok,
            error              = snap.error,
        },
        groups     = snap.groups     or {},
        zones      = snap.zones      or {},
        drawings   = snap.drawings   or {},
        nav_points = snap.nav_points or {},
        raw        = snap.raw        or {},
    }
end

local function summarize(snap, fullpath)
    return string.format(
        'mode=%s, groups=%d, zones=%d, drawings=%d, nav_points=%d',
        snap.selection_mode or 'unknown',
        #(snap.groups or {}),
        #(snap.zones or {}),
        #(snap.drawings or {}),
        #(snap.nav_points or {}))
end

function M._set_status(text)
    pcall(function()
        if statusLabel and statusLabel.setText then
            statusLabel:setText(text)
        end
    end)
end

function M._on_print_clicked()
    local snap = selection.snapshot()

    -- (1) Empty selection: no file, just log + status.
    if snap.ok and is_empty(snap) then
        log.write('sms.me', log.WARNING, 'no selection — nothing dumped')
        M._set_status('No selection — nothing dumped')
        return
    end

    -- (2) Open file. Failure means we can't write anything, return.
    paths.ensure_outbox()
    local filename = 'selection-' .. utc_filename_stamp() .. '.lua'
    local fullpath = paths.OUTBOX_DIR .. filename
    local f, err   = io.open(fullpath, 'w')
    if not f then
        local msg = 'open failed: ' .. tostring(err)
        log.write('sms.me', log.ERROR, msg)
        M._set_status('Failed: ' .. truncate(msg, 80) .. ' (see dcs.log)')
        return
    end
    f:write(serializer.serialize(envelope(snap)))
    f:close()

    -- (3) Snapshot itself failed: file written with ok=false, surface that.
    if not snap.ok then
        local msg = 'selection lookup failed: ' .. tostring(snap.error)
        log.write('sms.me', log.ERROR, msg .. ' (file: ' .. fullpath .. ')')
        M._set_status('Failed: ' .. truncate(snap.error or '', 80) .. ' (see dcs.log)')
        return
    end

    -- (4) Success.
    local summary = summarize(snap, fullpath)
    log.write('sms.me', log.INFO, 'selection dumped to ' .. fullpath
                                   .. ' (' .. summary .. ')')
    M._set_status('Dumped ' .. summary .. ' → ' .. filename)
end

function M.show()
    if window then return end
    local ok, err = pcall(function()
        -- Build the window imperatively. Layout: column with title (Static),
        -- button, and status label. Sized to fit a single dump-result line.
        local screen_w, screen_h = Gui.GetWindowSize()
        local w, h = 360, 110
        local x = screen_w - w - 20
        local y = 80

        window = Static.new()
        window:setBounds(x, y, w, h)
        window:setText('dcs-sms ME')
        window:setVisible(true)

        local title = Static.new()
        title:setBounds(10, 6, w - 20, 18)
        title:setText('dcs-sms ME — hello world')
        window:insertWidget(title)

        local button = Button.new()
        button:setBounds(10, 30, w - 20, 28)
        button:setText('Print selection')
        button:addChangeCallback(M._on_print_clicked)
        window:insertWidget(button)

        statusLabel = Static.new()
        statusLabel:setBounds(10, 64, w - 20, 36)
        statusLabel:setText('Ready.')
        window:insertWidget(statusLabel)
    end)
    if not ok then
        log.write('sms.me', log.ERROR, 'window construction failed: ' .. tostring(err))
        window = nil
        statusLabel = nil
        return
    end
    log.write('sms.me', log.INFO, 'window opened')
end

return M
