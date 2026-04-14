local M = {}

local contributors = {}
local aliases = {
    terminal_manager = 'terminalia',
    git_worktree = 'arboretum',
    remote_workspace = 'consulate',
    devcontainer = 'laboratory',
}

---@param name string
---@return string
local function canonical_name(name)
    local alias = aliases[name]

    if alias ~= nil and contributors[alias] ~= nil then
        return alias
    end

    return name
end

---@param name string
---@param contributor continuity.Contributor
function M.register(name, contributor)
    assert(type(name) == 'string' and name ~= '', 'Session contributor name must be a non-empty string')
    assert(type(contributor) == 'table', 'Session contributor must be a table')

    contributors[name] = contributor
end

---@param name string
---@return continuity.Contributor?
function M.get(name)
    return contributors[canonical_name(name)]
end

---@return string[]
function M.names()
    local names = vim.tbl_keys(contributors)
    table.sort(names)
    return names
end

---@return table<string, any>
function M.capture()
    local captured = {}

    for _, name in ipairs(M.names()) do
        local contributor = contributors[name]

        if type(contributor.capture) == 'function' then
            local value = contributor.capture()

            if value ~= nil then
                captured[name] = vim.deepcopy(value)
            end
        end
    end

    return captured
end

function M.clear()
    contributors = {}
end

---@param captured? table<string, any>
---@return table<string, any>
function M.normalize_captured(captured)
    local normalized = {}

    for name, value in pairs(captured or {}) do
        local canonical = canonical_name(name)

        if normalized[canonical] == nil or canonical == name then
            normalized[canonical] = value
        end
    end

    return normalized
end

return M
