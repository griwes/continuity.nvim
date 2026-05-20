local shada = require('continuity.persistence.shada')

local M = {}

---@class continuity.LayoutRestoreReport
---@field restored boolean
---@field windows table<integer, integer>
---@field buffers table<integer, integer>

---@param name string?
---@return string?
local function normalize_name(name)
    if type(name) ~= 'string' or name == '' then
        return nil
    end

    return vim.fs.normalize(name)
end

---@param bufnr? integer
---@return integer
local function open_tabpage(bufnr)
    return vim.api.nvim_open_tabpage(bufnr or 0, true, {})
end

local function close_other_tabpages()
    local current = vim.api.nvim_get_current_tabpage()

    for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
        if tabpage ~= current and vim.api.nvim_tabpage_is_valid(tabpage) then
            pcall(vim.api.nvim_win_close, vim.api.nvim_tabpage_get_win(tabpage), true)
        end
    end

    if vim.api.nvim_tabpage_is_valid(current) then
        pcall(vim.api.nvim_set_current_tabpage, current)
    end
end

---@param record continuity.Record
---@return table<integer, continuity.BufferState>
local function buffers_by_saved_id(record)
    local result = {}
    local buffers = record.state ~= nil and record.state.nvim ~= nil and record.state.nvim.buffers or {}

    for _, buffer in ipairs(buffers) do
        local id = tonumber(buffer.id)

        if id ~= nil then
            result[id] = buffer
        end
    end

    return result
end

---@param name string
---@return integer?
local function find_buffer_by_name(name)
    local normalized = normalize_name(name)

    if normalized == nil then
        return nil
    end

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and normalize_name(vim.api.nvim_buf_get_name(bufnr)) == normalized then
            return bufnr
        end
    end

    return nil
end

---@param buffer continuity.BufferState?
---@return integer
local function ensure_buffer(buffer)
    if buffer == nil then
        return vim.api.nvim_create_buf(true, false)
    end

    local name = normalize_name(buffer.name)
    local existing = name ~= nil and find_buffer_by_name(name) or nil

    if existing ~= nil then
        return existing
    end

    if name ~= nil and buffer.buftype == '' and vim.uv.fs_stat(name) ~= nil then
        local bufnr = vim.fn.bufadd(name)
        pcall(vim.fn.bufload, bufnr)
        pcall(function()
            vim.bo[bufnr].buflisted = buffer.listed ~= false
        end)
        return bufnr
    end

    local listed = buffer.listed ~= false
    local scratch = buffer.buftype ~= ''
    local bufnr = vim.api.nvim_create_buf(listed, scratch)

    if type(buffer.name) == 'string' and buffer.name ~= '' then
        pcall(vim.api.nvim_buf_set_name, bufnr, buffer.name)
    end

    if type(buffer.buftype) == 'string' and buffer.buftype ~= '' then
        pcall(function()
            vim.bo[bufnr].buftype = buffer.buftype
        end)
    end

    if type(buffer.filetype) == 'string' and buffer.filetype ~= '' then
        pcall(function()
            vim.bo[bufnr].filetype = buffer.filetype
        end)
    end

    return bufnr
end

---@param layout any
---@param out integer[]
local function flatten_layout_windows(layout, out)
    if type(layout) ~= 'table' then
        return
    end

    if layout[1] == 'leaf' then
        local win = tonumber(layout[2])

        if win ~= nil then
            table.insert(out, win)
        end
        return
    end

    for _, child in ipairs(layout[2] or {}) do
        flatten_layout_windows(child, out)
    end
end

---@param tabpage integer
---@return any?
local function current_layout(tabpage)
    local wins = vim.api.nvim_tabpage_list_wins(tabpage)
    local first = wins[1]

    if first == nil or not vim.api.nvim_win_is_valid(first) then
        return nil
    end

    local ok, layout = pcall(vim.api.nvim_win_call, first, vim.fn.winlayout)
    return ok and layout or nil
end

---@param tab continuity.TabState
---@return integer[]
local function window_order(tab)
    local order = {}
    flatten_layout_windows(tab.layout, order)

    if #order > 0 then
        return order
    end

    for _, win in ipairs(tab.windows or {}) do
        table.insert(order, tonumber(win.id))
    end

    return order
end

