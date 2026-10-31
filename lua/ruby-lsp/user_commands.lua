local M = {}

---@param what string
---@param err table
local function notify_error(what, err)
  local detail = type(err.message) == 'string' and err.message or vim.inspect(err)
  vim.notify('ruby-lsp: ' .. what .. ': ' .. detail, vim.log.levels.ERROR)
end

---@param client vim.lsp.Client
---@param bufnr integer
local function add_show_dependencies(client, bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, 'RubyLspShowDependencies', function(opts)
    local params = vim.lsp.util.make_text_document_params(bufnr)
    local show_all = opts.args == 'all'

    client:request('rubyLsp/workspace/dependencies', params, function(err, result)
      if err then
        notify_error('could not show dependencies', err)
        return
      end

      local items = {}
      for _, item in ipairs(result or {}) do
        if show_all or item.dependency then
          table.insert(items, {
            text = string.format('%s (%s) - %s', item.name, item.version, tostring(item.dependency)),
            filename = item.path,
          })
        end
      end

      vim.fn.setqflist(items)
      vim.cmd('copen')
    end, bufnr)
  end, {
    nargs = '?',
    desc = 'Show Ruby dependencies for the current workspace',
    complete = function()
      return { 'all' }
    end,
  })
end

---@param client vim.lsp.Client
---@param bufnr integer
local function add_show_syntax_tree(client, bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, 'RubyLspShowSyntaxTree', function()
    local winid = vim.fn.bufwinid(bufnr)
    local params = vim.lsp.util.make_position_params(winid == -1 and 0 or winid, client.offset_encoding)

    client:request('rubyLsp/textDocument/showSyntaxTree', params, function(err, result)
      if err then
        notify_error('could not show the syntax tree', err)
        return
      end

      local lines = {}
      for line in (result and result.ast or ''):gmatch('[^\r\n]+') do
        table.insert(lines, line)
      end

      vim.cmd.vnew()
      local buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.keymap.set('n', 'q', '<cmd>quit<CR>', { buffer = buf, silent = true })
    end, bufnr)
  end, {
    desc = 'Show the Ruby syntax tree for the current buffer',
  })
end

---@param tests table[]
---@param items table[]
local function flatten_tests(tests, items)
  for _, test in ipairs(tests) do
    table.insert(items, {
      text = test.label,
      filename = vim.uri_to_fname(test.uri),
      lnum = test.range.start.line + 1,
      col = test.range.start.character + 1,
    })
    if test.children then
      flatten_tests(test.children, items)
    end
  end
end

---@param client vim.lsp.Client
---@param bufnr integer
local function add_discover_tests(client, bufnr)
  vim.api.nvim_buf_create_user_command(bufnr, 'RubyLspDiscoverTests', function()
    local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

    client:request('rubyLsp/discoverTests', params, function(err, result)
      if err then
        notify_error('could not discover tests', err)
        return
      end

      local items = {}
      flatten_tests(result or {}, items)

      vim.fn.setqflist(items)
      vim.cmd('copen')
    end, bufnr)
  end, {
    desc = 'Discover Ruby tests in the current file',
  })
end

--- Creates the buffer-local :RubyLsp* commands for a ruby_lsp client.
---@param client vim.lsp.Client
---@param bufnr integer
function M.attach(client, bufnr)
  add_show_dependencies(client, bufnr)
  add_show_syntax_tree(client, bufnr)
  add_discover_tests(client, bufnr)
end

return M
