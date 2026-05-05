-- marquee_hook.lua — broadcast rect-complete events from the ME's MultiSelection tool.
--
-- Wraps three globals on `me_multiSelection`:
--   createRectSelect(mapX, mapY, color)            -- drag start (left-button mouse-down)
--   updateRectSelect(mapX, mapY)                   -- drag tick (mouse move while down)
--   multiSelectionState_onMouseUp(self, x, y, b)   -- drag complete (mouse-up)
-- All three are file-globals on `module('me_multiSelection')` so they can be
-- monkey-patched after `require('me_multiSelection')` runs.
--
-- The hook fires every subscriber once per left-button drag-complete with
-- (start_xy, end_xy) — both in MAP coords. Drags without a preceding
-- createRectSelect (e.g. ctrl-clicks, mouse-up off-canvas) are ignored.
--
-- Idempotency: install() guards via a sentinel on the me_multiSelection module,
-- so Ctrl+Shift+R reloads don't stack wrappers.

local M = {}

local mms = require('me_multiSelection')

local rect_start = nil   -- {x, y} of last createRectSelect, or nil
local rect_end   = nil   -- {x, y} of last updateRectSelect, or nil
local subscribers = {}

local function fire(start_xy, end_xy)
    for _, cb in ipairs(subscribers) do
        pcall(cb, start_xy, end_xy)
    end
end

function M.install()
    if mms._sms_marquee_patched then return end

    local orig_create  = mms.createRectSelect
    local orig_update  = mms.updateRectSelect
    local orig_mouseup = mms.multiSelectionState_onMouseUp

    mms.createRectSelect = function(mapX, mapY, color)
        -- rect_end is seeded to start so a release with no drag ticks
        -- (createRectSelect → no updateRectSelect → onMouseUp) still produces
        -- a coherent (start_xy, end_xy) pair. Downstream hit-tests on a
        -- zero-area rect naturally return no airdromes.
        rect_start = { x = mapX, y = mapY }
        rect_end   = { x = mapX, y = mapY }
        return orig_create(mapX, mapY, color)
    end

    mms.updateRectSelect = function(mapX, mapY)
        if rect_start then rect_end = { x = mapX, y = mapY } end
        return orig_update(mapX, mapY)
    end

    mms.multiSelectionState_onMouseUp = function(self, x, y, button)
        -- button: 1=LMB, 2=MMB, 3=RMB (dxgui convention)
        if button == 1 and rect_start and rect_end then
            fire(rect_start, rect_end)
            rect_start, rect_end = nil, nil
        end
        return orig_mouseup(self, x, y, button)
    end

    mms._sms_marquee_patched = true
end

function M.subscribe(callback)
    if type(callback) ~= 'function' then return end
    subscribers[#subscribers + 1] = callback
end

return M
