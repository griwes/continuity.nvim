local api = require('session.api')
local config = require('session.config')
local live = require('session.live')
local storage = require('session.storage')

---@class session.RootModule
---@field config session.Config
---@field api table

local M = {
    api = api,
}

---Configure session.nvim.
---@param opts? Partial<session.Config>
---@return session.Config
function M.setup(opts)
    M.config = config.set(opts)
    storage.restore()
    live.start()
    return M.config
end

M.config = config.get()

return M
