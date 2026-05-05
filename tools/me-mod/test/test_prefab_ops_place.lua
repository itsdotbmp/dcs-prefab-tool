-- Standalone test for prefab_ops place math (rotate + translate).
-- The ME-API injection itself is not unit-testable; covered by manual smoke.
-- Run via: lua test_prefab_ops_place.lua  (cwd: tools/me-mod/test/)

package.preload['lfs'] = function()
    return { writedir = function() return '' end, mkdir = function() return true end,
             dir = function() return function() return nil end end }
end
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function approx(a, b, eps)
    eps = eps or 0.001
    return math.abs(a - b) <= eps
end

-- Math helper: place_xy(rel_x, rel_y, anchor, rotation_deg) → (world_x, world_y)
do
    local x, y = prefab_ops._place_xy(100, 0, { x = 1000, y = 2000 }, 0)
    check('rot 0: (100, 0) at anchor (1000, 2000) → (1100, 2000)',
          approx(x, 1100) and approx(y, 2000), 'got ' .. x .. ', ' .. y)

    local x2, y2 = prefab_ops._place_xy(100, 0, { x = 0, y = 0 }, 90)
    check('rot 90: (100, 0) → (0, 100)',
          approx(x2, 0) and approx(y2, 100), 'got ' .. x2 .. ', ' .. y2)

    local x3, y3 = prefab_ops._place_xy(0, 100, { x = 0, y = 0 }, 90)
    check('rot 90: (0, 100) → (-100, 0)',
          approx(x3, -100) and approx(y3, 0), 'got ' .. x3 .. ', ' .. y3)

    local x4, y4 = prefab_ops._place_xy(100, 0, { x = 500, y = 500 }, 180)
    check('rot 180: (100, 0) at anchor (500, 500) → (400, 500)',
          approx(x4, 400) and approx(y4, 500), 'got ' .. x4 .. ', ' .. y4)
end

-- 0.1.0 back-compat un-rebase helper: adds world_anchor back to every
-- vertex inside mapData's geometry sub-arrays, leaves mapData.{x,y}
-- untouched. Locks behavior so a future bump can't silently break the
-- shim by misfiring (or not firing) on legacy saves.
do
    local md = {
        x = -100, y = -200,                 -- the polygon anchor in distilled coords; untouched
        points = {                          -- vertices have been over-rebased by (-1000, -2000)
            { x = -1000, y = -2000 },
            { x = -900,  y = -2000 },
        },
    }
    prefab_ops._unrebase_mapData_geometry(md, 1000, 2000)
    check('un-rebase: mapData.x untouched', md.x == -100, 'got ' .. md.x)
    check('un-rebase: mapData.y untouched', md.y == -200, 'got ' .. md.y)
    check('un-rebase: points[1] (-1000,-2000) + (1000,2000) = (0,0)',
          approx(md.points[1].x, 0) and approx(md.points[1].y, 0),
          'got ' .. md.points[1].x .. ', ' .. md.points[1].y)
    check('un-rebase: points[2] (-900,-2000) + (1000,2000) = (100,0)',
          approx(md.points[2].x, 100) and approx(md.points[2].y, 0),
          'got ' .. md.points[2].x .. ', ' .. md.points[2].y)

    -- nil mapData: no-op (no error).
    prefab_ops._unrebase_mapData_geometry(nil, 1000, 2000)
    check('un-rebase nil mapData: no error', true)

    -- Recurses through nested geometry tables.
    local md2 = {
        x = 0, y = 0,
        arc_points = { sub = { { x = -50, y = -50 } } },
    }
    prefab_ops._unrebase_mapData_geometry(md2, 50, 50)
    check('un-rebase: nested vertex (-50,-50) + (50,50) = (0,0)',
          approx(md2.arc_points.sub[1].x, 0) and approx(md2.arc_points.sub[1].y, 0),
          'got ' .. md2.arc_points.sub[1].x .. ', ' .. md2.arc_points.sub[1].y)
end

