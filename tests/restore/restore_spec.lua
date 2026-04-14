describe('continuity restore execution', function()
    local state_file

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

    it('executes restore steps through contributor-owned restore callbacks in order', function()
        local plugin = require('continuity')
        local calls = {}
        local root = vim.fn.tempname()
        local original_mksession = package.loaded['continuity.persistence.mksession']

        vim.fn.mkdir(root, 'p')

        package.loaded['continuity.persistence.mksession'] = {
            load = function(id)
                table.insert(calls, 'mksession:' .. id)
                return true
            end,
            capture = function() end,
            delete = function() end,
            clear_all = function() end,
        }

        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.api'] = nil
        plugin.api = require('continuity.api')

        plugin.api.register_contributor('workspace', {
            plan_restore = function()
                return {
                    {
                        kind = 'workspace.select',
                        title = 'Select workspace',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })
        plugin.api.register_contributor('terminal_manager', {
            restore_phase = 'after_mksession',
            restore_after = { 'workspace' },
            plan_restore = function()
                return {
                    {
                        kind = 'terminalia.reopen_terminals',
                        title = 'Reopen terminals',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })

        local saved = plugin.api.save({
            name = 'restore',
            cwd = root,
            contributors = {
                workspace = {},
                terminal_manager = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id)

        package.loaded['continuity.persistence.mksession'] = original_mksession
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.api'] = nil
        package.loaded.continuity.api = require('continuity.api')

        assert.are.same({ 'session:cwd', 'workspace:1', 'terminal_manager:1' }, report.executed_steps)
        assert.is_true(report.mksession_loaded)
        assert.are.same({ 'workspace.select', 'mksession:' .. saved.id, 'terminalia.reopen_terminals' }, calls)
    end)

    it('reports manual restore steps when a contributor has no restore callback', function()
        local plugin = require('continuity')
        local root = vim.fn.tempname()

        vim.fn.mkdir(root, 'p')

        plugin.api.register_contributor('remote_workspace', {
            plan_restore = function()
                return {
                    {
                        kind = 'consulate.use',
                        title = 'Select remote workspace',
                    },
                }
            end,
        })

        local saved = plugin.api.save({
            name = 'manual',
            cwd = root,
            contributors = {
                remote_workspace = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            use_mksession = false,
        })

        assert.are.same({ 'session:cwd' }, report.executed_steps)
        assert.are.equal(1, #report.manual_steps)
        assert.are.equal('consulate.use', report.manual_steps[1].kind)
        assert.is_false(report.mksession_loaded)
    end)

    it('writes an mksession substrate file when enabled', function()
        local plugin = require('continuity')
        local session_file = vim.fs.joinpath(vim.fn.tempname(), 'views')

        plugin.setup({
            state_file = state_file,
            mksession = {
                enabled = true,
                dir = session_file,
            },
        })

        local saved = plugin.api.save({
            name = 'with-mksession',
        })
        local mksession = require('continuity.persistence.mksession')

        assert.are.equal(1, vim.fn.filereadable(mksession.path(saved.id)))
    end)

    it('replays worktree and remote contributors before mksession and Terminalia reopen', function()
        local plugin = require('continuity')
        local root = vim.fn.tempname()
        local calls = {}
        local original_mksession = package.loaded['continuity.persistence.mksession']

        vim.fn.mkdir(root, 'p')

        package.loaded['continuity.persistence.mksession'] = {
            load = function(id)
                table.insert(calls, 'mksession:' .. id)
                return true
            end,
            capture = function() end,
            delete = function() end,
            clear_all = function() end,
        }

        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.api'] = nil
        plugin.api = require('continuity.api')

        plugin.api.register_contributor('git_worktree', {
            plan_restore = function()
                return {
                    {
                        kind = 'arboretum.switch',
                        title = 'Switch worktree',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })
        plugin.api.register_contributor('remote_workspace', {
            restore_after = { 'git_worktree' },
            plan_restore = function()
                return {
                    {
                        kind = 'consulate.use',
                        title = 'Select remote workspace',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })
        plugin.api.register_contributor('terminal_manager', {
            restore_phase = 'after_mksession',
            restore_after = { 'git_worktree', 'remote_workspace' },
            plan_restore = function()
                return {
                    {
                        kind = 'terminalia.reopen_terminals',
                        title = 'Reopen terminals',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })

        local saved = plugin.api.save({
            name = 'ordered-integration',
            cwd = root,
            contributors = {
                git_worktree = {},
                remote_workspace = {},
                terminal_manager = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id)

        package.loaded['continuity.persistence.mksession'] = original_mksession
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.api'] = nil
        package.loaded.continuity.api = require('continuity.api')

        assert.are.same({
            'session:cwd',
            'git_worktree:1',
            'remote_workspace:1',
            'terminal_manager:1',
        }, report.executed_steps)
        assert.are.same({
            'arboretum.switch',
            'consulate.use',
            'mksession:' .. saved.id,
            'terminalia.reopen_terminals',
        }, calls)
    end)

    it('preserves contributor ordering when mksession is disabled', function()
        local plugin = require('continuity')
        local root = vim.fn.tempname()
        local calls = {}

        vim.fn.mkdir(root, 'p')

        plugin.api.register_contributor('git_worktree', {
            plan_restore = function()
                return {
                    {
                        kind = 'arboretum.switch',
                        title = 'Switch worktree',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })
        plugin.api.register_contributor('terminal_manager', {
            restore_phase = 'after_mksession',
            restore_after = { 'git_worktree' },
            plan_restore = function()
                return {
                    {
                        kind = 'terminalia.reopen_terminals',
                        title = 'Reopen terminals',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })

        local saved = plugin.api.save({
            name = 'ordered-no-mksession',
            cwd = root,
            contributors = {
                git_worktree = {},
                terminal_manager = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            use_mksession = false,
        })

        assert.are.same({ 'session:cwd', 'git_worktree:1', 'terminal_manager:1' }, report.executed_steps)
        assert.are.same({ 'arboretum.switch', 'terminalia.reopen_terminals' }, calls)
        assert.is_false(report.mksession_loaded)
    end)

    it('uses contributor restore phases instead of contributor names to place post-mksession work', function()
        local plugin = require('continuity')
        local root = vim.fn.tempname()
        local calls = {}
        local original_mksession = package.loaded['continuity.persistence.mksession']

        vim.fn.mkdir(root, 'p')

        package.loaded['continuity.persistence.mksession'] = {
            load = function(id)
                table.insert(calls, 'mksession:' .. id)
                return true
            end,
            capture = function() end,
            delete = function() end,
            clear_all = function() end,
        }

        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.api'] = nil
        plugin.api = require('continuity.api')

        plugin.api.register_contributor('alpha', {
            plan_restore = function()
                return {
                    {
                        kind = 'alpha.restore',
                        title = 'Alpha',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })
        plugin.api.register_contributor('omega', {
            restore_phase = 'after_mksession',
            restore_after = { 'alpha' },
            plan_restore = function()
                return {
                    {
                        kind = 'omega.restore',
                        title = 'Omega',
                    },
                }
            end,
            restore = function(step)
                table.insert(calls, step.kind)
            end,
        })

        local saved = plugin.api.save({
            name = 'phase-driven',
            cwd = root,
            contributors = {
                alpha = {},
                omega = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id)

        package.loaded['continuity.persistence.mksession'] = original_mksession
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.api'] = nil
        package.loaded.continuity.api = require('continuity.api')

        assert.are.same({ 'session:cwd', 'alpha:1', 'omega:1' }, report.executed_steps)
        assert.are.same({ 'alpha.restore', 'mksession:' .. saved.id, 'omega.restore' }, calls)
    end)

    it('integrates real workspace providers for worktree plus remote restore execution when available', function()
        if
            not repo_exists('arboretum.nvim')
            or not repo_exists('consulate.nvim')
            or not repo_exists('terminalia.nvim')
        then
            assert.is_true(true)
            return
        end

        prepend_runtimepaths({
            'terminalia.nvim',
            'arboretum.nvim',
            'consulate.nvim',
        })

        package.loaded.arboretum = nil
        package.loaded['arboretum.api'] = nil
        package.loaded.consulate = nil
        package.loaded['consulate.api'] = nil
        package.loaded.terminalia = nil
        package.loaded['terminalia.api'] = nil

        require('terminalia').setup({
            history_dir = vim.fn.tempname(),
            notify_on_exit = false,
            persist_terminals = false,
            state_file = vim.fn.tempname(),
        })

        require('arboretum').setup({
            notify = false,
            system_runner = function()
                error('unexpected git invocation in session integration test')
            end,
        })

        require('consulate').setup({})

        local calls = {}
        local original_switch = arboretum.api.switch
        local original_set_current = consulate.api.set_current
        local original_reopen_terminal = consulate.api.reopen_terminal
        local original_open_uri = terminalia.api.open_uri

        arboretum.api.switch = function(options)
            table.insert(calls, {
                kind = 'arboretum.switch',
                value = options.path,
            })
            return {
                target = {
                    path = options.path,
                },
            }
        end
        consulate.api.set_current = function(item)
            table.insert(calls, {
                kind = 'consulate.use',
                value = item.id,
            })
            return item
        end
        consulate.api.reopen_terminal = function(id, opts)
            table.insert(calls, {
                kind = 'consulate.reopen_terminals',
                value = id,
                view = opts.view,
            })
            return {
                id = 'remote:' .. id,
            }
        end
        terminalia.api.open_uri = function(uri, opts)
            table.insert(calls, {
                kind = 'terminalia.reopen_terminals',
                value = uri,
                view = opts.view,
            })
            return {
                id = 'terminal:restored',
            }
        end

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')

        local terminal_uri = require('terminalia.uri').encode_terminal_uri({
            id = 'terminal:1',
            name = 'build',
            context_id = 'context:host',
        })

        local saved = plugin.api.save({
            name = 'workspace-integration',
            cwd = root,
            contributors = {
                arboretum = {
                    current = {
                        path = '/repo/feature',
                        branch_ref = 'refs/heads/feature/demo',
                    },
                },
                consulate = {
                    current = {
                        id = 'ssh|devbox|/repo|/srv/project',
                        name = 'project-ssh',
                        host = 'devbox',
                    },
                    linked_terminals = {
                        {
                            id = 'remoteterminal:1',
                            view = 'float',
                        },
                    },
                },
                terminalia = {
                    current_context_id = 'context:remote',
                    terminals = {
                        {
                            uri = terminal_uri,
                            preferred_view = 'float',
                        },
                    },
                },
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            use_mksession = false,
        })

        arboretum.api.switch = original_switch
        consulate.api.set_current = original_set_current
        consulate.api.reopen_terminal = original_reopen_terminal
        terminalia.api.open_uri = original_open_uri

        assert.are.same({ 'arboretum', 'consulate', 'terminalia' }, plugin.api.contributor_names())
        assert.are.same({
            'session:cwd',
            'arboretum:1',
            'consulate:1',
            'consulate:2',
            'terminalia:1',
        }, report.executed_steps)
        assert.are.same({
            { kind = 'arboretum.switch', value = '/repo/feature' },
            { kind = 'consulate.use', value = 'ssh|devbox|/repo|/srv/project' },
            { kind = 'consulate.reopen_terminals', value = 'remoteterminal:1', view = 'float' },
            { kind = 'terminalia.reopen_terminals', value = terminal_uri, view = 'float' },
        }, calls)
    end)

    it('integrates real workspace providers for worktree plus devcontainer restore execution when available', function()
        if
            not repo_exists('arboretum.nvim')
            or not repo_exists('laboratory.nvim')
            or not repo_exists('terminalia.nvim')
        then
            assert.is_true(true)
            return
        end

        prepend_runtimepaths({
            'terminalia.nvim',
            'arboretum.nvim',
            'laboratory.nvim',
        })

        package.loaded.arboretum = nil
        package.loaded['arboretum.api'] = nil
        package.loaded.laboratory = nil
        package.loaded['laboratory.api'] = nil
        package.loaded.terminalia = nil
        package.loaded['terminalia.api'] = nil

        require('terminalia').setup({
            history_dir = vim.fn.tempname(),
            notify_on_exit = false,
            persist_terminals = false,
            state_file = vim.fn.tempname(),
        })

        require('arboretum').setup({
            notify = false,
            system_runner = function()
                error('unexpected git invocation in session integration test')
            end,
        })

        require('laboratory').setup({})

        local calls = {}
        local original_switch = arboretum.api.switch
        local original_set_current = laboratory.api.set_current
        local original_open_terminal = laboratory.api.open_terminal
        local original_open_uri = terminalia.api.open_uri

        arboretum.api.switch = function(options)
            table.insert(calls, {
                kind = 'arboretum.switch',
                value = options.path,
            })
            return {
                target = {
                    path = options.path,
                },
            }
        end
        laboratory.api.set_current = function(item)
            table.insert(calls, {
                kind = 'laboratory.select',
                value = item.id,
            })
            return item
        end
        laboratory.api.open_terminal = function(id, opts)
            table.insert(calls, {
                kind = 'laboratory.reopen_terminals',
                value = id,
                view = opts.view,
            })
            return {
                id = 'dev:' .. id,
            }
        end
        terminalia.api.open_uri = function(uri, opts)
            table.insert(calls, {
                kind = 'terminalia.reopen_terminals',
                value = uri,
                view = opts.view,
            })
            return {
                id = 'terminal:restored',
            }
        end

        local root = vim.fn.tempname()
        vim.fn.mkdir(root, 'p')

        local terminal_uri = require('terminalia.uri').encode_terminal_uri({
            id = 'terminal:9',
            name = 'build',
            context_id = 'context:host',
        })

        local saved = plugin.api.save({
            name = 'workspace-devcontainer-integration',
            cwd = root,
            contributors = {
                arboretum = {
                    current = {
                        path = '/repo/feature',
                        branch_ref = 'refs/heads/feature/demo',
                    },
                },
                laboratory = {
                    current = {
                        id = 'devcontainer:workspace',
                        name = 'workspace',
                        config_path = '/repo/.devcontainer/laboratory.json',
                    },
                    linked_terminals = {
                        {
                            id = 'devcontainerterminal:1',
                            view = 'float',
                        },
                    },
                },
                terminalia = {
                    current_context_id = 'context:dev',
                    terminals = {
                        {
                            uri = terminal_uri,
                            preferred_view = 'float',
                        },
                    },
                },
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            use_mksession = false,
        })

        arboretum.api.switch = original_switch
        laboratory.api.set_current = original_set_current
        laboratory.api.open_terminal = original_open_terminal
        terminalia.api.open_uri = original_open_uri

        assert.are.same({
            'session:cwd',
            'arboretum:1',
            'laboratory:1',
            'laboratory:2',
            'terminalia:1',
        }, report.executed_steps)
        assert.are.same({
            { kind = 'arboretum.switch', value = '/repo/feature' },
            { kind = 'laboratory.select', value = 'devcontainer:workspace' },
            { kind = 'laboratory.reopen_terminals', value = 'devcontainerterminal:1', view = 'float' },
            {
                kind = 'terminalia.reopen_terminals',
                value = terminal_uri,
                view = 'float',
            },
        }, calls)
    end)
end)
