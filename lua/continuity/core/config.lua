---@class continuity.Config
---@field state_file string
---@field continuous continuity.ContinuousConfig
---@field mksession continuity.MksessionConfig

---@class continuity.ContinuousConfig
---@field enabled boolean
---@field session_id string
---@field write_debounce_ms integer

---@class continuity.MksessionConfig
---@field enabled boolean
---@field capture_live boolean
---@field dir string

local M = {}

local defaults = {
    state_file = vim.fs.joinpath(vim.fn.stdpath('state'), 'continuity.nvim', 'sessions.json'),
    continuous = {
        enabled = false,
        session_id = 'session:live',
        write_debounce_ms = 250,
    },
    mksession = {
        enabled = false,
        capture_live = false,
        dir = vim.fs.joinpath(vim.fn.stdpath('state'), 'continuity.nvim', 'mksession'),
    },
}

---@type continuity.Config
local current = vim.deepcopy(defaults)

---@param opts? Partial<continuity.Config>
---@return continuity.Config
function M.set(opts)
    current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
    return vim.deepcopy(current)
end

---@return continuity.Config
function M.get()
    return vim.deepcopy(current)
end

---@return continuity.Config
function M.reset()
    current = vim.deepcopy(defaults)
    return vim.deepcopy(current)
end

return M
