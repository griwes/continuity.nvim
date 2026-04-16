local contributors = require('continuity.contributors.registry')
local live = require('continuity.live.state')
local restore_execute = require('continuity.restore.execute')
local restore_plan = require('continuity.restore.plan')
local storage = require('continuity.persistence.storage')

local M = {}

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any>, contributors?: table<string, any> }
---@return continuity.Record
function M.save(opts)
    if opts ~= nil and opts.id ~= nil then
        return storage.save(opts)
    end

    return storage.create(opts)
end

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any> }
---@return continuity.Record
function M.capture(opts)
    local payload = vim.tbl_extend('force', {}, opts or {}, {
        contributors = contributors.capture(),
    })

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

---@param id string
---@return continuity.Record?
function M.delete(id)
    return storage.delete(id)
end

---@return continuity.Record[]
function M.restore()
    return storage.restore()
end

---@param session_ref string|continuity.Record
---@return continuity.RestorePlan
function M.plan_restore(session_ref)
    local record = type(session_ref) == 'string' and storage.get(session_ref) or session_ref

    assert(record ~= nil, 'Could not resolve a saved session to plan restore from')

    return restore_plan.build(vim.deepcopy(record))
end

---@param session_ref string|continuity.Record
---@param opts? { use_mksession?: boolean }
---@return continuity.RestoreExecutionReport
function M.execute_restore(session_ref, opts)
    local record = type(session_ref) == 'string' and storage.get(session_ref) or session_ref

    if record == nil then
        error('Could not resolve a saved session to execute restore from')
    end

    return restore_execute.execute(vim.deepcopy(record), nil, opts)
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
