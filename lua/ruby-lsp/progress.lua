local M = {}

local next_id = 0
local echo_ids = {}

local echo_opts = {
  kind = 'progress',
  source = 'ruby-lsp.nvim',
  title = 'ruby-lsp.nvim',
}

---Check if progress is enabled in config.
---@return boolean
local function is_enabled()
  return require('ruby-lsp.config').get().test_discovery.progress
end

---Send a progress echo update via vim.schedule.
---@param id integer progress ID
---@param message string
---@param status string "running", "success", or "failed"
---@param cleanup? boolean remove the echo_id mapping after sending
local function echo_progress(id, message, status, cleanup)
  vim.schedule(function()
    local echo_id = echo_ids[id]
    if not echo_id then
      return
    end
    vim.api.nvim_echo({ { message } }, false, vim.tbl_extend('force', echo_opts, { id = echo_id, status = status }))
    if cleanup then
      echo_ids[id] = nil
    end
  end)
end

function M.start(message)
  if not is_enabled() then
    return nil
  end

  next_id = next_id + 1
  local id = next_id

  vim.schedule(function()
    echo_ids[id] = vim.api.nvim_echo({ { message } }, false, vim.tbl_extend('force', echo_opts, { status = 'running' }))
  end)
  return id
end

function M.update(id, message)
  if not id then
    return
  end

  echo_progress(id, message, 'running')
end

function M.finish(id, message, success)
  if not id then
    return
  end

  echo_progress(id, message, success and 'success' or 'failed', true)
end

return M
