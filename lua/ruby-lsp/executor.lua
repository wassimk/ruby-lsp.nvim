local config = require("ruby-lsp.config")

local M = {}

local TERM_BUF_VAR = "ruby_lsp_terminal"

---Find an existing ruby-lsp terminal buffer.
---@return integer|nil
local function find_terminal_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ok, val = pcall(vim.api.nvim_buf_get_var, buf, TERM_BUF_VAR)
      if ok and val then
        return buf
      end
    end
  end
  return nil
end

---Run command in a builtin terminal split.
---@param cmd string
local function run_split(cmd)
  local cfg = config.get().split
  local existing = find_terminal_buf()

  if existing and vim.api.nvim_buf_is_valid(existing) then
    local wins = vim.fn.win_findbuf(existing)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
    else
      if cfg.direction == "vertical" then
        vim.cmd("vertical sbuffer " .. existing)
      else
        vim.cmd("belowright sbuffer " .. existing)
        vim.api.nvim_win_set_height(0, cfg.size)
      end
    end
    -- Delete old buffer and open a fresh terminal in this window
    local win = vim.api.nvim_get_current_win()
    local new_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, new_buf)
    vim.api.nvim_buf_delete(existing, { force = true })
    vim.fn.termopen(cmd)
    vim.api.nvim_buf_set_var(0, TERM_BUF_VAR, true)
  else
    if cfg.direction == "vertical" then
      vim.cmd("vnew")
    else
      vim.cmd("belowright new")
      vim.api.nvim_win_set_height(0, cfg.size)
    end
    vim.fn.termopen(cmd)
    vim.api.nvim_buf_set_var(0, TERM_BUF_VAR, true)
  end

  vim.cmd("normal! G")
end

---Run command via toggleterm.
---@param cmd string
local function run_toggleterm(cmd)
  local ok, Terminal = pcall(require, "toggleterm.terminal")
  if not ok then
    vim.notify("toggleterm.nvim is not installed", vim.log.levels.ERROR)
    return
  end

  local cfg = config.get().toggleterm

  Terminal.Terminal
    :new({
      cmd = cmd,
      close_on_exit = cfg.close_on_exit,
      direction = cfg.direction,
      -- When close_on_exit is false, auto-close on success so the terminal
      -- only stays open when tests fail (letting the user inspect output).
      on_exit = function(terminal, _, exit_code)
        if exit_code == 0 and not cfg.close_on_exit then
          terminal:close()
        end
      end,
    })
    :toggle()
end

---Run a shell command using the configured executor.
---@param cmd string
---@param opts? {file_path?: string, test_id?: string}
function M.run(cmd, opts)
  opts = opts or {}
  local executor = config.get().executor

  if type(executor) == "function" then
    executor(cmd, opts)
  elseif executor == "toggleterm" then
    run_toggleterm(cmd)
  else
    run_split(cmd)
  end
end

return M
