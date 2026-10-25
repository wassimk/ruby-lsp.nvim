# ruby-lsp.nvim

Make [Ruby LSP](https://github.com/Shopify/ruby-lsp) code lenses work in Neovim. **Run**, **Run In Terminal**, and **Debug** appear above your tests, and with this plugin they actually do something: run through [neotest](https://github.com/nvim-neotest/neotest), open a terminal, or start a debugger with [nvim-dap](https://github.com/mfussenegger/nvim-dap).

![demo](demo.gif)

## 💡 Why

Ruby LSP's code lenses call client-side commands like `rubyLsp.runTest` and `rubyLsp.debugTest`. VS Code's Ruby LSP extension implements them, but Neovim doesn't, so choosing a code lens fails with "Language server does not support command".

This plugin implements all five commands through `vim.lsp.commands`, and adds a neotest adapter and an rdbg debug adapter that use Ruby LSP to find and run your tests.

## 📝 Commands

| Command | What it does |
|---|---|
| `rubyLsp.runTest` | Runs the test through neotest if it's installed, otherwise in a terminal |
| `rubyLsp.runTestInTerminal` | Runs the test in a terminal |
| `rubyLsp.debugTest` | Debugs the test with nvim-dap and rdbg |
| `rubyLsp.openFile` | Opens a file, jumping to the line when one is given |
| `rubyLsp.runTask` | Runs a task such as a migration in a terminal |

## 📋 Requirements

- Neovim >= 0.12
- [Ruby LSP](https://github.com/Shopify/ruby-lsp) >= 0.23.0

### Optional

- [neotest](https://github.com/nvim-neotest/neotest) to run tests through neotest
- [nvim-dap](https://github.com/mfussenegger/nvim-dap) and the [debug](https://github.com/ruby/debug) gem in your project's bundle, to debug tests
- [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) to run tests in toggleterm instead of a split
- [ruby-lsp-rspec](https://github.com/st0012/ruby-lsp-rspec) in your Gemfile for RSpec projects. Minitest works out of the box.

## 🛠️ Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "wassimk/ruby-lsp.nvim",
  version = "*",
  ft = "ruby",
  opts = {},
}
```

## 🖥️ Ruby LSP Server Setup

This plugin doesn't start Ruby LSP for you. Configure and enable the server in your own LSP setup, with the `fullTestDiscovery` feature flag turned on. Code lenses and test discovery depend on it.

```lua
vim.lsp.config("ruby_lsp", {
  init_options = {
    enabledFeatureFlags = { fullTestDiscovery = true },
  },
})

vim.lsp.enable("ruby_lsp")
```

With [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) installed, that's all you need: it provides the base `ruby_lsp` config these settings merge into. Its older `require("lspconfig").ruby_lsp.setup()` style is deprecated, and the neotest adapter works best when the server is enabled with `vim.lsp.enable`.

Run `:checkhealth ruby-lsp` to check that the server is running and the feature flag is on.

## 🧪 Neotest

The neotest adapter finds tests with Ruby LSP and runs the commands Ruby LSP resolves for them, so it works the same for Minitest and RSpec, in Rails apps or plain Ruby projects. Register it in your neotest setup:

```lua
require("neotest").setup({
  adapters = {
    require("ruby-lsp.neotest"),
  },
})
```

With neotest installed, the **Run** code lens goes through neotest too, so results show up in neotest's signs, summary, and output. **Run In Terminal** always uses a terminal.

## 🐞 Debugging

When nvim-dap is installed, the plugin registers a `ruby` debug adapter that starts your tests under rdbg. The **Debug** code lens uses it, and so can your own configurations:

```lua
require("dap").configurations.ruby = {
  {
    type = "ruby",
    name = "debug current file",
    request = "attach",
    localfs = true,
    command = { "ruby" },
    script = { "${file}" },
  },
}
```

Sessions stop at your first breakpoint. Set `dap.auto_configure = false` to use your own adapter instead.

## ⚙️ Options

These are the defaults. You only need to pass the ones you want to change.

```lua
require("ruby-lsp").setup({
  -- How to run tests in a terminal.
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
    keep_open = true, -- keep the terminal open after the task finishes
  },

  -- Debugging
  dap = {
    auto_configure = true, -- register the rdbg adapter when nvim-dap is available
    adapter = "ruby",      -- debug adapter type name
  },

  -- Neotest test discovery
  test_discovery = {
    -- show progress while discovering the project's tests,
    -- or while waiting for Ruby LSP to start or finish indexing
    progress = true,
  },
})
```

## 🩺 Health Check

```
:checkhealth ruby-lsp
```

## 🔧 Development

One-time setup to enable the local git hooks:

```shell
make setup
```

The pre-commit hook checks Lua formatting with [stylua](https://github.com/JohnnyMorganz/StyLua) and regenerates `doc/ruby-lsp.nvim.txt` from `README.md` whenever the README is staged. It requires [pandoc](https://pandoc.org/installing.html).

```shell
make lint  # check Lua formatting
make docs  # regenerate vimdoc from README.md
```

## 🙏 Acknowledgements

Thank you to the [Ruby LSP](https://github.com/Shopify/ruby-lsp) team for such a great tool. This isn't an official Ruby LSP project, just my work to make Ruby LSP feel at home in Neovim.
