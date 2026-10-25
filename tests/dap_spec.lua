local dap = require('ruby-lsp.dap')

describe('dap', function()
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
