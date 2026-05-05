-- airbase_detect.lua — hit-test airdromes against an axis-aligned rect.
--
-- The ME's multi-select rectangle gives us two map-coord points; this module
-- returns every airdrome whose reference point falls inside the bounding box.
-- Airdromes come from Mission.AirdromeController.getAirdromes() — that returns
-- clones with x/y inherited from the Unit base class plus :getName() and
-- :getAirdromeNumber() accessors. We surface a flat table per hit so callers
-- don't need to know about the Airdrome class.

local M = {}

-- Returns array of { name, airdrome_number_at_save, x, y } for every airdrome
-- whose (x, y) reference point lies in the rect defined by start_xy and end_xy.
-- Bounds are inclusive. Either argument missing → empty array.
function M.airbases_in_rect(start_xy, end_xy)
    if type(start_xy) ~= 'table' or type(end_xy) ~= 'table' then return {} end
    if type(start_xy.x) ~= 'number' or type(start_xy.y) ~= 'number' then return {} end
    if type(end_xy.x)   ~= 'number' or type(end_xy.y)   ~= 'number' then return {} end

    local lo_x = math.min(start_xy.x, end_xy.x)
    local hi_x = math.max(start_xy.x, end_xy.x)
    local lo_y = math.min(start_xy.y, end_xy.y)
    local hi_y = math.max(start_xy.y, end_xy.y)

    local hits = {}
    local ok, AC = pcall(require, 'Mission.AirdromeController')
    if not ok or not AC or type(AC.getAirdromes) ~= 'function' then return hits end

    local airdromes = AC.getAirdromes() or {}
    for _, ad in ipairs(airdromes) do
        local x = type(ad.x) == 'number' and ad.x or nil
        local y = type(ad.y) == 'number' and ad.y or nil
        if x and y and x >= lo_x and x <= hi_x and y >= lo_y and y <= hi_y then
            hits[#hits + 1] = {
                name                    = ad.getName and ad:getName() or '?',
                airdrome_number_at_save = ad.getAirdromeNumber and ad:getAirdromeNumber() or nil,
                x                       = x,
                y                       = y,
            }
        end
    end
    return hits
end

return M
