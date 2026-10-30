local M = {}

M.MIN_NVIM_VERSION = '0.12'
M.MIN_RUBY_LSP_VERSION = '0.23.0'
M.FEATURE_FLAG_MSG = 'ruby-lsp.nvim needs the fullTestDiscovery feature flag, which it turns on by default.\n'
  .. 'Remove the fullTestDiscovery = false override from your ruby_lsp config.'

---@type table<integer, boolean>
local indexing_complete = {}

---Mark a client's indexing as complete and notify waiting consumers.
---@param client_id integer
function M.on_indexing_complete(client_id)
  indexing_complete[client_id] = true
  vim.api.nvim_exec_autocmds('User', { pattern = 'RubyLspIndexingComplete' })
end

---Check whether the ruby_lsp server has finished indexing.
---@return boolean
function M.is_indexing_complete()
  local client = M.get_client()
  return client ~= nil and indexing_complete[client.id] == true
end

---Run a function after indexing completes. If already complete, runs immediately.
---For callback-based contexts (commands, dap). Shows a notification while waiting.
---@param fn function
function M.after_indexing(fn)
  if M.is_indexing_complete() then
    fn()
    return
  end
  vim.notify('ruby-lsp: waiting for server indexing to complete...', vim.log.levels.INFO)
  vim.api.nvim_create_autocmd('User', {
    group = vim.api.nvim_create_augroup('RubyLspWaitIndexing', { clear = false }),
    pattern = 'RubyLspIndexingComplete',
    once = true,
    callback = vim.schedule_wrap(fn),
  })
end

local rspec_addon_checked = false

---Check if the project uses RSpec but is missing the ruby-lsp-rspec addon.
---Notifies once per session when indexing completes.
---@param client vim.lsp.Client
function M.check_rspec_addon(client)
  if rspec_addon_checked then
    return
  end
  rspec_addon_checked = true

  local bufnr = next(client.attached_buffers) or 0
  client:request('rubyLsp/workspace/dependencies', vim.lsp.util.make_text_document_params(bufnr), function(err, result)
    if err or not result then
      return
    end
    local has_rspec = false
    local has_addon = false
    for _, dep in ipairs(result) do
      if dep.name == 'rspec-core' then
        has_rspec = true
      elseif dep.name == 'ruby-lsp-rspec' then
        has_addon = true
      end
      if has_rspec and has_addon then
        return
      end
    end
    if has_rspec and not has_addon then
      vim.notify(
        'ruby-lsp: RSpec detected but ruby-lsp-rspec addon is not installed.\n'
          .. 'Test discovery and code lenses will not work for RSpec files.\n'
          .. 'Add to your Gemfile: gem "ruby-lsp-rspec", require: false, group: :development\n'
          .. 'Run :checkhealth ruby-lsp for details.',
        vim.log.levels.WARN
      )
    end
  end, bufnr)
end

---Check whether the fullTestDiscovery feature flag is enabled on a client.
---@param client vim.lsp.Client
---@return boolean
function M.full_test_discovery_enabled(client)
  local init_options = client.config.init_options or {}
  local flags = init_options.enabledFeatureFlags or {}
  return flags.fullTestDiscovery ~= false
end

---Get the first active ruby_lsp client, or nil if none is running.
---@return vim.lsp.Client|nil
function M.get_client()
  local clients = vim.lsp.get_clients({ name = 'ruby_lsp' })
  if #clients == 0 then
    return nil
  end
  return clients[1]
end

---Recursively search a list of test items (and their children) for a matching ID.
---@param items table[]
---@param target_id string
---@return table|nil
function M.find_test_item(items, target_id)
  for _, item in ipairs(items) do
    if item.id == target_id then
      return item
    end
    if item.children then
      local found = M.find_test_item(item.children, target_id)
      if found then
        return found
      end
    end
  end
  return nil
end

