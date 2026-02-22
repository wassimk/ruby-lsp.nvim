local executor = require("ruby-lsp.executor")

local M = {}

---rubyLsp.runTest handler.
---Routes through neotest when available, otherwise falls back to the executor.
---@param command lsp.Command
function M.run_test(command)
  local args = command.arguments or {}
  local cmd = args[3]
  if not cmd then
    vim.notify("ruby-lsp: missing test command in arguments", vim.log.levels.ERROR)
    return
  end

  local neotest_ok, neotest = pcall(require, "neotest")
  if neotest_ok then
    local range = args[4]
    if range and range.start then
      vim.api.nvim_win_set_cursor(0, { range.start.line + 1, 0 })
    end
    neotest.run.run()
    return
  end

  executor.run(cmd, {
    file_path = args[1],
    test_id = args[2],
    test_name = args[5],
  })
end

---rubyLsp.runTestInTerminal handler.
---Always runs via the executor (never routes through neotest).
---@param command lsp.Command
function M.run_test_terminal(command)
  local args = command.arguments or {}
  local cmd = args[3]
  if not cmd then
    vim.notify("ruby-lsp: missing test command in arguments", vim.log.levels.ERROR)
    return
  end

  executor.run(cmd, {
    file_path = args[1],
    test_id = args[2],
    test_name = args[5],
  })
end

---rubyLsp.debugTest handler.
---@param command lsp.Command
function M.debug_test(command)
  local ok, dap_mod = pcall(require, "ruby-lsp.dap")
  if not ok then
    vim.notify("ruby-lsp: failed to load dap module", vim.log.levels.ERROR)
    return
  end

  dap_mod.debug_test(command)
end

---Parse a file URI and optional line number.
---Supports `file:///path#L10` and `file:///path#L10,5` fragments.
---@param uri string
---@return string path
---@return integer? line
---@return integer? col
local function parse_file_uri(uri)
  local fragment_start = uri:find("#")
  local fragment = nil
  local base_uri = uri

  if fragment_start then
    fragment = uri:sub(fragment_start + 1)
    base_uri = uri:sub(1, fragment_start - 1)
  end

  local path = vim.uri_to_fname(base_uri)
  local line, col

  if fragment then
    local l, c = fragment:match("^L(%d+),?(%d*)")
    if l then
      line = tonumber(l)
      col = c ~= "" and tonumber(c) or nil
    end
  end

  return path, line, col
end

---rubyLsp.openFile handler.
---Arguments are [[uri1, uri2, ...]] — a single array of URI strings nested in arguments.
---@param command lsp.Command
function M.open_file(command)
  local args = command.arguments or {}
  local uris = args[1]

  if not uris or #uris == 0 then
    vim.notify("ruby-lsp: no file URI provided", vim.log.levels.WARN)
    return
  end

  local function open_uri(uri)
    local path, line, col = parse_file_uri(uri)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    if line then
      vim.api.nvim_win_set_cursor(0, { line, (col or 1) - 1 })
    end
  end

  if #uris == 1 then
    open_uri(uris[1])
  else
    vim.ui.select(uris, {
      prompt = "Open file:",
      format_item = function(uri)
        return vim.fn.fnamemodify(vim.uri_to_fname(uri:gsub("#.*$", "")), ":t")
      end,
    }, function(choice)
      if choice then
        open_uri(choice)
      end
    end)
  end
end

---rubyLsp.runTask handler.
---@param command lsp.Command
function M.run_task(command)
  local args = command.arguments or {}
  local cmd = args[1]
  if not cmd then
    vim.notify("ruby-lsp: missing task command in arguments", vim.log.levels.ERROR)
    return
  end

  executor.run(cmd)
end

return M
