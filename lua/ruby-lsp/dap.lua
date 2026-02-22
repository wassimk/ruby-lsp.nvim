local config = require("ruby-lsp.config")

local M = {}

---Register the rdbg DAP adapter if nvim-dap is available and no adapter is already set.
function M.setup_adapter()
  local ok, dap = pcall(require, "dap")
  if not ok then
    return
  end

  local cfg = config.get().dap
  local adapter_name = cfg.adapter

  if dap.adapters[adapter_name] then
    return
  end

  dap.adapters[adapter_name] = function(callback, dap_config)
    local args = {
      "exec",
      "rdbg",
      "--open",
      "--stop-at-load",
      "--port",
      "${port}",
      "--command",
      "--",
      "bundle",
      "exec",
    }

    vim.list_extend(args, dap_config.command)
    vim.list_extend(args, dap_config.script)

    if dap_config.script_args then
      vim.list_extend(args, dap_config.script_args)
    end

    callback({
      type = "server",
      host = "127.0.0.1",
      port = "${port}",
      executable = {
        command = "bundle",
        args = args,
      },
    })
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
local function parse_shell_command(shell_cmd)
  local tokens = {}
  for token in shell_cmd:gmatch("%S+") do
    table.insert(tokens, token)
  end

  -- Strip leading "bundle exec" since the DAP adapter adds it
  if #tokens >= 2 and tokens[1] == "bundle" and tokens[2] == "exec" then
    table.remove(tokens, 1)
    table.remove(tokens, 1)
  end

  -- Find the .rb file token to split command from script/args
  local rb_index = nil
  for i, token in ipairs(tokens) do
    if token:match("%.rb$") then
      rb_index = i
      break
    end
  end

  if not rb_index then
    -- No .rb file found, treat first token as command and rest as script
    return {
      command = { tokens[1] or "ruby" },
      script = vim.list_slice(tokens, 2),
      script_args = {},
    }
  end

  local command = vim.list_slice(tokens, 1, rb_index - 1)
  local script = { tokens[rb_index] }
  local script_args = vim.list_slice(tokens, rb_index + 1)

  if #command == 0 then
    command = { "ruby" }
  end

  return {
    command = command,
    script = script,
    script_args = script_args,
  }
end

---Handle rubyLsp.debugTest command.
---@param command lsp.Command
function M.debug_test(command)
  local ok, dap = pcall(require, "dap")
  if not ok then
    vim.notify(
      "ruby-lsp: nvim-dap is required for debugging. Install mfussenegger/nvim-dap.",
      vim.log.levels.WARN
    )
    return
  end

  local args = command.arguments or {}
  local shell_cmd = args[3]
  if not shell_cmd then
    vim.notify("ruby-lsp: missing test command in arguments", vim.log.levels.ERROR)
    return
  end

  local parsed = parse_shell_command(shell_cmd)
  local cfg = config.get().dap

  dap.run({
    type = cfg.adapter,
    request = "attach",
    localfs = true,
    command = parsed.command,
    script = parsed.script,
    script_args = #parsed.script_args > 0 and parsed.script_args or nil,
  })
end

return M
