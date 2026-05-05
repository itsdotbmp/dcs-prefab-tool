-- Standalone test for marquee_hook: install + subscribe + fire on rect-complete.
-- Stubs me_multiSelection so we don't depend on the real DCS module.
-- Run via: lua test_marquee_hook.lua  (cwd: tools/me-mod/test/)

-- Stub me_multiSelection with the three globals our hook patches.
local stub_mms = {}
stub_mms.createRectSelect = function(x, y, color)
    stub_mms._last_create = { x = x, y = y, color = color }
end
stub_mms.updateRectSelect = function(x, y)
    stub_mms._last_update = { x = x, y = y }
end
stub_mms.multiSelectionState_onMouseUp = function(self, x, y, button)
    stub_mms._last_mouseup = { self = self, x = x, y = y, button = button }
end
package.preload['me_multiSelection'] = function() return stub_mms end

-- Stub log so init.lua-style log.write calls don't fail.
package.preload['log'] = function()
    return { write = function() end, INFO = 1, WARNING = 2, ERROR = 3 }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local marquee_hook = require('dcs_sms_me.marquee_hook')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

-- Case: install patches the three functions and is idempotent.
do
    local orig_create  = stub_mms.createRectSelect
    local orig_update  = stub_mms.updateRectSelect
    local orig_mouseup = stub_mms.multiSelectionState_onMouseUp

    marquee_hook.install()
    check('install replaces createRectSelect',  stub_mms.createRectSelect ~= orig_create)
    check('install replaces updateRectSelect',  stub_mms.updateRectSelect ~= orig_update)
    check('install replaces onMouseUp',         stub_mms.multiSelectionState_onMouseUp ~= orig_mouseup)

    -- Idempotent — second install must not stack wrappers.
    local once_create = stub_mms.createRectSelect
    marquee_hook.install()
    check('install is idempotent', stub_mms.createRectSelect == once_create)
end

-- Case: drag → mouse-up fires subscribers with start + end map coords.
do
    local fired = {}
    marquee_hook.subscribe(function(start_xy, end_xy)
        fired[#fired + 1] = { start_xy = start_xy, end_xy = end_xy }
    end)

    -- Simulate a drag: createRectSelect (start) + a few updateRectSelect (drag ticks)
    -- + multiSelectionState_onMouseUp (release on left button = 1).
    stub_mms.createRectSelect(100, 200, {1,0,0,1})
    stub_mms.updateRectSelect(150, 250)
    stub_mms.updateRectSelect(180, 300)
    stub_mms.multiSelectionState_onMouseUp({}, 999, 999, 1)

    check('subscriber fired exactly once', #fired == 1, 'got ' .. tostring(#fired))
    check('subscriber received start xy', fired[1] and fired[1].start_xy.x == 100 and fired[1].start_xy.y == 200,
          'start was ' .. tostring(fired[1] and fired[1].start_xy.x))
    check('subscriber received end xy',   fired[1] and fired[1].end_xy.x == 180 and fired[1].end_xy.y == 300,
          'end was ' .. tostring(fired[1] and fired[1].end_xy.x))
end

-- Case: right-button mouse-up does NOT fire subscribers.
do
    local fired_count = 0
    marquee_hook.subscribe(function() fired_count = fired_count + 1 end)
    stub_mms.createRectSelect(0, 0, {})
    stub_mms.updateRectSelect(10, 10)
    stub_mms.multiSelectionState_onMouseUp({}, 0, 0, 3)  -- right button
    check('right-button mouseup did not fire subscribers', fired_count == 0, 'got ' .. fired_count)
end

-- Case: mouse-up without prior drag (no createRectSelect) does not fire.
do
    -- Reset module state by re-requiring (clears any retained start/end).
    package.loaded['dcs_sms_me.marquee_hook'] = nil
    -- Re-stub the originals so a fresh install starts clean.
    stub_mms.createRectSelect            = function(x, y, color) end
    stub_mms.updateRectSelect            = function(x, y) end
    stub_mms.multiSelectionState_onMouseUp = function(s, x, y, b) end
    local mh2 = require('dcs_sms_me.marquee_hook')
    mh2.install()
    local fired_count = 0
    mh2.subscribe(function() fired_count = fired_count + 1 end)
    stub_mms.multiSelectionState_onMouseUp({}, 0, 0, 1)  -- no createRectSelect first
    check('mouseup without prior drag did not fire subscribers', fired_count == 0, 'got ' .. fired_count)
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All marquee_hook tests passed.')
