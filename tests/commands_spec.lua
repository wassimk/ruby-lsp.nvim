-- Mock executor before requiring commands
package.loaded['ruby-lsp.commands'] = nil
package.loaded['ruby-lsp.executor'] = nil

local mock_executor = {}
mock_executor.run_calls = {}
mock_executor.run = function(cmd, opts)
  table.insert(mock_executor.run_calls, { cmd = cmd, opts = opts })
end
package.loaded['ruby-lsp.executor'] = mock_executor

local helpers = require('helpers')
local config = require('ruby-lsp.config')
local commands = require('ruby-lsp.commands')

describe('commands', function()
  local cmd_calls, cursor_calls
  local original_cmd, original_cursor, original_fnameescape, original_ui_select

  before_each(function()
    helpers.setup_mocks()
    config.setup()
    mock_executor.run_calls = {}

    cmd_calls = {}
    cursor_calls = {}

    original_cmd = vim.cmd
    original_cursor = vim.api.nvim_win_set_cursor
    original_fnameescape = rawget(vim.fn, 'fnameescape')
    original_ui_select = vim.ui.select

    vim.cmd = function(s)
      table.insert(cmd_calls, s)
    end
    vim.api.nvim_win_set_cursor = function(win, pos)
      table.insert(cursor_calls, { win = win, pos = pos })
    end
    vim.fn.fnameescape = function(p)
      return p
    end

    package.loaded['neotest'] = nil
  end)

  after_each(function()
    vim.cmd = original_cmd
    vim.api.nvim_win_set_cursor = original_cursor
    rawset(vim.fn, 'fnameescape', original_fnameescape)
    vim.ui.select = original_ui_select
    helpers.teardown_mocks()
    package.loaded['neotest'] = nil
  end)

  describe('open_file', function()
    it('opens file without line number', function()
      commands.open_file({
        arguments = { { 'file:///path/to/file.rb' } },
      })

      assert.equals(1, #cmd_calls)
      assert.equals('edit /path/to/file.rb', cmd_calls[1])
      assert.equals(0, #cursor_calls)
    end)

    it('opens file with line number', function()
      commands.open_file({
        arguments = { { 'file:///path/to/file.rb#L10' } },
      })

      assert.equals(1, #cmd_calls)
      assert.equals('edit /path/to/file.rb', cmd_calls[1])
      assert.equals(1, #cursor_calls)
      assert.same({ win = 0, pos = { 10, 0 } }, cursor_calls[1])
    end)

    it('opens file with line and column', function()
      commands.open_file({
        arguments = { { 'file:///path/to/file.rb#L10,5' } },
      })

      assert.equals('edit /path/to/file.rb', cmd_calls[1])
      assert.same({ win = 0, pos = { 10, 4 } }, cursor_calls[1])
    end)

    it('ignores non-matching fragment', function()
      commands.open_file({
        arguments = { { 'file:///path/to/file.rb#something' } },
      })

      assert.equals('edit /path/to/file.rb', cmd_calls[1])
      assert.equals(0, #cursor_calls)
    end)

    it('offers selection for multiple URIs', function()
      local select_items
      vim.ui.select = function(items, opts, on_choice)
        select_items = items
        on_choice(items[2])
      end

      commands.open_file({
        arguments = { { 'file:///path/to/a.rb', 'file:///path/to/b.rb#L5' } },
      })

      assert.equals(2, #select_items)
      assert.equals(1, #cmd_calls)
      assert.equals('edit /path/to/b.rb', cmd_calls[1])
      assert.same({ win = 0, pos = { 5, 0 } }, cursor_calls[1])
    end)

    it('does nothing when user cancels selection', function()
      vim.ui.select = function(items, opts, on_choice)
        on_choice(nil)
      end

      commands.open_file({
        arguments = { { 'file:///a.rb', 'file:///b.rb' } },
      })

      assert.equals(0, #cmd_calls)
    end)

    it('notifies when no arguments provided', function()
      commands.open_file({})

      assert.equals(1, #helpers.notifications)
      assert.equals(vim.log.levels.WARN, helpers.notifications[1].level)
    end)

    it('notifies when empty URI list', function()
      commands.open_file({ arguments = { {} } })

      assert.equals(1, #helpers.notifications)
      assert.equals(vim.log.levels.WARN, helpers.notifications[1].level)
    end)
  end)

  describe('run_test', function()
    it('returns early when no client', function()
      helpers.lsp_clients = {}

      commands.run_test({
        arguments = { '/path/to/test.rb', 'FooTest#test_bar' },
      })

      assert.equals(1, #helpers.notifications)
      assert.equals(vim.log.levels.ERROR, helpers.notifications[1].level)
    end)

    it('routes to neotest when available', function()
      helpers.lsp_clients = { helpers.mock_client() }

      local neotest_run_calls = {}
      package.loaded['neotest'] = {
        run = {
          run = function(id)
            table.insert(neotest_run_calls, id)
          end,
        },
      }

      commands.run_test({
        arguments = { '/path/to/test.rb', 'FooTest#test_bar' },
      })

      assert.equals(1, #neotest_run_calls)
      assert.equals('/path/to/test.rb::FooTest#test_bar', neotest_run_calls[1])
    end)
  end)

  describe('run_task', function()
    it('notifies error when no command argument', function()
      commands.run_task({ arguments = {} })

      assert.equals(1, #helpers.notifications)
      assert.equals(vim.log.levels.ERROR, helpers.notifications[1].level)
    end)

    it('notifies error when no arguments key', function()
      commands.run_task({})

      assert.equals(1, #helpers.notifications)
      assert.equals(vim.log.levels.ERROR, helpers.notifications[1].level)
    end)

    it('runs command via executor', function()
      commands.run_task({ arguments = { 'bundle exec rake db:migrate' } })

      assert.equals(1, #mock_executor.run_calls)
      assert.equals('bundle exec rake db:migrate', mock_executor.run_calls[1].cmd)
      assert.is_true(mock_executor.run_calls[1].opts.keep_open)
    end)

    it('passes configured keep_open to executor', function()
      config.setup({ task = { keep_open = false } })

      commands.run_task({ arguments = { 'rake test' } })

      assert.is_false(mock_executor.run_calls[1].opts.keep_open)
    end)
  end)
end)
