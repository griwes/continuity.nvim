describe('Terminalia integration', function()
    if vim.env.CONTINUITY_REQUIRE_TERMINALIA_INTEGRATION ~= '1' then
        it('requires the explicit integration gate', function()
            pending('set CONTINUITY_REQUIRE_TERMINALIA_INTEGRATION=1 to run the Terminalia integration gate')
        end)
        return
    end

    local continuity
    local terminalia
    local continuity_state_file
    local terminalia_state_file
    local terminalia_history_dir

    before_each(function()
        continuity_state_file = vim.fn.tempname()
        terminalia_state_file = vim.fn.tempname()
        terminalia_history_dir = vim.fn.tempname()

        continuity = require('continuity')
        continuity.setup({
            state_file = continuity_state_file,
            autoload = {
                policy = 'disabled',
            },
            continuous = {
                enabled = false,
            },
            shada = {
                external_policy = 'ignore',
            },
        })
        continuity.api.clear({
            wipe_contributors = true,
        })

        terminalia = require('terminalia')
        terminalia.setup({
            enable_editor_shell_integration = false,
            enable_parent_nvim_redirect = false,
            history_dir = terminalia_history_dir,
            notify_on_exit = false,
            persist_history = false,
            persist_terminals = true,
            state_file = terminalia_state_file,
        })
    end)

    after_each(function()
        if terminalia ~= nil then
            terminalia.api.clear()
        end
        if continuity ~= nil then
            continuity.api.clear({
                wipe_contributors = true,
            })
        end
        if continuity_state_file ~= nil then
            vim.fn.delete(continuity_state_file)
            vim.fn.delete(continuity_state_file .. '.d', 'rf')
        end
        if terminalia_state_file ~= nil then
            vim.fn.delete(terminalia_state_file)
            vim.fn.delete(terminalia_state_file .. '.d', 'rf')
        end
        if terminalia_history_dir ~= nil then
            vim.fn.delete(terminalia_history_dir, 'rf')
        end
    end)

    it('captures immutable terminal state and executes its restore plan', function()
        local created = terminalia.api.create_and_open({
            command = { 'sh' },
            cwd = vim.uv.cwd(),
            name = 'continuity-integration',
            preferred_view = 'split',
        })
        local saved = continuity.api.capture({
            id = 'terminalia-integration',
            name = 'Terminalia integration',
        })
        local captured = assert(saved.contributors.terminalia)
        local captured_terminal = assert(captured.terminals[1])

        assert.are.equal(2, captured.version)
        assert.are.equal('context:host', captured.current_context_id)
        assert.are.equal(1, #captured.contexts)
        assert.are.equal('context:host', captured.contexts[1].id)
        assert.are.equal(created.id, captured_terminal.id)
        assert.are.equal('continuity-integration', captured_terminal.name)
        assert.are.equal('context:host', captured_terminal.context_id)
        assert.are.same({ 'sh' }, captured_terminal.command)
        assert.is_true(captured_terminal.restart)
        assert.is_true(type(captured_terminal.instance_id) == 'string' and captured_terminal.instance_id ~= '')
        assert.is_true(type(captured_terminal.uri) == 'string' and captured_terminal.uri ~= '')
        assert.is_nil(captured.state_ref)
        assert.is_nil(captured.terminal_ids)

        terminalia.api.clear({
            wipe_storage = false,
            reset_setup_state = false,
        })
        assert.is_nil(terminalia.api.get(created.id))

        local report = continuity.api.execute_restore(saved.id, {
            force_current = true,
            restore_layout = false,
        })
        local restored = assert(terminalia.api.get(created.id))

        assert.are.same({ 'session:cwd', 'terminalia:1' }, report.executed_steps)
        assert.are.equal('continuity-integration', restored.name)
    end)
end)
