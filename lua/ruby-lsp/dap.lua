local config = require('ruby-lsp.config')
local utils = require('ruby-lsp.utils')

local M = {}

---Find the Gemfile root for a buffer.
---@param bufnr integer
---@return string|nil
function M.project_root(bufnr)
  return vim.fs.root(bufnr, 'Gemfile')
end

---Build the rdbg executable for a buffer. Runs under Bundler from the Gemfile root when there
---is one, otherwise runs rdbg directly from the buffer's directory.
---@param bufnr integer
---@param dap_config table
---@return {command: string, args: string[], cwd: string}
function M.executable(bufnr, dap_config)
  local root = M.project_root(bufnr)
  local args = { '--open', '--port', '${port}', '--command', '--' }
  local command = 'rdbg'
  local cwd

  if root then
    command = 'bundle'
    args = vim.list_extend({ 'exec', 'rdbg' }, args)
    vim.list_extend(args, { 'bundle', 'exec' })
    cwd = root
  else
    cwd = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  end

  vim.list_extend(args, dap_config.command)
  vim.list_extend(args, dap_config.script)
  if dap_config.script_args then
    vim.list_extend(args, dap_config.script_args)
  end

  return { command = command, args = args, cwd = cwd }
end

---Register the rdbg DAP adapter if nvim-dap is available and no adapter is already set.
function M.setup_adapter()
  local ok, dap = pcall(require, 'dap')
  if not ok then
    return
  end

  local cfg = config.get().dap
  local adapter_name = cfg.adapter

  if dap.adapters[adapter_name] then
    return
  end

  dap.adapters[adapter_name] = function(callback, dap_config)
    local function start(bufnr, exec_config)
      callback({
        type = 'server',
        host = '127.0.0.1',
        port = '${port}',
        executable = M.executable(bufnr, exec_config),
      })
    end

    -- The provided configurations name a buffer instead of a command. Resolve it through
    -- Ruby LSP, and start no session when there's nothing to debug.
    local target = dap_config.ruby_lsp_target
    if type(target) == 'table' and target.file then
      M.resolve_file(target.bufnr, function(exec_config)
        if exec_config then
          vim.list_extend(exec_config.script_args, dap_config.script_args or {})
          start(target.bufnr, exec_config)
        end
      end)
      return
    end
    if type(target) == 'table' then
      M.resolve_nearest(target.bufnr, target.line, function(cmd)
        if cmd then
          start(target.bufnr, M.parse_shell_command(cmd))
        end
      end)
      return
    end

    start(vim.api.nvim_get_current_buf(), dap_config)
  end

  -- Provide configurations instead of assigning dap.configurations.ruby, so a user who
  -- assigns that list keeps it and still sees ours. Older nvim-dap has no providers.
  if cfg.configurations and dap.providers and dap.providers.configs then
    dap.providers.configs['ruby-lsp.nvim'] = function(bufnr)
      local filetype = vim.b[bufnr]['dap-srcft'] or vim.bo[bufnr].filetype
      if filetype ~= 'ruby' then
        return {}
      end
      return M.configurations()
    end
  end

  -- rdbg pauses at startup so nvim-dap can set breakpoints before any code runs (with
  -- --nonstop, breakpoints are missed). Continue past that pause, so the session stops at
  -- the first breakpoint instead. The request goes straight to the session because
  -- nvim-dap only marks it stopped after this listener runs, so dap.continue() is a no-op.
  local started = setmetatable({}, { __mode = 'k' })
  dap.listeners.after.event_stopped['ruby-lsp'] = function(session, body)
    if session.config.type ~= adapter_name or started[session] then
      return
    end

    started[session] = true
    if body.reason == 'pause' then
      session:request('continue', { threadId = body.threadId })
    end
  end
end

