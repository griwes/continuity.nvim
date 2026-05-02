local api = require('continuity.api')
local commands = require('continuity.ui.commands')
local config = require('continuity.core.config')
local live = require('continuity.live.state')
local storage = require('continuity.persistence.storage')
local autoload = require('continuity.restore.autoload')

---@class continuity.RootModule
---@field config continuity.Config
---@field api table
---@field last_autoload? continuity.AutoloadReport

local M = {
    api = api,
}

commands.ensure(M)

---Configure continuity.nvim.
---@param opts? Partial<continuity.Config>
---@return continuity.Config
function M.setup(opts)
    M.config = config.set(opts)
    storage.restore()
    M.last_autoload = autoload.run()
    live.start()
    return M.config
end

M.config = config.get()

return M
