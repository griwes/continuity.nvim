---@class continuity.Config
---@field state_file string
---@field state_dir? string
---@field continuous continuity.ContinuousConfig
---@field session_key continuity.SessionKeyConfig
---@field autoload continuity.AutoloadConfig
---@field shada continuity.ShadaConfig

---@alias continuity.AutoloadPolicy '"disabled"'|'"cwd"'|'"cwd_branch"'|'"last"'

---@class continuity.ContinuousConfig
---@field enabled boolean
---@field session_id string Use "auto" to derive from the current session key.
---@field write_debounce_ms integer

---@class continuity.SessionKeyConfig
---@field use_git_branch boolean

---@class continuity.AutoloadConfig
---@field policy continuity.AutoloadPolicy

---@alias continuity.ExternalShadaPolicy '"ignore"'|'"warn"'|'"error"'

---@class continuity.ShadaConfig
---@field external_policy continuity.ExternalShadaPolicy

local M = {}

local state_root = vim.fs.joinpath(vim.fn.stdpath('state'), 'continuity.nvim')

local defaults = {
    state_file = vim.fs.joinpath(state_root, 'sessions.json'),
    state_dir = vim.fs.joinpath(state_root, 'sessions'),
    continuous = {
        enabled = false,
        session_id = 'session:live',
        write_debounce_ms = 250,
    },
    session_key = {
        use_git_branch = false,
    },
    autoload = {
        policy = 'disabled',
    },
    shada = {
        external_policy = 'warn',
    },
}

local valid_autoload_policies = {
    cwd = true,
    cwd_branch = true,
    disabled = true,
    last = true,
}

local valid_external_shada_policies = {
    error = true,
    ignore = true,
    warn = true,
}

---@type continuity.Config
local current = vim.deepcopy(defaults)

---@param opts? Partial<continuity.Config>
---@return continuity.Config
function M.set(opts)
    current = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

    if opts ~= nil and opts.state_file ~= nil and opts.state_dir == nil then
        current.state_dir = string.format('%s.d', current.state_file)
    end

    if valid_autoload_policies[current.autoload.policy] ~= true then
        current.autoload.policy = 'disabled'
    end

    if valid_external_shada_policies[current.shada.external_policy] ~= true then
        current.shada.external_policy = 'warn'
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
