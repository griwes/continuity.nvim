local api = require('continuity.api')

local M = {}

local registered = false

---@param message string
local function present(message)
    vim.notify(message)
end

---@param value string
---@return string?
local function non_empty(value)
    local trimmed = vim.trim(value)
    return trimmed ~= '' and trimmed or nil
end

---@param session continuity.Record
---@return string
local function session_label(session)
    return string.format('%s (%s)', session.name, session.id)
end

---@param command string
---@param rhs fun(opts: vim.api.keyset.create_user_command.command_args)
---@param opts vim.api.keyset.create_user_command
local function create(command, rhs, opts)
    if vim.api.nvim_get_commands({
        builtin = false,
    })[command] ~= nil then
        pcall(vim.api.nvim_del_user_command, command)
    end

    vim.api.nvim_create_user_command(command, rhs, opts)
end

---@param arglead string
---@return string[]
local function session_id_completions(arglead)
    local results = {}

    for _, session in ipairs(api.list()) do
        if vim.startswith(session.id, arglead) then
            table.insert(results, session.id)
        end
    end

    return results
end

---@param prompt string
---@param on_choice fun(item: continuity.SessionItem)
local function select_session(prompt, on_choice)
    local items = api.session_items()

    if #items == 0 then
        present('No Continuity sessions saved')
        return
    end

    vim.ui.select(items, {
        prompt = prompt,
        format_item = function(item)
            return item.label
        end,
    }, function(choice)
        if choice == nil then
            return
        end

        on_choice(choice)
    end)
end

---@param id string
local function load_session(id)
    local report = api.execute_restore(id)
    present(string.format('Loaded Continuity session %s', report.session_id))
end

---@param id string
local function delete_session(id)
    local deleted = api.delete(id)

    if deleted == nil then
        error(string.format('No Continuity session with id %s', id))
    end

    present(string.format('Deleted Continuity session %s', session_label(deleted)))
end

---Register Continuity user commands.
---@param root continuity.RootModule
function M.ensure(root)
    if registered then
        return
    end

    create('ContinuitySave', function(opts)
        local saved = root.api.capture({
            name = non_empty(opts.args),
        })

        present(string.format('Saved Continuity session %s', session_label(saved)))
    end, {
        nargs = '*',
        desc = 'Save the current Continuity session: [name]',
    })

    create('ContinuityList', function()
        select_session('Continuity sessions', function(item)
            present(item.label)
        end)
    end, {
        nargs = 0,
        desc = 'Pick and inspect saved Continuity sessions',
    })

    create('ContinuityLoad', function(opts)
        local id = non_empty(opts.args)

        if id ~= nil then
            load_session(id)
            return
        end

        select_session('Load Continuity session', function(item)
            load_session(item.id)
        end)
    end, {
        nargs = '?',
        desc = 'Load a Continuity session: [id]',
        complete = session_id_completions,
    })

    create('ContinuityDelete', function(opts)
        local id = non_empty(opts.args)

        if id ~= nil then
            delete_session(id)
            return
        end

        select_session('Delete Continuity session', function(item)
            delete_session(item.id)
        end)
    end, {
        nargs = '?',
        desc = 'Delete a Continuity session: [id]',
        complete = session_id_completions,
    })

    create('ContinuityCurrent', function()
        local current = root.api.current_session_key()
        local live = root.api.live_state()
        local message = string.format('Current Continuity key: %s  cwd=%s', current.id, current.cwd)

        if current.branch ~= nil then
            message = message .. string.format('  branch=%s', current.branch)
        end

        if live ~= nil then
            message = message .. string.format('  live=%s', live.id)
        end

        present(message)
    end, {
        nargs = 0,
        desc = 'Show the current Continuity session key and live session',
    })

    registered = true
end

return M
