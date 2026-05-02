local config = require('continuity.core.config')

local M = {}

---@class continuity.SessionKey
---@field id string
---@field name string
---@field cwd string
---@field branch? string

---@param value string
---@return string
local function slug(value)
    local normalized = value:gsub('[^%w_.-]', '_'):gsub('_+', '_'):gsub('^_+', ''):gsub('_+$', '')

    return normalized ~= '' and normalized or 'session'
end

---@param cwd string
---@return string?
local function git_branch(cwd)
    if vim.fn.executable('git') == 0 then
        return nil
    end

    local branch = vim.fn.systemlist({ 'git', '-C', cwd, 'symbolic-ref', '--quiet', '--short', 'HEAD' })

    if vim.v.shell_error == 0 and type(branch[1]) == 'string' and branch[1] ~= '' then
        return branch[1]
    end

    local commit = vim.fn.systemlist({ 'git', '-C', cwd, 'rev-parse', '--short', 'HEAD' })

    if vim.v.shell_error == 0 and type(commit[1]) == 'string' and commit[1] ~= '' then
        return 'detached-' .. commit[1]
    end

    return nil
end

---@param cwd? string
---@return string
local function normalize_cwd(cwd)
    return type(cwd) == 'string' and cwd ~= '' and vim.fs.normalize(cwd) or vim.fn.getcwd()
end

---@param opts? { cwd?: string, use_git_branch?: boolean }
---@return continuity.SessionKey
function M.current(opts)
    opts = opts or {}
    local cwd = normalize_cwd(opts.cwd)
    local basename = vim.fs.basename(cwd) or 'workspace'
    local configured = config.get()
    local use_git_branch = configured.session_key.use_git_branch

    if type(opts.use_git_branch) == 'boolean' then
        use_git_branch = opts.use_git_branch
    end

    local branch = use_git_branch and git_branch(cwd) or nil
    local key_parts = { cwd }
    local label_parts = { basename }

    if branch ~= nil then
        table.insert(key_parts, branch)
        table.insert(label_parts, branch)
    end

    local digest = vim.fn.sha256(table.concat(key_parts, '\0')):sub(1, 12)
    local id_parts = { 'session', slug(basename) }

    if branch ~= nil then
        table.insert(id_parts, slug(branch))
    end

    table.insert(id_parts, digest)

    return {
        id = table.concat(id_parts, ':'),
        name = table.concat(label_parts, ' @ '),
        cwd = cwd,
        branch = branch,
    }
end

---@param opts? { cwd?: string, use_git_branch?: boolean }
---@return table<string, any>
function M.state(opts)
    local key = M.current(opts)

    return {
        id = key.id,
        cwd = key.cwd,
        branch = key.branch,
    }
end

return M
