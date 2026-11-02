local helpers = require('helpers')
local config = require('ruby-lsp.config')
local ruby_lsp = require('ruby-lsp')

describe('setup', function()
  local original_enable, enabled

  before_each(function()
    helpers.setup_mocks()
    enabled = {}
    original_enable = vim.lsp.enable
    vim.lsp.enable = function(name)
      table.insert(enabled, name)
    end
  end)

  after_each(function()
    vim.lsp.enable = original_enable
    pcall(vim.api.nvim_del_augroup_by_name, 'RubyLsp')
    config.setup()
    helpers.teardown_mocks()
  end)

  it('enables ruby_lsp by default', function()
    ruby_lsp.setup({ dap = { auto_configure = false } })
    assert.are.same({ 'ruby_lsp' }, enabled)
  end)

  it('enables ruby_lsp when auto_start is a function', function()
    ruby_lsp.setup({
      dap = { auto_configure = false },
      lsp = {
        auto_start = function()
          return true
        end,
      },
    })
    assert.are.same({ 'ruby_lsp' }, enabled)
  end)

  it('does not enable ruby_lsp when auto_start is false', function()
    ruby_lsp.setup({ dap = { auto_configure = false }, lsp = { auto_start = false } })
    assert.are.same({}, enabled)
  end)

  it('provides the ruby_lsp config with test discovery on', function()
    local c = vim.lsp.config.ruby_lsp
    assert.is_true(c.init_options.enabledFeatureFlags.fullTestDiscovery)
    assert.equals('auto', c.init_options.formatter)
    assert.same({ 'ruby', 'eruby' }, c.filetypes)
    assert.equals('function', type(c.root_dir))
  end)

  it('uses the plugin cmd and root_dir functions by identity', function()
    local server = require('ruby-lsp.server')
    local c = vim.lsp.config.ruby_lsp
    assert.are.equal(server.cmd, c.cmd)
    assert.are.equal(server.root_dir, c.root_dir)
  end)

  it('reuses a client only for the same name and root', function()
    local c = vim.lsp.config.ruby_lsp
    local client = { name = 'ruby_lsp', config = { root_dir = '/app' } }
    local same = { name = 'ruby_lsp', root_dir = '/app' }
    local other = { name = 'ruby_lsp', root_dir = '/other' }

    assert.is_true(c.reuse_client(client, same))
    assert.are.equal('/app', same.cmd_cwd)
    assert.is_false(c.reuse_client(client, other))
  end)

  describe('on attach', function()
    local buf, clients, codelens_calls, originals

    local function attach(id)
      vim.api.nvim_exec_autocmds('LspAttach', { group = 'RubyLsp', buffer = buf, data = { client_id = id } })
    end

    before_each(function()
      buf = vim.api.nvim_create_buf(true, false)
      clients = {
        [1] = { id = 1, name = 'ruby_lsp', handlers = {}, request = function() end },
        [2] = { id = 2, name = 'lua_ls', handlers = {}, request = function() end },
      }
      codelens_calls = {}
      originals = {
        get_client_by_id = vim.lsp.get_client_by_id,
        codelens_enable = vim.lsp.codelens.enable,
        progress = vim.lsp.handlers['$/progress'],
      }
      vim.lsp.get_client_by_id = function(id)
        return clients[id]
      end
      vim.lsp.codelens.enable = function(enable, filter)
        table.insert(codelens_calls, { enable, filter })
      end
    end)

    after_each(function()
      vim.lsp.get_client_by_id = originals.get_client_by_id
      vim.lsp.codelens.enable = originals.codelens_enable
      vim.lsp.handlers['$/progress'] = originals.progress
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('adds user commands only when enabled', function()
      ruby_lsp.setup({ dap = { auto_configure = false } })
      attach(1)
      assert.is_nil(vim.api.nvim_buf_get_commands(buf, {}).RubyLspShowDependencies)

      ruby_lsp.setup({ dap = { auto_configure = false }, user_commands = true })
      attach(2)
      assert.is_nil(vim.api.nvim_buf_get_commands(buf, {}).RubyLspShowDependencies)
      attach(1)
      assert.is_not_nil(vim.api.nvim_buf_get_commands(buf, {}).RubyLspShowDependencies)
    end)

    it('drops null values from progress notifications', function()
      local received
      vim.lsp.handlers['$/progress'] = function(_, result)
        received = result
      end

      ruby_lsp.setup({ dap = { auto_configure = false } })
      attach(1)
      clients[1].handlers['$/progress'](
        nil,
        { token = 't', value = { kind = 'report', message = vim.NIL, percentage = vim.NIL } },
        {},
        {}
      )

      assert.same({ token = 't', value = { kind = 'report' } }, received)
    end)

    it('enables code lenses in buffers the ruby_lsp client attaches to', function()
      -- the real API, so the test checks what a user can observe
      vim.lsp.codelens.enable = originals.codelens_enable
      ruby_lsp.setup({ dap = { auto_configure = false } })
      attach(2)
      assert.is_false(vim.lsp.codelens.is_enabled({ bufnr = buf }))
      attach(1)
      assert.is_true(vim.lsp.codelens.is_enabled({ bufnr = buf }))
    end)

    it('leaves code lenses alone when turned off', function()
      ruby_lsp.setup({ dap = { auto_configure = false }, codelens = false })
      attach(1)
      assert.same({}, codelens_calls)
    end)
  end)
end)
