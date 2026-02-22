local M = {}

function M.check()
  vim.health.start("ruby-lsp.nvim")

  -- Check for Ruby LSP server in active clients
  local clients = vim.lsp.get_clients({ name = "ruby_lsp" })
  if #clients > 0 then
    vim.health.ok("Ruby LSP server is active (" .. #clients .. " client(s))")
  else
    vim.health.info("Ruby LSP server is not active (open a Ruby file to start it)")
  end

  -- Check for nvim-dap
  local dap_ok, dap = pcall(require, "dap")
  if dap_ok then
    vim.health.ok("nvim-dap is installed")

    local config = require("ruby-lsp.config")
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
