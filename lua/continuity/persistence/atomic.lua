local M = {}

local next_temp_id = 0

---@class continuity.AtomicWriteOptions
---@field write_file? fun(path: string, lines: string[]): integer?
---@field rename? fun(source: string, target: string): boolean?, string?, string?

---@param path string
local function remove_temp(path)
    pcall(vim.uv.fs_unlink, path)
end

---@param path string
---@return string
local function temp_path(path)
    next_temp_id = next_temp_id + 1

    return string.format('%s.tmp.%d.%d.%d', path, vim.uv.os_getpid(), vim.uv.hrtime(), next_temp_id)
end

---@param path string
---@param payload table
---@param opts? continuity.AtomicWriteOptions
function M.write_json(path, payload, opts)
    local encoded = vim.json.encode(payload)
    local parent = vim.fs.dirname(path)

    if parent ~= nil and parent ~= '' then
        local ok, result = pcall(vim.fn.mkdir, parent, 'p')
        if not ok or (result ~= 0 and result ~= 1) then
            error(string.format('Could not create directory for atomic JSON write %s: %s', path, result))
        end
    end

    local temporary = temp_path(path)
    local write_file = opts and opts.write_file
        or function(target, lines)
            return vim.fn.writefile(lines, target)
        end
    local rename = opts and opts.rename or vim.uv.fs_rename
    local write_ok, write_result = pcall(write_file, temporary, { encoded })

    if not write_ok or (write_result ~= nil and write_result ~= 0) then
        remove_temp(temporary)
        error(string.format('Could not write atomic JSON temporary file for %s: %s', path, write_result))
    end

    local rename_ok, renamed, rename_error, rename_code = pcall(rename, temporary, path)

    if not rename_ok or renamed ~= true then
        remove_temp(temporary)
        local reason = rename_ok and (rename_error or rename_code or 'unknown rename failure') or renamed
        error(string.format('Could not atomically replace %s: %s', path, reason))
    end
end

return M