---@param tab continuity.TabState
---@return table<integer, continuity.WindowState>
local function windows_by_saved_id(tab)
    local result = {}

    for _, win in ipairs(tab.windows or {}) do
        local id = tonumber(win.id)

        if id ~= nil then
            result[id] = win
        end
    end

    return result
end

---@param win integer
---@param saved_win continuity.WindowState?
---@param buffers table<integer, continuity.BufferState>
---@param report continuity.LayoutRestoreReport
local function assign_window(win, saved_win, buffers, report)
    if saved_win == nil or not vim.api.nvim_win_is_valid(win) then
        return
    end

    local saved_buffer_id = tonumber(saved_win.buffer)
    local bufnr = saved_buffer_id ~= nil and report.buffers[saved_buffer_id] or nil
    bufnr = bufnr or ensure_buffer(saved_buffer_id ~= nil and buffers[saved_buffer_id] or nil)

    report.windows[tonumber(saved_win.id) or win] = win
    if saved_buffer_id ~= nil then
        report.buffers[saved_buffer_id] = bufnr
    end

    pcall(vim.api.nvim_win_set_buf, win, bufnr)

    if type(saved_win.view) == 'table' then
        pcall(vim.api.nvim_win_call, win, function()
            pcall(vim.fn.winrestview, saved_win.view)
        end)
    end
end

---@param axis '"row"'|'"col"'
---@return string
local function split_command(axis)
    if axis == 'row' then
        return 'belowright vsplit'
    end

    return 'belowright split'
end

