-- context_menu.lua — right-click context menus for the Prefab Manager.
--
-- Owns:
--   * Lazy dxgui Menu construction (one menu per call site, rebuilt each show).
--   * Clipboard probe — resolves on first use to the best available strategy
--     and caches the result.
--   * Public:
--       M.show_for_file_row(x, y, row, hooks)    -- right-click on a prefab row
--       M.show_for_tree_node(x, y, node, hooks)  -- right-click on a tree node
--
-- All callbacks return immediately (no modal blocking). pcall-guarded
-- internally so a missing widget binding degrades to a no-op + log line.

local Menu;       do local ok, m = pcall(require, 'Menu');       if ok then Menu = m end end
local MenuItem;   do local ok, m = pcall(require, 'MenuItem');   if ok then MenuItem = m end end

local M = {}

-- ---------------------------------------------------------------------------
-- Clipboard probe. Resolves lazily on first call, caches the strategy.
-- ---------------------------------------------------------------------------

local clipboard_fn = nil
local clipboard_resolved = false

local function resolve_clipboard()
    if clipboard_resolved then return clipboard_fn end
    clipboard_resolved = true

    if _G.Gui and type(_G.Gui.setClipboard) == 'function' then
        clipboard_fn = function(s)
            local ok = pcall(_G.Gui.setClipboard, s); return ok
        end
        return clipboard_fn
    end

    if _G.dxgui and type(_G.dxgui.setClipboard) == 'function' then
        clipboard_fn = function(s)
            local ok = pcall(_G.dxgui.setClipboard, s); return ok
        end
        return clipboard_fn
    end

    local ok, input = pcall(require, 'Input')
    if ok and input and type(input.setClipboard) == 'function' then
        clipboard_fn = function(s)
            local ok2 = pcall(input.setClipboard, s); return ok2
        end
        return clipboard_fn
    end

    -- Last resort: write payload to a temp file and pipe it into `clip` via
    -- cmd.exe. Writing through a file avoids cmd metacharacter escaping and
    -- preserves newlines (the realistic payload is multi-line Lua text).
    clipboard_fn = function(s)
        if type(s) ~= 'string' then return false end
        local tmpdir = os.getenv('TEMP') or os.getenv('TMP') or '.'
        local tmpname = string.format('%s\\dcs_sms_clip_%d_%d.tmp',
            tmpdir, os.time(), math.random(1, 1e9))
        local f, err = io.open(tmpname, 'wb')
        if not f then
            if log and log.write then
                log.write('sms.me', log.WARNING,
                    'clipboard fallback: cannot open temp file: ' .. tostring(err))
            end
            return false
        end
        f:write(s)
        f:close()
        local rc = os.execute('cmd /c clip < "' .. tmpname .. '"')
        os.remove(tmpname)
        return rc == 0 or rc == true
    end
    return clipboard_fn
end

function M._copy_to_clipboard(text)
    if type(text) ~= 'string' then return false end
    local fn = resolve_clipboard()
    if not fn then return false end
    return fn(text)
end

-- ---------------------------------------------------------------------------
-- Menu construction. Each call rebuilds the menu — DCS Menu instances are
-- cheap to throw away and re-build, and rebuilding lets us toggle entry
-- visibility per-row (e.g. error rows show only Show in Explorer).
-- ---------------------------------------------------------------------------

local function build_menu(entries)
    if not Menu or not MenuItem then return nil end
    local menu = Menu.new()
    local by_label = {}
    for _, e in ipairs(entries) do
        if e.visible ~= false then
            local item = MenuItem.new()
            item:setText(e.label)
            menu:insertItem(item)
            by_label[e.label] = e.on_click
        end
    end
    function menu:onChange(label)
        local cb = by_label[label]
        if cb then pcall(cb) end
        return true  -- dxgui closes the menu
    end
    return menu
end

local function popup_menu(menu, x, y)
    if not menu then return false end
    if menu.popup then
        local ok = pcall(function() menu:popup(x, y) end)
        if ok then return true end
    end
    if menu.show then
        local ok = pcall(function() menu:show(x, y) end)
        if ok then return true end
    end
    if log and log.write then
        log.write('sms.me', log.WARNING, 'context_menu: no popup/show on Menu widget')
    end
    return false