---Parse a shell command string into DAP config fields.
---
---Example input: "bundle exec ruby -Itest /path/to/test.rb --name FooTest#test_bar"
---
---Strips leading `bundle exec` (the DAP adapter adds it).
---Splits at the `.rb` file to separate command from script/args.
---
---@param shell_cmd string
---@return {command: string[], script: string[], script_args: string[]}
function M.parse_shell_command(shell_cmd)
  local tokens = utils.shell_split(shell_cmd)

  -- Strip leading "bundle exec" since the DAP adapter adds it
  if #tokens >= 2 and tokens[1] == 'bundle' and tokens[2] == 'exec' then
    table.remove(tokens, 1)
    table.remove(tokens, 1)
  end

  -- Find the .rb file token to split command from script/args
  local rb_index = nil
  for i, token in ipairs(tokens) do
    if token:match('%.rb$') then
      rb_index = i
      break
    end
  end

  if not rb_index then
    -- No .rb file found, treat first token as command and rest as script
    return {
      command = { tokens[1] or 'ruby' },
      script = vim.list_slice(tokens, 2),
      script_args = {},
    }
  end

  local command = vim.list_slice(tokens, 1, rb_index - 1)
  local script = { tokens[rb_index] }
  local script_args = vim.list_slice(tokens, rb_index + 1)

  if #command == 0 then
    command = { 'ruby' }
  end

  return {
    command = command,
    script = script,
    script_args = script_args,
  }
end

---Launch a DAP session with a resolved shell command.
---@param shell_cmd string
local function launch_dap(shell_cmd)
  local ok, dap = pcall(require, 'dap')
  if not ok then
    vim.notify('ruby-lsp: nvim-dap is required for debugging. Install mfussenegger/nvim-dap.', vim.log.levels.WARN)
    return
  end

  local parsed = M.parse_shell_command(shell_cmd)
  local cfg = config.get().dap

  dap.run({
    type = cfg.adapter,
    request = 'attach',
    localfs = true,
    command = parsed.command,
    script = parsed.script,
    script_args = #parsed.script_args > 0 and parsed.script_args or nil,
  })
end

---Discover the tests in a file once indexing completes. Calls back with nothing after an
---error notification when there's no client or the request fails.
---@param uri string
---@param bufnr integer
---@param callback fun(client: vim.lsp.Client|nil, items: table[]|nil)
local function discover_tests(uri, bufnr, callback)
  local function no_client()
    vim.notify('ruby-lsp: no ruby_lsp client found', vim.log.levels.ERROR)
    callback(nil, nil)
  end

  -- Without a client, indexing never completes, so fail now instead of waiting
  if not utils.get_client() then
    no_client()
    return
  end

  utils.after_indexing(function()
    local client = utils.get_client()
    if not client then
      no_client()
      return
    end

    client:request('rubyLsp/discoverTests', { textDocument = { uri = uri } }, function(err, result)
      if err or not result then
        vim.notify('ruby-lsp: failed to discover tests', vim.log.levels.ERROR)
        callback(nil, nil)
        return
      end
      callback(client, result)
    end, bufnr)
  end)
end

---Resolve the shell command that runs test items. Calls back with nil after an error
---notification when the request fails.
---@param client vim.lsp.Client
---@param items table[]
---@param bufnr integer
---@param callback fun(cmd: string|nil)
local function resolve_command(client, items, bufnr, callback)
  local params = { items = vim.tbl_map(utils.wrap_test_item, items) }

  client:request('rubyLsp/resolveTestCommands', params, function(err, result)
    if err or not result or not result.commands or #result.commands == 0 then
      vim.notify('ruby-lsp: failed to resolve test command', vim.log.levels.ERROR)
      callback(nil)
      return
    end
    callback(result.commands[1])
  end, bufnr)
end

---Resolve the command that runs the innermost test containing a line of a buffer.
---Calls back with nil after a notification when there's no test there or a request fails.
---@param bufnr integer
---@param line integer 0-based
---@param callback fun(cmd: string|nil)
function M.resolve_nearest(bufnr, line, callback)
  discover_tests(vim.uri_from_bufnr(bufnr), bufnr, function(client, items)
    if not client or not items then
      callback(nil)
      return
    end

    local item = utils.find_nearest_test(items, line)
    if not item then
      vim.notify('ruby-lsp: no test at the cursor', vim.log.levels.INFO)
      callback(nil)
      return
    end

    resolve_command(client, { item }, bufnr, callback)
  end)
