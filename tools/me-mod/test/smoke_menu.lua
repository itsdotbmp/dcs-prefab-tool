-- Smoke-load test for menu.lua
-- Run: lua smoke_menu.lua  (from tools/me-mod/test/)

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path

-- Stub DCS-only modules
package.preload['Window'] = function()
    return { new = function() return { setSkin=function() end, setVisible=function() end,
                setDraggable=function() end, setResizable=function() end,
                setZOrder=function() end, insertWidget=function() end } end }
end
package.preload['Button'] = function()
    return { new = function() return { setBounds=function() end, setText=function() end,
                addChangeCallback=function() end } end }
end
package.preload['Skin']   = function() return { windowSkin = function() return {} end } end
package.preload['dxgui']  = function() return { GetWindowSize = function() return 1920, 1080 end } end
package.preload['me_menubar'] = function() return {} end
package.preload['dcs_sms_me.window'] = function() return { toggle = function() end } end

-- DCS globals that modules expect
log = { write = function() end, INFO = 0, WARNING = 1, ERROR = 2 }

local M = require('menu')
print(type(M.install))
