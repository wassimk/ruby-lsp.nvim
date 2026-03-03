# ruby-lsp.nvim

Neovim plugin that handles Ruby LSP client-side commands (`rubyLsp.*`) so code lens actions like **Run**, **Run In Terminal**, and **Debug** work natively in Neovim.

## The Problem

Ruby LSP emits code lens actions above test methods and classes, but these trigger client-side commands (`rubyLsp.runTest`, `rubyLsp.runTestInTerminal`, `rubyLsp.debugTest`) that VS Code handles in its extension. Neovim doesn't know about them, so clicking them fails with "Language server does not support command".

This plugin registers handlers for all five `rubyLsp.*` commands via `vim.lsp.commands`.

## Commands Handled

| Command | Behavior |
|---|---|
| `rubyLsp.runTest` | Run test command in terminal |
| `rubyLsp.runTestInTerminal` | Run test command in terminal |
| `rubyLsp.debugTest` | Launch DAP session with rdbg (requires nvim-dap) |
| `rubyLsp.openFile` | Open file URI with line number support |
| `rubyLsp.runTask` | Run rake/migration commands in terminal |

## Requirements

- Neovim >= 0.10
- [ruby-lsp](https://github.com/Shopify/ruby-lsp) >= 0.23.0

### Optional

- [ruby-lsp-rspec](https://github.com/st0012/ruby-lsp-rspec) for RSpec test discovery
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) for debug support
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) for running tests in toggleterm, otherwise falls back to split terminal
- [neotest](https://github.com/nvim-neotest/neotest) for running tests through neotest instead of the terminal

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "wassimk/ruby-lsp.nvim",
  version = "*",
  ft = "ruby",
  opts = {},
}
```

## Ruby LSP Server Setup

This plugin handles client-side commands and neotest integration. You still need to configure the Ruby LSP server yourself in your Neovim LSP setup. The `fullTestDiscovery` feature flag must be enabled for code lens and test discovery to work.

With `vim.lsp.config` (Neovim >= 0.11):

```lua
vim.lsp.config("ruby_lsp", {
  init_options = {
    enabledFeatureFlags = { fullTestDiscovery = true },
  },
})

vim.lsp.enable("ruby_lsp")
```

With [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig):

```lua
require("lspconfig").ruby_lsp.setup({
  init_options = {
    enabledFeatureFlags = { fullTestDiscovery = true },
  },
})
```

Run `:checkhealth ruby-lsp` to verify the server is running and the feature flag is enabled.

## Configuration

```lua
require("ruby-lsp").setup({
  -- How to run tests in terminal.
  -- "split" (builtin) | "toggleterm" | function(cmd, opts)
  executor = "split",

  -- Split executor options
  split = {
    direction = "horizontal", -- "horizontal" | "vertical"
    size = 15,
  },

  -- Toggleterm executor options
  toggleterm = {
    direction = "float", -- "float" | "horizontal" | "vertical"
    close_on_exit = false,
  },

  -- Task runner options (e.g., migrations)
  task = {
    keep_open = true, -- keep terminal open after task completes
  },

  -- DAP configuration
  dap = {
    auto_configure = true, -- register rdbg adapter if nvim-dap is available
    adapter = "ruby",      -- DAP adapter type name
  },
})
```

## Neotest Integration

This plugin includes a [neotest](https://github.com/nvim-neotest/neotest) adapter that uses Ruby LSP for test discovery and command resolution. When neotest is installed, the **Run** code lens (`rubyLsp.runTest`) automatically routes tests through neotest instead of the terminal executor. The **Run In Terminal** code lens always uses the terminal executor regardless of neotest.

The `fullTestDiscovery` feature flag must be enabled in your Ruby LSP server configuration (see [Ruby LSP Server Setup](#ruby-lsp-server-setup)) for test discovery to work.

To enable it, register the adapter in your neotest setup:

```lua
require("neotest").setup({
  adapters = {
    require("ruby-lsp.neotest"),
  },
})
```

## Health Check

```
:checkhealth ruby-lsp
```

## Development

One-time setup to enable local git hooks:

```shell
make setup
```

This activates a pre-commit hook that checks Lua formatting with [stylua](https://github.com/JohnnyMorganz/StyLua) and auto-generates `doc/ruby-lsp.nvim.txt` from `README.md` whenever the README is staged. Requires [pandoc](https://pandoc.org/installing.html).

```shell
make lint  # check Lua formatting
make docs  # regenerate vimdoc from README.md
```

## Acknowledgements

Thank you to [Ruby LSP](https://github.com/Shopify/ruby-lsp) for making such an amazing tool. This is not an official Ruby LSP project. This is just my work to make Ruby LSP work really well in Neovim.
