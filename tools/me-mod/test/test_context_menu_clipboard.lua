package.path = package.path .. ';../lua/?.lua;../lua/?/init.lua'

local function check(l, ok) if ok then io.write('PASS ', l, '\n') else io.write('FAIL ', l, '\n'); os.exit(1) end end

-- Case 1: Gui.setClipboard takes priority.
do
    package.loaded['dcs_sms_me.context_menu'] = nil
    local captured
    _G.Gui = { setClipboard = function(s) captured = s; return true end }
    _G.dxgui = nil
    package.preload['Input'] = function() return { setClipboard = function() error('should not be called') end } end
    local cm = require('dcs_sms_me.context_menu')
    local ok = cm._copy_to_clipboard('hello')
    check('Gui.setClipboard chosen', ok == true and captured == 'hello')
    _G.Gui = nil
    package.preload['Input'] = nil
end

-- Case 2: falls back to dxgui.setClipboard when Gui absent.
do
    package.loaded['dcs_sms_me.context_menu'] = nil
    local captured
    _G.Gui = nil
    _G.dxgui = { setClipboard = function(s) captured = s; return true end }
    local cm = require('dcs_sms_me.context_menu')
    local ok = cm._copy_to_clipboard('world')
    check('dxgui.setClipboard chosen', ok == true and captured == 'world')
    _G.dxgui = nil
end

-- Case 3: all four strategies fail -> returns false.
do
    package.loaded['dcs_sms_me.context_menu'] = nil
    _G.Gui, _G.dxgui = nil, nil
    package.preload['Input'] = function() error('no module') end
    -- Force os.execute to fail by returning non-zero.
    local real_execute = os.execute
    os.execute = function() return 1 end
    local cm = require('dcs_sms_me.context_menu')
    local ok = cm._copy_to_clipboard('x')
    check('all-fail returns false', ok == false)
    os.execute = real_execute
    package.preload['Input'] = nil
end

io.write('All context_menu clipboard tests passed.\n')
