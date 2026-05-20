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
-- Reload safety: the dev-loop Ctrl+Shift+R clears every `dcs_prefab_tool.*` from
-- package.loaded but leaves `me_multiSelection` cached. Our patched wrappers
-- on mms.* therefore survive the reload, but a fresh require of marquee_hook
-- creates new module-local closures — so the wrappers and the new module
-- would otherwise reference different `subscribers` tables and the new
-- window's subscriber would never fire.
--
-- The fix: store ALL mutable state on the `mms` table itself
-- (`mms._sms_marquee_state`) and have the wrappers look it up live at call
-- time. Reloads then transparently share state with the persistent wrappers.

local M = {}

local mms = require('me_multiSelection')

local function get_state()
    -- Lazy initialise on first use. Persisted on the me_multiSelection module
    -- table so the same state survives reloads of marquee_hook.
    if not mms._sms_marquee_state then
        mms._sms_marquee_state = {
            rect_start  = nil,    -- {x, y} of last createRectSelect, or nil
            rect_end    = nil,    -- {x, y} of last updateRectSelect, or nil
            subscribers = {},     -- list of callback functions
        }
    end
    return mms._sms_marquee_state
end

local function fire(start_xy, end_xy)
    for _, cb in ipairs(get_state().subscribers) do
        pcall(cb, start_xy, end_xy)
    end
end

function M.install()
    if mms._sms_marquee_patched then return end
    get_state()  -- ensure state table exists before any wrapper fires

    local orig_create  = mms.createRectSelect
    local orig_update  = mms.updateRectSelect
    local orig_mouseup = mms.multiSelectionState_onMouseUp

    mms.createRectSelect = function(mapX, mapY, color)
        -- rect_end is seeded to start so a release with no drag ticks
        -- (createRectSelect → no updateRectSelect → onMouseUp) still produces
        -- a coherent (start_xy, end_xy) pair. Downstream hit-tests on a
        -- zero-area rect naturally return no airdromes.
        local s = get_state()
        s.rect_start = { x = mapX, y = mapY }
        s.rect_end   = { x = mapX, y = mapY }
        return orig_create(mapX, mapY, color)
    end

    mms.updateRectSelect = function(mapX, mapY)
        local s = get_state()
        if s.rect_start then s.rect_end = { x = mapX, y = mapY } end
        return orig_update(mapX, mapY)
    end

    mms.multiSelectionState_onMouseUp = function(self, x, y, button)
        -- button: 1=LMB, 2=MMB, 3=RMB (dxgui convention)
        local s = get_state()
        if button == 1 and s.rect_start and s.rect_end then
            fire(s.rect_start, s.rect_end)
            s.rect_start, s.rect_end = nil, nil
        end
        return orig_mouseup(self, x, y, button)
    end

    mms._sms_marquee_patched = true
end

-- Append a subscriber to the persistent list. Reload-safe because the list
-- lives on mms — the next reload's `subscribe` adds to the same table the
-- pre-reload wrappers iterate.
function M.subscribe(callback)
    if type(callback) ~= 'function' then return end
    local s = get_state()
    s.subscribers[#s.subscribers + 1] = callback
end

-- Drop every registered subscriber. Window.lua calls this at start of each
-- M.show() to wipe stale callbacks left behind by previous-session windows
-- after a Ctrl+Shift+R reload, before re-subscribing the live one.
function M.reset_subscribers()
    local s = get_state()
    s.subscribers = {}
end

return M
