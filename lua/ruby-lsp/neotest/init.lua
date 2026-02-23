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
