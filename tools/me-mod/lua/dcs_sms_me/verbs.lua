-- dcs_sms_me/verbs.lua — host module for `dcs-sms me <noun> <verb>` commands.
--
-- Each verb is a Lua function that takes a single args table and returns a
-- result table (JSON-encoded by the bridge for the CLI response). Verb
-- functions live here rather than in the Go CLI because:
--   * the work happens in the ME's Lua state (we'd be string-templating Lua
--     into the bridge anyway), and
--   * keeping the logic in one Lua module makes verbs testable independently
--     of the CLI and reusable across clients (CLI today, possibly other
--     bridges or in-ME UI later).
--
-- Naming convention: verb function names use snake_case to mirror the CLI's
-- `<noun> <verb>` shape (`me file open` → `verbs.file_open(args)`).
--
-- Error handling: each verb wraps its work in pcall and returns a uniform
-- result shape:
--   { ok = true,  ... }       -- success, with verb-specific extra fields
--   { ok = false, error = "..." }  -- failure, error string
-- The CLI side checks resp.return_value.ok to decide its exit code.

local M = {}

-- ============================================================
-- File / mission lifecycle verbs
-- ============================================================

-- file_open — open a .miz file in the Mission Editor.
-- Wraps me_toolbar.loadMission. The actual file read is async (ED's
-- progressBar schedules it on a later UpdateManager tick), so this returns
-- as soon as the call is dispatched — not when the load has completed.
--
-- args: { path: string }     -- absolute path to .miz file (forward slashes
--                                preferred to dodge backslash-escape pain)
function M.file_open(args)
    if type(args) ~= 'table' or type(args.path) ~= 'string' or args.path == '' then
        return { ok = false, error = 'file_open requires args.path (string)' }
    end
    local ok_req, me_toolbar = pcall(require, 'me_toolbar')
    if not ok_req or type(me_toolbar) ~= 'table' or type(me_toolbar.loadMission) ~= 'function' then
        return { ok = false, error = 'me_toolbar.loadMission unavailable' }
    end
    local ok_call, err = pcall(me_toolbar.loadMission, args.path)
    if not ok_call then
        return { ok = false, error = 'loadMission: ' .. tostring(err) }
    end
    return { ok = true, path = args.path }
end

return M