-- Drawing rotation: vertices inside mapData get rotated around the local
-- origin; mapData.{x,y} itself stays untouched (it's the polygon anchor and
-- rotates downstream via _place_xy).
do
    local md = {
        x = 100, y = 200,
        points = {
            { x = 100, y = 0   },   -- east
            { x = 0,   y = 100 },   -- north
        },
    }
    prefab_ops._rotate_mapData_geometry(md, 90)
    -- 90deg rotation: (x, y) → (-y, x). So (100, 0) → (0, 100); (0, 100) → (-100, 0).
    check('rotate 90: mapData.x untouched', md.x == 100, 'got ' .. md.x)
    check('rotate 90: mapData.y untouched', md.y == 200, 'got ' .. md.y)
    check('rotate 90: points[1] (100,0) → (0,100)',
          approx(md.points[1].x, 0) and approx(md.points[1].y, 100),
          'got ' .. md.points[1].x .. ', ' .. md.points[1].y)
    check('rotate 90: points[2] (0,100) → (-100,0)',
          approx(md.points[2].x, -100) and approx(md.points[2].y, 0),
          'got ' .. md.points[2].x .. ', ' .. md.points[2].y)

    -- 0deg rotation: no-op.
    local md2 = { x = 5, y = 5, points = { { x = 7, y = 9 } } }
    prefab_ops._rotate_mapData_geometry(md2, 0)
    check('rotate 0: vertex unchanged',
          md2.points[1].x == 7 and md2.points[1].y == 9,
          'got ' .. md2.points[1].x .. ', ' .. md2.points[1].y)

    -- nil mapData: no-op (no error).
    prefab_ops._rotate_mapData_geometry(nil, 90)
    check('rotate nil mapData: no error', true)

    -- Recurses into nested geometry sub-arrays (e.g. arc_points).
    local md3 = {
        x = 0, y = 0,
        arc_points = {
            sub = { { x = 100, y = 0 } },
        },
    }
    prefab_ops._rotate_mapData_geometry(md3, 180)
    check('rotate 180: nested vertex (100,0) → (-100,0)',
          approx(md3.arc_points.sub[1].x, -100) and approx(md3.arc_points.sub[1].y, 0),
          'got ' .. md3.arc_points.sub[1].x .. ', ' .. md3.arc_points.sub[1].y)
end

-- Heading composition: world_heading_deg = (file_heading_deg + rotation_deg) mod 360
do
    check('heading 30 + rotation 60 = 90', prefab_ops._heading_world(30, 60) == 90)
    check('heading 350 + rotation 20 = 10', prefab_ops._heading_world(350, 20) == 10)
    check('heading -30 + rotation 0 = 330', prefab_ops._heading_world(-30, 0) == 330)
end

-- Full pipeline: file (deg) -> rotation -> radians for DCS injection.
-- The earlier triple-conversion bug had `v * (180/math.pi)` baked in, so a
-- 45-deg saved heading came out as ~1.0177 rad (= 58.31°) instead of the
-- correct 0.7854 rad. These assertions lock that down.
do
    -- 45° saved, no extra rotation → π/4 rad.
    local g = { heading = 45, units = { { heading = 45 } } }
    prefab_ops._transform_headings(g, 0)
    check('heading 45° → π/4 rad (group)',
          approx(g.heading, math.pi / 4),
          'got ' .. tostring(g.heading))
    check('heading 45° → π/4 rad (nested unit)',
          approx(g.units[1].heading, math.pi / 4),
          'got ' .. tostring(g.units[1].heading))

    -- 0° saved → 0 rad regardless of rotation.
    local g2 = { heading = 0 }
    prefab_ops._transform_headings(g2, 0)
    check('heading 0° → 0 rad', g2.heading == 0, 'got ' .. tostring(g2.heading))

    -- 30° saved + 60° place rotation → 90° → π/2 rad.
    local g3 = { heading = 30 }
    prefab_ops._transform_headings(g3, 60)
    check('heading 30° + rot 60° → π/2 rad',
          approx(g3.heading, math.pi / 2),
          'got ' .. tostring(g3.heading))

    -- Wrap: 350° + 20° → 10° → π/18 rad.
    local g4 = { heading = 350 }
    prefab_ops._transform_headings(g4, 20)
    check('heading 350° + rot 20° wraps to π/18 rad',
          approx(g4.heading, math.pi / 18),
          'got ' .. tostring(g4.heading))
end

