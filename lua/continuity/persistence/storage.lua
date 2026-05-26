local config = require('continuity.core.config')
local model = require('continuity.core.model')
local atomic = require('continuity.persistence.atomic')
local session_key = require('continuity.core.session_key')

local M = {}

local state = {
    last_session_id = nil,
    next_id = 1,
    sessions = {},
}
local CURRENT_VERSION = 1

local sorted_sessions

---@return string
local function state_file()
    return config.get().state_file
end

---@return string
local function state_dir()
    local configured = config.get().state_dir
    if type(configured) == 'string' and configured ~= '' then
        return configured
    end

    return string.format('%s.d', state_file())
end

---@param value string
---@return string
local function encode_path_component(value)
    return value:gsub('[^%w._-]', function(char)
        return string.format('%%%02X', char:byte())
    end)
end

---@param id string
---@return string
local function session_filename(id)
    return string.format('%s.json', encode_path_component(id))
end

---@param id string
---@return string
local function session_path(id)
    return vim.fs.joinpath(state_dir(), session_filename(id))
end

---@param path string
---@return table?
local function read_json(path)
    if vim.fn.filereadable(path) == 0 then
        return nil
    end

    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), '\n'))
    if not ok or type(decoded) ~= 'table' then
        return nil
    end

    return decoded
end

---@param record continuity.Record
---@return table
local function index_entry(record)
    return {
        id = record.id,
        name = record.name,
        cwd = record.cwd,
        created_at = record.created_at,
        updated_at = record.updated_at,
        file = session_filename(record.id),
    }
end

---@param id string
---@return boolean
local function is_clean_snapshot_id(id)
    return id:sub(-7) == '::clean'
end

---@param id string
---@return string
local function clean_snapshot_base_id(id)
    if is_clean_snapshot_id(id) then
        return id:sub(1, -8)
    end

    return id
end

---@param id string
---@return string
local function clean_snapshot_id(id)
    return string.format('%s::clean', clean_snapshot_base_id(id))
end

local function persist_index()
    atomic.write_json(state_file(), {
        version = CURRENT_VERSION,
        last_session_id = state.last_session_id,
        next_id = state.next_id,
        sessions = vim.tbl_map(index_entry, sorted_sessions()),
    })
end

---@param record continuity.Record
local function persist_record(record)
    atomic.write_json(session_path(record.id), record)
end

local function persist()
    for _, record in ipairs(sorted_sessions()) do
        persist_record(record)
    end

    persist_index()
end

---@return string
local function alloc_id()
    local id = string.format('session:%d', state.next_id)
    state.next_id = state.next_id + 1
    return id
end

---@return continuity.Record[]
function sorted_sessions()
    ---@type continuity.Record[]
    local items = vim.tbl_values(state.sessions)

    table.sort(items, function(left, right)
        return left.id < right.id
    end)

    return items
end

---@param record continuity.Record
---@param opts? { update_last?: boolean }
---@return continuity.Record
function M.save(record, opts)
    local restored = model.new_record(vim.tbl_extend('force', vim.deepcopy(record), {
        updated_at = os.time(),
    }))
    state.sessions[restored.id] = restored
    if opts == nil or opts.update_last ~= false then
        state.last_session_id = restored.id
    end
    persist()
    return vim.deepcopy(restored)
end

---@param record continuity.Record
---@return continuity.Record
function M.save_clean_snapshot(record)
    local base_id = clean_snapshot_base_id(record.id)
    local snapshot = model.new_record(vim.tbl_extend('force', vim.deepcopy(record), {
        id = clean_snapshot_id(base_id),
        name = string.format('%s clean snapshot', record.name),
    }))

    snapshot.state.continuity = snapshot.state.continuity or {}
    snapshot.state.continuity.snapshot = {
        kind = 'clean',
        base_id = base_id,
    }

    return M.save(snapshot)
end

---@param id string
---@return string
function M.clean_snapshot_id(id)
    return clean_snapshot_id(id)
end

---@param id string
---@return string?
function M.clean_snapshot_base_id(id)
    if not is_clean_snapshot_id(id) then
        return nil
    end

    return clean_snapshot_base_id(id)
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
    if not is_clean_snapshot_id(id) then
        state.sessions[clean_snapshot_id(id)] = nil
    end
    if
        state.last_session_id == id or (not is_clean_snapshot_id(id) and state.last_session_id == clean_snapshot_id(id))
    then
        state.last_session_id = nil
    end

    local path = session_path(id)
    if vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
    end
    if not is_clean_snapshot_id(id) then
        local clean_path = session_path(clean_snapshot_id(id))
        if vim.fn.filereadable(clean_path) == 1 then
            vim.fn.delete(clean_path)
        end
    end

    persist()
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

        local dir = state_dir()
        if dir ~= '' and dir ~= '/' and vim.fn.isdirectory(dir) == 1 then
            vim.fn.delete(dir, 'rf')
        end
    end
end

---@param entry table
---@return continuity.Record?
local function restore_fragment(entry)
    if type(entry) ~= 'table' or type(entry.id) ~= 'string' or entry.id == '' then
        return nil
    end

    local filename = type(entry.file) == 'string' and entry.file or session_filename(entry.id)
    local decoded = read_json(vim.fs.joinpath(state_dir(), filename))
    if decoded == nil then
        return nil
    end

    return model.restore_record(decoded)
end

---@return continuity.Record[]
function M.restore()
    local path = state_file()

    if vim.fn.filereadable(path) == 0 then
        M.clear({ wipe_storage = false })
        return {}
    end

    local decoded = read_json(path)

    if decoded == nil then
        M.clear({ wipe_storage = false })
        return {}
    end

    state.last_session_id = type(decoded.last_session_id) == 'string' and decoded.last_session_id or nil
    state.next_id = tonumber(decoded.next_id) or 1
    state.sessions = {}

    if decoded.version == CURRENT_VERSION then
        for _, item in ipairs(decoded.sessions or {}) do
            local restored = restore_fragment(item)
            if restored ~= nil then
                state.sessions[restored.id] = restored
            end
        end
    end

    if state.last_session_id ~= nil and state.sessions[state.last_session_id] == nil then
        state.last_session_id = nil
    end

    return M.list()
end

return M
