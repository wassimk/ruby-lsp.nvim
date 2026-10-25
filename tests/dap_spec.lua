local dap = require('ruby-lsp.dap')

describe('dap', function()
  describe('setup_adapter', function()
    local fake_dap

    before_each(function()
      fake_dap = {
        adapters = {},
        listeners = { after = { event_stopped = {} } },
      }
      package.loaded['dap'] = fake_dap
      dap.setup_adapter()
    end)

    after_each(function()
      package.loaded['dap'] = nil
    end)

    ---A fake nvim-dap session that records the continue requests it receives
    local function session(type)
      local s = { config = { type = type or 'ruby' }, continued = {} }
      function s:request(command, args)
        if command == 'continue' then
          table.insert(self.continued, args.threadId)
        end
      end
      return s
    end

    local function stopped(s, reason)
      fake_dap.listeners.after.event_stopped['ruby-lsp'](s, { reason = reason, threadId = 1 })
    end

    it('launches rdbg without --stop-at-load', function()
      local adapter
      fake_dap.adapters.ruby(function(a)
        adapter = a
      end, { command = { 'ruby' }, script = { 'test/foo_test.rb' } })

      assert.is_false(vim.tbl_contains(adapter.executable.args, '--stop-at-load'))
    end)

    -- rdbg pauses at startup so breakpoints are set before any code runs. Continue past
    -- that pause so the session stops at the first breakpoint instead.
    it('continues past the startup pause', function()
      local s = session()
      stopped(s, 'pause')

      assert.same({ 1 }, s.continued)
    end)

    it('only continues past the first pause of a session', function()
      local s = session()
      stopped(s, 'pause')
      stopped(s, 'pause')

      assert.same({ 1 }, s.continued)
    end)

    it('stays stopped when the first stop is a breakpoint', function()
      local s = session()
      stopped(s, 'breakpoint')
      stopped(s, 'pause')

      assert.same({}, s.continued)
    end)

    it('ignores sessions for other adapters', function()
      local s = session('python')
      stopped(s, 'pause')

      assert.same({}, s.continued)
    end)
  end)

  describe('parse_shell_command', function()
    it('splits a minitest command and drops bundle exec', function()
      local parsed = dap.parse_shell_command('bundle exec ruby -Itest test/calculator_test.rb')

      assert.same({ 'ruby', '-Itest' }, parsed.command)
      assert.same({ 'test/calculator_test.rb' }, parsed.script)
      assert.same({}, parsed.script_args)
    end)

    -- Outside Rails, Ruby LSP selects a test with a quoted --name regex. The quotes and the
    -- escaped $ must not reach rdbg, or the filter matches nothing and the debugger never stops.
    it('keeps a quoted --name regex as one unquoted argument', function()
      local parsed = dap.parse_shell_command(
        'bundle exec ruby -Itest test/calculator_test.rb --name "/^CalculatorTest#test_average\\$/"'
      )

      assert.same({ 'test/calculator_test.rb' }, parsed.script)
      assert.same({ '--name', '/^CalculatorTest#test_average$/' }, parsed.script_args)
    end)
  end)
end)
