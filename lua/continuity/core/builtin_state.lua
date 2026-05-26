local M = {}
local LAST_FILE_BUFFER_VAR = 'continuity_last_file_buffer'

---@class continuity.BufferState
---@field id integer
---@field name string
---@field listed boolean
---@field loaded boolean
---@field modified boolean
---@field buftype string
---@field filetype string
---@field changelist? { items: table[], index: integer }

---@class continuity.WindowState
---@field id integer
---@field buffer integer
---@field current boolean
---@field width integer
---@field height integer
---@field view table
---@field jumplist? { items: table[], index: integer }

---@class continuity.TabState
---@field id integer
---@field current boolean
---@field layout any
---@field windows continuity.WindowState[]

---@class continuity.NvimState
---@field cwd string
---@field current { buffer: integer, window: integer, tab: integer }
---@field buffers continuity.BufferState[]
---@field tabs continuity.TabState[]

---@param win integer
---@param callback fun(): any
---@return boolean, any
local function win_call(win, callback)
    if not vim.api.nvim_win_is_valid(win) then
        return false, nil
    end

    return pcall(vim.api.nvim_win_call, win, callback)
end

---@param win integer
---@return table
local function capture_view(win)
    local ok, view = win_call(win, vim.fn.winsaveview)
    return ok and type(view) == 'table' and view or {}
end

---@param win integer
---@return table?
local function capture_jumplist(win)
    local ok, value = pcall(vim.fn.getjumplist, win)

    if not ok or type(value) ~= 'table' then
        return nil
    end

    return {
        items = type(value[1]) == 'table' and value[1] or {},
        index = tonumber(value[2]) or 0,
    }
end

---@param bufnr integer
---@return boolean
local function is_file_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= '' then
        return false
    end

    local name = vim.api.nvim_buf_get_name(bufnr)
    return name ~= '' and vim.uv.fs_stat(name) ~= nil
end

---@param bufnr integer
---@return boolean
local function is_empty_anonymous_buffer(bufnr)
    return vim.api.nvim_buf_is_valid(bufnr)
        and vim.api.nvim_buf_get_name(bufnr) == ''
        and vim.bo[bufnr].buftype == ''
        and vim.bo[bufnr].modified == false
end

---@param win integer
---@param bufnr integer
---@return integer
local function resolve_window_buffer(win, bufnr)
    if is_file_buffer(bufnr) then
        pcall(vim.api.nvim_win_set_var, win, LAST_FILE_BUFFER_VAR, bufnr)
        return bufnr
    end

    if not is_empty_anonymous_buffer(bufnr) then
        return bufnr
    end

    local ok, previous = pcall(vim.api.nvim_win_get_var, win, LAST_FILE_BUFFER_VAR)
    previous = ok and tonumber(previous) or nil

    if previous ~= nil and is_file_buffer(previous) then
        return previous
    end

    return bufnr
end