end

-- Build the place-snippet string per GH#50.
local function build_place_snippet(name)
    return string.format('sms.prefab.place(%q, {x = 0, y = 0})  -- rotation = 0, country = nil', name or '')
end

-- ---------------------------------------------------------------------------
-- Public: file-row right-click menu.
--
-- Args:
--   x, y         cursor position
--   row          the W.visible_rows[i] table; carries .name, .path, .error
--   hooks        { on_move = function(row), on_status = function(text, sev) }
--
-- Entries (error rows hide all but Show in Explorer):
--   Move to...
--   (separator)
--   Copy file contents
--   Copy place snippet
--   Show in Explorer
-- ---------------------------------------------------------------------------

function M.show_for_file_row(x, y, row, hooks)
    if not row then return false end
    hooks = hooks or {}
    local function status(text, sev) if hooks.on_status then hooks.on_status(text, sev) end end

    local is_error = row.error ~= nil
    local entries = {
        {
            label = 'Move to...',
            visible = not is_error,
            on_click = function() if hooks.on_move then hooks.on_move(row) end end,
        },
        {
            label = '--',  -- visual separator; rendered as a disabled blank item if MenuItem supports it
            visible = not is_error,
            on_click = function() end,
        },
        {
            label = 'Copy file contents',
            visible = not is_error,
            on_click = function()
                local f = io.open(row.path, 'r')
                if not f then status('Copy failed: cannot open ' .. tostring(row.path), 'error'); return end
                local body = f:read('*a'); f:close()
                local ok = M._copy_to_clipboard(body)
                if ok then
                    status(string.format('Copied %s.prefab contents (%d bytes).', row.name, #body))
                else
                    status('Clipboard unavailable on this build — see dcs.log.', 'error')
                    if log and log.write then
                        log.write('sms.me', log.WARNING, 'clipboard probe found no working strategy')
                    end
                end
            end,
        },
        {
            label = 'Copy place snippet',
            visible = not is_error,
            on_click = function()
                local snippet = build_place_snippet(row.name)
                local ok = M._copy_to_clipboard(snippet)
                if ok then
                    status('Copied placement snippet. (sms.prefab.place not yet shipped in framework.)')
                else
                    status('Clipboard unavailable on this build — see dcs.log.', 'error')
                end
            end,
        },
        {
            label = 'Show in Explorer',
            visible = true,
            on_click = function()
                os.execute('explorer /select,"' .. tostring(row.path) .. '"')
            end,
        },
    }

    local menu = build_menu(entries)
    return popup_menu(menu, x, y)
end

M._build_place_snippet = build_place_snippet  -- exposed for tests

-- ---------------------------------------------------------------------------
-- Public: tree-node right-click menu.
--
-- Args:
--   x, y         cursor position
--   node         { path = 'CAP' / 'CAP/Tomcats' / '' (root) }
--   hooks        { on_new = function(parent_path),
--                  on_rename = function(node),
--                  on_delete = function(node) }
--
-- Entries (root node hides Rename/Delete):
--   New subfolder
--   (separator)  — only if Rename/Delete visible
--   Rename
--   Delete
-- ---------------------------------------------------------------------------

function M.show_for_tree_node(x, y, node, hooks)
    if not node then return false end
    hooks = hooks or {}
    local is_root = (node.path == '' or node.path == nil)

    local entries = {
        {
            label = 'New subfolder',
            visible = true,
            on_click = function() if hooks.on_new then hooks.on_new(node.path or '') end end,
        },
        {
            label = '--',
            visible = not is_root,
            on_click = function() end,
        },
        {
            label = 'Rename',
            visible = not is_root,
            on_click = function() if hooks.on_rename then hooks.on_rename(node) end end,
        },
        {
            label = 'Delete',
            visible = not is_root,
            on_click = function() if hooks.on_delete then hooks.on_delete(node) end end,
        },
    }

    local menu = build_menu(entries)
    return popup_menu(menu, x, y)
end

return M
