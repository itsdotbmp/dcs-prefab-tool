-- init.lua — loaded by the require() line patched into MissionEditor.lua.
--
-- Sub-project 3: registers a Tools-menu entry (with floating-button
-- fallback) instead of auto-showing the Prefab Manager window. The
-- window is constructed lazily on first toggle.
--
-- Outer pcall is the last-line defense: even if our require chain
-- breaks, the ME continues loading normally.

local ok, err = pcall(function()
    local menu = require('dcs_sms_me.menu')
    menu.install()
end)
if not ok then
    log.write('sms.me', log.ERROR, 'init failed: ' .. tostring(err))
end
