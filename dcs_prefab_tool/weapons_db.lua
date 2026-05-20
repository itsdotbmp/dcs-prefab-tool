-- weapons_db.lua — lazy index of ED's weapon DB by display name and CLSID.
--
-- The warehouse table indexes weapons by wsType (a 4-int tuple). For
-- friendly CLI input, we map fragment / display-name / CLSID inputs back
-- to that tuple. ED's DB.weapon_by_CLSID has ~2160 entries; we walk it
-- once on first access and cache the index for the life of the ME process.
--
-- find_by_name(needle) algorithm:
--   1. If needle starts with '{', treat as CLSID and route to find_by_clsid.
--   2. Lowercase + exact-match against the displayName index.
--   3. Otherwise substring-search across all entries (case-insensitive,
--      first match wins for unique; > 1 returns ambiguous + first 5
--      candidates so the user can refine).
--
-- Failure mode: if DB unavailable (broken install), all lookups return
-- { found = false, error = 'weapon DB not available' }. No throws.

local M = {}

-- nil until first lookup. Rebuilt next call if set back to nil (e.g. by
-- a hot-reload via package.loaded[...] = nil).
local _index

local function build()
    local DB_ok, DB = pcall(require, 'me_db_api')
    if not DB_ok or not DB or type(DB.weapon_by_CLSID) ~= 'table' then return nil end
    local idx = {
        by_displayname_lower = {},
        by_clsid             = {},
        all_entries          = {},
    }
    for clsid, w in pairs(DB.weapon_by_CLSID) do
        if type(w) == 'table'
                and type(w.displayName) == 'string'
                and type(w.wsTypeOfWeapon) == 'table' then
            local entry = {
                clsid        = clsid,
                name         = w.name,
                display_name = w.displayName,
                ws_type      = {
                    w.wsTypeOfWeapon[1],
                    w.wsTypeOfWeapon[2],
                    w.wsTypeOfWeapon[3],
                    w.wsTypeOfWeapon[4],
                },
                category     = w.category,
            }
            -- Multiple CLSIDs CAN share a displayName (rare in practice).
            -- Last-wins for the map; substring search still walks the full
            -- list, so ambiguity surfaces there.
            idx.by_displayname_lower[w.displayName:lower()] = entry
            idx.by_clsid[clsid] = entry
            idx.all_entries[#idx.all_entries + 1] = entry
        end
    end
    return idx
end

function M.find_by_clsid(clsid)
    _index = _index or build()
    if not _index then return { found = false, error = 'weapon DB not available' } end
    if type(clsid) ~= 'string' then return { found = false } end
    local e = _index.by_clsid[clsid]
    if e then return { found = true, entry = e } end
    return { found = false }
end

function M.find_by_name(needle)
    if type(needle) ~= 'string' or needle == '' then return { found = false } end
    if needle:sub(1, 1) == '{' then return M.find_by_clsid(needle) end
    _index = _index or build()
    if not _index then return { found = false, error = 'weapon DB not available' } end
    local n_low = needle:lower()
    local exact = _index.by_displayname_lower[n_low]
    if exact then return { found = true, entry = exact } end
    local hits = {}
    for _, e in ipairs(_index.all_entries) do
        if e.display_name:lower():find(n_low, 1, true) then
            hits[#hits + 1] = e
            if #hits > 5 then break end -- bound the candidate list
        end
    end
    if #hits == 0 then return { found = false } end
    if #hits == 1 then return { found = true, entry = hits[1] } end
    local cands = {}
    for _, e in ipairs(hits) do cands[#cands + 1] = e.display_name end
    return { ambiguous = true, candidates = cands }
end

return M
