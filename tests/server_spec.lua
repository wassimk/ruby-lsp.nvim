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
end)
