local config = require('continuity.core.config')
local builtin_state = require('continuity.core.builtin_state')
local contributors = require('continuity.contributors.registry')
local model = require('continuity.core.model')
local session_key = require('continuity.core.session_key')
local storage = require('continuity.persistence.storage')

local M = {}

local state = {
    group_id = nil,
    record = nil,
    timer = nil,
    suspend_count = 0,
}

local refresh_builtin_state
local refresh_contributor

---@return continuity.ContinuousConfig
local function live_config()
    return config.get().continuous
end

---@return boolean
local function enabled()
    return live_config().enabled == true
end

---@return boolean
local function suspended()
    return state.suspend_count > 0
end

---@return string
local function live_session_id()
    local session_id = live_config().session_id

    if session_id == 'auto' then
        return session_key.current().id
    end

    return session_id
end

---@return boolean
local function uses_auto_session_id()
    return live_config().session_id == 'auto'
end

---@param record continuity.Record
local function apply_auto_session_key_state(record)
    if not uses_auto_session_id() then
        return
    end

    record.state.continuity = record.state.continuity or {}
    record.state.continuity.session_key = session_key.state({
        cwd = record.cwd,
    })
end

local function stop_timer()
    if state.timer ~= nil then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
    end
end

---@return continuity.Record
local function ensure_record()
    local session_id = live_session_id()

    if state.record ~= nil and state.record.id ~= session_id then
        state.record = nil
    end

    if state.record ~= nil then
        return state.record
    end

    local existing = storage.get(session_id)

    state.record = existing
        or model.new_record({
            id = session_id,
            name = 'Live Session',
            cwd = vim.fn.getcwd(),
        })

    apply_auto_session_key_state(state.record)

    return state.record
end

local function persist_now()
    if not enabled() or suspended() or state.record == nil then
        return
    end

    storage.save(state.record)
end

local function refresh_contributors()
    for _, name in ipairs(contributors.names()) do
        local contributor = contributors.get(name)

        if contributor ~= nil and type(contributor.capture) == 'function' then
            refresh_contributor(name)
        end
    end
end

local function refresh_all_state()
    refresh_builtin_state()
    refresh_contributors()
end

local function flush_now()
    if not enabled() or suspended() then
        return
    end

    refresh_all_state()
    stop_timer()
    persist_now()
end

local function schedule_persist()
    if not enabled() or suspended() then
        return
    end

    local debounce_ms = math.max(tonumber(live_config().write_debounce_ms) or 0, 0)

    stop_timer()

    if debounce_ms == 0 then
        persist_now()
        return
    end

    state.timer = assert(vim.uv.new_timer())
    state.timer:start(
        debounce_ms,
        0,
        vim.schedule_wrap(function()
            stop_timer()
            persist_now()
        end)
    )
end

local function update_record(mutator)
    local record = ensure_record()
    mutator(record)
    state.record = model.new_record({
        id = record.id,
        name = record.name,
        cwd = record.cwd,
        state = record.state,
        contributors = record.contributors,
        created_at = record.created_at,
        updated_at = os.time(),
    })
end

refresh_builtin_state = function()
    update_record(function(record)
        record.cwd = vim.uv.cwd() or vim.fn.getcwd()
        apply_auto_session_key_state(record)
        record.state.nvim = builtin_state.capture()
    end)
end

refresh_contributor = function(name)
    local contributor = contributors.get(name)

    assert(contributor ~= nil, string.format('Unknown session contributor: %s', name))
    assert(
        type(contributor.capture) == 'function',
        string.format('Session contributor %s does not expose capture()', name)
    )

    local value = contributor.capture()

    update_record(function(record)
        if value == nil then
            record.contributors[name] = nil
        else
            record.contributors[name] = vim.deepcopy(value)
        end
    end)
end

---@return continuity.Record?
function M.record()
    if state.record == nil then
        return nil
    end

    return vim.deepcopy(state.record)
end

function M.refresh_all()
    if not enabled() or suspended() then
        return
    end

    refresh_all_state()
    schedule_persist()
end

---@param name string
function M.notify_contributor_changed(name)
    if not enabled() or suspended() then
        return
    end

    refresh_contributor(name)
    schedule_persist()
end

---@generic T
---@param callback fun(): T
---@param opts? { refresh_after?: boolean }
---@return T
function M.with_suspended(callback, opts)
    state.suspend_count = state.suspend_count + 1

    local ok, result = pcall(callback)

    state.suspend_count = math.max(state.suspend_count - 1, 0)

    if opts ~= nil and opts.refresh_after == true and enabled() then
        refresh_all_state()
        schedule_persist()
    end

    if not ok then
        error(result)
    end

    return result
end

local function register_autocmds()
    if state.group_id ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, state.group_id)
    end

    state.group_id = vim.api.nvim_create_augroup('continuity.nvim.live', {
        clear = true,
    })

    vim.api.nvim_create_autocmd({
        'BufAdd',
        'BufDelete',
        'BufEnter',
        'BufFilePost',
        'BufWinEnter',
        'BufWritePost',
        'DirChanged',
        'TabClosed',
        'TabEnter',
        'TabNewEntered',
        'WinClosed',
        'WinEnter',
        'WinResized',
    }, {
        group = state.group_id,
        callback = function()
            refresh_all_state()
            schedule_persist()
        end,
    })

    vim.api.nvim_create_autocmd({
        'TextChanged',
        'TextChangedI',
        'TextChangedP',
    }, {
        group = state.group_id,
        callback = function()
            refresh_builtin_state()
            schedule_persist()
        end,
    })

    vim.api.nvim_create_autocmd('VimLeavePre', {
        group = state.group_id,
        callback = flush_now,
    })

    vim.api.nvim_create_autocmd('OptionSet', {
        group = state.group_id,
        pattern = 'modified',
        callback = function()
            refresh_builtin_state()
            schedule_persist()
        end,
    })
end

function M.start()
    if not enabled() then
        M.stop()
        return
    end

    refresh_builtin_state()
    register_autocmds()

    refresh_contributors()

    schedule_persist()
end

function M.stop()
    stop_timer()

    if state.group_id ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, state.group_id)
        state.group_id = nil
    end

    state.record = nil
end

---@param opts? { wipe_storage?: boolean }
function M.clear(opts)
    M.stop()
    state.record = nil

    if enabled() and (opts == nil or opts.wipe_storage ~= false) then
        storage.delete(live_session_id())
    end
end

return M
