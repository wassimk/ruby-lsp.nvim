local M = {}

local originals = {}

M.notifications = {}
M.lsp_clients = {}
M.lsp_enabled = {}

function M.setup_mocks()
  M.notifications = {}
  M.lsp_clients = {}
  M.lsp_enabled = {}

  originals.notify = vim.notify
  originals.get_clients = vim.lsp.get_clients
  originals.is_enabled = vim.lsp.is_enabled

  vim.notify = function(msg, level)
    table.insert(M.notifications, { msg = msg, level = level })
  end

  vim.lsp.get_clients = function(opts)
    return M.lsp_clients
  end

  vim.lsp.is_enabled = function(name)
    return M.lsp_enabled[name] == true
  end
end

function M.teardown_mocks()
  vim.notify = originals.notify
  vim.lsp.get_clients = originals.get_clients
  vim.lsp.is_enabled = originals.is_enabled
  originals = {}
end

function M.mock_client(overrides)
  return vim.tbl_deep_extend('force', {
    id = 1,
    name = 'ruby_lsp',
    config = {
      init_options = {
        enabledFeatureFlags = { fullTestDiscovery = true },
      },
    },
  }, overrides or {})
end

return M
