vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.opt.runtimepath:prepend(vim.fn.getcwd())

local terminalia_path = vim.env.TERMINALIA_NVIM_PATH
if terminalia_path and terminalia_path ~= '' then
    terminalia_path = vim.fs.normalize(terminalia_path)
    if vim.fn.isdirectory(terminalia_path) == 0 then
        error('TERMINALIA_NVIM_PATH is not a plugin checkout: ' .. terminalia_path)
    end
    vim.opt.runtimepath:prepend(terminalia_path)
elseif vim.env.CONTINUITY_REQUIRE_TERMINALIA_INTEGRATION == '1' then
    error('CONTINUITY_REQUIRE_TERMINALIA_INTEGRATION requires TERMINALIA_NVIM_PATH')
end

local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
local dependency_versions = dofile('tests/dependency_versions.lua')

local function run_git(args)
    local output = vim.fn.system(args)
    if vim.v.shell_error ~= 0 then
        error(table.concat(args, ' ') .. '\n' .. output)
    end
    return output
end

if vim.fn.isdirectory(lazypath) == 0 then
    run_git({
        'git',
        'clone',
        '--filter=blob:none',
        'https://github.com/folke/lazy.nvim.git',
        '--branch=stable',
        lazypath,
    })
end

local lazy_head = vim.trim(run_git({ 'git', '-C', lazypath, 'rev-parse', 'HEAD' }))
if lazy_head ~= dependency_versions.lazy then
    run_git({ 'git', '-C', lazypath, 'checkout', '--force', '--detach', dependency_versions.lazy })
end

vim.opt.runtimepath:prepend(lazypath)

local test_plugins = {
    { dir = vim.fn.getcwd(), lazy = false },
    { 'nvim-lua/plenary.nvim', commit = dependency_versions.plenary, lazy = false },
}
if terminalia_path then
    test_plugins[#test_plugins + 1] = { dir = terminalia_path, lazy = false }
end

require('lazy').setup(test_plugins, {
    root = vim.fn.stdpath('data') .. '/lazy',
    lockfile = vim.fn.stdpath('state') .. '/lazy-lock.json',
})
