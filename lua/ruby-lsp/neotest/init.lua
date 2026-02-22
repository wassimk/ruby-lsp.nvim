local NeotestAdapter = { name = "ruby-lsp" }

---Perform an async LSP request using raw coroutines.
---Must be called from within a coroutine (neotest runs adapter methods in one).
---@param client vim.lsp.Client
---@param method string
---@param params table
---@param bufnr integer
---@return lsp.ResponseError? err
---@return any result
local function lsp_request(client, method, params, bufnr)
  local co = coroutine.running()
  assert(co, "lsp_request must be called from a coroutine")

  client:request(method, params, function(err, result)
    coroutine.resume(co, err, result)
  end, bufnr)

  return coroutine.yield()
end

---Convert an LSP Range to a neotest range tuple.
---@param range lsp.Range
---@return integer[]
local function to_neotest_range(range)
  return {
    range.start.line,
    range.start.character,
    range["end"].line,
    range["end"].character,
  }
end

---Map ruby-lsp test item kind to neotest position type.
---@param kind integer 1 = group, 2 = test
---@return string
local function to_neotest_type(kind)
  if kind == 2 then
    return "test"
  end
  return "namespace"
end

---Recursively build a nested list structure for neotest Tree.from_list.
---@param items table[] LSP test items
---@param file_path string
---@return table[]
local function build_tree_list(items, file_path)
  local children = {}
  for _, item in ipairs(items) do
    local cmd = nil
    if item.command and item.command.arguments then
      cmd = item.command.arguments[3]
    end

    local node = {
      {
        id = file_path .. "::" .. item.id,
        name = item.label,
        type = to_neotest_type(item.kind),
        path = file_path,
        range = to_neotest_range(item.range),
        cmd = cmd,
      },
    }

    if item.children and #item.children > 0 then
      local grandchildren = build_tree_list(item.children, file_path)
      for _, gc in ipairs(grandchildren) do
        table.insert(node, gc)
      end
    end

    table.insert(children, node)
  end
  return children
end

---Walk a neotest tree to find the first stored command.
---@param tree neotest.Tree
---@return string|nil
local function find_cmd_in_tree(tree)
  local data = tree:data()
  if data.cmd then
    return data.cmd
  end
  for _, child in ipairs(tree:children()) do
    local cmd = find_cmd_in_tree(child)
    if cmd then
      return cmd
    end
  end
  return nil
end

---Strip test-specific arguments from a command to produce a file-level command.
---Handles minitest (--name / -n) and rspec (:line_number) patterns.
---@param cmd string
---@return string
local function make_file_command(cmd)
  local file_cmd = cmd
  -- minitest: --name "value", --name 'value', --name /regex/, --name value
  file_cmd = file_cmd:gsub("%s+%-%-name%s+['\"].-['\"]", "")
  file_cmd = file_cmd:gsub("%s+%-%-name%s+/.-/", "")
  file_cmd = file_cmd:gsub("%s+%-%-name%s+%S+", "")
  -- minitest: -n "value", -n 'value', -n /regex/, -n value
  file_cmd = file_cmd:gsub("%s+%-n%s+['\"].-['\"]", "")
  file_cmd = file_cmd:gsub("%s+%-n%s+/.-/", "")
  file_cmd = file_cmd:gsub("%s+%-n%s+%S+", "")
  -- rspec: file.rb:42 line numbers
  file_cmd = file_cmd:gsub("%.rb:%d+", ".rb")
  return vim.trim(file_cmd)
end

function NeotestAdapter.root(dir)
  return vim.fs.root(dir, { "Gemfile", ".ruby-version", ".git" })
end

function NeotestAdapter.filter_dir(name)
  local skip = { vendor = true, node_modules = true, [".bundle"] = true, [".git"] = true }
  return not skip[name]
end

function NeotestAdapter.is_test_file(file_path)
  if not file_path or not vim.endswith(file_path, ".rb") then
    return false
  end
  local name = vim.fn.fnamemodify(file_path, ":t")
  return name:match("_test%.rb$") ~= nil
    or name:match("_spec%.rb$") ~= nil
    or name:match("^test_.*%.rb$") ~= nil
end

---Discover test positions via the ruby-lsp language server.
---@param file_path string
---@return neotest.Tree|nil
function NeotestAdapter.discover_positions(file_path)
  local clients = vim.lsp.get_clients({ name = "ruby_lsp" })
  if #clients == 0 then
    return nil
  end

  local client = clients[1]
  local params = {
    textDocument = { uri = vim.uri_from_fname(file_path) },
  }

  local bufnr = vim.fn.bufnr(file_path)
  if bufnr == -1 then
    bufnr = 0
  end

  local err, result = lsp_request(client, "rubyLsp/discoverTests", params, bufnr)

  if err or not result or type(result) ~= "table" or #result == 0 then
    return nil
  end

  local tree_list = {
    {
      id = file_path,
      type = "file",
      name = vim.fn.fnamemodify(file_path, ":t"),
      path = file_path,
    },
  }

  local children = build_tree_list(result, file_path)
  for _, child in ipairs(children) do
    table.insert(tree_list, child)
  end

  local Tree = require("neotest.types").Tree
  return Tree.from_list(tree_list, function(pos)
    return pos.id
  end)
end

---Build a test command spec from a neotest position.
---@param args neotest.RunArgs
---@return neotest.RunSpec|nil
function NeotestAdapter.build_spec(args)
  local position = args.tree:data()
  local tree = args.tree

  if position.type == "test" or position.type == "namespace" then
    local cmd = position.cmd
    if not cmd then
      return nil
    end
    return {
      command = vim.split(cmd, " "),
      context = { pos_id = position.id },
    }
  end

  if position.type == "file" then
    local cmd = find_cmd_in_tree(tree)
    if not cmd then
      return nil
    end
    return {
      command = vim.split(make_file_command(cmd), " "),
      context = { pos_id = position.id },
    }
  end

  return nil
end

---Parse test results from command execution.
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function NeotestAdapter.results(spec, result, tree)
  local results = {}
  local pos_id = spec.context.pos_id
  local status = result.code == 0 and "passed" or "failed"

  results[pos_id] = {
    status = status,
    output = result.output,
  }

  return results
end

setmetatable(NeotestAdapter, {
  __call = function(_, opts)
    return NeotestAdapter
  end,
})

return NeotestAdapter
