local session_key = require('continuity.core.session_key')
local storage = require('continuity.persistence.storage')

local M = {}

---@class continuity.SessionItem
---@field id string
---@field value string
---@field name string
---@field cwd string
---@field branch? string
---@field created_at integer
---@field updated_at integer
---@field is_current boolean
---@field is_last boolean
---@field label string
---@field detail string
---@field ordinal string
---@field record continuity.Record

---@param record continuity.Record
---@return string?
local function record_branch(record)
    local continuity_state = type(record.state.continuity) == 'table' and record.state.continuity or nil
    local key_state = continuity_state ~= nil
            and type(continuity_state.session_key) == 'table'
            and continuity_state.session_key
        or nil

    return key_state ~= nil and key_state.branch or nil
end

---@param record continuity.Record
---@param current_id string
---@param last_id? string
---@return continuity.SessionItem
function M.item(record, current_id, last_id)
    local branch = record_branch(record)
    local markers = {}

    if record.id == current_id then
        table.insert(markers, 'current')
    end

    if record.id == last_id then
        table.insert(markers, 'last')
    end

    local detail_parts = {
        record.cwd,
    }

    if branch ~= nil and branch ~= '' then
        table.insert(detail_parts, branch)
    end

    if #markers > 0 then
        table.insert(detail_parts, table.concat(markers, ', '))
    end

    local detail = table.concat(detail_parts, '  ')
    local label = string.format('%s  %s', record.name, detail)

    return {
        id = record.id,
        value = record.id,
        name = record.name,
        cwd = record.cwd,
        branch = branch,
        created_at = record.created_at,
        updated_at = record.updated_at,
        is_current = record.id == current_id,
        is_last = record.id == last_id,
        label = label,
        detail = detail,
        ordinal = table.concat({
            record.id,
            record.name,
            record.cwd,
            branch or '',
        }, ' '),
        record = vim.deepcopy(record),
    }
end

---@return continuity.SessionItem[]
function M.items()
    local current_id = session_key.current().id
    local last_id = storage.last_session_id()

    return vim.tbl_map(function(record)
        return M.item(record, current_id, last_id)
    end, storage.list())
end

---@return string[]
function M.lines()
    return vim.tbl_map(function(item)
        return item.label
    end, M.items())
end

return M
