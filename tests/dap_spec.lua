local config = require('ruby-lsp.config')
local dap = require('ruby-lsp.dap')
local helpers = require('helpers')
local utils = require('ruby-lsp.utils')

describe('dap', function()
  describe('setup_adapter', function()
    local fake_dap

    local function new_fake_dap()
      return {
        adapters = {},
        configurations = {},
        listeners = { after = { event_stopped = {} } },
        providers = { configs = {} },
        ABORT = {},
      }
    end

    before_each(function()
      fake_dap = new_fake_dap()
      package.loaded['dap'] = fake_dap
      dap.setup_adapter()
    end)

    after_each(function()
      package.loaded['dap'] = nil
      config.setup()
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

    describe('adapter command', function()
      local original_root

      before_each(function()
        original_root = vim.fs.root
      end)

      after_each(function()
        vim.fs.root = original_root
        vim.cmd('silent! %bwipeout!')
      end)

      local function resolve()
        local adapter
        fake_dap.adapters.ruby(function(a)
          adapter = a
        end, { command = { 'ruby', '-Itest' }, script = { 'test/foo_test.rb' }, script_args = { '--verbose' } })
        return adapter
      end

      it('runs under bundler from the Gemfile root', function()
        vim.fs.root = function()
          return '/app'
        end

        local exe = resolve().executable

        assert.equals('bundle', exe.command)
        assert.equals('/app', exe.cwd)
        assert.same({
          'exec',
          'rdbg',
          '--open',
          '--port',
          '${port}',
          '--command',
          '--',
          'bundle',
          'exec',
          'ruby',
          '-Itest',
          'test/foo_test.rb',
          '--verbose',
        }, exe.args)
      end)

      it('runs rdbg directly without a Gemfile', function()
        vim.fs.root = function()
          return nil
        end
        vim.cmd('silent edit /tmp/script.rb')

        local exe = resolve().executable

        assert.equals('rdbg', exe.command)
        assert.equals(vim.uv.fs_realpath('/tmp'), exe.cwd)
        assert.is_false(vim.tbl_contains(exe.args, 'bundle'))
        assert.same({
          '--open',
          '--port',
          '${port}',
          '--command',
          '--',
          'ruby',
          '-Itest',
          'test/foo_test.rb',
          '--verbose',
        }, exe.args)
      end)
    end)

    describe('provided configurations', function()
      local names = {
        'Ruby LSP: debug nearest test',
        'Ruby LSP: debug current file',
        'Ruby LSP: debug current file with arguments',
      }

      local function buffer(filetype)
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.bo[bufnr].filetype = filetype
        return bufnr
      end

      local function provided(bufnr)
        return fake_dap.providers.configs['ruby-lsp.nvim'](bufnr)
      end

      local function setup_again(fake)
        fake_dap = fake
        package.loaded['dap'] = fake_dap
        dap.setup_adapter()
      end

      after_each(function()
        vim.cmd('silent! %bwipeout!')
      end)

      it('provides three configurations for ruby buffers', function()
        local configs = provided(buffer('ruby'))

        assert.same(
          names,
          vim.tbl_map(function(c)
            return c.name
          end, configs)
        )
        for _, c in ipairs(configs) do
          assert.equals('ruby', c.type)
          assert.equals('attach', c.request)
          assert.is_true(c.localfs)
        end
      end)

      it('runs the current file with ruby', function()
        local current_file = provided(buffer('ruby'))[2]

        assert.same({ 'ruby' }, current_file.command)
        assert.same({ '${file}' }, current_file.script)
      end)

      it('targets the cursor line of the current buffer', function()
        local bufnr = buffer('ruby')
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'a', 'b', 'c' })
        vim.api.nvim_set_current_buf(bufnr)
        vim.api.nvim_win_set_cursor(0, { 3, 0 })

        local target = provided(bufnr)[1].ruby_lsp_target()

        assert.same({ bufnr = bufnr, line = 2 }, target)
      end)

      it('provides nothing for other filetypes', function()
        assert.same({}, provided(buffer('python')))
      end)

      it('keeps entries when the user replaces dap.configurations.ruby', function()
        local mine = { { name = 'mine' } }
        fake_dap.configurations = { ruby = mine }

        assert.equals(3, #provided(buffer('ruby')))
        assert.same({ { name = 'mine' } }, fake_dap.configurations.ruby)
      end)

      it('does not provide configurations when dap.configurations is false', function()
        config.setup({ dap = { configurations = false } })
        setup_again(new_fake_dap())

        assert.is_nil(fake_dap.providers.configs['ruby-lsp.nvim'])
      end)

      it('does not provide configurations when another adapter owns the name', function()
        local fake = new_fake_dap()
        fake.adapters.ruby = { type = 'server', port = 1234 }
        setup_again(fake)

        assert.is_nil(fake_dap.providers.configs['ruby-lsp.nvim'])
      end)

      it('registers the adapter with an nvim-dap that has no providers', function()
        local fake = new_fake_dap()
        fake.providers = nil
        setup_again(fake)

        assert.is_function(fake_dap.adapters.ruby)
      end)

      describe('arguments prompt', function()
        local original_input

        before_each(function()
          original_input = vim.ui.input
        end)

        after_each(function()
          vim.ui.input = original_input
        end)

        ---Evaluate script_args the way nvim-dap does and return the value it resumes with
        local function prompt(input)
          local prompted
          vim.ui.input = function(opts, on_confirm)
            prompted = opts.prompt
            on_confirm(input)
          end

          local received
          local dap_run_co = coroutine.create(function()
            received = coroutine.yield()
          end)
          coroutine.resume(dap_run_co)

          local co = provided(buffer('ruby'))[3].script_args()
          coroutine.resume(co, dap_run_co)

          assert.equals('Arguments: ', prompted)
          return received
        end

        it('aborts when the arguments prompt is cancelled', function()
          assert.equals(fake_dap.ABORT, prompt(nil))
        end)

        it('splits prompted arguments like a shell', function()
          assert.same({ 'one', 'two words' }, prompt('one "two words"'))
        end)
      end)

      describe('nearest test', function()
        local original_root
        local requests
        local bufnr

        local function range(first, last)
          return { start = { line = first, character = 0 }, ['end'] = { line = last, character = 3 } }
        end

        before_each(function()
          helpers.setup_mocks()
          original_root = vim.fs.root
          vim.fs.root = function()
            return '/app'
          end

          bufnr = vim.api.nvim_create_buf(true, false)
          vim.api.nvim_buf_set_name(bufnr, '/app/test/foo_test.rb')
          local uri = vim.uri_from_bufnr(bufnr)

          requests = {}
          helpers.lsp_clients = {
            helpers.mock_client({
              request = function(_, method, params, handler)
                table.insert(requests, { method = method, params = params })
                if method == 'rubyLsp/discoverTests' then
                  handler(nil, {
                    {
                      id = 'FooTest',
                      label = 'FooTest',
                      uri = uri,
                      range = range(0, 10),
                      tags = { 'framework:minitest' },
                      children = {
                        {
                          id = 'FooTest#test_bar',
                          label = 'test_bar',
                          uri = uri,
                          range = range(2, 4),
                          tags = { 'framework:minitest' },
                          children = {},
                        },
                      },
                    },
                  })
                elseif method == 'rubyLsp/resolveTestCommands' then
                  handler(nil, {
                    commands = { 'bundle exec ruby -Itest test/foo_test.rb --name "/^FooTest#test_bar\\$/"' },
                  })
                end
              end,
            }),
          }
          utils.on_indexing_complete(1)
        end)

        after_each(function()
          vim.fs.root = original_root
          helpers.teardown_mocks()
        end)

        local function start(line)
          local adapter
          fake_dap.adapters.ruby(function(a)
            adapter = a
          end, { type = 'ruby', request = 'attach', ruby_lsp_target = { bufnr = bufnr, line = line } })
          return adapter
        end

        it('debugs the nearest test through the resolved command', function()
          local exe = start(3).executable

          assert.equals('/app', exe.cwd)
          assert.equals('rubyLsp/discoverTests', requests[1].method)
          assert.equals(vim.uri_from_bufnr(bufnr), requests[1].params.textDocument.uri)
          assert.equals('FooTest#test_bar', requests[2].params.items[1].id)
          assert.same(
            { 'ruby', '-Itest', 'test/foo_test.rb', '--name', '/^FooTest#test_bar$/' },
            vim.list_slice(exe.args, #exe.args - 4)
          )
        end)

        it('notifies and does not start outside a test', function()
          assert.is_nil(start(15))
          assert.same(
            { { msg = 'ruby-lsp: no test at the cursor', level = vim.log.levels.INFO } },
            helpers.notifications
          )
        end)

        it('does not start without a client', function()
          helpers.lsp_clients = {}

          assert.is_nil(start(3))
          assert.equals('ruby-lsp: no ruby_lsp client found', helpers.notifications[1].msg)
        end)

        it('debugs a code lens test through the same requests', function()
          local runs = {}
          fake_dap.run = function(c)
            table.insert(runs, c)
          end

          dap.debug_test({ arguments = { '/app/test/foo_test.rb', 'FooTest#test_bar' } })
          vim.wait(100, function()
            return #runs > 0
          end)

          assert.equals('FooTest#test_bar', requests[2].params.items[1].id)
          assert.same({ 'ruby', '-Itest' }, runs[1].command)
          assert.same({ 'test/foo_test.rb' }, runs[1].script)
          assert.same({ '--name', '/^FooTest#test_bar$/' }, runs[1].script_args)
        end)
      end)
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
