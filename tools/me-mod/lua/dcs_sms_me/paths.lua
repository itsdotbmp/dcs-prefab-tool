-- paths.lua — output directory constants and dir-creation helper.
--
-- Nests under the same Saved Games\DCS\dcs-sms\ root the bridge uses, in a
-- sibling me/ subdir. Single root keeps user mental model simple.

local lfs = require('lfs')
local M = {}

M.ROOT       = lfs.writedir() .. 'dcs-sms\\'
M.OUTBOX_DIR = M.ROOT .. 'me\\'
M.LOG_TAG    = 'sms.me'

function M.ensure_outbox()
    lfs.mkdir(M.ROOT)
    lfs.mkdir(M.OUTBOX_DIR)
end

return M
