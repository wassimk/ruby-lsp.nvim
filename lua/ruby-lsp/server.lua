local M = {}

local CMD = { 'ruby-lsp', '--version' }

---@type table<string, { [1]: boolean, [2]: string|nil }>
local results = {}
---@type table<string, fun(ok: boolean, version: string|nil)[]>
local pending = {}

---Turn a vim.system result into ok and version.
---@param result vim.SystemCompleted
---@return boolean ok
---@return string|nil version
local function parse(result)
  if result.code == 0 then
    return true, vim.trim(result.stdout or '')
  end
  return false, nil
end

---@return boolean
local function runnable()
  return vim.fn.executable('ruby-lsp') == 1
end

---Check that `ruby-lsp --version` runs in `root`. The result is cached per root
---for the session, and callers arriving during a pending check share it.
---@param root string
---@param callback fun(ok: boolean, version: string|nil)
function M.probe(root, callback)
  local cached = results[root]
  if cached then
    vim.schedule(function()
      callback(cached[1], cached[2])
    end)
    return
  end

  if pending[root] then
    table.insert(pending[root], callback)
    return
  end

  if not runnable() then
    results[root] = { false, nil }
    vim.schedule(function()
      callback(false, nil)
    end)
    return
  end

  pending[root] = { callback }
  vim.system(CMD, { cwd = root, text = true }, function(result)
    local ok, version = parse(result)
    vim.schedule(function()
      local callbacks = pending[root]
      pending[root] = nil
      if not callbacks then
        return
      end
      results[root] = { ok, version }
      for _, cb in ipairs(callbacks) do
        cb(ok, version)
      end
    end)
  end)
end

---Blocking variant of `probe`, sharing the same cache.
---@param root string
---@return boolean ok
---@return string|nil version
function M.probe_sync(root)
  local cached = results[root]
  if cached then
    return cached[1], cached[2]
  end

  if not runnable() then
    results[root] = { false, nil }
    return false, nil
  end

  local ok, version = parse(vim.system(CMD, { cwd = root, text = true }):wait(5000))
  results[root] = { ok, version }
  return ok, version
end

---Start ruby-lsp in the project root. Mirrors nvim-lspconfig's default cmd.
---@param dispatchers vim.lsp.rpc.Dispatchers
---@param config vim.lsp.ClientConfig
---@return vim.lsp.rpc.PublicClient
function M.cmd(dispatchers, config)
  return vim.lsp.rpc.start(
    { 'ruby-lsp' },
    dispatchers,
    config and config.root_dir and { cwd = config.cmd_cwd or config.root_dir }
  )
end

---Whether the server should start for `root`, per `lsp.auto_start`.
---When `auto_start` is false the user enabled ruby_lsp themselves, so start.
---@param root string
---@return boolean
function M.should_start(root)
  local auto_start = require('ruby-lsp.config').get().lsp.auto_start
  if type(auto_start) == 'function' then
    return auto_start(root) == true
  end
  return true
end

---Find the project root for `bufnr` and call `on_dir` only when ruby-lsp can run there.
---A list `cmd` override only needs its executable on the path. Any `cmd` function
---(ours, nvim-lspconfig's, or a user's) runs the cached `ruby-lsp --version` check.
---Never notifies; when ruby-lsp is missing or broken the server just doesn't start.
---@param bufnr integer
---@param on_dir fun(root: string)
function M.root_dir(bufnr, on_dir)
  if vim.api.nvim_buf_get_name(bufnr) == '' or vim.bo[bufnr].buftype ~= '' then
    return
  end

  local root = vim.fs.root(bufnr, { 'Gemfile', '.git' })
  if not root or not M.should_start(root) then
    return
  end

  local cmd = vim.lsp.config.ruby_lsp.cmd
  if type(cmd) == 'table' then
    if cmd[1] and vim.fn.executable(cmd[1]) == 1 then
      on_dir(root)
    end
    return
  end

  M.probe(root, function(ok)
    if ok then
      on_dir(root)
    end
  end)
end

---Clear the cache and pending queue. For tests only.
function M._reset()
  results = {}
  pending = {}
end

return M
