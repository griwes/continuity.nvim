describe('continuity autoload', function()
    local original_cwd
    local state_file
    local test_git = require('tests.helpers.git')

    local function reset_modules()
        package.loaded.continuity = nil
        package.loaded['continuity.api'] = nil
        package.loaded['continuity.contributors.registry'] = nil
        package.loaded['continuity.core.config'] = nil
        package.loaded['continuity.core.model'] = nil
        package.loaded['continuity.core.session_key'] = nil
        package.loaded['continuity.live.state'] = nil
        package.loaded['continuity.persistence.mksession'] = nil
        package.loaded['continuity.persistence.storage'] = nil
        package.loaded['continuity.restore.autoload'] = nil
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.restore.plan'] = nil
    end

    ---@param path string
    local function mkdir(path)
        vim.fn.mkdir(path, 'p')
        return vim.fs.normalize(path)
    end

    ---@param sessions table[]
    ---@param opts? { last_session_id?: string }
    local function write_state(sessions, opts)
        vim.fn.writefile({
            vim.json.encode({
                last_session_id = opts and opts.last_session_id or nil,
                next_id = #sessions + 1,
                sessions = sessions,
            }),
        }, state_file)
    end

    ---@param opts table
    local function setup(opts)
        reset_modules()

        local plugin = require('continuity')

        plugin.setup(vim.tbl_deep_extend('force', {
            state_file = state_file,
        }, opts or {}))

        return plugin
    end

    before_each(function()
        original_cwd = vim.fn.getcwd()
        state_file = vim.fn.tempname()
        reset_modules()
    end)

    after_each(function()
        vim.api.nvim_set_current_dir(original_cwd)
        reset_modules()
    end)

    it('does nothing by default', function()
        local saved_cwd = mkdir(vim.fn.tempname())

        write_state({
            {
                id = 'session:saved',
                name = 'saved',
                cwd = saved_cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 1,
            },
        })

        local plugin = setup({})

        assert.is_false(plugin.last_autoload.loaded)
        assert.are.equal('disabled', plugin.last_autoload.reason)
        assert.are.equal(original_cwd, vim.fn.getcwd())
    end)

    it('autoloads the newest session for the current cwd', function()
        local cwd = mkdir(vim.fn.tempname())
        local other = mkdir(vim.fn.tempname())

        write_state({
            {
                id = 'session:old',
                name = 'old',
                cwd = cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 1,
            },
            {
                id = 'session:new',
                name = 'new',
                cwd = cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 1,
            },
            {
                id = 'session:other',
                name = 'other',
                cwd = other,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 4,
            },
        }, {
            last_session_id = 'session:new',
        })

        vim.api.nvim_set_current_dir(cwd)

        local plugin = setup({
            autoload = {
                policy = 'cwd',
            },
        })

        assert.is_true(plugin.last_autoload.loaded)
        assert.are.equal('session:new', plugin.last_autoload.session_id)
        assert.are.same({ 'session:cwd' }, plugin.last_autoload.execution.executed_steps)
        assert.are.equal(cwd, vim.fn.getcwd())
    end)

    it('does not let the last-session pointer override cwd recency', function()
        local cwd = mkdir(vim.fn.tempname())

        write_state({
            {
                id = 'session:old',
                name = 'old',
                cwd = cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 1,
            },
            {
                id = 'session:new',
                name = 'new',
                cwd = cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 2,
            },
        }, {
            last_session_id = 'session:old',
        })

        vim.api.nvim_set_current_dir(cwd)

        local plugin = setup({
            autoload = {
                policy = 'cwd',
            },
        })

        assert.is_true(plugin.last_autoload.loaded)
        assert.are.equal('session:new', plugin.last_autoload.session_id)
    end)

    it('autoloads the branch-specific session for the current repo', function()
        local repo = test_git.repo('continuity-autoload-branch')
        vim.api.nvim_set_current_dir(repo)

        local plugin = setup({
            session_key = {
                use_git_branch = true,
            },
        })
        local main = plugin.api.save({
            cwd = repo,
        })

        test_git.run({ 'checkout', '-b', 'feature/autoload' }, repo)

        local feature = plugin.api.save({
            cwd = repo,
        })

        assert.are_not.equal(main.id, feature.id)

        plugin = setup({
            autoload = {
                policy = 'cwd_branch',
            },
        })

        assert.is_true(plugin.last_autoload.loaded)
        assert.are.equal(feature.id, plugin.last_autoload.session_id)
        assert.are.equal(repo, vim.fn.getcwd())
    end)

    it('autoloads the newest session regardless of cwd', function()
        local old_cwd = mkdir(vim.fn.tempname())
        local new_cwd = mkdir(vim.fn.tempname())

        write_state({
            {
                id = 'session:old',
                name = 'old',
                cwd = old_cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 5,
            },
            {
                id = 'session:new',
                name = 'new',
                cwd = new_cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 5,
            },
        }, {
            last_session_id = 'session:new',
        })

        local plugin = setup({
            autoload = {
                policy = 'last',
            },
        })

        assert.is_true(plugin.last_autoload.loaded)
        assert.are.equal('session:new', plugin.last_autoload.session_id)
        assert.are.equal(new_cwd, vim.fn.getcwd())
    end)

    it('reports a safe miss instead of failing startup', function()
        local plugin = setup({
            autoload = {
                policy = 'cwd_branch',
            },
        })

        assert.is_false(plugin.last_autoload.loaded)
        assert.are.equal('not_found', plugin.last_autoload.reason)
    end)

    it('reports restore failures without stopping live startup', function()
        local cwd = vim.fs.joinpath(vim.fn.tempname(), 'missing')

        write_state({
            {
                id = 'session:bad',
                name = 'bad',
                cwd = cwd,
                state = {},
                contributors = {},
                created_at = 1,
                updated_at = 1,
            },
        }, {
            last_session_id = 'session:bad',
        })

        local plugin = setup({
            autoload = {
                policy = 'last',
            },
            continuous = {
                enabled = true,
                session_id = 'session:live-after-failure',
            },
        })

        assert.is_false(plugin.last_autoload.loaded)
        assert.are.equal('restore_failed', plugin.last_autoload.reason)
        assert.is_not_nil(plugin.last_autoload.error)
        assert.are.equal('session:live-after-failure', plugin.api.live_state().id)
    end)
end)
