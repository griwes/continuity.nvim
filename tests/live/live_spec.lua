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
        assert.are.equal(vim.api.nvim_win_get_width(0), live.state.nvim.tabs[1].windows[1].width)
        assert.are.equal(vim.api.nvim_win_get_height(0), live.state.nvim.tabs[1].windows[1].height)
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

    it('recaptures contributor-owned live state on layout events', function()
        local plugin = require('continuity')
        local value = 'alpha'

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 1000,
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
        vim.cmd('split')
        vim.cmd('close')

        assert.are.equal('beta', plugin.api.live_state().contributors.workspace.value)
        assert.is_nil(plugin.api.load('session:live'))
    end)

    it('flushes contributor-owned live state synchronously before exit', function()
        local plugin = require('continuity')
        local value = 'alpha'

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 1000,
            },
        })

        plugin.api.register_contributor('workspace', {
            capture = function()
                return {
                    value = value,
                }
            end,
        })

        value = 'final'
        vim.api.nvim_exec_autocmds('VimLeavePre', {
            modeline = false,
        })

        assert.are.equal('final', plugin.api.load('session:live').contributors.workspace.value)
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

    it('captures resized window dimensions on explicit save', function()
        local plugin = require('continuity')

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 1000,
            },
        })

        vim.cmd('split')
        vim.cmd('resize 5')

        local saved = plugin.api.capture()
        local heights = {}

        for _, tab in ipairs(saved.state.nvim.tabs or {}) do
            for _, win in ipairs(tab.windows or {}) do
                table.insert(heights, tonumber(win.height) or 0)
            end
        end

        table.sort(heights)

        assert.is_true(#heights >= 2)
        assert.is_true(heights[1] <= 7)
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

    it('captures the structured window layout in the live session', function()
        local plugin = require('continuity')

        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
        })

        vim.cmd('belowright split')
        plugin.api.sync_live_state()

        local live = assert(plugin.api.live_state())

        assert.are.equal('col', live.state.nvim.tabs[1].layout[1])
        assert.are.equal(2, #live.state.nvim.tabs[1].windows)
    end)

    it('refreshes live state only after restored windows are rebound to file buffers', function()
        local plugin = require('continuity')
        local root = vim.fn.tempname()
        local first = vim.fs.joinpath(root, 'first.txt')
        local second = vim.fs.joinpath(root, 'second.txt')

        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')
        vim.cmd('enew!')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'first' }, first)
        vim.fn.writefile({ 'second' }, second)
        vim.api.nvim_set_current_dir(root)

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
        })

        vim.cmd.edit(vim.fn.fnameescape(first))
        vim.cmd('belowright split')
        vim.cmd.edit(vim.fn.fnameescape(second))

        local saved = plugin.api.capture({
            id = 'two-file-windows',
            name = 'two-file-windows',
            cwd = root,
        })

        vim.cmd('silent! only!')
        vim.cmd('enew!')

        local report = plugin.api.execute_restore(saved.id)
        local live = assert(plugin.api.live_state())
        local persisted = assert(plugin.api.load('session:live'))
        local buffer_names = {}
        local visible = {}

        for _, buffer in ipairs(live.state.nvim.buffers or {}) do
            buffer_names[buffer.id] = buffer.name
        end

        for _, tab in ipairs(live.state.nvim.tabs or {}) do
            for _, win in ipairs(tab.windows or {}) do
                visible[vim.fs.normalize(buffer_names[win.buffer] or '')] = true
            end
        end

        assert.is_true(report.layout_restored)
        assert.are.equal(2, #live.state.nvim.tabs[1].windows)
        assert.is_true(visible[vim.fs.normalize(first)])
        assert.is_true(visible[vim.fs.normalize(second)])
        assert.are.same(live.state.nvim.tabs, persisted.state.nvim.tabs)
    end)

    it('does not persist hidden unnamed scratch buffers', function()
        local plugin = require('continuity')

        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')
        vim.cmd('enew!')

        local hidden = vim.api.nvim_create_buf(true, false)

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
        })

        plugin.api.sync_live_state()

        local saved_buffers = {}

        for _, buffer in ipairs(assert(plugin.api.live_state()).state.nvim.buffers or {}) do
            saved_buffers[buffer.id] = buffer
        end

        assert.is_true(vim.api.nvim_buf_is_valid(hidden))
        assert.is_nil(saved_buffers[hidden])
    end)

    it('uses a window last-file fallback for empty anonymous window buffers', function()
        local plugin = require('continuity')
        local root = vim.fn.tempname()
        local left = vim.fs.joinpath(root, 'left.txt')
        local right = vim.fs.joinpath(root, 'README.md')
        local other = vim.fs.joinpath(root, 'other.txt')

        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')
        vim.cmd('enew!')

        vim.fn.mkdir(root, 'p')
        vim.fn.writefile({ 'left' }, left)
        vim.fn.writefile({ 'right' }, right)
        vim.fn.writefile({ 'other' }, other)
        vim.api.nvim_set_current_dir(root)

        plugin.setup({
            state_file = state_file,
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
        })

        vim.cmd.edit(vim.fn.fnameescape(left))
        vim.cmd.vsplit(vim.fn.fnameescape(right))
        plugin.api.sync_live_state()

        vim.cmd.enew()
        vim.cmd.tabnew(vim.fn.fnameescape(other))

        local saved = plugin.api.capture({
            id = 'remember-file-window',
            name = 'remember-file-window',
            cwd = root,
        })
        local buffer_names = {}
        local visible = {}

        for _, buffer in ipairs(saved.state.nvim.buffers or {}) do
            buffer_names[buffer.id] = buffer.name
        end

        for _, win in ipairs(saved.state.nvim.tabs[1].windows or {}) do
            visible[vim.fs.normalize(buffer_names[win.buffer] or '')] = true
        end

        assert.is_true(visible[vim.fs.normalize(left)])
        assert.is_true(visible[vim.fs.normalize(right)])
    end)

    it('excludes floating UI windows and their unlisted buffers from builtin state capture', function()
        local plugin = require('continuity')

        vim.cmd('silent! tabonly!')
        vim.cmd('silent! only!')
        vim.cmd('enew')

        local uri_buffer = vim.api.nvim_get_current_buf()
        vim.bo[uri_buffer].buftype = 'nofile'
        vim.bo[uri_buffer].swapfile = false
        vim.api.nvim_buf_set_name(uri_buffer, 'acp://session/test')
        vim.bo[uri_buffer].buflisted = false

        local float_buffer = vim.api.nvim_create_buf(false, true)
        vim.bo[float_buffer].filetype = 'incline'
        local float_win = vim.api.nvim_open_win(float_buffer, false, {
            relative = 'editor',
            row = 1,
            col = 1,
            width = 12,
            height = 1,
            style = 'minimal',
        })

        plugin.setup({
            state_file = state_file,
        })

        local saved = plugin.api.capture()
        local saved_buffers = {}

        for _, buffer in ipairs(saved.state.nvim.buffers or {}) do
            saved_buffers[buffer.id] = buffer
        end

        assert.are.equal(1, #saved.state.nvim.tabs[1].windows)
        assert.are.equal(uri_buffer, saved.state.nvim.tabs[1].windows[1].buffer)
        assert.is_not_nil(saved_buffers[uri_buffer])
        assert.is_nil(saved_buffers[float_buffer])

        pcall(vim.api.nvim_win_close, float_win, true)
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

    it('does not write Vim session files for auto live sessions', function()
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

        plugin.api.sync_live_state()

        local live = assert(plugin.api.live_state())

        vim.api.nvim_set_current_dir(original_cwd)

        assert.is_not_nil(plugin.api.load(live.id))
    end)
end)
