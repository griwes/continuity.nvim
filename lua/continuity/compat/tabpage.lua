local M = {}

---@param bufnr? integer
---@return integer
function M.open(bufnr)
    if type(vim.api.nvim_open_tabpage) == 'function' then
        return vim.api.nvim_open_tabpage(bufnr or 0, true, {})
    end

    vim.api.nvim_cmd({ cmd = 'tabnew' }, {})

    if bufnr ~= nil and bufnr ~= 0 then
        vim.api.nvim_win_set_buf(0, bufnr)
    end

    return vim.api.nvim_get_current_tabpage()
end

return M
