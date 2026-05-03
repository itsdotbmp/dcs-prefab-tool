-- Synthetic ME selection dump for sms.prefab.distill tests.
-- Shape mirrors what the hello-world ME mod produces.
-- Three top-level entities: 1 group, 1 static (modeled as single-unit group),
-- 1 trigger zone, 1 drawing. Coordinates chosen so the centroid is (50, 100).
--
-- Used by framework/test/test_prefab_distill.lua.

local mission_country_belgium = { id = 11, name = "Belgium" }
local mission_country_usa     = { id =  2, name = "USA" }

-- The boss back-ref: each entity's boss points at a country, which back-points
-- at the entity. This recreates the cycle the real dump has and that distill
-- must strip.
local boss_belgium = { country = mission_country_belgium }
local boss_usa     = { country = mission_country_usa }

local group_aerial = {
    ["name"]    = "Aerial-1",
    ["type"]    = "plane",
    ["x"]       = 0,                 -- world coords; centroid will be (50, 100)
    ["y"]       = 0,
    ["heading"] = 0,
    ["units"] = {
        [1] = {
            ["name"]      = "Aerial-1-1",
            ["type"]      = "F-16C_50",
            ["x"]         = 0,
            ["y"]         = 0,
            ["alt"]       = 2000,
            ["alt_type"]  = "BARO",
            ["heading"]   = math.pi / 2,            -- 90 deg in rad
            ["livery_id"] = "104th fs maryland",
            ["skill"]     = "Veteran",
            ["callsign"]  = { [1] = 1, [2] = 1, [3] = 1, ["name"] = "Enfield11" },
            ["payload"]   = { ["pylons"] = {}, ["fuel"] = 5000 },
        },
    },
    ["route"] = {
        ["points"] = {
            [1] = { ["x"] = 0,    ["y"] = 0,    ["alt"] = 2000 },
            [2] = { ["x"] = 1000, ["y"] = 0,    ["alt"] = 3000 },
        },
    },
}
group_aerial.boss = boss_belgium
boss_belgium.aerial = group_aerial            -- back-ref → cycle

-- "Static" — modeled as single-unit group per ME convention.
local group_static_hangar = {
    ["name"]     = "Hangar A",
    ["type"]     = "Hangar A",
    ["category"] = "Heliports",
    ["dead"]     = false,
    ["x"]        = 100,
    ["y"]        = 200,
    ["heading"]  = 0,
    ["units"] = {
        [1] = {
            ["name"]    = "Hangar A",
            ["type"]    = "Hangar A",
            ["x"]       = 100,
            ["y"]       = 200,
            ["heading"] = 0,
        },
    },
}
group_static_hangar.boss = boss_usa
boss_usa.hangar = group_static_hangar

-- Trigger zone, anchor (50, 100) is implicit (centroid of all four).
local zone_no_fly = {
    ["name"]   = "no_fly",
    ["type"]   = 0,                 -- circle
    ["x"]      = 50,
    ["y"]      = 100,
    ["radius"] = 1500,
    ["properties"] = { ["alarm"] = "yes" },
}

-- Drawing: a polygon with three vertices in the real ME shape — vertices
-- live INSIDE mapData.points as deltas relative to mapData.{x,y}, not as
-- absolute world coords. distill at 0.2.0+ preserves this relativity by
-- rebasing only mapData.{x,y} and skipping its geometry sub-arrays.
local drawing_perimeter = {
    ["name"]          = "perimeter",
    ["primitiveType"] = "Polygon",
    ["mapData"] = {
        ["x"] = 100, ["y"] = 200,
        ["points"]  = {
            [1] = { ["x"] = 0,   ["y"] = 0   },
            [2] = { ["x"] = 100, ["y"] = 0   },
            [3] = { ["x"] = 50,  ["y"] = 100 },
        },
    },
    ["color"]      = { 1, 0, 0, 1 },
    ["fillColor"]  = { 1, 0, 0, 0.2 },
}

return {
    ["meta"] = {
        ["selection_mode"] = "multi",
        ["timestamp_utc"]  = "2026-05-03T09:12:54Z",
        ["ok"]             = true,
    },
    ["groups"]     = { [1] = group_aerial, [2] = group_static_hangar },
    ["statics"]    = {},                    -- ME models statics inside groups; distill partitions
    ["zones"]      = { [1] = zone_no_fly },
    ["drawings"]   = { [1] = drawing_perimeter },
    ["nav_points"] = {},
    ["raw"]        = {},
}
