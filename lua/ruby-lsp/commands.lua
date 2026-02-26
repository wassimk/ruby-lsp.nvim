local executor = require("ruby-lsp.executor")
local utils = require("ruby-lsp.utils")

local M = {}

---Discover tests for a file, find the item matching test_id, resolve the
---shell command via rubyLsp/resolveTestCommands, and run it.
---Defers until indexing is complete to avoid stale cached results.
---@param file_path string
---@param test_id string
local function resolve_and_run(file_path, test_id)
  utils.after_indexing(function()
    local client = utils.get_client()
    if not client then
      vim.notify("ruby-lsp: no ruby_lsp client found", vim.log.levels.ERROR)
      return
    end

    local uri = vim.uri_from_fname(file_path)

    client:request("rubyLsp/discoverTests", { textDocument = { uri = uri } }, function(err, result)
      if err or not result or #result == 0 then
        vim.notify("ruby-lsp: failed to discover tests", vim.log.levels.ERROR)
        return
      end

      local item = utils.find_test_item(result, test_id)
      if not item then
        vim.notify("ruby-lsp: test '" .. test_id .. "' not found", vim.log.levels.ERROR)
        return
      end

      local items = { utils.wrap_test_item(item) }

      client:request("rubyLsp/resolveTestCommands", { items = items }, function(err2, result2)
        if err2 or not result2 or not result2.commands or #result2.commands == 0 then
          vim.notify("ruby-lsp: failed to resolve test command", vim.log.levels.ERROR)
          return
        end
        vim.schedule(function()
          executor.run(result2.commands[1], { file_path = file_path, test_id = test_id })
        end)
      end, 0)
    end, 0)
  end)
end

---rubyLsp.runTest handler.
---Routes through neotest when available, otherwise resolves and runs via the executor.
---@param command lsp.Command
function M.run_test(command)
  local file_path, test_id = utils.validate_test_args(command)
  if not file_path then
    return
  end

  local neotest_ok, neotest = pcall(require, "neotest")
  if neotest_ok then
    neotest.run.run(file_path .. "::" .. test_id)
    return
  end

  resolve_and_run(file_path, test_id)
end

---rubyLsp.runTestInTerminal handler.
---Always runs via the executor (never routes through neotest).
---@param command lsp.Command
function M.run_test_terminal(command)
  local file_path, test_id = utils.validate_test_args(command)
  if not file_path then
    return
  end

  resolve_and_run(file_path, test_id)
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
