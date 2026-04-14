local config = require('continuity.core.config')
local mksession = require('continuity.persistence.mksession')
local model = require('continuity.core.model')

local M = {}

local state = {
    next_id = 1,
    sessions = {},
}

---@return string
local function state_file()
    return config.get().state_file
end

local function persist()
    local path = state_file()

    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    vim.fn.writefile({
        vim.json.encode({
            next_id = state.next_id,
            sessions = vim.tbl_values(state.sessions),
        }),
    }, path)
end

---@return string
local function alloc_id()
    local id = string.format('session:%d', state.next_id)
    state.next_id = state.next_id + 1
    return id
end

---@return continuity.Record[]
local function sorted_sessions()
    ---@type continuity.Record[]
    local items = vim.tbl_values(state.sessions)

    table.sort(items, function(left, right)
        return left.id < right.id
    end)

    return items
end

---@param record continuity.Record
---@return continuity.Record
function M.save(record)
    local restored = model.new_record(vim.tbl_extend('force', vim.deepcopy(record), {
        updated_at = os.time(),
    }))
    state.sessions[restored.id] = restored
    persist()
    mksession.capture(restored.id)
    return vim.deepcopy(restored)
end

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any>, contributors?: table<string, any> }
---@return continuity.Record
function M.create(opts)
    return M.save(model.new_record(vim.tbl_extend('force', opts or {}, {
        id = alloc_id(),
    })))
end

---@param id string
---@return continuity.Record?
function M.get(id)
    local record = state.sessions[id]
    return record ~= nil and vim.deepcopy(record) or nil
end

---@return continuity.Record[]
function M.list()
    return vim.tbl_map(vim.deepcopy, sorted_sessions())
end

---@param id string
---@return continuity.Record?
function M.delete(id)
    local record = state.sessions[id]

    if record == nil then
        return nil
    end

    state.sessions[id] = nil
    persist()
    mksession.delete(id)
    return vim.deepcopy(record)
end

---@param opts? { wipe_storage?: boolean }
function M.clear(opts)
    state.next_id = 1
    state.sessions = {}

    if opts == nil or opts.wipe_storage ~= false then
        local path = state_file()
        if vim.fn.filereadable(path) == 1 then
            vim.fn.delete(path)
        end
        mksession.clear_all()
    end
end

---@return continuity.Record[]
function M.restore()
    local path = state_file()

    if vim.fn.filereadable(path) == 0 then
        M.clear({ wipe_storage = false })
        return {}
    end

    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))

    if not ok or type(decoded) ~= 'table' then
        M.clear({ wipe_storage = false })
        return {}
    end

    state.next_id = tonumber(decoded.next_id) or 1
    state.sessions = {}

    for _, item in ipairs(decoded.sessions or {}) do
        local restored = model.restore_record(item)

        if restored ~= nil then
            state.sessions[restored.id] = restored
        end
    end

    return M.list()
end

return M
