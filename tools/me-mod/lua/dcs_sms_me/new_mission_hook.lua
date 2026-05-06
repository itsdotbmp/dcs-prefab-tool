-- new_mission_hook.lua — fire subscribers when the current mission is
-- about to be torn down (File > New, File > Open).
--
-- Wraps two file-globals on `me_toolbar`:
--   newMission()           — File > New (me_toolbar.lua:310). Hides the
--                            ME's own panels (coords_info / flightPlans /
--                            multiTemplate / managerDTC) and switches to
--                            the map-picker state.
--   loadMission(filename)  — File > Open (me_toolbar.lua:595). Removes the
--                            current mission and loads a new file.
--
-- Both events mean "the in-memory mission is going away" — subscribers
-- typically want to close their UI because it references state that's
-- about to be torn down. ME has no general "any-window-please-hide"
-- event, so each panel hooks the toolbar functions directly.
--
-- Reload safety: same shape as marquee_hook. Ctrl+Shift+R clears every
-- `dcs_sms_me.*` from package.loaded but leaves `me_toolbar` cached; the
-- patched wrappers survive, so we keep the subscriber list on the
-- `me_toolbar` table itself (`me_toolbar._sms_new_mission_state`) and
-- look it up live at call time. Reloads then transparently share state
-- with the persistent wrappers.

local M = {}

local me_toolbar = require('me_toolbar')

local function get_state()
    if not me_toolbar._sms_new_mission_state then
        me_toolbar._sms_new_mission_state = {
            subscribers = {},  -- list of callback functions
        }
    end
    return me_toolbar._sms_new_mission_state
end

local function fire()
    for _, cb in ipairs(get_state().subscribers) do
        pcall(cb)
    end
end

function M.install()
    if me_toolbar._sms_new_mission_patched then return end
    get_state()  -- ensure state table exists before any wrapper fires

    -- Fire subscribers BEFORE the original in both wrappers. Listeners
    -- typically want to close their own UI before the ME starts tearing
    -- down the mission.
    local orig_newMission = me_toolbar.newMission
    me_toolbar.newMission = function(...)
        fire()
        return orig_newMission(...)
    end

    local orig_loadMission = me_toolbar.loadMission
    me_toolbar.loadMission = function(...)
        fire()
        return orig_loadMission(...)
    end

    me_toolbar._sms_new_mission_patched = true
end

-- Append a subscriber. Reload-safe — the list lives on me_toolbar so the
-- next reload's subscribe adds to the same table the persistent wrapper
-- iterates.
function M.subscribe(callback)
    if type(callback) ~= 'function' then return end
    local s = get_state()
    s.subscribers[#s.subscribers + 1] = callback
end

-- Drop every registered subscriber. Window.lua calls this at start of each
-- M.show() to wipe stale callbacks from previous-session windows after a
-- Ctrl+Shift+R reload, before re-subscribing the live one.
function M.reset_subscribers()
    local s = get_state()
    s.subscribers = {}
end

return M