end

---Resolve the command that debugs a whole file. A file with tests runs them all through the
---command Ruby LSP resolves, which sets up load paths like -Itest or runs bin/rails test. Any other file, or any file
---without a client, runs with plain ruby. Calls back with nil after a notification when a
---request fails.
---@param bufnr integer
---@param callback fun(exec_config: {command: string[], script: string[], script_args: string[]}|nil)
function M.resolve_file(bufnr, callback)
  local function plain()
    callback({ command = { 'ruby' }, script = { vim.api.nvim_buf_get_name(bufnr) }, script_args = {} })
  end

  if not utils.get_client() then
    plain()
    return
  end

  discover_tests(vim.uri_from_bufnr(bufnr), bufnr, function(client, items)
    if not client or not items then
      callback(nil)
    elseif #items == 0 then
      plain()
    else
      resolve_command(client, M.file_items(items), bufnr, function(cmd)
        callback(cmd and M.parse_shell_command(cmd) or nil)
      end)
    end
  end)
end

---Build one item per test framework that stands for a whole file, the way VS Code's test
---explorer asks to run a file. Every resolver runs a `test_file` item without children as
---the whole file.
---@param items table[] top-level items discovered in one file
---@return table[]
function M.file_items(items)
  local file_items = {}
  local seen = {}
  for _, item in ipairs(items) do
    for _, tag in ipairs(item.tags or {}) do
      if vim.startswith(tag, 'framework:') and not seen[tag] then
        seen[tag] = true
        table.insert(file_items, {
          id = vim.uri_to_fname(item.uri),
          label = vim.fs.basename(vim.uri_to_fname(item.uri)),
          uri = item.uri,
          range = item.range,
          tags = { tag, 'test_file' },
          children = {},
        })
      end
    end
  end
  return file_items
end

---Debug configurations for the nearest test and the current file.
---@return table[]
function M.configurations()
  local adapter = config.get().dap.adapter

  local function configuration(name, fields)
    return vim.tbl_extend('force', { type = adapter, request = 'attach', localfs = true, name = name }, fields)
  end

  local function current_file()
    return { bufnr = vim.api.nvim_get_current_buf(), file = true }
  end

  return {
    configuration('Ruby LSP: debug nearest test', {
      ruby_lsp_target = function()
        return { bufnr = vim.api.nvim_get_current_buf(), line = vim.api.nvim_win_get_cursor(0)[1] - 1 }
      end,
    }),
    configuration('Ruby LSP: debug current file', {
      ruby_lsp_target = current_file,
    }),
    configuration('Ruby LSP: debug current file (with arguments)', {
      ruby_lsp_target = current_file,
      script_args = function()
        return coroutine.create(function(dap_run_co)
          vim.ui.input({ prompt = 'Arguments: ' }, function(input)
            local value = input == nil and require('dap').ABORT or utils.shell_split(input)
            coroutine.resume(dap_run_co, value)
          end)
        end)
      end,
    }),
  }
end

---Handle rubyLsp.debugTest command.
---Defers until indexing is complete to avoid stale cached results.
---@param command lsp.Command
function M.debug_test(command)
  local file_path, test_id = utils.validate_test_args(command)
  if not file_path then
    return
  end

  discover_tests(vim.uri_from_fname(file_path), 0, function(client, items)
    if not client or not items then
      return
    end

    if #items == 0 then
      vim.notify('ruby-lsp: failed to discover tests', vim.log.levels.ERROR)
      return
    end

    local item = utils.find_test_item(items, test_id)
    if not item then
      vim.notify("ruby-lsp: test '" .. test_id .. "' not found", vim.log.levels.ERROR)
      return
    end

    resolve_command(client, { item }, 0, function(cmd)
      if cmd then
        vim.schedule(function()
          launch_dap(cmd)
        end)
      end
    end)
  end)
end

return M
