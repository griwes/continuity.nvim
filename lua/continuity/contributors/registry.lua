local M = {}

local contributors = {}

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
    return contributors[name]
end

---@return string[]
function M.names()
    local names = vim.tbl_keys(contributors)
    table.sort(names)
    return names
end

---@param name string
---@return boolean, any
function M.capture_one(name)
    local contributor = contributors[name]

    assert(contributor ~= nil, string.format('Unknown session contributor: %s', name))
    assert(
        type(contributor.capture) == 'function',
        string.format('Session contributor %s does not expose capture()', name)
    )

    local ok, value = xpcall(contributor.capture, debug.traceback)

    if not ok then
        pcall(
            vim.notify,
            string.format('Continuity contributor %s capture failed: %s', name, value),
            vim.log.levels.ERROR
        )
        return false, nil
    end

    return true, value
end

---@param previous? table<string, any>
---@return table<string, any>
function M.capture(previous)
    local captured = vim.deepcopy(previous or {})

    for _, name in ipairs(M.names()) do
        local contributor = contributors[name]

        if type(contributor.capture) == 'function' then
            local ok, value = M.capture_one(name)

            if ok and value ~= nil then
                captured[name] = vim.deepcopy(value)
            elseif ok then
                captured[name] = nil
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
    return vim.deepcopy(captured or {})
end

return M
