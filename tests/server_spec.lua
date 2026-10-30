local helpers = require('helpers')
local server = require('ruby-lsp.server')

describe('server', function()
  local fake, original_system, original_executable, executable

  local function complete(index, result)
    fake.calls[index].on_exit(result)
    vim.wait(100, function()
      return false
    end)
  end

  before_each(function()
    helpers.setup_mocks()
    server._reset()

    fake = { calls = {} }
    executable = 1
    original_system = vim.system
    original_executable = vim.fn.executable

    vim.system = function(cmd, opts, on_exit)
      local call = { cmd = cmd, opts = opts, on_exit = on_exit }
      table.insert(fake.calls, call)
      return {
        wait = function()
          return fake.sync_result
        end,
      }
    end
    vim.fn.executable = function(name)
      return executable
    end
  end)

  after_each(function()
    vim.system = original_system
    vim.fn.executable = original_executable
    helpers.teardown_mocks()
  end)

  it('reports ok and the version when ruby-lsp exits 0', function()
    local got
    server.probe('/app', function(ok, version)
      got = { ok, version }
    end)

    assert.are.same({ 'ruby-lsp', '--version' }, fake.calls[1].cmd)
    assert.are.equal('/app', fake.calls[1].opts.cwd)
    assert.is_true(fake.calls[1].opts.text)

    complete(1, { code = 0, stdout = '0.26.11\n' })
    assert.are.same({ true, '0.26.11' }, got)
  end)

  it('reports not ok when ruby-lsp exits non-zero', function()
    local got
    server.probe('/app', function(ok, version)
      got = { ok = ok, version = version }
    end)

    complete(1, { code = 127, stdout = '' })
    assert.is_false(got.ok)
    assert.is_nil(got.version)
  end)

  it('reports not ok without spawning when ruby-lsp is not executable', function()
    executable = 0
    local got
    server.probe('/app', function(ok, version)
      got = { ok = ok, version = version }
    end)

    vim.wait(100, function()
      return got ~= nil
    end)
    assert.is_false(got.ok)
    assert.is_nil(got.version)
    assert.are.equal(0, #fake.calls)
  end)

  it('caches the result per root', function()
    server.probe('/app', function() end)
    complete(1, { code = 0, stdout = '0.26.11\n' })

    local got
    server.probe('/app', function(ok, version)
      got = { ok, version }
    end)
    vim.wait(100, function()
      return got ~= nil
    end)
    assert.are.same({ true, '0.26.11' }, got)
    assert.are.equal(1, #fake.calls)

    server.probe('/other', function() end)
    assert.are.equal(2, #fake.calls)
  end)

  it('shares one pending check between callers', function()
    local results = {}
    server.probe('/app', function(ok, version)
      table.insert(results, { ok, version })
    end)
    server.probe('/app', function(ok, version)
      table.insert(results, { ok, version })
    end)
    assert.are.equal(1, #fake.calls)

    complete(1, { code = 0, stdout = '0.26.11\n' })
    assert.are.same({ { true, '0.26.11' }, { true, '0.26.11' } }, results)
  end)

  it('probe_sync waits for the check and fills the cache', function()
    fake.sync_result = { code = 0, stdout = '1.0.0\n' }
    local ok, version = server.probe_sync('/app')
    assert.is_true(ok)
    assert.are.equal('1.0.0', version)

    ok, version = server.probe_sync('/app')
    assert.is_true(ok)
    assert.are.equal('1.0.0', version)
    assert.are.equal(1, #fake.calls)
  end)

  it('probe_sync uses the same cache as probe', function()
    server.probe('/app', function() end)
    complete(1, { code = 0, stdout = '0.26.11\n' })

    local ok, version = server.probe_sync('/app')
    assert.is_true(ok)
    assert.are.equal('0.26.11', version)
    assert.are.equal(1, #fake.calls)
  end)

  it('probe_sync returns false without spawning when ruby-lsp is not executable', function()
    executable = 0
    local ok, version = server.probe_sync('/app')
    assert.is_false(ok)
    assert.is_nil(version)
    assert.are.equal(0, #fake.calls)
  end)

  it('never notifies', function()
    server.probe('/app', function() end)
    complete(1, { code = 127, stdout = '' })
    executable = 0
    server.probe('/other', function() end)
    vim.wait(50, function()
      return false
    end)
    assert.are.same({}, helpers.notifications)
  end)

  describe('root_dir', function()
    local config = require('ruby-lsp.config')
    local original_root, original_probe, original_lsp_config
    local root, probe_calls, lsp_cmd, bufnr

    local function resolve(buf)
      local got = {}
      server.root_dir(buf or bufnr, function(dir)
        table.insert(got, dir)
      end)
      return got
    end

    before_each(function()
      config.setup()
      root = '/app'
      probe_calls = {}
      lsp_cmd = server.cmd
      bufnr = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(bufnr, '/app/app/models/user.rb')

      original_root = vim.fs.root
      original_probe = server.probe
      original_lsp_config = vim.lsp.config

      vim.fs.root = function()
        return root
      end
      server.probe = function(dir, callback)
        table.insert(probe_calls, { root = dir, callback = callback })
      end
      vim.lsp.config = {
        ruby_lsp = setmetatable({}, {
          __index = function(_, key)
            if key == 'cmd' then
              return lsp_cmd
            end
          end,
        }),
      }
    end)

    after_each(function()
      vim.fs.root = original_root
      server.probe = original_probe
      vim.lsp.config = original_lsp_config
      vim.api.nvim_buf_delete(bufnr, { force = true })
      config.setup()
    end)

    it('starts when the root has a working ruby-lsp', function()
      local got = resolve()
      assert.are.equal(1, #probe_calls)
      assert.are.equal('/app', probe_calls[1].root)

      probe_calls[1].callback(true, '0.26.11')
      assert.are.same({ '/app' }, got)
    end)

    it('does nothing for a buffer without a file', function()
      local scratch = vim.api.nvim_create_buf(false, true)
      root = nil
      local got = resolve(scratch)
      vim.api.nvim_buf_delete(scratch, { force = true })

      assert.are.same({}, got)
      assert.are.equal(0, #probe_calls)
      assert.are.same({}, helpers.notifications)
    end)

    it('does nothing for an unnamed buffer even when the cwd has a root', function()
      local unnamed = vim.api.nvim_create_buf(true, false)
      local got = resolve(unnamed)
      vim.api.nvim_buf_delete(unnamed, { force = true })

      assert.are.same({}, got)
      assert.are.equal(0, #probe_calls)
    end)

    it('does nothing when no root is found', function()
      root = nil
      assert.are.same({}, resolve())
      assert.are.equal(0, #probe_calls)
    end)

    it('does not start when the version check fails', function()
      local got = resolve()
      probe_calls[1].callback(false, nil)

      assert.are.same({}, got)
      assert.are.same({}, helpers.notifications)
    end)

    it('does not start when auto_start returns false for the root', function()
      config.setup({
        lsp = {
          auto_start = function(dir)
            return dir ~= '/app'
          end,
        },
      })

      assert.are.same({}, resolve())
      assert.are.equal(0, #probe_calls)
    end)

    it('passes the root to auto_start', function()
      local received
      config.setup({
        lsp = {
          auto_start = function(dir)
            received = dir
            return true
          end,
        },
      })

      resolve()
      assert.are.equal('/app', received)
      assert.are.equal(1, #probe_calls)
    end)

    it('checks only the executable for a list cmd override', function()
      lsp_cmd = { 'bundle', 'exec', 'ruby-lsp' }
      local checked = {}
      vim.fn.executable = function(name)
        table.insert(checked, name)
        return name == 'bundle' and 1 or 0
      end

      assert.are.same({ '/app' }, resolve())
      assert.are.same({ 'bundle' }, checked)
      assert.are.equal(0, #probe_calls)
    end)

    it('does not start a list cmd override that is not executable', function()
      lsp_cmd = { 'bundle', 'exec', 'ruby-lsp' }
      executable = 0

      assert.are.same({}, resolve())
      assert.are.equal(0, #probe_calls)
      assert.are.same({}, helpers.notifications)
    end)

    it('checks that ruby-lsp runs for a foreign cmd function and skips a failed check', function()
      lsp_cmd = function() end

      local got = resolve()
      assert.are.equal(1, #probe_calls)
      assert.are.equal('/app', probe_calls[1].root)

      probe_calls[1].callback(false, nil)
      assert.are.same({}, got)
      assert.are.same({}, helpers.notifications)
    end)

    it('starts with a foreign cmd function when the check succeeds', function()
      lsp_cmd = function() end

      local got = resolve()
      assert.are.equal(1, #probe_calls)

      probe_calls[1].callback(true, '0.26.11')
      assert.are.same({ '/app' }, got)
    end)

    it('starts every buffer waiting on the same root', function()
      server.probe = original_probe
      server._reset()

      local first = resolve()
      local other = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(other, '/app/app/models/post.rb')
      local second = resolve(other)
      vim.api.nvim_buf_delete(other, { force = true })

      assert.are.equal(1, #fake.calls)
      complete(1, { code = 0, stdout = '0.26.11\n' })
      assert.are.same({ '/app' }, first)
      assert.are.same({ '/app' }, second)
    end)
  end)

  describe('should_start', function()
    local config = require('ruby-lsp.config')

    after_each(function()
      config.setup()
    end)

    it('starts by default', function()
      config.setup()
      assert.is_true(server.should_start('/app'))
    end)

    it('starts when auto_start is false because the user enabled it', function()
      config.setup({ lsp = { auto_start = false } })
      assert.is_true(server.should_start('/app'))
    end)

    it('starts only when the auto_start function returns true', function()
      config.setup({
        lsp = {
          auto_start = function()
            return 'yes'
          end,
        },
      })
      assert.is_false(server.should_start('/app'))
    end)
  end)

  describe('cmd', function()
    local original_start

    before_each(function()
      original_start = vim.lsp.rpc.start
    end)

    after_each(function()
      vim.lsp.rpc.start = original_start
    end)

    it('starts ruby-lsp in the root directory', function()
      local got
      vim.lsp.rpc.start = function(cmd, dispatchers, opts)
        got = { cmd = cmd, dispatchers = dispatchers, opts = opts }
        return 'client'
      end
      local dispatchers = {}

      assert.are.equal('client', server.cmd(dispatchers, { root_dir = '/app' }))
      assert.are.same({ 'ruby-lsp' }, got.cmd)
      assert.are.equal(dispatchers, got.dispatchers)
      assert.are.same({ cwd = '/app' }, got.opts)
    end)

    it('prefers cmd_cwd over root_dir', function()
      local got
      vim.lsp.rpc.start = function(_, _, opts)
        got = opts
      end

      server.cmd({}, { root_dir = '/app', cmd_cwd = '/app/sub' })
      assert.are.same({ cwd = '/app/sub' }, got)
    end)
  end)
end)
