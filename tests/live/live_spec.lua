describe('continuity live state', function()
    local state_file
    local test_git = require('tests.helpers.git')

    before_each(function()
        package.loaded.continuity = nil
        package.loaded['continuity.api'] = nil
        package.loaded['continuity.core.config'] = nil
        package.loaded['continuity.contributors.registry'] = nil
        package.loaded['continuity.core.model'] = nil
        package.loaded['continuity.core.session_key'] = nil
        package.loaded['continuity.live.state'] = nil
        package.loaded['continuity.persistence.mksession'] = nil
        package.loaded['continuity.restore.plan'] = nil
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.persistence.storage'] = nil

        state_file = vim.fn.tempname()

        local plugin = require('continuity')
        plugin.setup({
            state_file = state_file,
        })
        plugin.api.clear()
    end)

    it('keeps an in-memory live session snapshot when continuous state is enabled', function()
        local plugin = require('continuity')

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
        })

        local live = plugin.api.live_state()

        assert.are.equal('session:live', assert(live).id)
        assert.are.equal(vim.fn.getcwd(), live.cwd)
        assert.are.equal(vim.api.nvim_get_current_buf(), live.state.nvim.current.buffer)
        assert.are.equal(vim.api.nvim_get_current_tabpage(), live.state.nvim.current.tab)
    end)

    it('recaptures contributor-owned live state when notified and persists it on the configured cadence', function()
        local plugin = require('continuity')
        local value = 'alpha'

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 10,
            },
        })

        plugin.api.register_contributor('workspace', {
            capture = function()
                return {
                    value = value,
                }
            end,
        })

        value = 'beta'
        plugin.api.notify_contributor_changed('workspace')

        assert.are.equal('beta', plugin.api.live_state().contributors.workspace.value)

        local persisted = vim.wait(200, function()
            local loaded = plugin.api.load('session:live')
            return loaded ~= nil
                and loaded.contributors.workspace ~= nil
                and loaded.contributors.workspace.value == 'beta'
        end, 10)

        assert.is_true(persisted)
    end)

    it('ignores contributor notifications when continuous state is disabled', function()
        local plugin = require('continuity')

        plugin.api.register_contributor('workspace', {
            capture = function()
                return {
                    value = 'disabled',
                }
            end,
        })

        plugin.api.notify_contributor_changed('workspace')

        assert.is_nil(plugin.api.live_state())
    end)

    it('updates live builtin state from editor events without forcing immediate disk writes', function()
        local plugin = require('continuity')

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 1000,
            },
        })

        vim.cmd('enew')

        local live = plugin.api.live_state()
        local persisted = plugin.api.load('session:live')

        assert.are.equal(vim.api.nvim_get_current_buf(), assert(live).state.nvim.current.buffer)
        assert.is_true(#live.state.nvim.buffers >= 1)
        assert.is_nil(persisted)
    end)

    it('refreshes buffer modified state from edit and write events', function()
        local plugin = require('continuity')
        local path = vim.fn.tempname()

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 1000,
            },
        })

        vim.cmd('edit ' .. vim.fn.fnameescape(path))
        local buffer = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { 'alpha' })
        vim.api.nvim_exec_autocmds('TextChanged', {
            modeline = false,
        })

        local edited = plugin.api.live_state().state.nvim.buffers[buffer]
        assert.is_true(assert(edited).modified)

        vim.cmd('write')

        local written = plugin.api.live_state().state.nvim.buffers[buffer]
        assert.is_false(assert(written).modified)
        assert.is_nil(plugin.api.load('session:live'))
    end)

    it('does not capture mksession for the live session by default', function()
        local plugin = require('continuity')
        local session_dir = vim.fs.joinpath(vim.fn.tempname(), 'views')

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
            mksession = {
                enabled = true,
                dir = session_dir,
            },
        })

        plugin.api.sync_live_state()

        local mksession = require('continuity.persistence.mksession')

        assert.are.equal(0, vim.fn.filereadable(mksession.path('session:live')))
    end)

    it('can opt into capturing mksession for the live session', function()
        local plugin = require('continuity')
        local session_dir = vim.fs.joinpath(vim.fn.tempname(), 'views')

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
            mksession = {
                enabled = true,
                capture_live = true,
                dir = session_dir,
            },
        })

        plugin.api.sync_live_state()

        local mksession = require('continuity.persistence.mksession')

        assert.are.equal(1, vim.fn.filereadable(mksession.path('session:live')))
    end)

    it('can derive the live session id from cwd and Git branch', function()
        local plugin = require('continuity')
        local original_cwd = vim.fn.getcwd()
        local repo = test_git.repo('continuity-live-git')

        vim.api.nvim_set_current_dir(repo)
        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                session_id = 'auto',
                write_debounce_ms = 0,
            },
            session_key = {
                use_git_branch = true,
            },
        })

        local main = assert(plugin.api.live_state())

        test_git.run({ 'checkout', '-b', 'feature/live' }, repo)
        plugin.api.sync_live_state()

        local feature = assert(plugin.api.live_state())

        vim.api.nvim_set_current_dir(original_cwd)

        assert.are_not.equal(main.id, feature.id)
        assert.is_true(main.id:find('main', 1, true) ~= nil)
        assert.is_true(feature.id:find('feature_live', 1, true) ~= nil)
        assert.are.equal('feature/live', plugin.api.load(feature.id).state.continuity.session_key.branch)
    end)

    it('does not capture mksession for auto live sessions by default', function()
        local plugin = require('continuity')
        local original_cwd = vim.fn.getcwd()
        local repo = test_git.repo('continuity-live-git')
        local session_dir = vim.fs.joinpath(vim.fn.tempname(), 'views')

        vim.api.nvim_set_current_dir(repo)
        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                session_id = 'auto',
                write_debounce_ms = 0,
            },
            mksession = {
                enabled = true,
                dir = session_dir,
            },
            session_key = {
                use_git_branch = true,
            },
        })

        plugin.api.sync_live_state()

        local live = assert(plugin.api.live_state())
        local mksession = require('continuity.persistence.mksession')

        vim.api.nvim_set_current_dir(original_cwd)

        assert.are.equal(0, vim.fn.filereadable(mksession.path(live.id)))
    end)
end)
