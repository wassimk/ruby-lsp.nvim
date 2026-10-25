--
-- Minimal config for recording the README demo with VHS (see demo/ruby-lsp.tape)
--

local demo_dir = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
local plugin_dir = vim.fn.fnamemodify(demo_dir, ':h')

---Clone a plugin into /tmp once, pinned to a tag or commit
local function clone(repo, ref)
  local dir = '/tmp/' .. repo:match('[^/]+$') .. '-' .. ref
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.system({ 'git', 'clone', '--quiet', '--filter=blob:none', 'https://github.com/' .. repo, dir })
    vim.fn.system({ 'git', '-C', dir, 'checkout', '--quiet', ref })
  end
  vim.opt.rtp:append(dir)
end

-- Pinned plugins may call deprecated APIs; keep those warnings out of the recording
vim.deprecate = function() end

vim.opt.rtp:prepend(plugin_dir)
clone('navarasu/onedark.nvim', 'master')
clone('rcarriga/nvim-notify', 'v3.15.0')
clone('folke/snacks.nvim', 'v2.31.0')
clone('nvim-lua/plenary.nvim', 'v0.1.4')
clone('nvim-neotest/nvim-nio', 'v1.10.1')
clone('nvim-neotest/neotest', 'v5.20.0')
clone('mfussenegger/nvim-dap', '0.10.0')
clone('rcarriga/nvim-dap-ui', 'v4.0.0')
clone('akinsho/toggleterm.nvim', 'v2.13.1')

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.swapfile = false
vim.opt.wrap = false
vim.opt.signcolumn = 'yes'
vim.opt.shortmess:append('I')
vim.opt.statusline = " %{expand('%:.')} %m%=%l:%c "
vim.opt.winborder = 'rounded'
-- Keys pressed for mappings stay off screen, so popups appear without showing how
vim.opt.showcmd = false
vim.g.mapleader = ' '

require('onedark').setup({ style = 'darker' })
require('onedark').load()

-- Notifications and vim.ui.select styled like the author's setup
require('notify').setup({ render = 'wrapped-compact', stages = 'static', timeout = 3000 })
vim.notify = require('notify')
require('snacks').setup({ picker = { enabled = true, ui_select = true } })

-- Ruby LSP, defined inline so the demo doesn't need nvim-lspconfig
vim.lsp.config('ruby_lsp', {
  cmd = { 'ruby-lsp' },
  filetypes = { 'ruby' },
  root_markers = { 'Gemfile', '.git' },
  init_options = {
    enabledFeatureFlags = { fullTestDiscovery = true },
    -- The sample has no RuboCop, so skip formatting and linting instead of warning about it
    formatter = 'none',
    linters = {},
  },
})
vim.lsp.enable('ruby_lsp')

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client:supports_method('textDocument/codeLens') then
      vim.lsp.codelens.enable(true, { bufnr = args.buf })
    end
  end,
})

-- Run the code lens on the cursor line (the author's mapping)
vim.keymap.set('n', 'gll', vim.lsp.codelens.run, { desc = 'codelens run' })

require('toggleterm').setup()

-- Run In Terminal opens a horizontal toggleterm, like the author's config
require('ruby-lsp').setup({
  executor = 'toggleterm',
  toggleterm = { direction = 'horizontal' },
  test_discovery = { progress = false },
})

-- Neotest with the ruby-lsp adapter. With neotest installed, the Run code lens goes through it.
require('neotest').setup({
  adapters = { require('ruby-lsp.neotest') },
  -- Plain status characters, so the gutter renders cleanly and the tape can wait on them.
  -- No sign until a test has run, like the author's config.
  icons = {
    passed = '✔',
    failed = '✖',
    running = '●',
    skipped = '○',
    unknown = ' ',
    test = ' ',
    namespace = ' ',
  },
  output = { open_on_run = false },
  -- Narrower than the author's 70 columns so code, summary, and dap-ui fit in the recording
  summary = { open = 'botright vsplit | vertical resize 34' },
})
vim.keymap.set('n', '<leader>ts', function()
  require('neotest').summary.toggle()
end, { desc = 'summary sidebar' })
-- nvim-dap with the author's signs and keymaps. ruby-lsp.nvim registers the rdbg adapter.
vim.fn.sign_define('DapBreakpoint', { text = '●', texthl = 'DiagnosticError' })
vim.fn.sign_define('DapStopped', { text = '▶', texthl = 'DiagnosticWarn', linehl = 'Visual' })
local dap = require('dap')
local widgets = require('dap.ui.widgets')
vim.keymap.set('n', '<leader>db', dap.toggle_breakpoint, { desc = 'toggle breakpoint' })
vim.keymap.set('n', '<leader>dd', dap.continue, { desc = 'debug / continue' })
vim.keymap.set('n', '<leader>dh', function()
  widgets.hover()
end, { desc = 'hover popup' })

-- dap-ui opening on attach and closing when the session ends, like the author's config.
-- Scopes, breakpoints, and the REPL (with its controls) only, so the recording isn't crowded.
local dapui = require('dapui')
dapui.setup({
  icons = { expanded = '▾', collapsed = '▸', current_frame = '▸' },
  layouts = {
    { elements = { { id = 'scopes', size = 0.5 }, { id = 'breakpoints', size = 0.5 } }, size = 40, position = 'left' },
    { elements = { { id = 'repl', size = 1 } }, size = 10, position = 'bottom' },
  },
})
dap.listeners.before.attach.dapui_config = dapui.open
dap.listeners.before.launch.dapui_config = dapui.open
dap.listeners.before.event_terminated.dapui_config = dapui.close
dap.listeners.before.event_exited.dapui_config = dapui.close

vim.keymap.set('n', '<leader>th', function()
  require('neotest').output.open({ short = true })
end, { desc = 'test output float' })
