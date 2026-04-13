describe('session', function()
    local state_file

    before_each(function()
        package.loaded.session = nil
        package.loaded['session.api'] = nil
        package.loaded['session.config'] = nil
        package.loaded['session.contributors'] = nil
        package.loaded['session.model'] = nil
        package.loaded['session.live'] = nil
        package.loaded['session.restore_plan'] = nil
        package.loaded['session.storage'] = nil

        state_file = vim.fn.tempname()

        local plugin = require('session')
        plugin.setup({
            state_file = state_file,
        })
        plugin.api.clear()
    end)

    it('loads and exposes setup', function()
        local plugin = require('session')

        assert.are.equal('function', type(plugin.setup))
        assert.are.equal('table', type(plugin.api))
    end)

    it('stores normalized setup config', function()
        local plugin = require('session')

        local configured = plugin.setup({
            state_file = state_file,
        })

        assert.are.equal(state_file, configured.state_file)
    end)

    it('keeps an in-memory live session snapshot when continuous state is enabled', function()
        local plugin = require('session')

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

    it('saves and lists local session metadata records', function()
        local plugin = require('session')

        local first = plugin.api.save({
            name = 'alpha',
            cwd = vim.fn.getcwd(),
            state = {
                terminal = 'terminal:1',
            },
        })
        local second = plugin.api.save({
            name = 'beta',
        })

        local listed = plugin.api.list()

        assert.are.equal('session:1', first.id)
        assert.are.equal('session:2', second.id)
        assert.are.same({ 'session:1', 'session:2' }, { listed[1].id, listed[2].id })
        assert.are.equal('terminal:1', listed[1].state.terminal)
    end)

    it('loads restored session metadata from disk', function()
        local plugin = require('session')

        local saved = plugin.api.save({
            name = 'alpha',
            state = {
                cwd = '/tmp/workspace',
            },
        })

        plugin.api.clear({
            wipe_storage = false,
        })

        local restored = plugin.api.restore()

        assert.are.equal(1, #restored)
        assert.are.equal(saved.id, restored[1].id)
        assert.are.equal('/tmp/workspace', restored[1].state.cwd)
        assert.are.same(restored[1], plugin.api.load(saved.id))
    end)

    it('deletes persisted session metadata records', function()
        local plugin = require('session')

        local saved = plugin.api.save({
            name = 'alpha',
        })

        local removed = plugin.api.delete(saved.id)

        assert.are.equal(saved.id, removed.id)
        assert.is_nil(plugin.api.load(saved.id))
        assert.are.same({}, plugin.api.list())
    end)

    it('registers contributors and captures their state into saved session records', function()
        local plugin = require('session')

        plugin.api.register_contributor('terminal_manager', {
            capture = function()
                return {
                    terminals = { 'terminal:1' },
                }
            end,
        })
        plugin.api.register_contributor('workspace', {
            capture = function()
                return {
                    cwd = '/tmp/workspace',
                }
            end,
        })

        local saved = plugin.api.capture({
            name = 'captured',
        })

        assert.are.same({ 'terminal_manager', 'workspace' }, plugin.api.contributor_names())
        assert.are.same({ 'terminal:1' }, saved.contributors.terminal_manager.terminals)
        assert.are.equal('/tmp/workspace', saved.contributors.workspace.cwd)
    end)

    it('restores contributor-owned session state from disk', function()
        local plugin = require('session')

        plugin.api.register_contributor('terminal_manager', {
            capture = function()
                return {
                    terminals = { 'terminal:1' },
                }
            end,
        })

        local saved = plugin.api.capture({
            name = 'captured',
        })

        plugin.api.clear({
            wipe_storage = false,
        })

        local restored = plugin.api.restore()

        assert.are.equal(saved.id, restored[1].id)
        assert.are.same({ 'terminal:1' }, restored[1].contributors.terminal_manager.terminals)
    end)

    it('plans restore steps from a saved session record', function()
        local plugin = require('session')

        local saved = plugin.api.save({
            name = 'alpha',
            cwd = '/tmp/workspace',
        })

        local plan = plugin.api.plan_restore(saved.id)

        assert.are.equal(saved.id, plan.session_id)
        assert.are.equal('/tmp/workspace', plan.cwd)
        assert.are.equal(1, #plan.steps)
        assert.are.equal('session:cwd', plan.steps[1].id)
        assert.are.equal('session.chdir', plan.steps[1].kind)
        assert.are.equal('/tmp/workspace', plan.steps[1].payload.cwd)
    end)

    it('orders contributor restore steps through restore_after dependencies', function()
        local plugin = require('session')

        plugin.api.register_contributor('workspace', {
            plan_restore = function(captured)
                return {
                    {
                        kind = 'workspace.select',
                        title = 'Select workspace',
                        payload = captured,
                    },
                }
            end,
        })
        plugin.api.register_contributor('terminal_manager', {
            restore_after = { 'workspace' },
            plan_restore = function(captured)
                return {
                    {
                        kind = 'terminal.restore_context',
                        title = 'Restore terminal context',
                        payload = captured.current_context_id,
                    },
                    {
                        kind = 'terminal.restore_buffers',
                        title = 'Reopen terminal buffers',
                        payload = captured.terminals,
                    },
                }
            end,
        })

        local saved = plugin.api.save({
            name = 'ordered',
            cwd = '/tmp/workspace',
            contributors = {
                terminal_manager = {
                    current_context_id = 'context:demo',
                    terminals = { 'terminal-manager://demo' },
                },
                workspace = {
                    id = 'workspace:demo',
                },
            },
        })

        local plan = plugin.api.plan_restore(saved.id)

        assert.are.same(
            {
                'session:cwd',
                'workspace:1',
                'terminal_manager:1',
                'terminal_manager:2',
            },
            vim.tbl_map(function(step)
                return step.id
            end, plan.steps)
        )
        assert.are.same({ 'session:cwd' }, plan.steps[2].depends_on)
        assert.are.same({ 'session:cwd', 'workspace:1' }, plan.steps[3].depends_on)
        assert.are.same({ 'terminal_manager:1' }, plan.steps[4].depends_on)
    end)

    it('keeps captured contributors without restore planners visible as manual steps', function()
        local plugin = require('session')

        plugin.api.register_contributor('remote_workspace', {
            capture = function()
                return {
                    current = {
                        name = 'ssh-main',
                    },
                }
            end,
        })

        local saved = plugin.api.capture({
            name = 'manual',
        })

        local plan = plugin.api.plan_restore(saved.id)

        assert.are.equal(2, #plan.steps)
        assert.are.equal('remote_workspace:1', plan.steps[2].id)
        assert.are.equal('session.manual_restore', plan.steps[2].kind)
        assert.is_true(plan.steps[2].manual)
        assert.are.same({ 'session:cwd' }, plan.steps[2].depends_on)
        assert.are.equal('ssh-main', plan.steps[2].payload.current.name)
    end)

    it('recaptures contributor-owned live state when notified and persists it on the configured cadence', function()
        local plugin = require('session')
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
        local plugin = require('session')

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
end)
