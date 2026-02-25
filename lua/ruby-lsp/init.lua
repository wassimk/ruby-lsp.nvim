local config = require("ruby-lsp.config")
local commands = require("ruby-lsp.commands")
local utils = require("ruby-lsp.utils")

local M = {}

---@param opts? table
function M.setup(opts)
  config.setup(opts)

  vim.lsp.commands["rubyLsp.runTest"] = commands.run_test
  vim.lsp.commands["rubyLsp.runTestInTerminal"] = commands.run_test_terminal
  vim.lsp.commands["rubyLsp.debugTest"] = commands.debug_test
  vim.lsp.commands["rubyLsp.openFile"] = commands.open_file
  vim.lsp.commands["rubyLsp.runTask"] = commands.run_task

  vim.api.nvim_create_autocmd("LspProgress", {
    group = vim.api.nvim_create_augroup("RubyLspIndexing", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client or client.name ~= "ruby_lsp" then
        return
      end
      local token = ev.data.params.token
      local value = ev.data.params.value
      if token == "indexing-progress" and value.kind == "end" then
        utils.on_indexing_complete(client.id)
        utils.check_rspec_addon(client)
      end
    end,
  })

  local cfg = config.get()
  if cfg.dap.auto_configure then
    local dap_mod = require("ruby-lsp.dap")
    dap_mod.setup_adapter()
  end
end

return M
