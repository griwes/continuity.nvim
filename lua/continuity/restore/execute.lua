local contributors = require('continuity.contributors.registry')
local mksession = require('continuity.persistence.mksession')
local restore_plan = require('continuity.restore.plan')

local M = {}

---@param value any
---@param message string
---@return any
local function require_value(value, message)
    if value == nil then
        error(message)
    end

    return value
end

---@class continuity.RestoreExecutionReport
---@field session_id string
---@field session_name string
---@field executed_steps string[]
---@field manual_steps continuity.RestorePlanStep[]
---@field mksession_loaded boolean

---@param report continuity.RestoreExecutionReport
---@param step continuity.RestorePlanStep
local function mark_manual(report, step)
    table.insert(report.manual_steps, vim.deepcopy(step))
end

---@param report continuity.RestoreExecutionReport
---@param step continuity.RestorePlanStep
local function mark_executed(report, step)
    table.insert(report.executed_steps, step.id)
end

---@param step continuity.RestorePlanStep
---@param executed table<string, boolean>
local function assert_dependencies(step, executed)
    for _, dependency in ipairs(step.depends_on or {}) do
        if executed[dependency] ~= true then
            error(string.format('Restore step %s depends on unfinished step %s', step.id, dependency))
        end
    end
end

---@param step continuity.RestorePlanStep
---@param record continuity.Record
---@param opts? table
---@return boolean
local function run_step(step, record, opts)
    if step.manual or step.kind == 'continuity.manual_restore' or step.kind == 'continuity.unknown_contributor' then
        return false
    end

    if step.contributor == 'session' then
        if step.kind == 'continuity.chdir' then
            local payload = require_value(step.payload, 'Session cwd restore step is missing payload')
            local cwd = require_value(payload.cwd, 'Session cwd restore step is missing cwd')
            vim.api.nvim_set_current_dir(cwd)
            return true
        end

        error(string.format('Unsupported builtin session restore step: %s', step.kind))
    end

    local contributor = contributors.get(step.contributor)

    if contributor == nil or type(contributor.restore) ~= 'function' then
        return false
    end

    contributor.restore(vim.deepcopy(step), vim.deepcopy(record), opts)
    return true
end

---@param step continuity.RestorePlanStep
---@return '"before_mksession"'|'"after_mksession"'
local function restore_phase(step)
    if step.contributor == 'session' then
        return 'before_mksession'
    end

    local contributor = contributors.get(step.contributor)

    if contributor ~= nil and contributor.restore_phase == 'after_mksession' then
        return 'after_mksession'
    end

    return 'before_mksession'
end

---@param steps continuity.RestorePlanStep[]
---@return continuity.RestorePlanStep[], continuity.RestorePlanStep[]
local function partition_steps(steps)
    local before = {}
    local after = {}

    for _, step in ipairs(steps) do
        if restore_phase(step) == 'after_mksession' then
            table.insert(after, step)
        else
            table.insert(before, step)
        end
    end

    return before, after
end

---@param report continuity.RestoreExecutionReport
---@param steps continuity.RestorePlanStep[]
---@param record continuity.Record
---@param executed table<string, boolean>
---@param opts? table
local function run_steps(report, steps, record, executed, opts)
    for _, step in ipairs(steps) do
        assert_dependencies(step, executed)

        if run_step(step, record, opts) then
            mark_executed(report, step)
        else
            mark_manual(report, step)
        end

        executed[step.id] = true
    end
end

---@param record continuity.Record
---@param plan? continuity.RestorePlan
---@param opts? { use_mksession?: boolean }
---@return continuity.RestoreExecutionReport
function M.execute(record, plan, opts)
    local resolved_plan = plan or restore_plan.build(record)
    local report = {
        session_id = record.id,
        session_name = record.name,
        executed_steps = {},
        manual_steps = {},
        mksession_loaded = false,
    }
    local executed = {}
    local pre_mksession_steps, post_mksession_steps = partition_steps(resolved_plan.steps)
    local use_mksession = opts == nil or opts.use_mksession ~= false

    run_steps(report, pre_mksession_steps, record, executed, opts)

    if use_mksession and mksession.load(record.id) then
        report.mksession_loaded = true
    end

    run_steps(report, post_mksession_steps, record, executed, opts)

    return report
end

return M
