-- dtc_skins.lua — DTC-style skin builders.
--
-- The DTC editor dialog (modules/dialogs/me_DTCnew.dlg) uses a different
-- skin set than the rest of the dxgui Skin module:
--
--   * Buttons:   inline override of toggleButtonSkin_ME with btnmean2.png
--                (small dark-blue rectangular buttons — the ADD/EDIT look).
--                Not registered in skin_names.lua, so we clone the base
--                skin at runtime and swap each `bkg.file` reference.
--   * Grid:      gridSkin_Multiplayer_roleNew  + selectionColor 0x2da1beff
--                (registered in skin_names.lua → grid4mulnew.skin.lua).
--   * Headers:   gridHeaderCellSkinNew (registered → grid_header_cell5snew).
--
-- All builders return a freshly cloned skin table so callers can mutate
-- without affecting the cached Skin module copy.

local Skin = require('Skin')

local M = {}

-- Recursively swap any `["file"] = "...btn_ME_all_*.png"` reference inside
-- the cloned toggleButtonSkin_ME for the DTC btnmean2 image. Same image is
-- used across all states; per-state color modulation in the base skin
-- (released = full alpha, hover = brighter, pressed = dimmer, etc.) is
-- preserved automatically.
local DTC_BTN_IMAGE = 'dxgui\\skins\\skinme\\images\\m1\\buttons\\btnmini\\btnmean2.png'

local function swap_btn_image(node)
    if type(node) ~= 'table' then return end
    for k, v in pairs(node) do
        if k == 'file' and type(v) == 'string' and v:find('btn_ME_all') then
            node[k] = DTC_BTN_IMAGE
        elseif type(v) == 'table' then
            swap_btn_image(v)
        end
    end
end

function M.button()
    local s = Skin.toggleButtonSkin_ME and Skin.toggleButtonSkin_ME() or nil
    if not s then return nil end
    if s.skinData and s.skinData.states then
        swap_btn_image(s.skinData.states)
    end
    return s
end

function M.grid()
    local s = Skin.gridSkin_Multiplayer_roleNew and Skin.gridSkin_Multiplayer_roleNew() or nil
    if not s then return nil end
    -- The DTC dialog overrides selectionColor inline. Copy that here so a
    -- selected row gets the teal-blue highlight rather than the default
    -- grayish 0x3c3e40.
    if s.skinData and s.skinData.params then
        s.skinData.params.selectionColor = '0x2da1beff'
    end
    return s
end

function M.grid_header()
    return Skin.gridHeaderCellSkinNew and Skin.gridHeaderCellSkinNew() or nil
end

return M
