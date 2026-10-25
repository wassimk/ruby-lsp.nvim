local nio = require('nio')
local progress = require('ruby-lsp.progress')
local utils = require('ruby-lsp.utils')

local NeotestAdapter = { name = 'ruby-lsp' }

local POLL_MS = 100
-- Indexing has no time limit since large projects can take minutes on a cold
-- start, but a server that never starts (e.g. a broken bundle) gives up.
local CLIENT_START_TIMEOUT_MS = 120000

local discovery_state = {
  active_count = 0,
  progress_id = nil,
  had_error = false,
  phase = nil,
  warned = false,
}

---Show a waiting stage on the shared discovery progress message, once per stage.
---@param phase string
---@param message string
local function set_phase(phase, message)
  if discovery_state.phase ~= phase then
    discovery_state.phase = phase
    progress.update(discovery_state.progress_id, message)
  end
end

---Wait for the ruby_lsp client to start and finish indexing.
---@return vim.lsp.Client|nil client nil if the server never started
local function wait_for_server()
  local waited_for_client = 0
  while true do
    local client = utils.get_client()
    if client and utils.is_indexing_complete() then
      return client
    end

    if client then
      set_phase('indexing', 'Waiting for Ruby LSP to finish indexing...')
    else
      if waited_for_client >= CLIENT_START_TIMEOUT_MS then
        if not discovery_state.warned then
          discovery_state.warned = true
          vim.notify('ruby-lsp: timed out waiting for the ruby_lsp server to start', vim.log.levels.WARN)
        end
        return nil
      end
      set_phase('starting', 'Waiting for Ruby LSP to start...')
      waited_for_client = waited_for_client + POLL_MS
    end

    nio.sleep(POLL_MS)
  end
end

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
    range['end'].line,
    range['end'].character,
  }
end

---Determine neotest position type from a test item's structure.
---Items with children are namespaces (classes/groups), leaves are tests.
---@param item table LSP test item
---@return string
local function to_neotest_type(item)
  if item.children and #item.children > 0 then
    return 'namespace'
  end
  return 'test'
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
        id = file_path .. '::' .. item.id,
        name = item.label,
        type = to_neotest_type(item),
        path = file_path,
        range = to_neotest_range(item.range),
        lsp_test_item = utils.wrap_test_item(item),
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
  if data.type == 'test' and data.lsp_test_item then
    table.insert(items, data.lsp_test_item)
  end
  for _, child in ipairs(tree:children()) do
    collect_test_items(child, items)
  end
end

function NeotestAdapter.root(dir)
  return vim.fs.root(dir, { 'Gemfile', '.ruby-version', '.git' })
end

function NeotestAdapter.filter_dir(name)
  local skip = { vendor = true, node_modules = true, ['.bundle'] = true, ['.git'] = true }
  return not skip[name]
end

function NeotestAdapter.is_test_file(file_path)
  -- Check that ruby_lsp is enabled rather than running. neotest scans for test
  -- files once and caches the answer, often before the server has started.
  -- The client check covers servers started without vim.lsp.enable().
  if not vim.lsp.is_enabled('ruby_lsp') and not utils.get_client() then
    return false
  end
  if not file_path or not vim.endswith(file_path, '.rb') then
    return false
  end
  local name = file_path:match('[^/]+$') or ''
  return name:match('_test%.rb$') ~= nil or name:match('_spec%.rb$') ~= nil or name:match('^test_.*%.rb$') ~= nil
end

