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

  it('adds user commands on attach only when enabled', function()
    local buf = vim.api.nvim_create_buf(true, false)
    local original_get = vim.lsp.get_client_by_id
    local client = { id = 7, name = 'ruby_lsp', request = function() end }
    local other = { id = 8, name = 'lua_ls', request = function() end }
    vim.lsp.get_client_by_id = function(id)
      return id == 7 and client or other
    end

    local function attach(id)
      vim.api.nvim_exec_autocmds('LspAttach', {
        group = 'RubyLsp',
        buffer = buf,
        data = { client_id = id },
      })
    end

    ruby_lsp.setup({ dap = { auto_configure = false } })
    attach(7)
    assert.is_nil(vim.api.nvim_buf_get_commands(buf, {}).RubyLspShowDependencies)

    ruby_lsp.setup({ dap = { auto_configure = false }, user_commands = true })
    attach(8)
    assert.is_nil(vim.api.nvim_buf_get_commands(buf, {}).RubyLspShowDependencies)
    attach(7)
    assert.is_not_nil(vim.api.nvim_buf_get_commands(buf, {}).RubyLspShowDependencies)

    vim.lsp.get_client_by_id = original_get
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
