local autoload = require('continuity.restore.autoload')
local contributors = require('continuity.contributors.registry')
local restore_plan = require('continuity.restore.plan')
local storage = require('continuity.persistence.storage')

local M = {}

local state = {
    attempted_steps = {},
    completed_steps = {},
    generation = 0,
    group_id = nil,
    pending_contributors = {},
    record = nil,
    running = false,
    scheduled = false,
    session_id = nil,
    rerun = false,
}

---@param message string
local function notify_error(message)
    pcall(vim.notify, message, vim.log.levels.ERROR)
end

---@return boolean
local function initialize()
    local report = autoload.last_report()

    if
        report == nil
        or report.loaded ~= true
        or type(report.session_id) ~= 'string'
        or type(report.execution) ~= 'table'
    then
        return false
    end

    if state.session_id == report.session_id then
        return state.record ~= nil
    end

    local record = storage.get(report.session_id)

    if record == nil then
        return false
    end

    state.attempted_steps = {}
    state.completed_steps = {}
    state.pending_contributors = {}
    state.record = record
    state.session_id = report.session_id

    for _, step_id in ipairs(report.execution.executed_steps or {}) do
        state.completed_steps[step_id] = true
    end

    for _, step in ipairs(report.execution.manual_steps or {}) do
        if type(step.contributor) == 'string' and step.contributor ~= 'session' then
            state.pending_contributors[step.contributor] = true
        end
    end

    return true
end

---@param step continuity.RestorePlanStep
---@return boolean
local function dependencies_complete(step)
    for _, dependency in ipairs(step.depends_on or {}) do
        if state.completed_steps[dependency] ~= true then
            return false
        end
    end

    return true
end

---@param step continuity.RestorePlanStep
---@param phase 'before_layout'|'after_layout'
---@return boolean
local function can_run(step, phase)
    if state.pending_contributors[step.contributor] ~= true then
        return false
    end

    if step.manual == true or state.attempted_steps[step.id] == true then
        return false
    end

    local step_phase = step.restore_phase == 'after_layout' and 'after_layout' or 'before_layout'

    return step_phase == phase and dependencies_complete(step)
end

---@param step continuity.RestorePlanStep
local function run_step(step)
    local contributor = contributors.get(step.contributor)

    if contributor == nil or type(contributor.restore) ~= 'function' then
        return
    end

    state.attempted_steps[step.id] = true

    local ok, err = xpcall(function()
        contributor.restore(vim.deepcopy(step), vim.deepcopy(state.record), {
            late_registration = true,
            restore_layout = false,
        })
    end, debug.traceback)

    if not ok then
        notify_error(string.format('Continuity late restore step %s failed: %s', step.id, err))
        return
    end

    state.completed_steps[step.id] = true
end

---@param plan continuity.RestorePlan
---@param phase 'before_layout'|'after_layout'
local function drain_phase(plan, phase)
    local progressed = true

    while progressed do
        progressed = false

        for _, step in ipairs(plan.steps) do
            if can_run(step, phase) then
                local attempted_before = state.attempted_steps[step.id] == true
                run_step(step)

                if not attempted_before and state.attempted_steps[step.id] == true then
                    progressed = true
                end
            end
        end
    end
end

---@param plan continuity.RestorePlan
local function settle_attempted_contributors(plan)
    local steps_by_contributor = {}

    for _, step in ipairs(plan.steps) do
        if state.pending_contributors[step.contributor] == true then
            steps_by_contributor[step.contributor] = steps_by_contributor[step.contributor] or {}
            table.insert(steps_by_contributor[step.contributor], step)
        end
    end

    for name in pairs(state.pending_contributors) do
        local contributor = contributors.get(name)

        if
            contributor ~= nil
            and type(contributor.plan_restore) == 'function'
            and type(contributor.restore) == 'function'
        then
            local settled = true

            for _, step in ipairs(steps_by_contributor[name] or {}) do
                if step.manual == true or state.attempted_steps[step.id] ~= true then
                    settled = false
                    break
                end
            end

            if settled then
                state.pending_contributors[name] = nil
            end
        end
    end
end

local function drain_once()
    local ok, plan = xpcall(function()
        return restore_plan.build(vim.deepcopy(state.record))
    end, debug.traceback)

    if not ok then
        notify_error(string.format('Continuity could not plan late contributor restore: %s', plan))
        return
    end

    drain_phase(plan, 'before_layout')
    drain_phase(plan, 'after_layout')
    settle_attempted_contributors(plan)
end

local function drain()
    if not initialize() then
        return
    end

    if state.running then
        state.rerun = true
        return
    end

    state.running = true

    repeat
        state.rerun = false
        drain_once()
    until state.rerun ~= true

    state.running = false
end

local function schedule_drain()
    if state.scheduled then
        return
    end

    state.scheduled = true
    local generation = state.generation

    local function run_scheduled()
        if generation ~= state.generation then
            return
        end

        state.scheduled = false
        drain()
    end

    if vim.v.vim_did_enter == 1 then
        vim.schedule(run_scheduled)
        return
    end

    state.group_id = vim.api.nvim_create_augroup('continuity.nvim.late_restore', {
        clear = true,
    })
    vim.api.nvim_create_autocmd('VimEnter', {
        group = state.group_id,
        once = true,
        callback = function()
            vim.schedule(run_scheduled)
        end,
    })
end

---@param name string
function M.contributor_registered(name)
    if not initialize() or state.pending_contributors[name] ~= true then
        return
    end

    schedule_drain()
end

function M.clear()
    if state.group_id ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, state.group_id)
    end

    state.attempted_steps = {}
    state.completed_steps = {}
    state.generation = state.generation + 1
    state.group_id = nil
    state.pending_contributors = {}
    state.record = nil
    state.running = false
    state.scheduled = false
    state.session_id = nil
    state.rerun = false
end

return M
