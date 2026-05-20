describe('continuity commands', function()
    local notifications
    local original_cwd
    local original_notify
    local original_select
    local state_file

    local function reset_modules()
        package.loaded.continuity = nil
        package.loaded['continuity.api'] = nil
        package.loaded['continuity.contributors.registry'] = nil
        package.loaded['continuity.core.config'] = nil
        package.loaded['continuity.core.model'] = nil
        package.loaded['continuity.core.session_items'] = nil
        package.loaded['continuity.core.session_key'] = nil
        package.loaded['continuity.live.state'] = nil
        package.loaded['continuity.persistence.storage'] = nil
        package.loaded['continuity.restore.autoload'] = nil
        package.loaded['continuity.restore.execute'] = nil
        package.loaded['continuity.restore.plan'] = nil
        package.loaded['continuity.ui.commands'] = nil
    end

    ---@param path string
    ---@return string
    local function mkdir(path)
        vim.fn.mkdir(path, 'p')
        return vim.fs.normalize(path)
    end

    ---@param opts? table
    ---@param helper_opts? { clear?: boolean }
    ---@return continuity.RootModule
    local function setup(opts, helper_opts)
        reset_modules()

        local plugin = require('continuity')

        plugin.setup(vim.tbl_deep_extend('force', {
            state_file = state_file,
        }, opts or {}))

        if helper_opts == nil or helper_opts.clear ~= false then
            plugin.api.clear()
        end

        return plugin
    end

    before_each(function()
        original_cwd = vim.fn.getcwd()
        original_notify = vim.notify
        original_select = vim.ui.select
        state_file = vim.fn.tempname()
        notifications = {}
        vim.notify = function(message)
            table.insert(notifications, message)
        end
        reset_modules()
    end)

    after_each(function()
        vim.api.nvim_set_current_dir(original_cwd)
        vim.notify = original_notify
        vim.ui.select = original_select
        reset_modules()
    end)

    it('registers user commands when the plugin loads', function()
        setup()

        local commands = vim.api.nvim_get_commands({
            builtin = false,
        })

        assert.is_not_nil(commands.ContinuitySave)
        assert.is_not_nil(commands.ContinuityList)
        assert.is_not_nil(commands.ContinuityLoad)
        assert.is_not_nil(commands.ContinuityDelete)
        assert.is_not_nil(commands.ContinuityCurrent)
    end)

    it('exposes structured picker items for saved sessions', function()
        local plugin = setup()
        local cwd = mkdir(vim.fn.tempname())
        local saved = plugin.api.save({
            name = 'alpha',
            cwd = cwd,
        })

        local item = plugin.api.session_items()[1]

        assert.are.equal(saved.id, item.id)
        assert.are.equal(saved.id, item.value)
        assert.are.equal('alpha', item.name)
        assert.are.equal(cwd, item.cwd)
        assert.is_true(item.is_last)
        assert.is_true(item.ordinal:find('alpha', 1, true) ~= nil)
        assert.are.same({ item.label }, plugin.api.session_lines())
    end)

    it('exposes clean snapshots as loadable picker items', function()
        local plugin = setup({
            continuous = {
                enabled = true,
                write_debounce_ms = 0,
            },
        }, {
            clear = false,
        })

        local saved = plugin.api.capture({
            name = 'alpha',
        })
        local clean_id = saved.id .. '::clean'
        local clean_item

        for _, item in ipairs(plugin.api.session_items()) do
            if item.id == clean_id then
                clean_item = item
                break
            end
        end

        assert.is_not_nil(clean_item)
        assert.are.equal(clean_id, clean_item.value)
        assert.are.equal('clean', clean_item.snapshot_kind)
        assert.are.equal(saved.id, clean_item.base_id)
        assert.is_true(clean_item.label:find('clean', 1, true) ~= nil)
    end)

    it('saves the current session through ContinuitySave', function()
        local plugin = setup()

        vim.cmd('ContinuitySave dogfood command')

        local sessions = plugin.api.list()

        assert.are.equal(1, #sessions)
        assert.are.equal('dogfood command', sessions[1].name)
        assert.is_true(notifications[#notifications]:find('Saved Continuity session', 1, true) ~= nil)
    end)

    it('loads an explicit session id through ContinuityLoad', function()
        local plugin = setup()
        local target = mkdir(vim.fn.tempname())
        local saved = plugin.api.save({
            name = 'target',
            cwd = target,
        })

        vim.cmd('ContinuityLoad ' .. saved.id)

        assert.are.equal(target, vim.fn.getcwd())
        assert.is_true(notifications[#notifications]:find(saved.id, 1, true) ~= nil)
    end)

    it('does not reload the currently active live session through ContinuityLoad', function()
        local target = mkdir(vim.fn.tempname())
        local plugin = setup({
            continuous = {
                enabled = true,
                session_id = 'session:active-command',
            },
        }, {
            clear = false,
        })

        plugin.api.save({
            id = 'session:active-command',
            name = 'active',
            cwd = target,
        })

        vim.cmd('ContinuityLoad session:active-command')

        assert.are.equal(original_cwd, vim.fn.getcwd())
        assert.are.equal('Continuity session session:active-command is already active', notifications[#notifications])
    end)

    it('loads a picked session when ContinuityLoad receives no id', function()
        local plugin = setup()
        local target = mkdir(vim.fn.tempname())
        local saved = plugin.api.save({
            name = 'target',
            cwd = target,
        })

        vim.ui.select = function(items, _, on_choice)
            assert.are.equal(saved.id, items[1].id)
            on_choice(items[1])
        end

        vim.cmd('ContinuityLoad')

        assert.are.equal(target, vim.fn.getcwd())
    end)

    it('deletes a picked session through ContinuityDelete', function()
        local plugin = setup()
        local saved = plugin.api.save({
            name = 'delete-me',
        })

        vim.ui.select = function(items, _, on_choice)
            assert.are.equal(saved.id, items[1].id)
            on_choice(items[1])
        end

        vim.cmd('ContinuityDelete')

        assert.are.equal(0, #plugin.api.list())
        assert.is_true(notifications[#notifications]:find('Deleted Continuity session', 1, true) ~= nil)
    end)

    it('deletes an explicit session id through ContinuityDelete', function()
        local plugin = setup()
        local saved = plugin.api.save({
            name = 'delete-me',
        })

        vim.cmd('ContinuityDelete ' .. saved.id)

        assert.are.equal(0, #plugin.api.list())
    end)

    it('handles empty and cancelled pickers without side effects', function()
        local plugin = setup()

        vim.cmd('ContinuityList')

        assert.are.equal('No Continuity sessions saved', notifications[#notifications])

        local saved = plugin.api.save({
            name = 'keep-me',
        })

        vim.ui.select = function(_, _, on_choice)
            on_choice(nil)
        end

        vim.cmd('ContinuityDelete')

        assert.is_not_nil(plugin.api.load(saved.id))
    end)

    it('shows the current session key', function()
        setup()

        vim.cmd('ContinuityCurrent')

        assert.is_true(notifications[#notifications]:find('Current Continuity key:', 1, true) ~= nil)
    end)

    it('shows the live session when continuous saving is enabled', function()
        setup({
            continuous = {
                enabled = true,
                session_id = 'session:live-command',
            },
        }, {
            clear = false,
        })

        vim.cmd('ContinuityCurrent')

        assert.is_true(notifications[#notifications]:find('live=session:live-command', 1, true) ~= nil)
    end)
end)
