local nio = require("nio")

local NeotestAdapter = { name = "ruby-lsp" }

---Perform an async LSP request compatible with nio's coroutine scheduler.
---@param client vim.lsp.Client
---@param method string
---@param params table
---@param bufnr integer
---@return lsp.ResponseError? err
---@return any result
local lsp_request = nio.wrap(function(client, method, params, bufnr, cb)
  client:request(method, params, function(err, result)
    cb(err, result)
  end, bufnr)
end, 5)

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

---Determine neotest position type from a test item's structure.
---Items with children are namespaces (classes/groups), leaves are tests.
---@param item table LSP test item
---@return string
local function to_neotest_type(item)
  if item.children and #item.children > 0 then
    return "namespace"
  end
  return "test"
end

---Recursively build a nested list structure for neotest Tree.from_list.
---Stores the raw LSP test item on each position for use in build_spec.
---@param items table[] LSP test items
---@param file_path string
---@return table[]
local function build_tree_list(items, file_path)
  local children = {}
  for _, item in ipairs(items) do
    local node = {
      {
        id = file_path .. "::" .. item.id,
        name = item.label,
        type = to_neotest_type(item),
        path = file_path,
        range = to_neotest_range(item.range),
        lsp_test_item = {
          id = item.id,
          label = item.label,
          uri = item.uri,
          range = item.range,
          tags = item.tags or {},
          children = {},
        },
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

---Recursively collect leaf test items from a neotest tree.
---Only collects items with type "test", skipping namespaces.
---@param tree neotest.Tree
---@param items table[]
local function collect_test_items(tree, items)
  local data = tree:data()
  if data.type == "test" and data.lsp_test_item then
    table.insert(items, data.lsp_test_item)
  end
  for _, child in ipairs(tree:children()) do
    collect_test_items(child, items)
  end
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
  local name = file_path:match("[^/]+$") or ""
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

  local bufnr = nio.fn.bufnr(file_path)
  if bufnr == -1 then
    bufnr = 0
  end

  local err, result = lsp_request(client, "rubyLsp/discoverTests", params, bufnr)

  if err or not result or type(result) ~= "table" or #result == 0 then
    return nil
  end

  local last_line = 0
  for _, item in ipairs(result) do
    local end_line = item.range and item.range["end"] and item.range["end"].line or 0
    if end_line > last_line then
      last_line = end_line
    end
  end

  local tree_list = {
    {
      id = file_path,
      type = "file",
      name = nio.fn.fnamemodify(file_path, ":t"),
      path = file_path,
      range = { 0, 0, last_line, 0 },
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
---Resolves the actual shell command via rubyLsp/resolveTestCommands.
---@param args neotest.RunArgs
---@return neotest.RunSpec|nil
function NeotestAdapter.build_spec(args)
  local position = args.tree:data()
  local tree = args.tree

  local items = {}
  if position.type == "test" then
    if position.lsp_test_item then
      table.insert(items, position.lsp_test_item)
    end
  else
    collect_test_items(tree, items)
  end

  if #items == 0 then
    return nil
  end

  local clients = vim.lsp.get_clients({ name = "ruby_lsp" })
  if #clients == 0 then
    return nil
  end

  local client = clients[1]
  local bufnr = nio.fn.bufnr(position.path)
  if bufnr == -1 then
    bufnr = 0
  end

  local err, result = lsp_request(client, "rubyLsp/resolveTestCommands", { items = items }, bufnr)

  if err or not result or not result.commands or #result.commands == 0 then
    return nil
  end

  return {
    command = vim.split(result.commands[1], " "),
    context = { pos_id = position.id },
  }
end

---Parse Minitest output to extract failed test IDs.
---Looks for "N) Failure:" or "N) Error:" markers followed by "ClassName#test_method".
---@param output_path string
---@return table<string, boolean>
local function parse_failed_tests(output_path)
  local failed = {}
  local f = io.open(output_path, "r")
  if not f then
    return failed
  end

  local in_failure = false
  for line in f:lines() do
    if line:match("^%s*%d+%) Failure:") or line:match("^%s*%d+%) Error:") then
      in_failure = true
    elseif in_failure then
      local test_id = line:match("^(%S+#%S+)")
      if test_id then
        -- Strip trailing " [file:line]:" portion
        test_id = test_id:match("^([^%[]+)")
        failed[test_id] = true
      end
      in_failure = false
    end
  end

  f:close()
  return failed
end

---Recursively mark each leaf test node with its result.
---@param node neotest.Tree
---@param failed table<string, boolean>
---@param output string
---@param results table<string, neotest.Result>
local function assign_test_results(node, failed, output, results)
  local data = node:data()
  if data.type == "test" then
    local test_failed = data.lsp_test_item and failed[data.lsp_test_item.id] or false
    results[data.id] = {
      status = test_failed and "failed" or "passed",
      output = output,
    }
  end
  for _, child in ipairs(node:children()) do
    assign_test_results(child, failed, output, results)
  end
end

---Parse test results from command execution.
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function NeotestAdapter.results(spec, result, tree)
  local results = {}
  local pos_id = spec.context.pos_id

  if result.code == 0 then
    -- All tests passed — mark every leaf
    assign_test_results(tree, {}, result.output, results)
  else
    -- Parse output to identify which specific tests failed
    local failed = parse_failed_tests(result.output)
    if next(failed) then
      assign_test_results(tree, failed, result.output, results)
    else
      -- Could not parse individual failures — fall back to marking parent
      results[pos_id] = { status = "failed", output = result.output }
    end
  end

  return results
end

setmetatable(NeotestAdapter, {
  __call = function(_, opts)
    return NeotestAdapter
  end,
})

return NeotestAdapter
