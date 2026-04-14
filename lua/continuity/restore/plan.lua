local contributors = require('continuity.contributors.registry')

local M = {}

---@class continuity.RestorePlanStep
---@field id string
---@field contributor string
---@field kind string
---@field title string
---@field detail? string
---@field depends_on string[]
---@field payload any
---@field manual boolean

---@class continuity.RestorePlan
---@field session_id string
---@field session_name string
---@field cwd string
---@field steps continuity.RestorePlanStep[]

---@param contributor string
---@param index integer
---@param step table
---@return continuity.RestorePlanStep
local function normalize_step(contributor, index, step)
    return {
        id = type(step.id) == 'string' and step.id ~= '' and step.id or string.format('%s:%d', contributor, index),
        contributor = contributor,
        kind = type(step.kind) == 'string' and step.kind ~= '' and step.kind or 'continuity.restore',
        title = type(step.title) == 'string' and step.title ~= '' and step.title
            or string.format('Restore %s state', contributor),
        detail = type(step.detail) == 'string' and step.detail ~= '' and step.detail or nil,
        depends_on = type(step.depends_on) == 'table' and vim.deepcopy(step.depends_on) or {},
        payload = step.payload ~= nil and vim.deepcopy(step.payload) or nil,
        manual = step.manual == true,
    }
end

---@param name string
---@param contributor continuity.Contributor
---@param captured any
---@param record continuity.Record
---@return continuity.RestorePlanStep[]
local function contributor_steps(name, contributor, captured, record)
    if captured == nil then
        return {}
    end

    if contributor == nil then
        return {
            normalize_step(name, 1, {
                kind = 'continuity.unknown_contributor',
                title = string.format('Review %s restore state', name),
                detail = string.format(
                    '%s captured state exists, but the contributor is not currently registered',
                    name
                ),
                payload = captured,
                manual = true,
            }),
        }
    end

    if type(contributor.plan_restore) ~= 'function' then
        return {
            normalize_step(name, 1, {
                kind = 'continuity.manual_restore',
                title = string.format('Review %s restore state', name),
                detail = string.format('%s captured state exists, but no restore planner is registered yet', name),
                payload = captured,
                manual = true,
            }),
        }
    end

    local fragment = contributor.plan_restore(vim.deepcopy(captured), vim.deepcopy(record))
    local raw_steps = type(fragment) == 'table' and fragment.steps or fragment

    if type(raw_steps) ~= 'table' or vim.tbl_isempty(raw_steps) then
        return {}
    end

    local steps = {}

    for index, step in ipairs(raw_steps) do
        steps[index] = normalize_step(name, index, step)
    end

    return steps
end

---@param names string[]
---@return string[]
local function ordered_contributors(names)
    local ordered = {}
    local visiting = {}
    local visited = {}

    table.sort(names)

    local function visit(name)
        if visited[name] then
            return
        end

        if visiting[name] then
            return
        end

        visiting[name] = true

        local contributor = contributors.get(name)

        if contributor ~= nil then
            local dependencies = type(contributor.restore_after) == 'table' and vim.deepcopy(contributor.restore_after)
                or {}
            table.sort(dependencies)

            for _, dependency in ipairs(dependencies) do
                if vim.tbl_contains(names, dependency) then
                    visit(dependency)
                end
            end
        end

        visiting[name] = nil
        visited[name] = true
        table.insert(ordered, name)
    end

    for _, name in ipairs(names) do
        visit(name)
    end

    return ordered
end

---@param record continuity.Record
---@return continuity.RestorePlan
function M.build(record)
    local captured_contributors = contributors.normalize_captured(record.contributors or {})
    local steps = {
        {
            id = 'session:cwd',
            contributor = 'session',
            kind = 'continuity.chdir',
            title = 'Change workspace directory',
            detail = string.format('Restore Neovim cwd to %s', record.cwd),
            depends_on = {},
            payload = {
                cwd = record.cwd,
            },
            manual = false,
        },
    }
    local tail_step_ids = {
        session = { 'session:cwd' },
    }
    local contributor_names = ordered_contributors(vim.tbl_keys(captured_contributors))

    for _, name in ipairs(contributor_names) do
        local contributor = contributors.get(name)
        local contributor_steps_list = contributor_steps(name, contributor, captured_contributors[name], record)
        local dependency_ids = { 'session:cwd' }
        local restore_after = contributor ~= nil
                and type(contributor.restore_after) == 'table'
                and contributor.restore_after
            or {}

        for _, dependency in ipairs(restore_after) do
            for _, step_id in ipairs(tail_step_ids[dependency] or {}) do
                table.insert(dependency_ids, step_id)
            end
        end

        for index, step in ipairs(contributor_steps_list) do
            if index == 1 then
                step.depends_on = vim.list_extend(dependency_ids, step.depends_on)
            else
                table.insert(step.depends_on, contributor_steps_list[index - 1].id)
            end

            table.insert(steps, step)
        end

        if #contributor_steps_list > 0 then
            tail_step_ids[name] = { contributor_steps_list[#contributor_steps_list].id }
        end
    end

    return {
        session_id = record.id,
        session_name = record.name,
        cwd = record.cwd,
        steps = steps,
    }
end

return M
