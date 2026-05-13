---@class continuity.Record
---@field id string
---@field name string
---@field cwd string
---@field state table<string, any>
---@field contributors table<string, any>
---@field created_at integer
---@field updated_at integer

---@class continuity.Contributor
---@field capture? fun(): any
---@field plan_restore? fun(captured: any, record: continuity.Record): continuity.RestorePlanStep[]|{ steps: continuity.RestorePlanStep[] }|nil
---@field restore? fun(step: continuity.RestorePlanStep, record: continuity.Record, opts?: table)
---@field restore_phase? '"before_layout"'|'"after_layout"'
---@field restore_after? string[]

local M = {}

---@param opts { id: string, name?: string, cwd?: string, state?: table<string, any>, created_at?: integer, updated_at?: integer }
---@return continuity.Record
function M.new_record(opts)
    local now = os.time()

    return {
        id = opts.id,
        name = type(opts.name) == 'string' and opts.name ~= '' and opts.name or opts.id,
        cwd = type(opts.cwd) == 'string' and opts.cwd ~= '' and vim.fs.normalize(opts.cwd) or vim.fn.getcwd(),
        state = type(opts.state) == 'table' and vim.deepcopy(opts.state) or {},
        contributors = type(opts.contributors) == 'table' and vim.deepcopy(opts.contributors) or {},
        created_at = tonumber(opts.created_at) or now,
        updated_at = tonumber(opts.updated_at) or now,
    }
end

---@param value any
---@return continuity.Record?
function M.restore_record(value)
    if type(value) ~= 'table' or type(value.id) ~= 'string' or value.id == '' then
        return nil
    end

    return M.new_record({
        id = value.id,
        name = value.name,
        cwd = value.cwd,
        state = value.state,
        contributors = value.contributors,
        created_at = value.created_at,
        updated_at = value.updated_at,
    })
end

return M