-- Bounding box: AABB over every entity's position, in the prefab's
-- anchor-relative frame (the frame distill produces).
do
    local prefab = {
        meta   = { name = 'fixture' },
        groups = {
            { x = 0, y = 0, units = { { x = 100, y = -50 }, { x = -200, y = 30 } } },
        },
        statics = { { x = 50, y = 75 } },
        zones   = { { x = 0, y = 0, radius = 80 } },     -- expands ±80 on both axes
        drawings = {
            { mapData = { x = -10, y = 10, points = { { x = -50, y = 0 }, { x = 50, y = 100 } } } },
            -- Effective vertex coords: (-60, 10) and (40, 110).
        },
    }
    local bb = prefab_ops.compute_bbox(prefab)
    check('bbox: x range covers unit + drawing left', bb.min_x == -200, 'got ' .. bb.min_x)
    check('bbox: x range covers unit right', bb.max_x == 100, 'got ' .. bb.max_x)
    check('bbox: y range covers drawing vertex top', bb.min_y == -80, 'got ' .. bb.min_y)
    check('bbox: y range covers drawing vertex bottom', bb.max_y == 110, 'got ' .. bb.max_y)

    local empty = prefab_ops.compute_bbox({ meta = {}, groups = {}, statics = {}, zones = {}, drawings = {} })
    check('empty prefab: bbox is nil', empty == nil)

    check('non-table prefab: bbox is nil', prefab_ops.compute_bbox('nope') == nil)
end

-- Country override: stamps country_name + clears numeric country on the
-- group AND each unit. nil/empty leaves everything alone.
do
    local g = {
        country = 80,
        country_name = 'Russia',
        units = { { country = 80 }, { country = 80, country_name = 'Russia' } },
    }
    prefab_ops._override_country(g, 'USA')
    check('override: group country_name set', g.country_name == 'USA')
    check('override: group country (numeric) cleared', g.country == nil)
    check('override: unit[1] country_name set', g.units[1].country_name == 'USA')
    check('override: unit[1] country (numeric) cleared', g.units[1].country == nil)
    check('override: unit[2] country_name overwritten', g.units[2].country_name == 'USA')

    local g2 = { country = 80, country_name = 'Russia' }
    prefab_ops._override_country(g2, nil)
    check('override nil: country_name untouched', g2.country_name == 'Russia')
    check('override nil: country (numeric) untouched', g2.country == 80)

    prefab_ops._override_country(g2, '')
    check('override "": country_name untouched', g2.country_name == 'Russia')
    check('override "": country (numeric) untouched', g2.country == 80)

    -- Static (no units array) must not blow up.
    local s = { country = 1, type = 'static' }
    prefab_ops._override_country(s, 'Insurgents')
    check('override on static (no units): country_name set', s.country_name == 'Insurgents')
    check('override on static (no units): no error', s.country == nil)
end

-- Resolve effective anchor: keep_position uses meta.world_anchor.
do
    local prefab = { meta = { world_anchor = { x = 5000, y = 6000 } }, groups = {}, statics = {}, zones = {}, drawings = {} }
    local a, r = prefab_ops._resolve_anchor(prefab, { keep_position = true, anchor = { x = 1, y = 1 }, rotation = 30 })
    check('keep_position: anchor from meta', a.x == 5000 and a.y == 6000)
    check('keep_position: rotation forced 0', r == 0)

    local a2, r2 = prefab_ops._resolve_anchor(prefab, { anchor = { x = 100, y = 200 }, rotation = 45 })
    check('non-keep_position: anchor from opts', a2.x == 100 and a2.y == 200)
    check('non-keep_position: rotation passed through', r2 == 45)

    local a3 = prefab_ops._resolve_anchor(prefab, { rotation = 0 })
    check('no anchor + no keep_position: returns nil', a3 == nil)

    -- Malformed-meta paths under keep_position: every "the world_anchor
    -- is missing or not a coordinate pair" path should fall through to
    -- nil rather than spawn at (0,0) or throw on the field access.
    local no_meta = { groups = {}, statics = {}, zones = {}, drawings = {} }
    check('keep_position + no meta: returns nil',
          prefab_ops._resolve_anchor(no_meta, { keep_position = true }) == nil)

    local no_anchor = { meta = {}, groups = {}, statics = {}, zones = {}, drawings = {} }
    check('keep_position + meta but no world_anchor: returns nil',
          prefab_ops._resolve_anchor(no_anchor, { keep_position = true }) == nil)

    local bad_x = { meta = { world_anchor = { x = 'oops', y = 6000 } } }
    check('keep_position + non-numeric world_anchor.x: returns nil',
          prefab_ops._resolve_anchor(bad_x, { keep_position = true }) == nil)

    local bad_y = { meta = { world_anchor = { x = 5000 } } }   -- missing y entirely
    check('keep_position + missing world_anchor.y: returns nil',
          prefab_ops._resolve_anchor(bad_y, { keep_position = true }) == nil)

    -- Same defensive checks for the non-keep_position path.
    local bad_opts_anchor = { meta = { world_anchor = { x = 1, y = 2 } } }
    check('non-keep_position + non-numeric opts.anchor.x: returns nil',
          prefab_ops._resolve_anchor(bad_opts_anchor, { anchor = { x = 'oops', y = 1 } }) == nil)
