local config = require('ruby-lsp.config')
local server = require('ruby-lsp.server')
local utils = require('ruby-lsp.utils')

local M = {}

---Check whether the Gemfile.lock in `root` lists ruby-lsp as a direct dependency.
---Add-ons such as ruby-lsp-rails resolve ruby-lsp too, so only DEPENDENCIES counts.
---@param root string
---@return boolean
local function bundles_ruby_lsp(root)
  local path = root .. '/Gemfile.lock'
  if vim.fn.filereadable(path) == 0 then
    return false
  end
  local in_dependencies = false
  for _, line in ipairs(vim.fn.readfile(path)) do
    if line == 'DEPENDENCIES' then
      in_dependencies = true
    elseif in_dependencies then
      if line == '' then
        break
      end
      if line:match('^  ruby%-lsp$') or line:match('^  ruby%-lsp[ !(]') then
        return true
      end
    end
  end
  return false
end

---@param root string
local function check_install(root)
  local ok, version = server.probe_sync(root)
  if ok then
    vim.health.ok('ruby-lsp ' .. (version or '') .. ' runs from ' .. root)
  else
    vim.health.error('ruby-lsp does not run from ' .. root .. ', so the server will not start', {
      'Install it with: gem install ruby-lsp',
      'With rbenv, rvm, mise, or asdf, install it for the Ruby version this project uses.',
    })
  end

  local auto_start = config.get().lsp.auto_start
  if type(auto_start) == 'function' then
    vim.health.info('auto_start: function')
  else
    vim.health.info('auto_start: ' .. (auto_start and 'on' or 'off'))
  end

  if bundles_ruby_lsp(root) then
    vim.health.warn('ruby-lsp is in ' .. root .. '/Gemfile.lock', {
      'Bundling ruby-lsp is not supported by ruby-lsp.nvim.',
      'The global gem is recommended: gem install ruby-lsp',
    })
  end
end

function M.check()
  vim.health.start('ruby-lsp.nvim')

  -- Check Neovim version (drop build metadata, e.g. "0.12.6+v0.12.6")
  local nvim_version = tostring(vim.version()):gsub('%+.*$', '')
  if vim.fn.has('nvim-' .. utils.MIN_NVIM_VERSION) == 1 then
    vim.health.ok('Neovim ' .. nvim_version)
  else
    vim.health.error('Neovim ' .. nvim_version .. ' is too old (minimum: ' .. utils.MIN_NVIM_VERSION .. ')')
  end

  check_install(vim.fs.root(0, { 'Gemfile', '.git' }) or vim.fn.getcwd())

  -- Check for Ruby LSP server in active clients
  local clients = vim.lsp.get_clients({ name = 'ruby_lsp' })
  if #clients > 0 then
    vim.health.ok('Ruby LSP server is active (' .. #clients .. ' client(s))')

    local server_info = clients[1].server_info
    if server_info and server_info.version then
      local version = server_info.version
      if vim.version.cmp(version, utils.MIN_RUBY_LSP_VERSION) >= 0 then
        vim.health.ok('Ruby LSP version ' .. version)
      else
        vim.health.error(
          'Ruby LSP version ' .. version .. ' is too old (minimum: ' .. utils.MIN_RUBY_LSP_VERSION .. ')',
          {
            'Update ruby-lsp: gem update ruby-lsp ruby-lsp-rails',
            'Then delete .ruby-lsp/ in your project to force a fresh bundle',
          }
        )
      end
    else
      vim.health.warn('Could not determine Ruby LSP server version')
    end

    if utils.full_test_discovery_enabled(clients[1]) then
      vim.health.ok('fullTestDiscovery feature flag is enabled')
    else
      vim.health.warn('fullTestDiscovery feature flag is not enabled', {
        utils.FEATURE_FLAG_MSG,
      })
    end

    -- Check for ruby-lsp-rspec addon in RSpec projects
    local client = clients[1]
    local deps_bufnr = next(client.attached_buffers) or 0
    local ok, deps_resp = pcall(
      client.request_sync,
      client,
      'rubyLsp/workspace/dependencies',
      vim.lsp.util.make_text_document_params(deps_bufnr),
      5000,
      deps_bufnr
    )
    if ok and deps_resp and not deps_resp.err and deps_resp.result then
      local has_rspec = false
      local has_rspec_addon = false
      for _, dep in ipairs(deps_resp.result) do
        if dep.name == 'rspec-core' then
          has_rspec = true
        elseif dep.name == 'ruby-lsp-rspec' then
          has_rspec_addon = true
        end
        if has_rspec and has_rspec_addon then
          break
        end
      end
      if has_rspec and has_rspec_addon then
        vim.health.ok('ruby-lsp-rspec addon is installed')
      elseif has_rspec then
        vim.health.warn('RSpec is a project dependency but the ruby-lsp-rspec addon is not installed', {
          'The ruby-lsp server has no built-in RSpec support. Without the ruby-lsp-rspec addon,',
          'test discovery, code lenses, and test running will not work for RSpec files.',
          'Install: gem "ruby-lsp-rspec", require: false, group: :development',
          'See: https://github.com/st0012/ruby-lsp-rspec',
        })
      else
        vim.health.ok('No RSpec dependency detected (Minitest/Test::Unit project)')
      end
    else
      vim.health.info('Could not query workspace dependencies (server may still be loading)')
    end
  else
    vim.health.info('Ruby LSP server is not active (open a Ruby file to start it)')
  end

  -- Check for nvim-dap
  local dap_ok, dap = pcall(require, 'dap')
  if dap_ok then
    vim.health.ok('nvim-dap is installed')

    if vim.fn.executable('rdbg') == 1 then
      vim.health.ok('rdbg is installed')
    else
      vim.health.info('rdbg not found (debugging needs the debug gem: gem install debug)')
    end

    local adapter_name = config.get().dap.adapter
    if dap.adapters[adapter_name] then
      vim.health.ok("DAP adapter '" .. adapter_name .. "' is registered")
    else
      vim.health.warn(
        "DAP adapter '" .. adapter_name .. "' is not registered",
        { "Call require('ruby-lsp').setup() with dap.auto_configure = true", 'Or configure the adapter manually' }
      )
    end
  else
    vim.health.info('nvim-dap is not installed (debugging will not be available)')
  end

  -- Check for neotest
  local neotest_ok = pcall(require, 'neotest')
  if neotest_ok then
    vim.health.ok('neotest is installed')
  else
    vim.health.info('neotest is not installed (code lens will run tests via executor)')
  end

  -- Check for toggleterm
  local toggleterm_ok = pcall(require, 'toggleterm')
  if toggleterm_ok then
    vim.health.ok('toggleterm.nvim is installed')
  else
    vim.health.info('toggleterm.nvim is not installed (split executor will be used)')
  end
end

return M
