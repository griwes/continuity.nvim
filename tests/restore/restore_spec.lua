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

    local function reset_modules()
        package.loaded.continuity = nil
        package.loaded['continuity.api'] = nil
        package.loaded['continuity.core.builtin_state'] = nil
        package.loaded['continuity.core.config'] = nil
        package.loaded['continuity.contributors.registry'] = nil
        package.loaded['continuity.core.model'] = nil
        package.loaded['continuity.live.state'] = nil
        package.loaded['continuity.persistence.shada'] = nil
        package.loaded['continuity.restore.layout'] = nil
        package.loaded['continuity.restore.plan'] = nil
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.persistence.storage'] = nil
    end

    local function setup_plugin(opts)
        local plugin = require('continuity')

        plugin.setup(vim.tbl_deep_extend('force', {
            state_file = state_file,
            shada = {
                external_policy = 'ignore',
            },
        }, opts or {}))
        plugin.api.clear()

        return plugin
    end

    ---@param layout any
    ---@return any
    local function layout_buffer_names(layout)
        if type(layout) ~= 'table' then
            return layout
        end

        if layout[1] == 'leaf' then
            local win = tonumber(layout[2])
            local name = win ~= nil and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) or ''

            return { 'leaf', vim.fs.basename(name) }
        end

        local children = {}
        for _, child in ipairs(layout[2] or {}) do
            table.insert(children, layout_buffer_names(child))
        end

        return { layout[1], children }
    end

    before_each(function()
        reset_modules()
        state_file = vim.fn.tempname()
        setup_plugin()
        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')
        vim.cmd('enew!')
    end)

    it('executes restore steps through contributor-owned restore callbacks around layout restore', function()
        local plugin = setup_plugin()
        local calls = {}
        local root = vim.fn.tempname()
        local file = vim.fs.joinpath(root, 'target.txt')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'target' }, file)

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
        plugin.api.register_contributor('terminalia', {
            restore_phase = 'after_layout',
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
                table.insert(calls, step.kind .. ':' .. #vim.api.nvim_list_wins())
            end,
        })

        local saved = plugin.api.save({
            id = 'restore-order',
            name = 'restore-order',
            cwd = root,
            state = {
                nvim = {
                    buffers = {
                        {
                            id = 1,
                            name = file,
                            listed = true,
                            loaded = true,
                            modified = false,
                            buftype = '',
                        },
                    },
                    tabs = {
                        {
                            id = 1,
                            current = true,
                            layout = { 'leaf', 1001 },
                            windows = {
                                {
                                    id = 1001,
                                    buffer = 1,
                                    current = true,
                                },
                            },
                        },
                    },
                },
            },
            contributors = {
                workspace = {},
                terminalia = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })

        assert.are.same({ 'session:cwd', 'workspace:1', 'terminalia:1' }, report.executed_steps)
        assert.is_true(report.layout_restored)
        assert.are.same({ 'workspace.select', 'terminalia.reopen_terminals:1' }, calls)
    end)

    it('reasserts restored window buffers after post-layout contributors mutate tabpages', function()
        local plugin = setup_plugin()
        local root = vim.fn.tempname()
        local first = vim.fs.joinpath(root, 'first.txt')
        local second = vim.fs.joinpath(root, 'second.txt')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'first' }, first)
        vim.fn.writefile({ 'second' }, second)

        plugin.api.register_contributor('tab_model', {
            restore_phase = 'after_layout',
            plan_restore = function()
                return {
                    {
                        kind = 'tab_model.restore',
                        title = 'Restore tab model',
                    },
                }
            end,
            restore = function()
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                    vim.api.nvim_win_set_buf(win, vim.api.nvim_create_buf(true, false))
                end
            end,
        })

        local saved = plugin.api.save({
            id = 'post-layout-buffer-rebind',
            name = 'post-layout-buffer-rebind',
            cwd = root,
            state = {
                nvim = {
                    buffers = {
                        {
                            id = 1,
                            name = first,
                            listed = true,
                            loaded = true,
                            modified = false,
                            buftype = '',
                        },
                        {
                            id = 2,
                            name = second,
                            listed = true,
                            loaded = true,
                            modified = false,
                            buftype = '',
                        },
                    },
                    tabs = {
                        {
                            id = 1,
                            current = true,
                            layout = { 'row', { { 'leaf', 1001 }, { 'leaf', 1002 } } },
                            windows = {
                                {
                                    id = 1001,
                                    buffer = 1,
                                },
                                {
                                    id = 1002,
                                    buffer = 2,
                                    current = true,
                                },
                            },
                        },
                    },
                },
            },
            contributors = {
                tab_model = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })
        local visible = {}

        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local name = vim.fs.normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))

            visible[name] = true
        end

        assert.is_true(report.layout_restored)
        assert.is_true(visible[vim.fs.normalize(first)])
        assert.is_true(visible[vim.fs.normalize(second)])
    end)

    it('reports manual restore steps when a contributor has no restore callback', function()
        local plugin = setup_plugin()
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
            force_current = true,
        })

        assert.are.same({ 'session:cwd' }, report.executed_steps)
        assert.are.equal(1, #report.manual_steps)
        assert.are.equal('consulate.use', report.manual_steps[1].kind)
    end)

    it('captures and restores builtin layout for named saves without continuous mode', function()
        local plugin = setup_plugin()
        local root = vim.fn.tempname()
        local first = vim.fs.joinpath(root, 'first.txt')
        local second = vim.fs.joinpath(root, 'second.txt')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'first' }, first)
        vim.fn.writefile({ 'second' }, second)
        vim.api.nvim_set_current_dir(root)

        vim.cmd.edit(vim.fn.fnameescape(first))
        vim.cmd('belowright split')
        vim.cmd.edit(vim.fn.fnameescape(second))
        vim.cmd('resize 5')

        local saved = plugin.api.capture({
            id = 'structured-split',
            name = 'structured-split',
            cwd = root,
        })

        assert.is_not_nil(saved.state.nvim)

        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')
        vim.cmd('enew!')

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })
        local visible = {}
        local heights = {}

        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local name = vim.fs.normalize(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)))

            visible[name] = true
            table.insert(heights, vim.api.nvim_win_get_height(win))
        end

        table.sort(heights)

        assert.is_true(report.layout_restored)
        assert.are.equal(2, #vim.api.nvim_list_wins())
        assert.is_true(visible[vim.fs.normalize(first)])
        assert.is_true(visible[vim.fs.normalize(second)])
        assert.is_true(heights[1] < heights[2])
    end)

    it('restores nested mixed-axis split trees without flattening sibling regions', function()
        local plugin = setup_plugin()
        local root = vim.fn.tempname()
        local left_top = vim.fs.joinpath(root, 'left-top.txt')
        local left_bottom = vim.fs.joinpath(root, 'left-bottom.txt')
        local right = vim.fs.joinpath(root, 'right.txt')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'left-top' }, left_top)
        vim.fn.writefile({ 'left-bottom' }, left_bottom)
        vim.fn.writefile({ 'right' }, right)

        vim.cmd.edit(vim.fn.fnameescape(left_top))
        vim.cmd.vsplit(vim.fn.fnameescape(right))
        vim.cmd.wincmd('h')
        vim.cmd.split(vim.fn.fnameescape(left_bottom))

        local saved = plugin.api.capture({
            id = 'nested-layout',
            name = 'nested-layout',
            cwd = root,
        })
        local saved_shape = layout_buffer_names(saved.state.nvim.tabs[1].layout)

        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')
        vim.cmd('enew!')

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })
        local restored_shape = layout_buffer_names(vim.fn.winlayout())

        assert.is_true(report.layout_restored)
        assert.are.same(saved_shape, restored_shape)
    end)

    it('restores captured hidden listed buffers even when they are not visible in a window', function()
        local plugin = setup_plugin()
        local root = vim.fn.tempname()
        local visible = vim.fs.joinpath(root, 'visible.txt')
        local hidden = vim.fs.joinpath(root, 'hidden.txt')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'visible' }, visible)
        vim.fn.writefile({ 'hidden' }, hidden)

        vim.cmd.edit(vim.fn.fnameescape(visible))
        local hidden_buf = vim.fn.bufadd(hidden)
        vim.fn.bufload(hidden_buf)

        local saved = plugin.api.capture({
            id = 'hidden-buffer',
            name = 'hidden-buffer',
            cwd = root,
        })

        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            pcall(vim.api.nvim_buf_delete, bufnr, {
                force = true,
            })
        end
        vim.cmd('enew!')

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })
        local found_hidden = false

        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == vim.fs.normalize(hidden) then
                found_hidden = true
                break
            end
        end

        assert.is_true(report.layout_restored)
        assert.is_true(found_hidden)
    end)

    it('restores structured tabs and the selected tab', function()
        local plugin = setup_plugin({
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
        })
        local root = vim.fn.tempname()
        local first = vim.fs.joinpath(root, 'first.txt')
        local second = vim.fs.joinpath(root, 'second.txt')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'first' }, first)
        vim.fn.writefile({ 'second' }, second)

        vim.cmd.edit(vim.fn.fnameescape(first))
        vim.cmd.tabnew(vim.fn.fnameescape(second))

        local saved = plugin.api.capture({
            id = 'structured-tabs',
            name = 'structured-tabs',
            cwd = root,
        })

        vim.cmd('silent! tabonly!')
        vim.cmd('enew!')

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })

        assert.is_true(report.layout_restored)
        assert.are.equal(2, #vim.api.nvim_list_tabpages())
        assert.are.equal(vim.fs.normalize(second), vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
    end)

    it('restores URI-named nofile buffers as structured placeholders', function()
        local plugin = setup_plugin()
        local uri = 'legate://session/demo'

        local saved = plugin.api.save({
            id = 'uri-buffer',
            name = 'uri-buffer',
            state = {
                nvim = {
                    buffers = {
                        {
                            id = 1,
                            name = uri,
                            listed = true,
                            loaded = true,
                            modified = false,
                            buftype = 'nofile',
                            filetype = 'legate',
                        },
                    },
                    tabs = {
                        {
                            id = 1,
                            current = true,
                            layout = { 'leaf', 1001 },
                            windows = {
                                {
                                    id = 1001,
                                    buffer = 1,
                                    current = true,
                                },
                            },
                        },
                    },
                },
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })

        assert.is_true(report.layout_restored)
        assert.are.equal(uri, vim.api.nvim_buf_get_name(0))
        assert.are.equal('nofile', vim.bo[0].buftype)
    end)

    it('restores jump and change list contents through synthetic ShaDa', function()
        local plugin = setup_plugin()
        local root = vim.fn.tempname()
        local file = vim.fs.joinpath(root, 'target.txt')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'one', 'two', 'three' }, file)

        local saved = plugin.api.save({
            id = 'shada-restore',
            name = 'shada-restore',
            state = {
                nvim = {
                    buffers = {
                        {
                            id = 1,
                            name = file,
                            listed = true,
                            loaded = true,
                            modified = false,
                            buftype = '',
                            changelist = {
                                items = {
                                    {
                                        lnum = 2,
                                        col = 0,
                                    },
                                },
                            },
                        },
                    },
                    tabs = {
                        {
                            id = 1,
                            current = true,
                            layout = { 'leaf', 1001 },
                            windows = {
                                {
                                    id = 1001,
                                    buffer = 1,
                                    current = true,
                                    jumplist = {
                                        items = {
                                            {
                                                filename = file,
                                                lnum = 3,
                                                col = 0,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })
        local jumps = vim.fn.getjumplist()[1]
        local changes = vim.fn.getchangelist(vim.api.nvim_get_current_buf())[1]

        assert.is_true(report.layout_restored)
        assert.are.equal(3, jumps[#jumps].lnum)
        assert.are.equal(2, changes[#changes].lnum)
    end)

    it('normalizes after-layout dependency edges to avoid ordering failures', function()
        local plugin = setup_plugin()
        local calls = {}

        plugin.api.register_contributor('terminalia', {
            restore_phase = 'after_layout',
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
        plugin.api.register_contributor('workspace', {
            restore_after = { 'terminalia' },
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

        local saved = plugin.api.save({
            name = 'ordered-normalized-cross-phase',
            contributors = {
                terminalia = {},
                workspace = {},
            },
        })

        local report = plugin.api.execute_restore(saved.id, {
            force_current = true,
        })

        assert.are.same({ 'session:cwd', 'terminalia:1', 'workspace:1' }, report.executed_steps)
        assert.are.same({ 'terminalia.reopen_terminals', 'workspace.select' }, calls)
    end)

    it('integrates real dogfood providers including Tabulature hierarchy replay when available', function()
        if
            not repo_exists('arboretum.nvim')
            or not repo_exists('consulate.nvim')
            or not repo_exists('laboratory.nvim')
            or not repo_exists('tabulature.nvim')
            or not repo_exists('terminalia.nvim')
        then
            assert.is_true(true)
            return
        end

        prepend_runtimepaths({
            'terminalia.nvim',
            'arboretum.nvim',
            'consulate.nvim',
            'laboratory.nvim',
            'tabulature.nvim',
        })

        package.loaded.arboretum = nil
        package.loaded['arboretum.api'] = nil
        package.loaded.consulate = nil
        package.loaded['consulate.api'] = nil
        package.loaded.laboratory = nil
        package.loaded['laboratory.api'] = nil
        package.loaded.tabulature = nil
        package.loaded['tabulature.session'] = nil
        package.loaded['tabulature.state'] = nil
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
        require('laboratory').setup({})
        require('tabulature').setup({
            commands = false,
            manifold = false,
            theme = false,
        })

        local calls = {}
        local original_switch = arboretum.api.switch
        local original_consulate_set_current = consulate.api.set_current
        local original_consulate_reopen_terminal = consulate.api.reopen_terminal
        local original_laboratory_set_current = laboratory.api.set_current
        local original_laboratory_open_terminal = laboratory.api.open_terminal
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
            id = 'terminal:dogfood',
            name = 'build',
            context_id = 'context:host',
        })

        local saved = plugin.api.save({
            name = 'dogfood-all-provider-integration',
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
                tabulature = {
                    version = 1,
                    children = {
                        {
                            label = 'Workspace',
                            selected_child_index = 1,
                            children = {
                                {
                                    label = 'Editor',
                                    active = true,
                                },
                            },
                        },
                    },
                },
                terminalia = {
                    current_context_id = 'context:host',
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
            force_current = true,
        })
        local tab_tree = require('tabulature.state').to_tree()

        arboretum.api.switch = original_switch
        consulate.api.set_current = original_consulate_set_current
        consulate.api.reopen_terminal = original_consulate_reopen_terminal
        laboratory.api.set_current = original_laboratory_set_current
        laboratory.api.open_terminal = original_laboratory_open_terminal
        terminalia.api.open_uri = original_open_uri

        assert.are.same({
            'arboretum',
            'consulate',
            'laboratory',
            'tabulature',
            'terminalia',
        }, plugin.api.contributor_names())
        assert.are.same({
            'session:cwd',
            'arboretum:1',
            'consulate:1',
            'consulate:2',
            'laboratory:1',
            'laboratory:2',
            'tabulature:1',
            'terminalia:1',
        }, report.executed_steps)
        assert.are.same({
            { kind = 'arboretum.switch', value = '/repo/feature' },
            { kind = 'consulate.use', value = 'ssh|devbox|/repo|/srv/project' },
            { kind = 'consulate.reopen_terminals', value = 'remoteterminal:1', view = 'float' },
            { kind = 'laboratory.select', value = 'devcontainer:workspace' },
            { kind = 'laboratory.reopen_terminals', value = 'devcontainerterminal:1', view = 'float' },
            { kind = 'terminalia.reopen_terminals', value = terminal_uri, view = 'float' },
        }, calls)
        assert.are.equal('Workspace', tab_tree.children[1].label)
        assert.are.equal('Editor', tab_tree.children[1].children[1].label)
        assert.is_true(tab_tree.children[1].children[1].active)
    end)
end)
