# Demo GIF

`demo.gif` in the repo root is generated from `ruby-lsp.tape` with [VHS](https://github.com/charmbracelet/vhs). Regenerate it whenever the plugin's behavior or the README demo should change.

## Requirements

- [VHS](https://github.com/charmbracelet/vhs#installation) (`brew install vhs`)
- Neovim >= 0.12, git, and bash
- Ruby and Bundler
- [Ruby LSP](https://github.com/Shopify/ruby-lsp) installed globally (`gem install ruby-lsp`), the way most people run it
- `rdbg`, from the [debug](https://github.com/ruby/debug) gem
- [JetBrainsMono Nerd Font](https://www.nerdfonts.com/font-downloads) (optional, the tape tries MonoLisaCode first and VHS falls back to a default font)
- Network access on the first run, to install the sample's gems and clone the pinned Neovim plugins into `/tmp`

## Regenerate

From the repo root:

```shell
vhs demo/ruby-lsp.tape
```

This overwrites `demo.gif`. Commit it along with any tape changes. The first run takes a few minutes to install gems; later runs reuse them.

## How it works

- `sample/` is a small RSpec project with one deliberately failing example. `setup.sh` copies it to `/tmp/ruby-lsp-demo` and installs its bundle (`debug`, `rspec`, `ruby-lsp-rspec`) into `/tmp/ruby-lsp-demo-bundle`, which is reused across renders.
- `setup.sh` also writes `env.sh`, which keeps Neovim's data and state in the sandbox, ignores personal git config, and runs `bundle` through a symlink in the sandbox so paths shown by the debugger don't reveal where Ruby is installed.
- `init.lua` is a minimal config that loads this checkout of the plugin plus pinned releases of neotest, nvim-dap, nvim-dap-ui, toggleterm, nvim-notify, snacks.nvim (for the code lens picker), and onedark. Ruby LSP is configured inline with `fullTestDiscovery` enabled.
- The tape hides startup until Ruby LSP has drawn its code lenses, then shows the neotest summary, a Run through neotest, Run In Terminal through toggleterm, and Debug with dap-ui.
- Steps wait on screen text (`Wait+Screen`), so if the plugin's behavior changes the render fails instead of recording a broken demo.
