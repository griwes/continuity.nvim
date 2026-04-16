local config = require('continuity.core.config')
local contributors = require('continuity.contributors.registry')
local model = require('continuity.core.model')
local storage = require('continuity.persistence.storage')

local M = {}

local state = {
    group_id = nil,
    record = nil,
    timer = nil,
}

---@return continuity.ContinuousConfig
local function live_config()
    return config.get().continuous
end

---@return boolean
local function enabled()
    return live_config().enabled == true
end

local function stop_timer()
    if state.timer ~= nil then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
    end
end

---@return table
local function builtin_state()
    local buffers = {}
    local current_buffer = vim.api.nvim_get_current_buf()
    local current_window = vim.api.nvim_get_current_win()
    local current_tab = vim.api.nvim_get_current_tabpage()

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        table.insert(buffers, {
            id = buffer,
            name = vim.api.nvim_buf_get_name(buffer),
            listed = vim.fn.buflisted(buffer) == 1,
            loaded = vim.api.nvim_buf_is_loaded(buffer),
            modified = vim.bo[buffer].modified,
            buftype = vim.bo[buffer].buftype,
        })
    end

    table.sort(buffers, function(left, right)
        return left.id < right.id
    end)

    local tabs = {}

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local windows = {}

        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            table.insert(windows, {
                id = window,
                buffer = vim.api.nvim_win_get_buf(window),
                current = window == current_window,
            })
        end

        table.insert(tabs, {
            id = tab,
            current = tab == current_tab,
            windows = windows,
        })
    end

    return {
        cwd = vim.fn.getcwd(),
        current = {
            buffer = current_buffer,
            window = current_window,
            tab = current_tab,
        },
        buffers = buffers,
        tabs = tabs,
    }
end

---@return continuity.Record
local function ensure_record()
    local session_id = live_config().session_id

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

    return state.record
end

local function persist_now()
    if not enabled() or state.record == nil then
        return
    end

    storage.save(state.record)
end

local function schedule_persist()
    if not enabled() then
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

local function refresh_builtin_state()
    update_record(function(record)
        record.cwd = vim.fn.getcwd()
        record.state.nvim = builtin_state()
    end)
end

local function refresh_contributor(name)
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
    refresh_builtin_state()

    for _, name in ipairs(contributors.names()) do
        local contributor = contributors.get(name)

        if contributor ~= nil and type(contributor.capture) == 'function' then
            refresh_contributor(name)
        end
    end

    schedule_persist()
end

---@param name string
function M.notify_contributor_changed(name)
    refresh_contributor(name)
    schedule_persist()
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
        'BufModifiedSet',
        'DirChanged',
        'TabClosed',
        'TabEnter',
        'TabNewEntered',
        'VimLeavePre',
        'WinClosed',
        'WinEnter',
    }, {
        group = state.group_id,
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

    for _, name in ipairs(contributors.names()) do
        local contributor = contributors.get(name)

        if contributor ~= nil and type(contributor.capture) == 'function' then
            refresh_contributor(name)
        end
    end

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
        storage.delete(live_config().session_id)
    end
end

return M
