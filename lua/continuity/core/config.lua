---@class continuity.Config
---@field state_file string
---@field continuous continuity.ContinuousConfig
---@field mksession continuity.MksessionConfig
---@field session_key continuity.SessionKeyConfig
---@field autoload continuity.AutoloadConfig

---@alias continuity.AutoloadPolicy '"disabled"'|'"cwd"'|'"cwd_branch"'|'"last"'

---@class continuity.ContinuousConfig
---@field enabled boolean
---@field session_id string Use "auto" to derive from the current session key.
---@field write_debounce_ms integer

---@class continuity.MksessionConfig
---@field enabled boolean
---@field capture_live boolean
---@field dir string
---@field sessionoptions? string|string[]

---@class continuity.SessionKeyConfig
---@field use_git_branch boolean

---@class continuity.AutoloadConfig
---@field policy continuity.AutoloadPolicy

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
        sessionoptions = nil,
    },
    session_key = {
        use_git_branch = false,
    },
    autoload = {
        policy = 'disabled',
    },
}

local valid_autoload_policies = {
    cwd = true,
    cwd_branch = true,
    disabled = true,
    last = true,
}

---@type continuity.Config
local current = vim.deepcopy(defaults)

---@param opts? Partial<continuity.Config>
---@return continuity.Config
function M.set(opts)
    current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

    if valid_autoload_policies[current.autoload.policy] ~= true then
        current.autoload.policy = 'disabled'
    end

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
