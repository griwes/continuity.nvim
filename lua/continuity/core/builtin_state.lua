local M = {}

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

---@return continuity.BufferState[]
local function capture_buffers()
    local buffers = {}

    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buffer) then
            table.insert(buffers, {
                id = buffer,
                name = vim.api.nvim_buf_get_name(buffer),
                listed = vim.api.nvim_get_option_value('buflisted', {
                    buf = buffer,
                }),
                loaded = vim.api.nvim_buf_is_loaded(buffer),
                modified = vim.api.nvim_get_option_value('modified', {
                    buf = buffer,
                }),
                buftype = vim.api.nvim_get_option_value('buftype', {
                    buf = buffer,
                }),
                filetype = vim.api.nvim_get_option_value('filetype', {
                    buf = buffer,
                }),
                changelist = capture_changelist(buffer),
            })
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

        for _, window in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            table.insert(windows, {
                id = window,
                buffer = vim.api.nvim_win_get_buf(window),
                current = window == current_window,
                width = vim.api.nvim_win_get_width(window),
                height = vim.api.nvim_win_get_height(window),
                view = capture_view(window),
                jumplist = capture_jumplist(window),
            })
        end

        table.insert(tabs, {
            id = tab,
            current = tab == current_tab,
            layout = capture_layout(tab),
            windows = windows,
        })
    end

    return tabs
end

---@return continuity.NvimState
function M.capture()
    return {
        cwd = vim.uv.cwd() or vim.fn.getcwd(),
        current = {
            buffer = vim.api.nvim_get_current_buf(),
            window = vim.api.nvim_get_current_win(),
            tab = vim.api.nvim_get_current_tabpage(),
        },
        buffers = capture_buffers(),
        tabs = capture_tabs(),
    }
end

return M
