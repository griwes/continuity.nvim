local M = {}

---@param prefix string
---@return string
local function mkdtemp(prefix)
    local dir, err = vim.uv.fs_mkdtemp(vim.fs.joinpath(vim.fn.stdpath('run'), prefix .. '.XXXXXX'))

    assert(dir, err)

    return dir
end

---@param args string[]
---@param cwd string
function M.run(args, cwd)
    local command = { 'git', '-C', cwd }
    vim.list_extend(command, args)

    local output = vim.fn.system(command)

    assert.are.equal(0, vim.v.shell_error, output)
end

---@param prefix string
---@return string
function M.repo(prefix)
    if vim.fn.executable('git') == 0 then
        pending('git is not available')
        return ''
    end

    local repo = mkdtemp(prefix)

    M.run({ 'init', '--initial-branch=main' }, repo)
    M.run({ 'config', 'user.email', 'continuity@example.invalid' }, repo)
    M.run({ 'config', 'user.name', 'Continuity Tests' }, repo)
    M.run({ 'config', 'commit.gpgsign', 'false' }, repo)
    vim.fn.writefile({ 'root' }, vim.fs.joinpath(repo, 'README.md'))
    M.run({ 'add', 'README.md' }, repo)
    M.run({ 'commit', '-m', 'initial' }, repo)

    return repo
end

return M
