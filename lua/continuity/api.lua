local contributors = require('continuity.contributors.registry')
local builtin_state = require('continuity.core.builtin_state')
local live = require('continuity.live.state')
local autoload = require('continuity.restore.autoload')
local restore_execute = require('continuity.restore.execute')
local restore_plan = require('continuity.restore.plan')
local session_key = require('continuity.core.session_key')
local session_items = require('continuity.core.session_items')
local storage = require('continuity.persistence.storage')

local M = {}

---@param name string
---@param contributor continuity.Contributor
---@param record continuity.Record
local function restore_late_contributor(name, contributor, record)
    local captured = contributors.normalize_captured(record.contributors or {})[name]

    if captured == nil or type(contributor.plan_restore) ~= 'function' or type(contributor.restore) ~= 'function' then
        return
    end

    local fragment = contributor.plan_restore(vim.deepcopy(captured), vim.deepcopy(record))
    local steps = type(fragment) == 'table' and fragment.steps or fragment

    if type(steps) ~= 'table' then
        return
    end

    for _, step in ipairs(steps) do
        if type(step) == 'table' and step.manual ~= true then
            contributor.restore(vim.deepcopy(step), vim.deepcopy(record), {
                late_registration = true,
                restore_layout = false,
            })
        end
    end
end

---@param name string
---@param contributor continuity.Contributor
local function restore_pending_autoload_contributor(name, contributor)
    local report = autoload.last_report()

    if report == nil or report.loaded ~= true or type(report.session_id) ~= 'string' then
        return
    end

    local record = storage.get(report.session_id)

    if record == nil then
        return
    end

    for _, step in ipairs(report.execution and report.execution.manual_steps or {}) do
        if step.contributor == name and step.kind == 'continuity.unknown_contributor' then
            local function restore()
                restore_late_contributor(name, contributor, record)
            end

            if vim.v.vim_did_enter == 1 then
                restore()
            else
                vim.api.nvim_create_autocmd('VimEnter', {
                    once = true,
                    callback = function()
                        vim.schedule(restore)
                    end,
                })
            end
            return
        end
    end
end

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any>, contributors?: table<string, any> }
---@return continuity.Record
function M.save(opts)
    local current = live.record()
    local saved

    if opts ~= nil and opts.id ~= nil then
        saved = storage.save(opts)
    else
        saved = storage.create(opts)
    end

    if current ~= nil and saved.id == current.id then
        storage.save_clean_snapshot(saved)
    end

    return saved
end

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any> }
---@return continuity.Record
function M.capture(opts)
    live.refresh_all()

    local payload = {
        cwd = vim.uv.cwd() or vim.fn.getcwd(),
        state = {
            nvim = builtin_state.capture(),
        },
        contributors = contributors.capture(),
    }
    local current = live.record()

    if current ~= nil then
        payload = vim.tbl_deep_extend('force', current, payload)
    end

    payload = vim.tbl_deep_extend('force', payload, opts or {})

    return M.save(payload)
end

---@param id string
---@return continuity.Record?
function M.load(id)
    return storage.get(id)
end

---@return continuity.Record[]
function M.list()
    return storage.list()
end

---@return continuity.SessionItem[]
function M.session_items()
    return session_items.items()
end

---@return string[]
function M.session_lines()
    return session_items.lines()
end

---@param id string
---@return continuity.Record?
function M.delete(id)
    return storage.delete(id)
end

---@return continuity.Record[]
function M.restore()
    return storage.restore()
end

---@param opts? { cwd?: string, use_git_branch?: boolean }
---@return continuity.SessionKey
function M.current_session_key(opts)
    return session_key.current(opts)
end

---@return continuity.AutoloadReport
function M.autoload()
    return autoload.run()
end

---@param session_ref string|continuity.Record
---@return continuity.RestorePlan
function M.plan_restore(session_ref)
    local record = type(session_ref) == 'string' and storage.get(session_ref) or session_ref

    assert(record ~= nil, 'Could not resolve a saved session to plan restore from')

    return restore_plan.build(vim.deepcopy(record))
end

---@param session_ref string|continuity.Record
---@return boolean
function M.is_current_session(session_ref)
    local record = type(session_ref) == 'string' and storage.get(session_ref) or session_ref
    local current = live.record()

    return record ~= nil and current ~= nil and record.id == current.id
end

---@param session_ref string|continuity.Record
---@param opts? { force_current?: boolean, restore_layout?: boolean }
---@return continuity.RestoreExecutionReport
function M.execute_restore(session_ref, opts)
    local record = type(session_ref) == 'string' and storage.get(session_ref) or session_ref

    if record == nil then
        error('Could not resolve a saved session to execute restore from')
    end

    if opts == nil or opts.force_current ~= true then
        local current = live.record()

        if current ~= nil and current.id == record.id then
            error(string.format('Refusing to restore currently active Continuity session %s', record.id))
        end
    end

    return live.with_suspended(function()
        return restore_execute.execute(vim.deepcopy(record), nil, opts)
    end, {
        refresh_after = true,
    })
end

---@return continuity.Record?
function M.live_state()
    return live.record()
end

function M.sync_live_state()
    live.refresh_all()
end

---@param name string
function M.notify_contributor_changed(name)
    live.notify_contributor_changed(name)
end

---@param opts? { wipe_storage?: boolean, wipe_contributors?: boolean }
function M.clear(opts)
    live.clear(opts)
    storage.clear(opts)
    if opts ~= nil and opts.wipe_contributors == true then
        contributors.clear()
    end
end

---@param name string
---@param contributor continuity.Contributor
function M.register_contributor(name, contributor)
    contributors.register(name, contributor)
    restore_pending_autoload_contributor(name, contributor)

    if
        require('continuity.core.config').get().continuous.enabled == true
        and type(contributor.capture) == 'function'
    then
        live.notify_contributor_changed(name)
    end
end

---@return string[]
function M.contributor_names()
    return contributors.names()
end

return M
