local server = require('ruby-lsp.server')

return {
  cmd = server.cmd,
  filetypes = { 'ruby', 'eruby' },
  root_dir = server.root_dir,
  reuse_client = function(client, config)
    config.cmd_cwd = config.root_dir
    return client.name == config.name and client.config.root_dir == config.root_dir
  end,
  init_options = {
    formatter = 'auto',
    enabledFeatureFlags = { fullTestDiscovery = true },
  },
}
