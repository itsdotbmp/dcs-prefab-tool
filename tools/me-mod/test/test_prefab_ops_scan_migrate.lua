-- Standalone test for prefab_ops.scan_dir's .lua -> .prefab migration.
-- Uses a temp directory so we can mutate files without touching committed fixtures.
-- Run via: lua test_prefab_ops_scan_migrate.lua  (cwd: tools/me-mod/test/)

local tmp_dir = os.getenv('TEMP') or os.getenv('TMP') or '.'
-- Make a uniquely named subdir per run to avoid stale state across runs.
local run_dir = tmp_dir .. '\\dcs_sms_test_migrate_' .. tostring(os.time()) .. '\\'
os.execute('mkdir "' .. run_dir:sub(1, -2) .. '" 2>nul')

-- Helper: write a minimal valid prefab to a path.
local function write_prefab(path, name)
    local f = assert(io.open(path, 'w'))
    f:write(string.format(
        'return {\n  ["meta"] = { ["name"] = %q, ["sms_prefab_version"] = "0.1.0" },\n  ["groups"] = {},\n  ["statics"] = {},\n  ["zones"] = {},\n  ["drawings"] = {},\n}\n',
        name))
    f:close()
end

-- Stub lfs (mkdir + dir). dir uses io.popen("dir /b") on Windows.
local function list_dir(path)
    local fixtures_path = path:gsub('\\', '/'):gsub('/$', '')
    local p = io.popen('dir /b "' .. fixtures_path:gsub('/', '\\') .. '" 2>nul')
    local files = {}
    if p then
        for line in p:lines() do files[#files + 1] = line end
        p:close()
    end
    return files
end
package.preload['lfs'] = function()
    return {
        writedir = function() return '' end,
        mkdir    = function() return true end,
        attributes = function(path) return { mode = 'file' } end,
        dir = function(p)
            local files = list_dir(p)
            local i = 0
            return function() i = i + 1; return files[i] end
        end,
    }
end

-- Stub selection (not used by scan_dir, but prefab_ops requires it).
package.preload['dcs_sms_me.selection'] = function()
    return { snapshot = function() return { ok = true, groups = {}, statics = {}, zones = {}, drawings = {} } end }
end

-- Capture log calls so we can assert on warnings/info.
local log_calls = {}
log = log or {}
log.INFO    = log.INFO    or 'INFO'
log.WARNING = log.WARNING or 'WARNING'
log.ERROR   = log.ERROR   or 'ERROR'
log.write   = function(tag, level, msg) log_calls[#log_calls + 1] = { tag = tag, level = level, msg = msg } end

package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
local paths = require('dcs_sms_me.paths')
paths.PREFABS_DIR = run_dir

local prefab_ops = require('prefab_ops')

local failures = 0
local function check(name, ok, msg)
    if ok then print('PASS ' .. name)
    else print('FAIL ' .. name .. ': ' .. tostring(msg)); failures = failures + 1
    end
end

local function file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close(); return true end
    return false
end

local function clean_dir()
    -- Remove every file in the run_dir.
    local files = list_dir(run_dir)
    for _, name in ipairs(files) do os.remove(run_dir .. name) end
    log_calls = {}
end

-- Case: a single legacy .lua gets renamed to .prefab.
do
    clean_dir()
    write_prefab(run_dir .. 'old_one.lua', 'old_one')
    local rows = prefab_ops.scan_dir()
    check('migration: 1 row returned', #rows == 1, 'got ' .. tostring(#rows))
    check('migration: row has no error', rows[1] and rows[1].error == nil,
          'got error: ' .. tostring(rows[1] and rows[1].error))
    check('migration: .prefab file exists',  file_exists(run_dir .. 'old_one.prefab'))
    check('migration: .lua file is gone',    not file_exists(run_dir .. 'old_one.lua'))
    check('migration: row.path ends in .prefab',
          rows[1] and rows[1].path:sub(-7) == '.prefab',
          'got path: ' .. tostring(rows[1] and rows[1].path))

    -- Should have logged INFO for migration.
    local found_info = false
    for _, c in ipairs(log_calls) do
        if c.level == 'INFO' and c.msg:match('migrated') then found_info = true end
    end
    check('migration: INFO log line for rename', found_info, 'no migration INFO log')
end

-- Case: collision between foo.lua and foo.prefab — both kept, warning logged.
do
    clean_dir()
    write_prefab(run_dir .. 'twin.lua',    'twin')
    write_prefab(run_dir .. 'twin.prefab', 'twin')
    local rows = prefab_ops.scan_dir()
    check('collision: 2 rows returned (one per file)', #rows == 2, 'got ' .. tostring(#rows))
    check('collision: .lua still on disk',    file_exists(run_dir .. 'twin.lua'))
    check('collision: .prefab still on disk', file_exists(run_dir .. 'twin.prefab'))

    local found_warn = false
    for _, c in ipairs(log_calls) do
        if c.level == 'WARNING' and c.msg:match('collision') then found_warn = true end
    end
    check('collision: WARNING log line', found_warn, 'no collision WARNING log')
end

-- Case: rename failure (stubbed os.rename returns false) — file stays as .lua.
do
    clean_dir()
    write_prefab(run_dir .. 'locked.lua', 'locked')
    local real_rename = os.rename
    os.rename = function() return false end
    local rows = prefab_ops.scan_dir()
    os.rename = real_rename

    check('rename-fail: 1 row returned',          #rows == 1, 'got ' .. tostring(#rows))
    check('rename-fail: row has no error',        rows[1] and rows[1].error == nil,
          'got error: ' .. tostring(rows[1] and rows[1].error))
    check('rename-fail: .lua still on disk',      file_exists(run_dir .. 'locked.lua'))
    check('rename-fail: .prefab does NOT exist',  not file_exists(run_dir .. 'locked.prefab'))

    local found_warn = false
    for _, c in ipairs(log_calls) do
        if c.level == 'WARNING' and c.msg:match('rename failed') then found_warn = true end
    end
    check('rename-fail: WARNING log line', found_warn, 'no rename-fail WARNING log')
end

-- Case: a pre-existing .prefab is left untouched (no rename attempted).
do
    clean_dir()
    write_prefab(run_dir .. 'native.prefab', 'native')
    local rename_was_called = false
    local real_rename = os.rename
    os.rename = function(...) rename_was_called = true; return real_rename(...) end
    local rows = prefab_ops.scan_dir()
    os.rename = real_rename

    check('native: 1 row',                        #rows == 1)
    check('native: rename not called',            rename_was_called == false,
          'os.rename should not be called for .prefab entries')
    check('native: .prefab still on disk',        file_exists(run_dir .. 'native.prefab'))
end

local function cleanup_run_dir()
    local files = list_dir(run_dir)
    for _, name in ipairs(files) do os.remove(run_dir .. name) end
    os.execute('rmdir "' .. run_dir:sub(1, -2) .. '" 2>nul')
end

cleanup_run_dir()

if failures > 0 then
    print(string.format('%d failure(s)', failures))
    os.exit(1)
end
print('All scan_dir migration tests passed.')
