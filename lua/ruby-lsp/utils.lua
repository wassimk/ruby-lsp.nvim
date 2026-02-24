local M = {}

M.FEATURE_FLAG_MSG = "ruby-lsp.nvim requires the fullTestDiscovery feature flag.\n"
  .. "Add to your ruby_lsp LSP config:\n"
  .. "  init_options = { enabledFeatureFlags = { fullTestDiscovery = true } }"

---Check whether the fullTestDiscovery feature flag is enabled on a client.
---@param client vim.lsp.Client
---@return boolean
function M.full_test_discovery_enabled(client)
  local init_options = client.config.init_options or {}
  local flags = init_options.enabledFeatureFlags or {}
  return flags.fullTestDiscovery == true
end

return M
