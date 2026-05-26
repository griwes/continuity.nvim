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
        package.loaded['continuity.persistence.storage'] = nil
        package.loaded['continuity.restore.autoload'] = nil
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.restore.late'] = nil
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
        local state_dir = string.format('%s.d', state_file)
        local index_sessions = {}

        vim.fn.mkdir(state_dir, 'p')

        local function encode_path_component(value)
            return value:gsub('[^%w._-]', function(char)
                return string.format('%%%02X', char:byte())
            end)
        end

        local function session_filename(id)
            return string.format('%s.json', encode_path_component(id))
        end

        for _, session in ipairs(sessions) do
            local filename = session_filename(session.id)

            vim.fn.writefile({ vim.json.encode(session) }, vim.fs.joinpath(state_dir, filename))
            table.insert(index_sessions, {
                id = session.id,
                name = session.name,
                cwd = session.cwd,
                created_at = session.created_at,
                updated_at = session.updated_at,
                file = filename,
            })
        end

        vim.fn.writefile({
            vim.json.encode({
                version = 1,
                last_session_id = opts and opts.last_session_id or nil,
                next_id = #sessions + 1,
                sessions = index_sessions,
            }),
        }, state_file)
    end

    ---@param opts table
    local function setup(opts)
        reset_modules()

        local plugin = require('continuity')

        plugin.setup(vim.tbl_deep_extend('force', {
            state_file = state_file,
            shada = {
                external_policy = 'ignore',
            },
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

    it('prefers the branch-specific clean snapshot when one exists', function()
        local repo = test_git.repo('continuity-autoload-clean-branch')
        vim.api.nvim_set_current_dir(repo)

        local plugin = setup({
            session_key = {
                use_git_branch = true,
            },
        })
        local saved = plugin.api.save({
            cwd = repo,
            state = {
                marker = 'live',
            },
        })
        local clean =
            require('continuity.persistence.storage').save_clean_snapshot(vim.tbl_deep_extend('force', saved, {
                state = {
                    marker = 'clean',
                    continuity = saved.state.continuity,
                },
            }))

        plugin = setup({
            autoload = {
                policy = 'cwd_branch',
            },
        })

        assert.is_true(plugin.last_autoload.loaded)
        assert.are.equal(clean.id, plugin.last_autoload.session_id)
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

    it('restores an autoloaded contributor that registers after startup', function()
        local cwd = mkdir(vim.fn.tempname())
        local captured = {
            version = 1,
            active_path = { 2, 1 },
            children = {
                {
                    label = 'One',
                    selected_child_index = 1,
                    children = {
                        {
                            label = 'Two',
                            selected_child_index = 1,
                            children = {
                                { label = 'Three', children = {} },
                            },
                        },
                    },
                },
                {
                    label = 'Four',
                    selected_child_index = 1,
                    children = {
                        { label = 'Five', children = {} },
                    },
                },
            },
        }

        write_state({
            {
                id = 'session:tabs',
                name = 'tabs',
                cwd = cwd,
                state = {},
                contributors = {
                    tabulature = captured,
                },
                created_at = 1,
                updated_at = 1,
            },
        })

        vim.api.nvim_set_current_dir(cwd)

        local plugin = setup({
            autoload = {
                policy = 'cwd',
            },
        })

        assert.is_true(plugin.last_autoload.loaded)
        assert.are.equal('session:tabs', plugin.last_autoload.session_id)
        assert.are.equal(1, #plugin.last_autoload.execution.manual_steps)
        assert.are.equal('continuity.unknown_contributor', plugin.last_autoload.execution.manual_steps[1].kind)
        assert.are.equal('tabulature', plugin.last_autoload.execution.manual_steps[1].contributor)

        local restored

        plugin.api.register_contributor('tabulature', {
            plan_restore = function(payload, record)
                return {
                    {
                        id = 'tabulature:restore',
                        kind = 'tabulature.restore_tabs',
                        payload = payload,
                        detail = record.id,
                    },
                }
            end,
            restore = function(step, record, opts)
                restored = {
                    step = step,
                    record = record,
                    opts = opts,
                }
            end,
        })

        if restored == nil then
            vim.api.nvim_exec_autocmds('VimEnter', {})
            vim.wait(1000, function()
                return restored ~= nil
            end)
        end

        assert.is_not_nil(restored)
        assert.are.same(captured, restored.step.payload)
        assert.are.equal('session:tabs', restored.record.id)
        assert.are.same({
            late_registration = true,
            restore_layout = false,
        }, restored.opts)
    end)

    local function late_restore_fixture()
        local cwd = mkdir(vim.fn.tempname())

        write_state({
            {
                id = 'session:providers',
                name = 'providers',
                cwd = cwd,
                state = {},
                contributors = {
                    terminal = { value = 'terminal' },
                    workspace = { value = 'workspace' },
                },
                created_at = 1,
                updated_at = 1,
            },
        })

        vim.api.nvim_set_current_dir(cwd)

        return setup({
            autoload = {
                policy = 'cwd',
            },
        })
    end

    ---@param calls string[]
    ---@param expected_count integer
    local function wait_for_late_restore(calls, expected_count)
        if #calls < expected_count then
            vim.api.nvim_exec_autocmds('VimEnter', {})
            local restored = vim.wait(1000, function()
                return #calls >= expected_count
            end)

            assert.is_true(restored)
        end
    end

    local function drain_late_restore()
        vim.api.nvim_exec_autocmds('VimEnter', {})
        vim.wait(20)
    end

    ---@param calls string[]
    ---@return continuity.Contributor
    local function workspace_contributor(calls)
        return {
            restore_phase = 'before_layout',
            plan_restore = function(payload)
                return {
                    {
                        id = 'workspace:restore',
                        kind = 'workspace.restore',
                        payload = payload,
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.contributor)
            end,
        }
    end

    ---@param calls string[]
    ---@param depends_on_workspace? boolean
    ---@param step_id? string
    ---@return continuity.Contributor
    local function terminal_contributor(calls, depends_on_workspace, step_id)
        return {
            restore_phase = 'after_layout',
            restore_after = depends_on_workspace == false and nil or { 'workspace' },
            plan_restore = function(payload)
                return {
                    {
                        id = step_id or 'terminal:restore',
                        kind = 'terminal.restore',
                        payload = payload,
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.contributor)
            end,
        }
    end

    it('defers late dependencies and does not repeat settled contributors with new step ids', function()
        local plugin = late_restore_fixture()
        local calls = {}
        local terminal = terminal_contributor(calls)

        plugin.api.register_contributor('terminal', terminal)
        drain_late_restore()

        assert.are.same({}, calls)

        plugin.api.register_contributor('workspace', workspace_contributor(calls))
        wait_for_late_restore(calls, 2)

        assert.are.same({ 'workspace', 'terminal' }, calls)

        plugin.api.register_contributor('terminal', terminal_contributor(calls, true, 'terminal:replacement'))
        drain_late_restore()

        assert.are.same({ 'workspace', 'terminal' }, calls)
    end)

    it('preserves late contributor phases when after-layout registers first', function()
        local plugin = late_restore_fixture()
        local calls = {}

        plugin.api.register_contributor('terminal', terminal_contributor(calls, false))
        plugin.api.register_contributor('workspace', workspace_contributor(calls))
        wait_for_late_restore(calls, 2)

        assert.are.same({ 'workspace', 'terminal' }, calls)
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
