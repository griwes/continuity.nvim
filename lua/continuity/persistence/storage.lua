local config = require('continuity.core.config')
local mksession = require('continuity.persistence.mksession')
local model = require('continuity.core.model')
local session_key = require('continuity.core.session_key')

local M = {}

local state = {
    last_session_id = nil,
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
            last_session_id = state.last_session_id,
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
    state.last_session_id = restored.id
    persist()
    mksession.capture(restored.id)
    return vim.deepcopy(restored)
end

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any>, contributors?: table<string, any> }
---@return continuity.Record
function M.create(opts)
    local create_opts = vim.deepcopy(opts or {})

    if create_opts.id == nil and config.get().session_key.use_git_branch == true then
        local key = session_key.current({
            cwd = create_opts.cwd,
        })
        create_opts.id = key.id
        create_opts.name = type(create_opts.name) == 'string' and create_opts.name ~= '' and create_opts.name
            or key.name
        create_opts.cwd = key.cwd
        create_opts.state = vim.tbl_deep_extend('force', create_opts.state or {}, {
            continuity = {
                session_key = session_key.state({
                    cwd = key.cwd,
                }),
            },
        })
    end

    return M.save(model.new_record(vim.tbl_extend('force', create_opts, {
        id = create_opts.id or alloc_id(),
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

---@return string?
function M.last_session_id()
    return state.last_session_id
end

---@param id string
---@return continuity.Record?
function M.delete(id)
    local record = state.sessions[id]

    if record == nil then
        return nil
    end

    state.sessions[id] = nil
    if state.last_session_id == id then
        state.last_session_id = nil
    end
    persist()
    mksession.delete(id)
    return vim.deepcopy(record)
end

---@param opts? { wipe_storage?: boolean }
function M.clear(opts)
    state.last_session_id = nil
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

    state.last_session_id = type(decoded.last_session_id) == 'string' and decoded.last_session_id or nil
    state.next_id = tonumber(decoded.next_id) or 1
    state.sessions = {}

    for _, item in ipairs(decoded.sessions or {}) do
        local restored = model.restore_record(item)

        if restored ~= nil then
            state.sessions[restored.id] = restored
        end
    end

    if state.last_session_id ~= nil and state.sessions[state.last_session_id] == nil then
        state.last_session_id = nil
    end

    return M.list()
end

return M