end

-- ---------------------------------------------------------------------------
-- find_missing_types: country catalog check.
-- Stubs me_db_api so we can assert the helper walks Countries[*].Units[*][*]
-- correctly and returns the list of types the country can't deploy.
-- ---------------------------------------------------------------------------

-- DB stub: USA has the carrier and a humvee; Abkhazia has only a Hi-Speed Boat.
package.preload['me_db_api'] = function()
    return {
        db = {
            Countries = {
                [1] = {
                    Name = 'USA',
                    Units = {
                        Ships  = { Ship = { { Name = 'CVN_71_Theodore_Roosevelt' } } },
                        Cars   = { Car  = { { Name = 'Hummer' } } },
                        Planes = { Plane = { { Name = 'F-16C_50' } } },
                    },
                },
                [2] = {
                    Name = 'Abkhazia',
                    Units = {
                        Ships = { Ship = { { Name = 'speedboat' } } },
                    },
                },
                [3] = {
                    Name = 'NoUnits',  -- well-formed but empty catalog
                    Units = {},
                },
            },
        },
    }
end

do
    -- Carrier under USA: empty missing list (USA has it).
    local prefab = {
        meta = {},
        groups = {
            { units = { { type = 'CVN_71_Theodore_Roosevelt' } } },
        },
    }
    local m = prefab_ops._find_missing_types(prefab, 'USA')
    check('USA supports carrier: no missing types', type(m) == 'table' and #m == 0,
          'got ' .. tostring(m and #m))
end

do
    -- Carrier under Abkhazia: the carrier type comes back as missing.
    local prefab = {
        meta = {},
        groups = {
            { units = { { type = 'CVN_71_Theodore_Roosevelt' } } },
        },
    }
    local m = prefab_ops._find_missing_types(prefab, 'Abkhazia')
    check('Abkhazia missing carrier: 1 missing type',
          type(m) == 'table' and #m == 1, 'got ' .. tostring(m and #m))
    check('Abkhazia missing carrier: name reported',
          m and m[1] == 'CVN_71_Theodore_Roosevelt')
end

do
    -- Multiple missing types come back sorted + de-duplicated.
    local prefab = {
        meta = {},
        groups = {
            { units = { { type = 'CVN_71_Theodore_Roosevelt' }, { type = 'F-16C_50' } } },
            { units = { { type = 'F-16C_50' } } },         -- duplicate; should not be repeated
            { units = { { type = 'Hummer' } } },           -- USA has it; Abkhazia doesn't
        },
        statics = {
            { units = { { type = 'CVN_71_Theodore_Roosevelt' } } },  -- duplicate, walks statics too
        },
    }
    local m = prefab_ops._find_missing_types(prefab, 'Abkhazia')
    check('multi-missing: 3 unique entries', type(m) == 'table' and #m == 3,
          'got ' .. tostring(m and #m))
    check('multi-missing: sorted alphabetically',
          m[1] == 'CVN_71_Theodore_Roosevelt' and m[2] == 'F-16C_50' and m[3] == 'Hummer',
          'got ' .. table.concat(m or {}, ', '))
end

do
    -- Unknown country in DB: nil (caller should treat as "skip the check").
    local prefab = { meta = {}, groups = { { units = { { type = 'Hummer' } } } } }
    local m = prefab_ops._find_missing_types(prefab, 'Atlantis')
    check('unknown country returns nil', m == nil)
end

do
    -- Empty / nil country name: nil.
    check('nil country returns nil',
          prefab_ops._find_missing_types({ meta = {}, groups = {} }, nil) == nil)
    check('empty country returns nil',
          prefab_ops._find_missing_types({ meta = {}, groups = {} }, '') == nil)
end

do
    -- Country with empty Units catalog: every type is missing.
    local prefab = {
        meta = {},
        groups = { { units = { { type = 'CVN_71_Theodore_Roosevelt' } } } },
    }
    local m = prefab_ops._find_missing_types(prefab, 'NoUnits')
    check('empty catalog: all types reported missing',
          type(m) == 'table' and #m == 1 and m[1] == 'CVN_71_Theodore_Roosevelt')
end

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All prefab_ops place tests passed.')
