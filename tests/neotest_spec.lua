-- Mock nio before requiring the neotest adapter
package.loaded['nio'] = {
  wrap = function(fn, nparams)
    return fn
  end,
  sleep = function() end,
  fn = setmetatable({}, {
    __index = function()
      return function() end
    end,
  }),
}

local helpers = require('helpers')
local adapter = require('ruby-lsp.neotest')

local function make_node(data, children)
  return {
    data = function()
      return data
    end,
    children = function()
      return children or {}
    end,
  }
end

describe('neotest adapter', function()
  before_each(function()
    helpers.setup_mocks()
  end)

  after_each(function()
    helpers.teardown_mocks()
  end)

  describe('is_test_file', function()
    before_each(function()
      helpers.lsp_clients = { helpers.mock_client() }
    end)

    it('matches _test.rb files', function()
      assert.is_true(adapter.is_test_file('/path/to/foo_test.rb'))
    end)

    it('matches _spec.rb files', function()
      assert.is_true(adapter.is_test_file('/path/to/foo_spec.rb'))
    end)

    it('matches test_*.rb files', function()
      assert.is_true(adapter.is_test_file('/path/to/test_foo.rb'))
    end)

    it('rejects non-test .rb files', function()
      assert.is_false(adapter.is_test_file('/path/to/foo.rb'))
    end)

    it('rejects files that contain test in path but not filename', function()
      assert.is_false(adapter.is_test_file('/path/to/test/helper.rb'))
    end)

    it('rejects non-.rb files', function()
      assert.is_false(adapter.is_test_file('/path/to/foo_test.py'))
    end)

    it('rejects nil path', function()
      assert.is_false(adapter.is_test_file(nil))
    end)

    it('returns false when no LSP client is active', function()
      helpers.lsp_clients = {}

      assert.is_false(adapter.is_test_file('/path/to/foo_test.rb'))
    end)
  end)

  describe('filter_dir', function()
    it('allows regular directories', function()
      assert.is_true(adapter.filter_dir('app'))
      assert.is_true(adapter.filter_dir('test'))
      assert.is_true(adapter.filter_dir('spec'))
      assert.is_true(adapter.filter_dir('lib'))
    end)

    it('skips vendor', function()
      assert.is_false(adapter.filter_dir('vendor'))
    end)

    it('skips node_modules', function()
      assert.is_false(adapter.filter_dir('node_modules'))
    end)

    it('skips .bundle', function()
      assert.is_false(adapter.filter_dir('.bundle'))
    end)

    it('skips .git', function()
      assert.is_false(adapter.filter_dir('.git'))
    end)
  end)

  describe('results', function()
    it('marks all tests as passed when exit code is 0', function()
      local node1 = make_node({
        type = 'test',
        id = '/path/test.rb::FooTest#test_one',
        lsp_test_item = { id = 'FooTest#test_one' },
      })
      local node2 = make_node({
        type = 'test',
        id = '/path/test.rb::FooTest#test_two',
        lsp_test_item = { id = 'FooTest#test_two' },
      })
      local tree = make_node({ type = 'file', id = '/path/test.rb' }, { node1, node2 })

      local spec = { context = { pos_id = '/path/test.rb' } }
      local result = { code = 0, output = '/dev/null' }
      local results = adapter.results(spec, result, tree)

      assert.equals('passed', results['/path/test.rb::FooTest#test_one'].status)
      assert.equals('passed', results['/path/test.rb::FooTest#test_two'].status)
    end)

    it('parses minitest failures', function()
      local passing = make_node({
        type = 'test',
        id = '/path/test.rb::FooTest#test_passing',
        lsp_test_item = { id = 'FooTest#test_passing' },
      })
      local failing = make_node({
        type = 'test',
        id = '/path/test.rb::FooTest#test_bar',
        lsp_test_item = { id = 'FooTest#test_bar' },
      })
      local erroring = make_node({
        type = 'test',
        id = '/path/test.rb::FooTest#test_baz',
        lsp_test_item = { id = 'FooTest#test_baz' },
      })
      local tree = make_node({ type = 'file', id = '/path/test.rb' }, { passing, failing, erroring })

      local spec = { context = { pos_id = '/path/test.rb' } }
      local result = { code = 1, output = 'tests/fixtures/minitest_output.txt' }
      local results = adapter.results(spec, result, tree)

      assert.equals('passed', results['/path/test.rb::FooTest#test_passing'].status)
      assert.equals('failed', results['/path/test.rb::FooTest#test_bar'].status)
      assert.equals('failed', results['/path/test.rb::FooTest#test_baz'].status)
    end)

    it('parses rspec failures by line number', function()
      local passing = make_node({
        type = 'test',
        id = '/path/spec.rb::test_passing',
        lsp_test_item = { id = 'test_passing', range = { start = { line = 24 } } },
      })
      local failing1 = make_node({
        type = 'test',
        id = '/path/spec.rb::test_bar',
        lsp_test_item = { id = 'test_bar', range = { start = { line = 4 } } },
      })
      local failing2 = make_node({
        type = 'test',
        id = '/path/spec.rb::test_baz',
        lsp_test_item = { id = 'test_baz', range = { start = { line = 14 } } },
      })
      local tree = make_node({ type = 'file', id = '/path/spec.rb' }, { passing, failing1, failing2 })

      local spec = { context = { pos_id = '/path/spec.rb', framework = 'rspec' } }
      local result = { code = 1, output = 'tests/fixtures/rspec_output.txt' }
      local results = adapter.results(spec, result, tree)

      assert.equals('passed', results['/path/spec.rb::test_passing'].status)
      assert.equals('failed', results['/path/spec.rb::test_bar'].status)
      assert.equals('failed', results['/path/spec.rb::test_baz'].status)
    end)

    it('handles ANSI escape codes in minitest output', function()
      local tmp = os.tmpname()
      local f = io.open(tmp, 'w')
      f:write('  1) Failure:\n')
      f:write('\27[31mFooTest#test_colored\27[0m [test.rb:10]:\n')
      f:write('Expected true\n')
      f:close()

      local failing = make_node({
        type = 'test',
        id = '/path/test.rb::FooTest#test_colored',
        lsp_test_item = { id = 'FooTest#test_colored' },
      })
      local tree = make_node({ type = 'file', id = '/path/test.rb' }, { failing })

      local spec = { context = { pos_id = '/path/test.rb' } }
      local result = { code = 1, output = tmp }
      local results = adapter.results(spec, result, tree)

      assert.equals('failed', results['/path/test.rb::FooTest#test_colored'].status)
      os.remove(tmp)
    end)

    it('handles ANSI escape codes in rspec output', function()
      local tmp = os.tmpname()
      local f = io.open(tmp, 'w')
      f:write('Failed examples:\n')
      f:write('\27[31mrspec ./spec/foo_spec.rb:5\27[0m # Foo does bar\n')
      f:close()

      local failing = make_node({
        type = 'test',
        id = '/path/spec.rb::test_bar',
        lsp_test_item = { id = 'test_bar', range = { start = { line = 4 } } },
      })
      local tree = make_node({ type = 'file', id = '/path/spec.rb' }, { failing })

      local spec = { context = { pos_id = '/path/spec.rb', framework = 'rspec' } }
      local result = { code = 1, output = tmp }
      local results = adapter.results(spec, result, tree)

      assert.equals('failed', results['/path/spec.rb::test_bar'].status)
      os.remove(tmp)
    end)

    it('walks nested namespaces to find test leaves', function()
      local leaf = make_node({
        type = 'test',
        id = '/path/test.rb::FooTest#test_bar',
        lsp_test_item = { id = 'FooTest#test_bar' },
      })
      local namespace = make_node({
        type = 'namespace',
        id = '/path/test.rb::FooTest',
        lsp_test_item = { id = 'FooTest' },
      }, { leaf })
      local tree = make_node({ type = 'file', id = '/path/test.rb' }, { namespace })

      local spec = { context = { pos_id = '/path/test.rb' } }
      local result = { code = 0, output = '/dev/null' }
      local results = adapter.results(spec, result, tree)

      assert.equals('passed', results['/path/test.rb::FooTest#test_bar'].status)
      assert.is_nil(results['/path/test.rb::FooTest'])
    end)

    it('falls back to marking parent when parser finds no individual failures', function()
      local tmp = os.tmpname()
      local f = io.open(tmp, 'w')
      f:write('Some unexpected output format\n')
      f:close()

      local node = make_node({
        type = 'test',
        id = '/path/test.rb::SomeTest#test_thing',
        lsp_test_item = { id = 'SomeTest#test_thing' },
      })
      local tree = make_node({ type = 'file', id = '/path/test.rb' }, { node })

      local spec = { context = { pos_id = '/path/test.rb' } }
      local result = { code = 1, output = tmp }
      local results = adapter.results(spec, result, tree)

      assert.equals('failed', results['/path/test.rb'].status)
      assert.is_nil(results['/path/test.rb::SomeTest#test_thing'])
      os.remove(tmp)
    end)
  end)
end)
