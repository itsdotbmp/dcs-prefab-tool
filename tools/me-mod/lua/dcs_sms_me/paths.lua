-- paths.lua — output directory constants and dir-creation helpers.
--
-- Nests under the same Saved Games\DCS\dcs-sms\ root the bridge uses, with
-- per-feature subdirs:
--   me/        — selection dumps (sub-project 2)
--   prefabs/   — distilled prefab files (sub-project 3)

local lfs = require('lfs')
local M = {}

M.ROOT        = lfs.writedir() .. 'dcs-sms\\'
M.OUTBOX_DIR  = M.ROOT .. 'me\\'
M.PREFABS_DIR = M.ROOT .. 'prefabs\\'
M.LOG_TAG     = 'sms.me'

function M.ensure_outbox()
    lfs.mkdir(M.ROOT)
    lfs.mkdir(M.OUTBOX_DIR)
end

function M.ensure_prefabs()
    lfs.mkdir(M.ROOT)
    lfs.mkdir(M.PREFABS_DIR)
end

return M
