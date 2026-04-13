local M = {}

local contributors = {}

---@param name string
---@param contributor session.Contributor
function M.register(name, contributor)
    assert(type(name) == 'string' and name ~= '', 'Session contributor name must be a non-empty string')
    assert(type(contributor) == 'table', 'Session contributor must be a table')

    contributors[name] = contributor
end

---@param name string
---@return session.Contributor?
function M.get(name)
    return contributors[name]
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

return M
