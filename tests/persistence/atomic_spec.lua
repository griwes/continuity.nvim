describe('continuity atomic persistence', function()
    local target

    local function read_target()
        return table.concat(vim.fn.readfile(target), '\n')
    end

    local function temporary_files()
        return vim.fn.glob(target .. '.tmp.*', false, true)
    end

    before_each(function()
        package.loaded['continuity.persistence.atomic'] = nil
        target = vim.fn.tempname()
        vim.fn.writefile({ vim.json.encode({ value = 'old' }) }, target)
    end)

    it('replaces JSON through a same-directory rename', function()
        local atomic = require('continuity.persistence.atomic')
        local temporary

        atomic.write_json(target, {
            value = 'new',
        }, {
            write_file = function(path, lines)
                temporary = path
                return vim.fn.writefile(lines, path)
            end,
        })

        assert.are.equal(vim.fs.dirname(target), vim.fs.dirname(temporary))
        assert.are.same({ value = 'new' }, vim.json.decode(read_target()))
        assert.are.same({}, temporary_files())
    end)

    it('preserves the prior file and cleans up after an interrupted temporary write', function()
        local atomic = require('continuity.persistence.atomic')
        local original = read_target()
        local ok, err = pcall(atomic.write_json, target, {
            value = 'new',
        }, {
            write_file = function(path)
                vim.fn.writefile({ '{"value":"partial"' }, path)
                error('injected write interruption')
            end,
        })

        assert.is_false(ok)
        assert.is_true(tostring(err):find(target, 1, true) ~= nil)
        assert.is_true(tostring(err):find('injected write interruption', 1, true) ~= nil)
        assert.are.equal(original, read_target())
        assert.are.same({}, temporary_files())
    end)

    it('preserves the prior file and cleans up after a failed atomic replacement', function()
        local atomic = require('continuity.persistence.atomic')
        local original = read_target()
        local ok, err = pcall(atomic.write_json, target, {
            value = 'new',
        }, {
            rename = function()
                return nil, 'injected rename failure', 'EIO'
            end,
        })

        assert.is_false(ok)
        assert.is_true(tostring(err):find(target, 1, true) ~= nil)
        assert.is_true(tostring(err):find('injected rename failure', 1, true) ~= nil)
        assert.are.equal(original, read_target())
        assert.are.same({}, temporary_files())
    end)
end)