---Discover test positions via the ruby-lsp language server.
---Waits for the server to start and finish indexing before making requests.
---@param file_path string
---@return neotest.Tree|nil
function NeotestAdapter.discover_positions(file_path)
  local file_name = nio.fn.fnamemodify(file_path, ':t')

  discovery_state.active_count = discovery_state.active_count + 1
  if discovery_state.active_count == 1 then
    discovery_state.progress_id = progress.start('Discovering tests...')
  end

  local err, result
  local client = wait_for_server()
  if client then
    discovery_state.phase = 'discovering'
    progress.update(discovery_state.progress_id, 'Discovering: ' .. file_name)

    local bufnr = nio.fn.bufnr(file_path)
    if bufnr == -1 then
      bufnr = 0
    end
    local params = {
      textDocument = { uri = vim.uri_from_fname(file_path) },
    }
    err, result = lsp_request(client, 'rubyLsp/discoverTests', params, bufnr)
  else
    err = 'ruby_lsp server did not start'
  end

  if err then
    discovery_state.had_error = true
  end

  discovery_state.active_count = discovery_state.active_count - 1
  if discovery_state.active_count == 0 then
    if discovery_state.progress_id then
      local success = not discovery_state.had_error
      progress.finish(discovery_state.progress_id, success and 'Tests discovered' or 'Test discovery failed', success)
    end
    discovery_state.progress_id = nil
    discovery_state.had_error = false
    discovery_state.phase = nil
    discovery_state.warned = false
  end

  if err or not result or type(result) ~= 'table' or #result == 0 then
    return nil
  end

  local last_line = 0
  for _, item in ipairs(result) do
    local end_line = item.range and item.range['end'] and item.range['end'].line or 0
    if end_line > last_line then
      last_line = end_line
    end
  end

  local tree_list = {
    {
      id = file_path,
      type = 'file',
      name = file_name,
      path = file_path,
      range = { 0, 0, last_line, 0 },
    },
  }

  local children = build_tree_list(result, file_path)
  for _, child in ipairs(children) do
    table.insert(tree_list, child)
  end

  local Tree = require('neotest.types').Tree
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
  if position.type == 'test' then
    if position.lsp_test_item then
      table.insert(items, position.lsp_test_item)
    end
  else
    collect_test_items(tree, items)
  end

  if #items == 0 then
    return nil
  end

  local client = utils.get_client()
  if not client then
    return nil
  end
  local bufnr = nio.fn.bufnr(position.path)
  if bufnr == -1 then
    bufnr = 0
  end

  local err, result = lsp_request(client, 'rubyLsp/resolveTestCommands', { items = items }, bufnr)

  if err or not result or not result.commands or #result.commands == 0 then
    return nil
  end

  -- Extract framework from the first test item's tags (e.g. "framework:rspec")
  local framework
  local tags = items[1].tags
  if tags then
    for _, tag in ipairs(tags) do
      local fw = tag:match('^framework:(.*)')
      if fw then
        framework = fw
        break
      end
    end
  end

  return {
    command = vim.split(result.commands[1], ' '),
    context = { pos_id = position.id, framework = framework },
  }
end

---Strip ANSI escape sequences from a string.
---@param s string
---@return string
local function strip_ansi(s)
  return s:gsub('\27%[[%d;]*m', '')
end

---Parse Minitest output to extract failed test IDs.
---Looks for "N) Failure:" or "N) Error:" markers followed by "ClassName#test_method".
---@param output_path string
---@return table<string, boolean>
local function parse_minitest_failures(output_path)
  local failed = {}
  local f = io.open(output_path, 'r')
  if not f then
    return failed
  end

  local in_failure = false
  for raw_line in f:lines() do
    local line = strip_ansi(raw_line)
    if line:match('^%s*%d+%) Failure:') or line:match('^%s*%d+%) Error:') then
      in_failure = true
    elseif in_failure then
      local test_id = line:match('^(%S+#%S+)')
      if test_id then
        -- Strip trailing " [file:line]:" portion
        test_id = test_id:match('^([^%[]+)')
        failed[test_id] = true
      end
      in_failure = false
    end
  end

  f:close()
  return failed
end

---Parse RSpec output to extract failed test line numbers.
---Reads the "Failed examples:" section and extracts file:line pairs.
---Returns 0-indexed line numbers to match LSP range convention.
---@param output_path string
---@return table<integer, boolean>
local function parse_rspec_failures(output_path)
  local failed_lines = {}
  local f = io.open(output_path, 'r')
  if not f then
    return failed_lines
  end

  local in_failed_examples = false
  for raw_line in f:lines() do
    local line = strip_ansi(raw_line)
    if line:match('^Failed examples:') then
      in_failed_examples = true
    elseif in_failed_examples then
      local line_num = line:match('^rspec %S+:(%d+)')
      if line_num then
        failed_lines[tonumber(line_num) - 1] = true
      end
    end
  end

  f:close()
  return failed_lines
end

---Recursively mark each leaf test node with its result.
---@param node neotest.Tree
---@param failed table<string|integer, boolean> Failed test IDs (Minitest) or 0-indexed line numbers (RSpec)
---@param framework string|nil "rspec" or "minitest"
---@param output string
---@param results table<string, neotest.Result>
local function assign_test_results(node, failed, framework, output, results)
  local data = node:data()
  if data.type == 'test' and data.lsp_test_item then
    local test_failed
    if framework == 'rspec' then
      test_failed = data.lsp_test_item.range and failed[data.lsp_test_item.range.start.line] or false
    else
      test_failed = failed[data.lsp_test_item.id] or false
    end
    results[data.id] = {
      status = test_failed and 'failed' or 'passed',
      output = output,
    }
  end
  for _, child in ipairs(node:children()) do
    assign_test_results(child, failed, framework, output, results)
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
  local framework = spec.context.framework

  if result.code == 0 then
    -- All tests passed — mark every leaf
    assign_test_results(tree, {}, framework, result.output, results)
  else
    local failed
    if framework == 'rspec' then
      failed = parse_rspec_failures(result.output)
    else
      failed = parse_minitest_failures(result.output)
    end
    if next(failed) then
      assign_test_results(tree, failed, framework, result.output, results)
    else
      -- Could not parse individual failures — fall back to marking parent
      results[pos_id] = { status = 'failed', output = result.output }
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
