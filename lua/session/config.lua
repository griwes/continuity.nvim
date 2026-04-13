---@class session.Config
---@field state_file string
---@field continuous session.ContinuousConfig

---@class session.ContinuousConfig
---@field enabled boolean
---@field session_id string
---@field write_debounce_ms integer

local M = {}

local defaults = {
    state_file = vim.fs.joinpath(vim.fn.stdpath('state'), 'session.nvim', 'sessions.json'),
    continuous = {
        enabled = false,
        session_id = 'session:live',
        write_debounce_ms = 250,
    },
}

---@type session.Config
local current = vim.deepcopy(defaults)

---@param opts? Partial<session.Config>
---@return session.Config
function M.set(opts)
    current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
    return vim.deepcopy(current)
end

---@return session.Config
function M.get()
    return vim.deepcopy(current)
end

---@return session.Config
function M.reset()
    current = vim.deepcopy(defaults)
    return vim.deepcopy(current)
end

return M
