local M = {}

local defaults = {
  executor = "split",

  split = {
    direction = "horizontal",
    size = 15,
  },

  toggleterm = {
    direction = "float",
    close_on_exit = false,
  },

  task = {
    keep_open = true,
  },

  dap = {
    auto_configure = true,
    adapter = "ruby",
  },
}

---@type table
M._config = vim.deepcopy(defaults)

---@param opts? table
function M.setup(opts)
  M._config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@return table
function M.get()
  return M._config
end

return M
