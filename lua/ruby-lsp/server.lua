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

---Clear the cache and pending queue. For tests only.
function M._reset()
  results = {}
  pending = {}
end

return M
