local helpers = require('helpers')
local config = require('ruby-lsp.config')
local health = require('ruby-lsp.health')
local server = require('ruby-lsp.server')

describe('health', function()
  local reports, originals, tmp

  before_each(function()
    helpers.setup_mocks()
    config.setup()
    reports = {}
    originals = {
      health = vim.health,
      has = rawget(vim.fn, 'has'),
      executable = rawget(vim.fn, 'executable'),
      probe_sync = server.probe_sync,
      root = vim.fs.root,
      getcwd = rawget(vim.fn, 'getcwd'),
    }
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, 'p')
    server.probe_sync = function()
      return true, '0.26.0'
    end
    vim.fs.root = function()
      return tmp
    end
    vim.fn.getcwd = function()
      return tmp
    end
    local function record(kind)
      return function(msg, advice)
        local full = type(advice) == 'table' and (msg .. '\n' .. table.concat(advice, '\n')) or msg
        table.insert(reports, { kind = kind, msg = full })
      end
    end
    vim.health = {
      start = function() end,
      ok = record('ok'),
      info = record('info'),
      warn = record('warn'),
      error = record('error'),
    }
  end)

  after_each(function()
    vim.health = originals.health
    rawset(vim.fn, 'has', originals.has)
    rawset(vim.fn, 'executable', originals.executable)
    server.probe_sync = originals.probe_sync
    vim.fs.root = originals.root
    rawset(vim.fn, 'getcwd', originals.getcwd)
    vim.fn.delete(tmp, 'rf')
    helpers.teardown_mocks()
  end)

  describe('Neovim version', function()
    it('reports ok when Neovim meets the minimum', function()
      vim.fn.has = function()
        return 1
      end
      health.check()

      assert.equals('ok', reports[1].kind)
      assert.equals('Neovim ' .. tostring(vim.version()):gsub('%+.*$', ''), reports[1].msg)
    end)

    it('reports an error when Neovim is too old', function()
      vim.fn.has = function()
        return 0
      end
      health.check()

      assert.equals('error', reports[1].kind)
      assert.truthy(reports[1].msg:find('is too old %(minimum: 0.12%)'))
    end)
  end)

  local function find(kind, pattern)
    for _, r in ipairs(reports) do
      if r.kind == kind and r.msg:find(pattern) then
        return r
      end
    end
  end

  local function write_lock(lines)
    vim.fn.writefile(lines, tmp .. '/Gemfile.lock')
  end

  describe('ruby-lsp install', function()
    it('reports ok with the version when ruby-lsp runs', function()
      health.check()

      assert.truthy(find('ok', 'ruby%-lsp 0%.26%.0 runs from ' .. vim.pesc(tmp)))
    end)

    it('reports an error with install advice when ruby-lsp does not run', function()
      server.probe_sync = function()
        return false, nil
      end
      health.check()

      local r = find('error', 'gem install ruby%-lsp')
      assert.truthy(r)
    end)

    it('warns when ruby-lsp is a direct dependency in the Gemfile.lock', function()
      write_lock({
        'GEM',
        '  specs:',
        '    ruby-lsp (0.26.11)',
        '',
        'DEPENDENCIES',
        '  rails',
        '  ruby-lsp',
        '',
        'BUNDLED WITH',
        '   2.5.0',
      })
      health.check()

      assert.truthy(find('warn', 'not supported'))
    end)

    it('does not warn when ruby-lsp is only a dependency of an add-on', function()
      write_lock({
        'GEM',
        '  specs:',
        '    ruby-lsp (0.26.11)',
        '    ruby-lsp-rails (0.4.8)',
        '      ruby-lsp (>= 0.26.0, < 0.27.0)',
        '    ruby-lsp-rspec (0.1.0)',
        '      ruby-lsp (>= 0.26.0, < 0.27.0)',
        '',
        'DEPENDENCIES',
        '  rails',
        '  ruby-lsp-rails',
        '  ruby-lsp-rspec',
        '',
        'BUNDLED WITH',
        '   2.5.0',
      })
      health.check()

      assert.is_nil(find('warn', 'not supported'))
    end)

    it('reports the auto_start setting', function()
      health.check()
      assert.truthy(find('info', 'auto_start: on'))

      reports = {}
      config.setup({ lsp = { auto_start = false } })
      health.check()
      assert.truthy(find('info', 'auto_start: off'))

      reports = {}
      config.setup({ lsp = { auto_start = function() end } })
      health.check()
      assert.truthy(find('info', 'auto_start: function'))
    end)

    it('places the checks after the Neovim version check', function()
      health.check()

      assert.truthy(reports[1].msg:find('^Neovim'))
      assert.truthy(reports[2].msg:find('ruby%-lsp'))
    end)
  end)

  describe('project root', function()
    local probed, bufs

    before_each(function()
      probed = {}
      bufs = {}
      server.probe_sync = function(root, opts)
        table.insert(probed, { root = root, opts = opts })
        return true, '0.26.0'
      end
    end)

    after_each(function()
      for _, b in ipairs(bufs) do
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end)

    ---Make `alt` the alternate buffer of a new scratch buffer, like :checkhealth does.
    local function open_scratch_after(alt)
      vim.api.nvim_set_current_buf(alt)
      local scratch = vim.api.nvim_create_buf(false, true)
      table.insert(bufs, scratch)
      vim.api.nvim_set_current_buf(scratch)
      assert.equals(alt, vim.fn.bufnr('#'))
    end

    it('re-runs the install check instead of reading the cache', function()
      health.check()

      assert.same({ refresh = true }, probed[1].opts)
    end)

    it("uses the active ruby_lsp client's root_dir", function()
      helpers.lsp_clients = { helpers.mock_client({ config = { root_dir = '/app' } }) }
      health.check()

      assert.equals('/app', probed[1].root)
      assert.truthy(find('ok', 'runs from /app'))
    end)

    it('uses the root of the alternate file buffer when no client is active', function()
      local alt = vim.api.nvim_create_buf(true, false)
      table.insert(bufs, alt)
      vim.api.nvim_buf_set_name(alt, '/alt_project/app/models/user.rb')
      local root_source
      vim.fs.root = function(source)
        root_source = source
        return '/alt_project'
      end
      open_scratch_after(alt)
      health.check()

      assert.equals(alt, root_source)
      assert.equals('/alt_project', probed[1].root)
    end)

    it('falls back to the cwd when the alternate buffer is not a file', function()
      local alt = vim.api.nvim_create_buf(true, true)
      table.insert(bufs, alt)
      vim.fs.root = function()
        return '/should_not_be_used'
      end
      open_scratch_after(alt)
      health.check()

      assert.equals(tmp, probed[1].root)
    end)

    it('falls back to the cwd when the alternate file has no project root', function()
      local alt = vim.api.nvim_create_buf(true, false)
      table.insert(bufs, alt)
      vim.api.nvim_buf_set_name(alt, '/no_project/script.rb')
      vim.fs.root = function()
        return nil
      end
      open_scratch_after(alt)
      health.check()

      assert.equals(tmp, probed[1].root)
    end)
  end)

  describe('fullTestDiscovery', function()
    local function check_with(init_options)
      local client = helpers.mock_client()
      client.config.init_options = init_options
      local orig = vim.lsp.get_clients
      vim.lsp.get_clients = function()
        return { client }
      end
      local ok, err = pcall(health.check)
      vim.lsp.get_clients = orig
      assert.is_true(ok, err)
    end

    it('reports ok when it is turned on', function()
      check_with({ enabledFeatureFlags = { fullTestDiscovery = true } })
      assert.truthy(find('ok', 'fullTestDiscovery'))
      assert.is_nil(find('warn', 'fullTestDiscovery'))
    end)

    it('warns when it is turned off or not set', function()
      check_with({ enabledFeatureFlags = { fullTestDiscovery = false } })
      assert.truthy(find('warn', 'fullTestDiscovery'))

      reports = {}
      check_with({})
      local r = find('warn', 'fullTestDiscovery')
      assert.truthy(r)
      assert.truthy(r.msg:find('lazy%-load'))
    end)
  end)
end)
