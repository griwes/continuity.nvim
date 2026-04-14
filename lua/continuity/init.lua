local api = require('continuity.api')
local config = require('continuity.core.config')
local live = require('continuity.live.state')
local storage = require('continuity.persistence.storage')

---@class continuity.RootModule
---@field config continuity.Config
---@field api table

local M = {
    api = api,
}

---Configure continuity.nvim.
---@param opts? Partial<continuity.Config>
---@return continuity.Config
function M.setup(opts)
    M.config = config.set(opts)
    storage.restore()
    live.start()
    return M.config
end

M.config = config.get()

return M
