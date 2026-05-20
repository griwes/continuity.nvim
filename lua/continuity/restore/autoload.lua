local config = require('continuity.core.config')
local layout = require('continuity.restore.layout')
local restore_execute = require('continuity.restore.execute')
local session_key = require('continuity.core.session_key')
local storage = require('continuity.persistence.storage')

local M = {}
local state = {
    last_report = nil,
}

---@class continuity.AutoloadReport
---@field policy continuity.AutoloadPolicy
---@field loaded boolean
---@field reason? '"disabled"'|'"not_found"'|'"restore_failed"'
---@field error? string
---@field session_id? string
---@field execution? continuity.RestoreExecutionReport

---@param policy continuity.AutoloadPolicy
---@param fields? Partial<continuity.AutoloadReport>
---@return continuity.AutoloadReport
local function report(policy, fields)
    return vim.tbl_extend('force', {
        policy = policy,
        loaded = false,
    }, fields or {})
end

---@param left continuity.Record
---@param right continuity.Record
---@return boolean
local function newer_first(left, right)
    local left_updated = tonumber(left.updated_at) or 0
    local right_updated = tonumber(right.updated_at) or 0

    if left_updated == right_updated then
        return left.id > right.id
    end

    return left_updated > right_updated
end

---@param records continuity.Record[]
---@param preferred_id? string
---@return continuity.Record?
local function newest(records, preferred_id)
    table.sort(records, newer_first)

    if preferred_id ~= nil and records[1] ~= nil then
        local newest_updated = tonumber(records[1].updated_at) or 0

        for _, record in ipairs(records) do
            if (tonumber(record.updated_at) or 0) ~= newest_updated then
                break
            end

            if record.id == preferred_id then
                return record
            end
        end
    end

    return records[1]
end

---@param cwd string
---@return continuity.Record?
local function newest_for_cwd(cwd)
    local matches = {}

    for _, record in ipairs(storage.list()) do
        if record.cwd == cwd then
            table.insert(matches, record)
        end
    end

    return newest(matches, storage.last_session_id())
end

---@param record continuity.Record
local function schedule_startup_rebind(record)
    local function rebind()
        pcall(layout.rebind_buffers, vim.deepcopy(record))
    end

    if vim.v.vim_did_enter == 1 then
        vim.schedule(rebind)
        return
    end

    vim.api.nvim_create_autocmd('VimEnter', {
        once = true,
        callback = function()
            vim.schedule(rebind)
        end,
    })
end

---@param policy continuity.AutoloadPolicy
---@return continuity.Record?
function M.select(policy)
    if policy == 'cwd' then
        return newest_for_cwd(vim.fs.normalize(vim.fn.getcwd()))
    end

    if policy == 'cwd_branch' then
        local id = session_key.current({ use_git_branch = true }).id

        return storage.get(storage.clean_snapshot_id(id)) or storage.get(id)
    end

    if policy == 'last' then
        local last_session_id = storage.last_session_id()

        if last_session_id ~= nil then
            local record = storage.get(last_session_id)

            if record ~= nil then
                return record
            end
        end

        return newest(storage.list())
    end

    return nil
end

---@return continuity.AutoloadReport
function M.run()
    local policy = config.get().autoload.policy

    if policy == 'disabled' then
        state.last_report = report(policy, {
            reason = 'disabled',
        })
        return state.last_report
    end

    local record = M.select(policy)

    if record == nil then
        state.last_report = report(policy, {
            reason = 'not_found',
        })
        return state.last_report
    end

    local ok, execution = pcall(restore_execute.execute, vim.deepcopy(record))

    if not ok then
        state.last_report = report(policy, {
            reason = 'restore_failed',
            error = tostring(execution),
            session_id = record.id,
        })
        return state.last_report
    end

    schedule_startup_rebind(record)

    state.last_report = report(policy, {
        loaded = true,
        session_id = record.id,
        execution = execution,
    })
    return state.last_report
end

---@return continuity.AutoloadReport?
function M.last_report()
    return state.last_report ~= nil and vim.deepcopy(state.last_report) or nil
end

return M