---@param layout any
---@param saved_windows table<integer, continuity.WindowState>
---@param buffers table<integer, continuity.BufferState>
---@param report continuity.LayoutRestoreReport
---@return integer?
local function restore_node(layout, saved_windows, buffers, report)
    if type(layout) ~= 'table' then
        return nil
    end

    if layout[1] == 'leaf' then
        local saved_id = tonumber(layout[2])
        local win = vim.api.nvim_get_current_win()
        assign_window(win, saved_id ~= nil and saved_windows[saved_id] or nil, buffers, report)
        return win
    end

    local axis = layout[1]
    local children = type(layout[2]) == 'table' and layout[2] or {}
    local child_windows = {
        vim.api.nvim_get_current_win(),
    }

    for _ = 2, #children do
        vim.api.nvim_set_current_win(child_windows[#child_windows])
        vim.cmd(split_command(axis))
        table.insert(child_windows, vim.api.nvim_get_current_win())
    end

    for index, child in ipairs(children) do
        vim.api.nvim_set_current_win(child_windows[index])
        local child_win = restore_node(child, saved_windows, buffers, report)
        child_windows[index] = child_win or child_windows[index]
    end

    return child_windows[1]
end

---@param buffers table<integer, continuity.BufferState>
---@param report continuity.LayoutRestoreReport
local function ensure_saved_buffers(buffers, report)
    for saved_id, buffer in pairs(buffers) do
        report.buffers[saved_id] = ensure_buffer(buffer)
    end
end

---@param tab continuity.TabState
---@param buffers table<integer, continuity.BufferState>
---@param report continuity.LayoutRestoreReport
local function restore_tab(tab, buffers, report)
    local saved_windows = windows_by_saved_id(tab)

    if type(tab.layout) == 'table' then
        restore_node(tab.layout, saved_windows, buffers, report)
    else
        local order = window_order(tab)

        for index, saved_id in ipairs(order) do
            if index > 1 then
                vim.cmd('belowright split')
            end
            assign_window(vim.api.nvim_get_current_win(), saved_windows[saved_id], buffers, report)
        end
    end
end

---@param tab continuity.TabState
---@param report continuity.LayoutRestoreReport
local function restore_tab_window_sizes(tab, report)
    for _, saved_win in ipairs(tab.windows or {}) do
        local saved_id = tonumber(saved_win.id)
        local win = saved_id ~= nil and report.windows[saved_id] or nil

        if win ~= nil and vim.api.nvim_win_is_valid(win) then
            if tonumber(saved_win.width) ~= nil and saved_win.width > 0 then
                pcall(vim.api.nvim_win_set_width, win, saved_win.width)
            end
            if tonumber(saved_win.height) ~= nil and saved_win.height > 0 then
                pcall(vim.api.nvim_win_set_height, win, saved_win.height)
            end
        end
    end
end

---@param saved_win continuity.WindowState
---@param buffers table<integer, continuity.BufferState>
---@param report continuity.LayoutRestoreReport
local function restore_jumps(saved_win, buffers, report)
    local saved_id = tonumber(saved_win.id)
    local win = saved_id ~= nil and report.windows[saved_id] or nil

    if win == nil or not vim.api.nvim_win_is_valid(win) then
        return
    end

    local saved_buffer_id = tonumber(saved_win.buffer)
    local saved_buffer = saved_buffer_id ~= nil and buffers[saved_buffer_id] or nil
    local fallback = saved_buffer ~= nil and saved_buffer.name or nil
    local items = saved_win.jumplist ~= nil and saved_win.jumplist.items or nil

    if type(items) ~= 'table' or vim.tbl_isempty(items) then
        return
    end

    pcall(vim.api.nvim_win_call, win, function()
        pcall(vim.cmd.clearjumps)
        shada.restore_jumps(items, fallback)
    end)
end

---@param buffer continuity.BufferState
local function restore_changes(buffer)
    if type(buffer.name) ~= 'string' or buffer.name == '' then
        return
    end

    local items = buffer.changelist ~= nil and buffer.changelist.items or nil

    if type(items) ~= 'table' or vim.tbl_isempty(items) then
        return
    end

    shada.restore_changes(items, buffer.name)
end

---@param nvim_state continuity.NvimState?
---@return boolean
local function has_tabs(nvim_state)
    return type(nvim_state) == 'table' and type(nvim_state.tabs) == 'table' and nvim_state.tabs[1] ~= nil
end

---@param record continuity.Record
---@return continuity.LayoutRestoreReport
function M.restore(record)
    local nvim_state = record.state ~= nil and record.state.nvim or nil
    local report = {
        restored = false,
        windows = {},
        buffers = {},
    }

    if not has_tabs(nvim_state) then
        return report
    end

    local buffers = buffers_by_saved_id(record)
    local tabs = nvim_state.tabs

    close_other_tabpages()
    vim.cmd('silent! only!')
    ensure_saved_buffers(buffers, report)

    for index, tab in ipairs(tabs) do
        if index > 1 then
            open_tabpage()
        end

        restore_tab(tab, buffers, report)
        restore_tab_window_sizes(tab, report)
    end

    for _, tab in ipairs(tabs) do
        for _, saved_win in ipairs(tab.windows or {}) do
            restore_jumps(saved_win, buffers, report)
        end
    end

    for _, buffer in pairs(buffers) do
        restore_changes(buffer)
    end

    for index, tab in ipairs(tabs) do
        if tab.current == true then
            pcall(vim.api.nvim_set_current_tabpage, vim.api.nvim_list_tabpages()[index])
            break
        end
    end

    local found_current_win = false
    for _, tab in ipairs(tabs) do
        for _, saved_win in ipairs(tab.windows or {}) do
            if saved_win.current == true then
                local saved_id = tonumber(saved_win.id)
                local win = saved_id ~= nil and report.windows[saved_id] or nil
                if win ~= nil and vim.api.nvim_win_is_valid(win) then
                    pcall(vim.api.nvim_set_current_win, win)
                end
                found_current_win = true
                break
            end
        end
        if found_current_win then
            break
        end
    end

    report.restored = true
    return report
end

---@param record continuity.Record
---@return continuity.LayoutRestoreReport
function M.rebind_buffers(record)
    local nvim_state = record.state ~= nil and record.state.nvim or nil
    local report = {
        restored = false,
        windows = {},
        buffers = {},
    }

    if not has_tabs(nvim_state) then
        return report
    end

    local buffers = buffers_by_saved_id(record)
    local tabpages = vim.api.nvim_list_tabpages()

    for index, tab in ipairs(nvim_state.tabs or {}) do
        local tabpage = tabpages[index]

        if tabpage ~= nil and vim.api.nvim_tabpage_is_valid(tabpage) then
            local saved_order = window_order(tab)
            local actual_order = {}

            flatten_layout_windows(current_layout(tabpage), actual_order)

            if #saved_order == #actual_order then
                local saved_windows = windows_by_saved_id(tab)

                for order_index, saved_id in ipairs(saved_order) do
                    assign_window(actual_order[order_index], saved_windows[saved_id], buffers, report)
                end
            end
        end
    end

    report.restored = true
    return report
end

return M
