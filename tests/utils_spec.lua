local helpers = require('helpers')
local utils = require('ruby-lsp.utils')

describe('utils', function()
  before_each(function()
    helpers.setup_mocks()
  end)

  after_each(function()
    helpers.teardown_mocks()
  end)

  describe('find_test_item', function()
    it('finds item at top level', function()
      local items = {
        { id = 'FooTest', label = 'FooTest' },
        { id = 'BarTest', label = 'BarTest' },
      }

      local found = utils.find_test_item(items, 'BarTest')

      assert.is_not_nil(found)
      assert.equals('BarTest', found.id)
    end)

    it('finds deeply nested item', function()
      local items = {
        {
          id = 'FooTest',
          children = {
            {
              id = 'FooTest::Inner',
              children = {
                { id = 'FooTest::Inner#test_deep' },
              },
            },
          },
        },
      }

      local found = utils.find_test_item(items, 'FooTest::Inner#test_deep')

      assert.is_not_nil(found)
      assert.equals('FooTest::Inner#test_deep', found.id)
    end)

    it('returns nil when not found', function()
      local items = {
        { id = 'FooTest', children = { { id = 'FooTest#test_bar' } } },
      }

      assert.is_nil(utils.find_test_item(items, 'NonExistent'))
    end)

    it('returns nil for empty items list', function()
      assert.is_nil(utils.find_test_item({}, 'anything'))
    end)

    it('finds first match when duplicates exist', function()
      local items = {
        { id = 'FooTest', label = 'first' },
        { id = 'FooTest', label = 'second' },
      }

      local found = utils.find_test_item(items, 'FooTest')

      assert.equals('first', found.label)
    end)
  end)

  describe('wrap_test_item', function()
    it('wraps item with expected fields', function()
      local item = {
        id = 'FooTest#test_bar',
        label = 'test_bar',
        uri = 'file:///path/to/test.rb',
        range = { start = { line = 5, character = 2 }, ['end'] = { line = 10, character = 5 } },
        tags = { 'framework:minitest' },
      }

      local wrapped = utils.wrap_test_item(item)

      assert.equals('FooTest#test_bar', wrapped.id)
      assert.equals('test_bar', wrapped.label)
      assert.equals('file:///path/to/test.rb', wrapped.uri)
      assert.same(item.range, wrapped.range)
      assert.same({ 'framework:minitest' }, wrapped.tags)
      assert.same({}, wrapped.children)
    end)

    it('defaults tags to empty table when missing', function()
      local item = { id = 'test', label = 'test', uri = 'file:///test.rb', range = {} }

      local wrapped = utils.wrap_test_item(item)

      assert.same({}, wrapped.tags)
    end)

    it('always sets children to empty table', function()
      local item = {
        id = 'test',
        label = 'test',
        uri = 'file:///test.rb',
        range = {},
        children = { { id = 'child' } },
      }

      local wrapped = utils.wrap_test_item(item)

      assert.same({}, wrapped.children)
    end)
  end)

  describe('full_test_discovery_enabled', function()
    it('returns true when flag is set', function()
      local client = helpers.mock_client()

      assert.is_true(utils.full_test_discovery_enabled(client))
    end)

    it('returns false when flag is not set', function()
      local client = { config = { init_options = { enabledFeatureFlags = {} } } }

      assert.is_false(utils.full_test_discovery_enabled(client))
    end)

    it('returns false when no enabledFeatureFlags', function()
      local client = { config = { init_options = {} } }

      assert.is_false(utils.full_test_discovery_enabled(client))
    end)

    it('returns false when no init_options', function()
      local client = { config = {} }

      assert.is_false(utils.full_test_discovery_enabled(client))
    end)
  end)

  describe('validate_test_args', function()
    it('returns file_path and test_id on success', function()
      helpers.lsp_clients = { helpers.mock_client() }

      local file_path, test_id = utils.validate_test_args({
        arguments = { '/path/to/test.rb', 'FooTest#test_bar' },
      })

      assert.equals('/path/to/test.rb', file_path)
      assert.equals('FooTest#test_bar', test_id)
    end)

    it('returns nil when no client is running', function()
      helpers.lsp_clients = {}

      local file_path, test_id = utils.validate_test_args({
        arguments = { '/path/to/test.rb', 'FooTest#test_bar' },
      })

      assert.is_nil(file_path)
      assert.is_nil(test_id)
      assert.equals(1, #helpers.notifications)
      assert.equals(vim.log.levels.ERROR, helpers.notifications[1].level)
    end)

    it('returns nil when feature flag is not enabled', function()
      helpers.lsp_clients = {
        { id = 1, name = 'ruby_lsp', config = { init_options = { enabledFeatureFlags = {} } } },
      }

      local file_path, test_id = utils.validate_test_args({
        arguments = { '/path/to/test.rb', 'FooTest#test_bar' },
      })

      assert.is_nil(file_path)
      assert.is_nil(test_id)
      assert.equals(1, #helpers.notifications)
      assert.equals(vim.log.levels.WARN, helpers.notifications[1].level)
    end)

    it('returns nil when missing file_path', function()
      helpers.lsp_clients = { helpers.mock_client() }

      local file_path, test_id = utils.validate_test_args({
        arguments = {},
      })

      assert.is_nil(file_path)
      assert.is_nil(test_id)
    end)

    it('returns nil when missing test_id', function()
      helpers.lsp_clients = { helpers.mock_client() }

      local file_path, test_id = utils.validate_test_args({
        arguments = { '/path/to/test.rb' },
      })

      assert.is_nil(file_path)
      assert.is_nil(test_id)
    end)

    it('returns nil when no arguments key', function()
      helpers.lsp_clients = { helpers.mock_client() }

      local file_path, test_id = utils.validate_test_args({})

      assert.is_nil(file_path)
      assert.is_nil(test_id)
    end)
  end)
end)
