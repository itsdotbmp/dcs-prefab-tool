-- context_menu.lua — right-click context menus for the Prefab Manager.
--
-- Owns:
--   * Lazy dxgui Menu construction (one menu per call site, rebuilt each show).
--   * Clipboard probe — resolves on first use to the best available strategy
--     and caches the result.
--   * Public:
--       M.show_for_file_row(x, y, row, on_move)   -- right-click on a prefab row
--       M.show_for_tree_node(x, y, node, hooks)   -- right-click on a tree node
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

    -- Last resort: pipe to `clip` via cmd.exe. Escape double-quotes.
    clipboard_fn = function(s)
        if type(s) ~= 'string' then return false end
        local escaped = s:gsub('"', '""'):gsub('[\r\n]', ' ')
        local rc = os.execute('echo ' .. escaped .. '|clip')
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
-- (Menu builder + show_for_* defined in subsequent tasks.)
-- ---------------------------------------------------------------------------

return M
