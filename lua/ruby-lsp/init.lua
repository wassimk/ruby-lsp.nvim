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

  local group = vim.api.nvim_create_augroup("RubyLsp", { clear = true })

  -- WORKAROUND: ruby-lsp-rails addon sends $/progress notifications with
  -- explicit null fields (e.g., message: null, percentage: null). This happens
  -- because the addon's server.rb builds raw Ruby hashes where nil values
  -- serialize as JSON null, unlike the core ruby-lsp server which uses
  -- Interface objects that omit nil fields entirely.
  --
  -- Neovim decodes JSON null as vim.NIL (truthy userdata). Notification plugins
  -- like fidget.nvim expect string|nil for the message field and crash with
  -- "message: expected string, got userdata" when they encounter vim.NIL.
  --
  -- This wraps the $/progress handler for the ruby_lsp client to convert
  -- vim.NIL values to nil before they reach the LspProgress autocmd.
  --
  -- Upstream fix: open an issue against Shopify/ruby-lsp-rails to use the
  -- Interface objects (WorkDoneProgressBegin, etc.) or strip nil values from
  -- the hash before serialization in begin_progress/report_progress.
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client or client.name ~= "ruby_lsp" then
        return
      end
      if client._ruby_lsp_nvim_attached then
        return
      end
      client._ruby_lsp_nvim_attached = true

      local default_progress = vim.lsp.handlers["$/progress"]
      if default_progress then
        client.handlers["$/progress"] = function(err, result, ctx, cfg2)
          if result and type(result.value) == "table" then
            for k, v in pairs(result.value) do
              if v == vim.NIL then
                result.value[k] = nil
              end
            end
          end
          return default_progress(err, result, ctx, cfg2)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspProgress", {
    group = group,
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if not client or client.name ~= "ruby_lsp" then
        return
      end
      local token = ev.data.params.token
      local value = ev.data.params.value
      if token == "indexing-progress" and value and value.kind == "end" then
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
