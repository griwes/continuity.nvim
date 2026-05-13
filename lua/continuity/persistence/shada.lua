local M = {}

local ENTRY_JUMP = 8
local ENTRY_CHANGE = 11

---@param value any
---@return string
local function encode(value)
    return vim.mpack.encode(value)
end

---@param entry_type integer
---@param timestamp integer
---@param data table
---@return string
local function entry(entry_type, timestamp, data)
    local payload = encode(data)
    return encode(entry_type) .. encode(timestamp) .. encode(#payload) .. payload
end

---@param item table
---@param fallback_name? string
---@return table?
local function filemark(item, fallback_name)
    local filename = item.filename or item.file or fallback_name

    if type(filename) ~= 'string' or filename == '' then
        return nil
    end

    local lnum = tonumber(item.lnum) or 0

    if lnum <= 0 then
        return nil
    end

    local mark = {
        f = filename,
    }

    if lnum ~= 1 then
        mark.l = lnum
    end

    local col = tonumber(item.col) or 0
    if col > 0 then
        mark.c = col
    end

    return mark
end

---@param items table[]?
---@param entry_type integer
---@param fallback_name? string
---@return string
local function encode_filemarks(items, entry_type, fallback_name)
    local chunks = {}
    local timestamp = os.time()

    for index, item in ipairs(items or {}) do
        local mark = filemark(item, fallback_name)

        if mark ~= nil then
            table.insert(chunks, entry(entry_type, timestamp + index, mark))
        end
    end

    return table.concat(chunks)
end

---@param bytes string
---@return string
local function write_temp(bytes)
    local root = vim.fs.joinpath(vim.fn.stdpath('state'), 'continuity.nvim')

    assert(vim.uv.fs_mkdir(root, 448) or vim.uv.fs_stat(root))

    local dir = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(root, 'synthetic-shada-XXXXXX')))
    local path = vim.fs.joinpath(dir, 'synthetic.shada')
    local fd = assert(vim.uv.fs_open(path, 'w', 384))

    assert(vim.uv.fs_write(fd, bytes, 0))
    assert(vim.uv.fs_close(fd))

    return path
end

---@param path string
local function cleanup(path)
    pcall(vim.uv.fs_unlink, path)
    pcall(vim.uv.fs_rmdir, vim.fs.dirname(path))
end

---@param bytes string
---@param opts? { shada?: string }
local function read_bytes(bytes, opts)
    if bytes == '' then
        return
    end

    local path = write_temp(bytes)
    local old_shada = vim.o.shada
    local shada = opts ~= nil and opts.shada or "!,'100"

    local ok, err = pcall(function()
        vim.o.shada = shada
        vim.cmd('rshada! ' .. vim.fn.fnameescape(path))
    end)

    vim.o.shada = old_shada
    cleanup(path)

    if not ok then
        error(err)
    end
end

---@param items table[]?
---@param filename? string
---@return string
function M.encode_jumps(items, filename)
    return encode_filemarks(items, ENTRY_JUMP, filename)
end

---@param items table[]?
---@param filename string
---@return string
function M.encode_changes(items, filename)
    return encode_filemarks(items, ENTRY_CHANGE, filename)
end

---@param items table[]?
---@param filename? string
function M.restore_jumps(items, filename)
    read_bytes(M.encode_jumps(items, filename))
end

---@param items table[]?
---@param filename string
function M.restore_changes(items, filename)
    read_bytes(M.encode_changes(items, filename))
end

return M
