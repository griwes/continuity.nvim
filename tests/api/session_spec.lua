describe('session', function()
    local state_file
    local test_git = require('tests.helpers.git')

    ---@param name string
    ---@return string
    local function sibling_repo(name)
        return vim.fs.normalize(vim.fs.joinpath(vim.fn.getcwd(), '..', name))
    end

    ---@param name string
    ---@return boolean
    local function repo_exists(name)
        return vim.fn.isdirectory(sibling_repo(name)) == 1
    end

    ---@param names string[]
    local function prepend_runtimepaths(names)
        for _, name in ipairs(names) do
            if repo_exists(name) then
                vim.opt.runtimepath:prepend(sibling_repo(name))
            end
        end
    end

    before_each(function()
        package.loaded.continuity = nil
        package.loaded['continuity.api'] = nil
        package.loaded['continuity.contributors.registry'] = nil
        package.loaded['continuity.core.config'] = nil
        package.loaded['continuity.core.model'] = nil
        package.loaded['continuity.core.session_key'] = nil
        package.loaded['continuity.live.state'] = nil
        package.loaded['continuity.persistence.mksession'] = nil
        package.loaded['continuity.persistence.storage'] = nil
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.restore.plan'] = nil

        state_file = vim.fn.tempname()

        local plugin = require('continuity')
        plugin.setup({
            state_file = state_file,
        })
        plugin.api.clear()
    end)

    it('loads and exposes setup', function()
        local plugin = require('continuity')

        assert.are.equal('function', type(plugin.setup))
        assert.are.equal('table', type(plugin.api))
    end)

    it('stores normalized setup config', function()
        local plugin = require('continuity')

        local configured = plugin.setup({
            state_file = state_file,
        })

        assert.are.equal(state_file, configured.state_file)
    end)

    it('saves and lists local session metadata records', function()
        local plugin = require('continuity')

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

    it('derives opt-in session ids from cwd and Git branch', function()
        local plugin = require('continuity')
        local repo = test_git.repo('continuity-git')

        plugin.setup({
            state_file = state_file,
            session_key = {
                use_git_branch = true,
            },
        })

        local main = plugin.api.save({
            cwd = repo,
        })

        test_git.run({ 'checkout', '-b', 'feature/dogfood' }, repo)

        local feature = plugin.api.save({
            cwd = repo,
        })
        local listed = plugin.api.list()

        assert.are.equal(2, #listed)
        assert.is_true(main.id:find('session:') == 1)
        assert.is_true(feature.id:find('feature_dogfood', 1, true) ~= nil)
        assert.are_not.equal(main.id, feature.id)
        assert.are.equal('main', main.state.continuity.session_key.branch)
        assert.are.equal('feature/dogfood', feature.state.continuity.session_key.branch)
        assert.are.equal(repo, feature.state.continuity.session_key.cwd)
    end)

    it('keeps sequential session ids as the default', function()
        local plugin = require('continuity')
        local repo = test_git.repo('continuity-git')

        local saved = plugin.api.save({
            cwd = repo,
        })

        assert.are.equal('session:1', saved.id)
        assert.is_nil(saved.state.continuity)
    end)

    it('loads restored session metadata from disk', function()
        local plugin = require('continuity')

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
        local plugin = require('continuity')

        local saved = plugin.api.save({
            name = 'alpha',
        })

        local removed = plugin.api.delete(saved.id)

        assert.are.equal(saved.id, removed.id)
        assert.is_nil(plugin.api.load(saved.id))
        assert.are.same({}, plugin.api.list())
    end)

    it('registers contributors and captures their state into saved session records', function()
        local plugin = require('continuity')

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
        local plugin = require('continuity')

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
        local plugin = require('continuity')

        local saved = plugin.api.save({
            name = 'alpha',
            cwd = '/tmp/workspace',
        })

        local plan = plugin.api.plan_restore(saved.id)

        assert.are.equal(saved.id, plan.session_id)
        assert.are.equal('/tmp/workspace', plan.cwd)
        assert.are.equal(1, #plan.steps)
        assert.are.equal('session:cwd', plan.steps[1].id)
        assert.are.equal('continuity.chdir', plan.steps[1].kind)
        assert.are.equal('/tmp/workspace', plan.steps[1].payload.cwd)
    end)

    it('maps legacy contributor keys onto branded contributors when planning restore', function()
        local plugin = require('continuity')

        plugin.api.register_contributor('terminalia', {
            plan_restore = function(captured)
                return {
                    {
                        kind = 'terminalia.reopen_terminals',
                        payload = captured,
                    },
                }
            end,
        })

        local plan = plugin.api.plan_restore({
            id = 'session:legacy',
            name = 'legacy',
            cwd = '/tmp/legacy',
            contributors = {
                terminal_manager = {
                    terminals = { 'terminal:1' },
                },
            },
        })

        assert.are.same(
            { 'session:cwd', 'terminalia:1' },
            vim.tbl_map(function(step)
                return step.id
            end, plan.steps)
        )
        assert.are.same({ 'terminal:1' }, plan.steps[2].payload.terminals)
    end)

    it('preserves contributor registrations when clearing session state', function()
        local plugin = require('continuity')

        plugin.api.register_contributor('workspace', {
            capture = function()
                return {
                    cwd = '/tmp/workspace',
                }
            end,
        })

        local captured = plugin.api.capture({
            name = 'captured',
        })
        assert.are.equal('/tmp/workspace', captured.contributors.workspace.cwd)
        assert.are.same({ 'workspace' }, plugin.api.contributor_names())

        plugin.api.clear({
            wipe_storage = false,
        })

        assert.are.same({ 'workspace' }, plugin.api.contributor_names())
        local recaptured = plugin.api.capture({
            name = 'recaptured',
        })
        assert.are.equal('/tmp/workspace', recaptured.contributors.workspace.cwd)

        plugin.api.clear({
            wipe_storage = false,
            wipe_contributors = true,
        })

        assert.are.same({}, plugin.api.contributor_names())
    end)

    it('canonicalizes legacy restore_after names when resolving contributor dependencies', function()
        local plugin = require('continuity')

        plugin.api.register_contributor('workspace', {
            restore_after = { 'terminal_manager' },
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
        plugin.api.register_contributor('terminalia', {
            restore_after = { 'terminal_manager' },
            plan_restore = function()
                return {
                    {
                        kind = 'terminalia.reopen_terminals',
                        title = 'Reopen terminals',
                    },
                }
            end,
        })

        local saved = plugin.api.save({
            name = 'canonical-restores',
            cwd = '/tmp/workspace',
            contributors = {
                workspace = {},
                terminal_manager = {},
            },
        })

        local plan = plugin.api.plan_restore(saved.id)

        assert.are.same(
            {
                'session:cwd',
                'terminalia:1',
                'workspace:1',
            },
            vim.tbl_map(function(step)
                return step.id
            end, plan.steps)
        )
        assert.are.same({ 'session:cwd' }, plan.steps[2].depends_on)
        assert.are.same({ 'session:cwd', 'terminalia:1' }, plan.steps[3].depends_on)
    end)

    it('orders contributor restore steps through restore_after dependencies', function()
        local plugin = require('continuity')

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
                    terminals = { 'terminalia://demo' },
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
        local plugin = require('continuity')

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
        assert.are.equal('continuity.manual_restore', plan.steps[2].kind)
        assert.is_true(plan.steps[2].manual)
        assert.are.same({ 'session:cwd' }, plan.steps[2].depends_on)
        assert.are.equal('ssh-main', plan.steps[2].payload.current.name)
    end)
end)
