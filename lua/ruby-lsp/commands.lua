local executor = require("ruby-lsp.executor")

local M = {}

---rubyLsp.runTest handler.
---@param command lsp.Command
function M.run_test(command)
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

---rubyLsp.runTestInTerminal handler.
---@param command lsp.Command
function M.run_test_terminal(command)
  M.run_test(command)
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
---@param command lsp.Command
function M.open_file(command)
  local args = command.arguments or {}

  if #args == 0 then
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

  if #args == 1 then
    open_uri(args[1])
  else
    vim.ui.select(args, { prompt = "Open file:" }, function(choice)
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
