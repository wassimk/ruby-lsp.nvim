# ruby-lsp.nvim

> [!CAUTION]
> This project is in active development and will very likely be broken for you. Use at your own risk.

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
- [ruby-lsp](https://github.com/Shopify/ruby-lsp) language server

### Optional

- [nvim-dap](https://github.com/mfussenegger/nvim-dap) for `rubyLsp.debugTest` support
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) for the `toggleterm` executor

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "wassimk/ruby-lsp.nvim",
  ft = "ruby",
  opts = {},
}
```

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

  -- DAP configuration
  dap = {
    auto_configure = true, -- register rdbg adapter if nvim-dap is available
    adapter = "ruby",      -- DAP adapter type name
  },
})
```

## Health Check

```
:checkhealth ruby-lsp
```

## Acknowledgements

Thank you to [Ruby LSP](https://github.com/Shopify/ruby-lsp) for making such an amazing product. This is not an official Ruby LSP project. This is just my work to make Ruby LSP work really well in Neovim.
