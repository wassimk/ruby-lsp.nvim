local M = {}

M.MIN_RUBY_LSP_VERSION = "0.23.0"
M.MIN_RUBY_LSP_RAILS_VERSION = "0.4.0"

M.FEATURE_FLAG_MSG = "ruby-lsp.nvim requires the fullTestDiscovery feature flag.\n"
  .. "Add to your ruby_lsp LSP config:\n"
  .. "  init_options = { enabledFeatureFlags = { fullTestDiscovery = true } }"

---@type table<integer, boolean>
local indexing_complete = {}

---Mark a client's indexing as complete and notify waiting consumers.
---@param client_id integer
function M.on_indexing_complete(client_id)
  indexing_complete[client_id] = true
  vim.api.nvim_exec_autocmds("User", { pattern = "RubyLspIndexingComplete" })
end

---Check whether the ruby_lsp server has finished indexing.
---@return boolean
function M.is_indexing_complete()
  local client = M.get_client()
  return client ~= nil and indexing_complete[client.id] == true
end

---Run a function after indexing completes. If already complete, runs immediately.
---For callback-based contexts (commands, dap). Shows a notification while waiting.
---@param fn function
function M.after_indexing(fn)
  if M.is_indexing_complete() then
    fn()
    return
  end
  vim.notify("ruby-lsp: waiting for server indexing to complete...", vim.log.levels.INFO)
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("RubyLspWaitIndexing", { clear = false }),
    pattern = "RubyLspIndexingComplete",
    once = true,
    callback = vim.schedule_wrap(fn),
  })
end

---Check whether the fullTestDiscovery feature flag is enabled on a client.
---@param client vim.lsp.Client
---@return boolean
function M.full_test_discovery_enabled(client)
  local init_options = client.config.init_options or {}
  local flags = init_options.enabledFeatureFlags or {}
  return flags.fullTestDiscovery == true
end

---Get the first active ruby_lsp client, or nil if none is running.
---@return vim.lsp.Client|nil
function M.get_client()
  local clients = vim.lsp.get_clients({ name = "ruby_lsp" })
  if #clients == 0 then
    return nil
  end
  return clients[1]
end

---Recursively search a list of test items (and their children) for a matching ID.
---@param items table[]
---@param target_id string
---@return table|nil
function M.find_test_item(items, target_id)
  for _, item in ipairs(items) do
    if item.id == target_id then
      return item
    end
    if item.children then
      local found = M.find_test_item(item.children, target_id)
      if found then
        return found
      end
    end
  end
  return nil
end

---Build a test item wrapper suitable for rubyLsp/resolveTestCommands.
---@param item table LSP test item
---@return table
function M.wrap_test_item(item)
  return {
    id = item.id,
    label = item.label,
    uri = item.uri,
    range = item.range,
    tags = item.tags or {},
    children = {},
  }
end

return M
