local config = require("ruby-lsp.config")
local commands = require("ruby-lsp.commands")

local M = {}

---@param opts? table
function M.setup(opts)
  config.setup(opts)

  vim.lsp.commands["rubyLsp.runTest"] = commands.run_test
  vim.lsp.commands["rubyLsp.runTestInTerminal"] = commands.run_test_terminal
  vim.lsp.commands["rubyLsp.debugTest"] = commands.debug_test
  vim.lsp.commands["rubyLsp.openFile"] = commands.open_file
  vim.lsp.commands["rubyLsp.runTask"] = commands.run_task

  local cfg = config.get()
  if cfg.dap.auto_configure then
    local dap_mod = require("ruby-lsp.dap")
    dap_mod.setup_adapter()
  end
end

return M
