local config = require("ruby-lsp.config")
local utils = require("ruby-lsp.utils")

local M = {}

function M.check()
  vim.health.start("ruby-lsp.nvim")

  -- Check for Ruby LSP server in active clients
  local clients = vim.lsp.get_clients({ name = "ruby_lsp" })
  if #clients > 0 then
    vim.health.ok("Ruby LSP server is active (" .. #clients .. " client(s))")

    local server_info = clients[1].server_info
    if server_info and server_info.version then
      local version = server_info.version
      if vim.version.cmp(version, utils.MIN_RUBY_LSP_VERSION) >= 0 then
        vim.health.ok("Ruby LSP version " .. version)
      else
        vim.health.error(
          "Ruby LSP version " .. version .. " is too old (minimum: " .. utils.MIN_RUBY_LSP_VERSION .. ")",
          { "Update ruby-lsp: gem update ruby-lsp ruby-lsp-rails", "Then delete .ruby-lsp/ in your project to force a fresh bundle" }
        )
      end
    else
      vim.health.warn("Could not determine Ruby LSP server version")
    end

    if utils.full_test_discovery_enabled(clients[1]) then
      vim.health.ok("fullTestDiscovery feature flag is enabled")
    else
      vim.health.warn("fullTestDiscovery feature flag is not enabled", {
        utils.FEATURE_FLAG_MSG,
      })
    end
  else
    vim.health.info("Ruby LSP server is not active (open a Ruby file to start it)")
  end

  -- Check for nvim-dap
  local dap_ok, dap = pcall(require, "dap")
  if dap_ok then
    vim.health.ok("nvim-dap is installed")

    local adapter_name = config.get().dap.adapter
    if dap.adapters[adapter_name] then
      vim.health.ok("DAP adapter '" .. adapter_name .. "' is registered")
    else
      vim.health.warn(
        "DAP adapter '" .. adapter_name .. "' is not registered",
        { "Call require('ruby-lsp').setup() with dap.auto_configure = true", "Or configure the adapter manually" }
      )
    end
  else
    vim.health.info("nvim-dap is not installed (debugging will not be available)")
  end

  -- Check for neotest
  local neotest_ok = pcall(require, "neotest")
  if neotest_ok then
    vim.health.ok("neotest is installed")
  else
    vim.health.info("neotest is not installed (code lens will run tests via executor)")
  end

  -- Check for toggleterm
  local toggleterm_ok = pcall(require, "toggleterm")
  if toggleterm_ok then
    vim.health.ok("toggleterm.nvim is installed")
  else
    vim.health.info("toggleterm.nvim is not installed (split executor will be used)")
  end
end

return M
