local M = {}

function M.check()
    vim.health.start('continuity.nvim')

    if vim.fn.has('nvim-0.11') == 1 then
        vim.health.ok('Neovim 0.11 or newer')
    else
        vim.health.error('Neovim 0.11 or newer is required')
    end

    local config = require('continuity.core.config').get()
    local parent = vim.fs.dirname(config.state_file)
    if vim.fn.isdirectory(parent) == 1 and vim.fn.filewritable(parent) == 2 then
        vim.health.ok('Session state directory is writable: ' .. parent)
    elseif vim.fn.isdirectory(parent) == 0 then
        vim.health.info('Session state directory will be created on first write: ' .. parent)
    else
        vim.health.error('Session state directory is not writable: ' .. parent)
    end

    if pcall(require, 'terminalia') then
        vim.health.ok('Terminalia contributor integration is available')
    else
        vim.health.info('Terminalia contributor integration is not installed')
    end
end

return M