---@param bufnr integer
---@return boolean
local function is_transient_buffer(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end

    return vim.b[bufnr].legate_surface_role ~= nil or vim.b[bufnr].continuity_transient_buffer == true
end

---@param win integer
---@return boolean
local function is_transient_window(win)
    if not vim.api.nvim_win_is_valid(win) then
        return false
    end

    local bufnr = vim.api.nvim_win_get_buf(win)

    return vim.w[win].legate_surface_role ~= nil
        or vim.w[win].continuity_transient_window == true
        or is_transient_buffer(bufnr)
end

---@param bufnr integer
---@return table?
local function capture_changelist(bufnr)
    local ok, value = pcall(vim.fn.getchangelist, bufnr)

    if not ok or type(value) ~= 'table' then
        return nil
    end

    return {
        items = type(value[1]) == 'table' and value[1] or {},
        index = tonumber(value[2]) or 0,
    }
end

---@param tab integer
---@return any
local function capture_layout(tab)
    local wins = vim.api.nvim_tabpage_list_wins(tab)
    local first = wins[1]

    if first == nil then
        return nil
    end

    local ok, layout = win_call(first, vim.fn.winlayout)
    return ok and layout or nil
end

---@param layout any
---@param out table<integer, boolean>
local function collect_layout_windows(layout, out)
    if type(layout) ~= 'table' then
        return
    end

    if layout[1] == 'leaf' then
        local win = tonumber(layout[2])

        if win ~= nil then
            out[win] = true
        end
        return
    end

    for _, child in ipairs(layout[2] or {}) do
        collect_layout_windows(child, out)
    end
end

---@param layout any
---@return any
local function prune_transient_layout(layout)
    if type(layout) ~= 'table' then
        return nil
    end

    if layout[1] == 'leaf' then
        local win = tonumber(layout[2])

        if win == nil or is_transient_window(win) then
            return nil
        end

        return layout
    end

    local children = {}

    for _, child in ipairs(layout[2] or {}) do
        local pruned = prune_transient_layout(child)

        if pruned ~= nil then
            table.insert(children, pruned)
        end
    end

    if #children == 0 then
        return nil
    end

    if #children == 1 then
        return children[1]
    end

    return {
        layout[1],
        children,
    }
end

---@param tabs continuity.TabState[]
---@return table<integer, boolean>
local function visible_layout_buffers(tabs)
    local result = {}

    for _, tab in ipairs(tabs) do
        for _, window in ipairs(tab.windows or {}) do
            result[window.buffer] = true
        end
    end

    return result
end

---@param visible_buffers table<integer, boolean>
---@return continuity.BufferState[]
local function capture_buffers(visible_buffers)
    local buffers = {}

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) then
            local name = vim.api.nvim_buf_get_name(buffer)
            local listed = vim.bo[buffer].buflisted
            local buftype = vim.bo[buffer].buftype
            local visible = visible_buffers[buffer] == true
            local path_backed_file = buftype == '' and name ~= '' and vim.uv.fs_stat(name) ~= nil
            local named_or_special = name ~= '' or buftype ~= ''

            if not is_transient_buffer(buffer) and (visible or path_backed_file or (listed and named_or_special)) then
                table.insert(buffers, {
                    id = buffer,
                    name = name,
                    listed = listed,
                    loaded = vim.api.nvim_buf_is_loaded(buffer),
                    modified = vim.bo[buffer].modified,
                    buftype = buftype,
                    filetype = vim.bo[buffer].filetype,
                    changelist = capture_changelist(buffer),
                })
            end
        end
    end

    table.sort(buffers, function(left, right)
        return left.id < right.id
    end)

    return buffers
end

---@return continuity.TabState[]
local function capture_tabs()
    local tabs = {}
    local current_window = vim.api.nvim_get_current_win()
    local current_tab = vim.api.nvim_get_current_tabpage()

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local windows = {}
        local layout = prune_transient_layout(capture_layout(tab))
        local layout_windows = {}

        collect_layout_windows(layout, layout_windows)

        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            if layout_windows[window] == true and not is_transient_window(window) then
                local buffer = resolve_window_buffer(window, vim.api.nvim_win_get_buf(window))

                table.insert(windows, {
                    id = window,
                    buffer = buffer,
                    current = window == current_window,
                    width = vim.api.nvim_win_get_width(window),
                    height = vim.api.nvim_win_get_height(window),
                    view = capture_view(window),
                    jumplist = capture_jumplist(window),
                })
            end
        end

        table.insert(tabs, {
            id = tab,
            current = tab == current_tab,
            layout = layout,
            windows = windows,
        })
    end

    return tabs
end

---@return continuity.NvimState
function M.capture()
    local tabs = capture_tabs()
    local current_window = vim.api.nvim_get_current_win()
    local current_tab = vim.api.nvim_get_current_tabpage()
    local current_buffer = vim.api.nvim_get_current_buf()

    if is_transient_window(current_window) then
        for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
            if not is_transient_window(winid) then
                current_window = winid
                current_buffer = vim.api.nvim_win_get_buf(winid)
                break
            end
        end
    end

    return {
        cwd = vim.uv.cwd() or vim.fn.getcwd(),
        current = {
            buffer = current_buffer,
            window = current_window,
            tab = current_tab,
        },
        buffers = capture_buffers(visible_layout_buffers(tabs)),
        tabs = tabs,
    }
end

return M
