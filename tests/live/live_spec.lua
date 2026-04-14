describe('continuity live state', function()
    local state_file

    before_each(function()
        package.loaded.continuity = nil
        package.loaded['continuity.api'] = nil
        package.loaded['continuity.core.config'] = nil
        package.loaded['continuity.contributors.registry'] = nil
        package.loaded['continuity.core.model'] = nil
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
end)
