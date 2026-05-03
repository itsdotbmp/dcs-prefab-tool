-- init.lua — loaded by the require() line patched into MissionEditor.lua.
-- Outer pcall is the last-line defense: even if our require chain breaks,
-- the ME continues loading normally.

local ok, err = pcall(function()
    local window = require('dcs_sms_me.window')
    window.show()
end)
if not ok then
    log.write('sms.me', log.ERROR, 'init failed: ' .. tostring(err))
end
