local contributors = require('continuity.contributors.registry')
local config = require('continuity.core.config')
local layout = require('continuity.restore.layout')
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
---@field layout_restored boolean

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
---@return '"before_layout"'|'"after_layout"'
local function restore_phase(step)
    if step.contributor == 'session' then
        return 'before_layout'
    end

    if step.restore_phase == 'after_layout' then
        return 'after_layout'
    end

    local contributor = contributors.get(step.contributor)

    if contributor ~= nil and contributor.restore_phase == 'after_layout' then
        return 'after_layout'
    end

    return 'before_layout'
end

---@param steps continuity.RestorePlanStep[]
---@return continuity.RestorePlanStep[], continuity.RestorePlanStep[]
local function partition_steps(steps)
    local before = {}
    local after = {}

    for _, step in ipairs(steps) do
        if restore_phase(step) == 'after_layout' then
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
local function validate_external_shada(record)
    local policy = config.get().shada.external_policy

    if vim.o.shada == '' or policy == 'ignore' then
        return
    end

    local message = string.format(
        'Continuity is restoring session %s with external shada configured; synthetic ShaDa fidelity may be affected',
        record.id
    )

    if policy == 'error' then
        error(message)
    end

    vim.notify(message, vim.log.levels.WARN)
end

---@param record continuity.Record
---@param plan? continuity.RestorePlan
---@param opts? { force_current?: boolean, restore_layout?: boolean }
---@return continuity.RestoreExecutionReport
function M.execute(record, plan, opts)
    local resolved_plan = plan or restore_plan.build(record)
    local report = {
        session_id = record.id,
        session_name = record.name,
        executed_steps = {},
        manual_steps = {},
        layout_restored = false,
    }
    local executed = {}
    local pre_layout_steps, post_layout_steps = partition_steps(resolved_plan.steps)
    local layout_restored = false

    run_steps(report, pre_layout_steps, record, executed, opts)

    if opts == nil or opts.restore_layout ~= false then
        validate_external_shada(record)
        layout_restored = layout.restore(record).restored
        report.layout_restored = layout_restored
    end

    run_steps(report, post_layout_steps, record, executed, opts)

    if layout_restored then
        layout.rebind_buffers(record)
    end

    return report
end

return M
