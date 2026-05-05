-- init.lua — loaded by the require() line patched into MissionEditor.lua.
--
-- Sub-project 3: registers a Tools-menu entry (with floating-button
-- fallback) instead of auto-showing the Prefab Manager window. The
-- window is constructed lazily on first toggle.
--
-- Outer pcall is the last-line defense: even if our require chain
-- breaks, the ME continues loading normally.

local ok, err = pcall(function()
    local version = require('dcs_sms_me.version')
    log.write('sms.me', log.INFO, 'bootstrap (version ' .. tostring(version) .. ')')

    local menu = require('dcs_sms_me.menu')
    menu.install()

    -- Install the marquee hook eagerly on bootstrap so a rect drawn before the
    -- prefab manager window opens still gets remembered. Subscribers attach
    -- later (window.lua attaches on its first show).
    local marquee_hook = require('dcs_sms_me.marquee_hook')
    marquee_hook.install()
end)
if not ok then
    log.write('sms.me', log.ERROR, 'init failed: ' .. tostring(err))
end
