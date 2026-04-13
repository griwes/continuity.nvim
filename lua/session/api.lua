local contributors = require('session.contributors')
local live = require('session.live')
local restore_plan = require('session.restore_plan')
local storage = require('session.storage')

local M = {}

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any>, contributors?: table<string, any> }
---@return session.Record
function M.save(opts)
    if opts ~= nil and opts.id ~= nil then
        return storage.save(opts)
    end

    return storage.create(opts)
end

---@param opts? { id?: string, name?: string, cwd?: string, state?: table<string, any> }
---@return session.Record
function M.capture(opts)
    local payload = vim.tbl_extend('force', {}, opts or {}, {
        contributors = contributors.capture(),
    })

    return M.save(payload)
end

---@param id string
---@return session.Record?
function M.load(id)
    return storage.get(id)
end

---@return session.Record[]
function M.list()
    return storage.list()
end

---@param id string
---@return session.Record?
function M.delete(id)
    return storage.delete(id)
end

---@return session.Record[]
function M.restore()
    return storage.restore()
end

---@param session_ref string|session.Record
---@return session.RestorePlan
function M.plan_restore(session_ref)
    local record = type(session_ref) == 'string' and storage.get(session_ref) or session_ref

    assert(record ~= nil, 'Could not resolve a saved session to plan restore from')

    return restore_plan.build(vim.deepcopy(record))
end

---@return session.Record?
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

---@param opts? { wipe_storage?: boolean }
function M.clear(opts)
    live.clear(opts)
    storage.clear(opts)
    contributors.clear()
end

---@param name string
---@param contributor session.Contributor
function M.register_contributor(name, contributor)
    contributors.register(name, contributor)

    if require('session.config').get().continuous.enabled == true and type(contributor.capture) == 'function' then
        live.notify_contributor_changed(name)
    end
end

---@return string[]
function M.contributor_names()
    return contributors.names()
end

return M
