local config = require('continuity.core.config')
local session_key = require('continuity.core.session_key')

local M = {}

---@return continuity.MksessionConfig
local function session_config()
    return config.get().mksession
end

---@param value? string|string[]
---@return string?
local function normalize_sessionoptions(value)
    if type(value) == 'string' then
        return value
    end

    if type(value) ~= 'table' then
        return nil
    end

    local parts = {}

    for _, item in ipairs(value) do
        if type(item) == 'string' and item ~= '' then
            table.insert(parts, item)
        end
    end

    return table.concat(parts, ',')
end

---@param callback fun()
local function with_sessionoptions(callback)
    local configured = normalize_sessionoptions(session_config().sessionoptions)

    if configured == nil then
        callback()
        return
    end

    local original = vim.o.sessionoptions
    local ok, err = pcall(function()
        vim.o.sessionoptions = configured
        callback()
    end)
    vim.o.sessionoptions = original

    if not ok then
        error(err)
    end
end

---@param id string
---@return boolean
local function live_session(id)
    local continuous = config.get().continuous

    if continuous.enabled ~= true then
        return false
    end

    if continuous.session_id == 'auto' then
        return session_key.current().id == id
    end

    return continuous.session_id == id
end

---@param id string
---@return string
local function filename(id)
    return string.format('%s.vim', id:gsub('[^%w_.-]', '_'))
end

---@return boolean
function M.enabled()
    return session_config().enabled == true
end

---@param id string
---@return boolean
function M.should_capture(id)
    if not M.enabled() then
        return false
    end

    if live_session(id) and session_config().capture_live ~= true then
        return false
    end

    return true
end

---@param id string
---@return string
function M.path(id)
    return vim.fs.joinpath(session_config().dir, filename(id))
end

---@param id string
---@return boolean
function M.exists(id)
    return vim.fn.filereadable(M.path(id)) == 1
end

---@param id string
function M.capture(id)
    if not M.should_capture(id) then
        return
    end

    local path = M.path(id)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    with_sessionoptions(function()
        vim.cmd(string.format('silent! mksession! %s', vim.fn.fnameescape(path)))
    end)
end

---@param id string
---@return boolean
function M.load(id)
    if not M.enabled() or not M.exists(id) then
        return false
    end

    vim.cmd(string.format('silent source %s', vim.fn.fnameescape(M.path(id))))
    return true
end

---@param id string
function M.delete(id)
    local path = M.path(id)

    if vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
    end
end

function M.clear_all()
    local dir = session_config().dir

    if vim.fn.isdirectory(dir) == 1 then
        vim.fn.delete(dir, 'rf')
    end
end

return M