---Find the innermost test item (searching children) whose range contains a line. Inside a
---group but between its tests, that is the group. Among siblings with the same range, the
---first wins.
---@param items table[]
---@param line integer 0-based
---@return table|nil
function M.find_nearest_test(items, line)
  for _, item in ipairs(items) do
    local range = item.range
    if range and range.start.line <= line and line <= range['end'].line then
      return M.find_nearest_test(item.children or {}, line) or item
    end
  end
  return nil
end

-- Ruby LSP 0.26 no longer tags test items as `test_group` or `test_case`, but
-- ruby-lsp-rspec still needs those tags to run a single example or group. Without
-- them it resolves every RSpec item to the whole file. Add them back until the
-- upstream fix is released: https://github.com/st0012/ruby-lsp-rspec/pull/103
---@param item table
---@param tags string[]
---@return string[]
local function with_rspec_kind_tag(item, tags)
  if not vim.tbl_contains(tags, 'framework:rspec') then
    return tags
  end
  if vim.tbl_contains(tags, 'test_group') or vim.tbl_contains(tags, 'test_case') then
    return tags
  end

  local kind = (item.children and #item.children > 0) and 'test_group' or 'test_case'
  return vim.list_extend(vim.deepcopy(tags), { kind })
end

---Build a test item wrapper suitable for rubyLsp/resolveTestCommands.
---@param item table LSP test item
---@return table
function M.wrap_test_item(item)
  return {
    id = item.id,
    label = item.label,
    uri = item.uri,
    range = item.range,
    tags = with_rspec_kind_tag(item, item.tags or {}),
    children = {},
  }
end

---Validate that fullTestDiscovery is enabled and extract test arguments.
---Returns file_path and test_id on success, or nil if preconditions aren't met.
---@param command lsp.Command
---@return string|nil file_path
---@return string|nil test_id
function M.validate_test_args(command)
  local client = M.get_client()
  if not client then
    vim.notify('ruby-lsp: no ruby_lsp client found', vim.log.levels.ERROR)
    return nil, nil
  end

  if not M.full_test_discovery_enabled(client) then
    vim.notify(M.FEATURE_FLAG_MSG, vim.log.levels.WARN)
    return nil, nil
  end

  local args = command.arguments or {}
  local file_path = args[1]
  local test_id = args[2]

  if not file_path or not test_id then
    vim.notify('ruby-lsp: missing test arguments', vim.log.levels.ERROR)
    return nil, nil
  end

  return file_path, test_id
end

-- Characters a backslash escapes inside double quotes, per POSIX shell rules
local double_quote_escapes = { ['$'] = true, ['`'] = true, ['"'] = true, ['\\'] = true, ['\n'] = true }

---Split a shell command string into arguments using POSIX shell quoting rules.
---Ruby LSP resolves test commands as shell strings (e.g. `--name "/^FooTest#test_bar\$/"`),
---so they can't be split on spaces when run without a shell.
---@param cmd string
---@return string[]
function M.shell_split(cmd)
  local args = {}
  local current = {}
  local in_arg = false
  local quote = nil
  local i = 1

  while i <= #cmd do
    local char = cmd:sub(i, i)

    if quote == "'" then
      if char == "'" then
        quote = nil
      else
        table.insert(current, char)
      end
    elseif quote == '"' then
      local next_char = cmd:sub(i + 1, i + 1)
      if char == '"' then
        quote = nil
      elseif char == '\\' and double_quote_escapes[next_char] then
        table.insert(current, next_char)
        i = i + 1
      else
        table.insert(current, char)
      end
    elseif char == "'" or char == '"' then
      quote = char
      in_arg = true
    elseif char == '\\' then
      table.insert(current, cmd:sub(i + 1, i + 1))
      in_arg = true
      i = i + 1
    elseif char:match('%s') then
      if in_arg then
        table.insert(args, table.concat(current))
        current = {}
        in_arg = false
      end
    else
      table.insert(current, char)
      in_arg = true
    end

    i = i + 1
  end

  if in_arg then
    table.insert(args, table.concat(current))
  end

  return args
end

return M
