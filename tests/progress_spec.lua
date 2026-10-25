local helpers = require('helpers')
local config = require('ruby-lsp.config')

describe('progress', function()
  local echo_calls, original_nvim_echo, original_schedule

  before_each(function()
    helpers.setup_mocks()
    config.setup()
    echo_calls = {}
    original_nvim_echo = vim.api.nvim_echo
    original_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end
    vim.api.nvim_echo = function(chunks, history, opts)
      local call = { chunks = chunks, history = history, opts = opts }
      table.insert(echo_calls, call)
      return #echo_calls
    end
  end)

  after_each(function()
    vim.api.nvim_echo = original_nvim_echo
    vim.schedule = original_schedule
    helpers.teardown_mocks()
    package.loaded['ruby-lsp.progress'] = nil
  end)

  describe('when config disables progress', function()
    before_each(function()
      config.setup({ test_discovery = { progress = false } })
      package.loaded['ruby-lsp.progress'] = nil
    end)

    it('start returns nil and does not notify', function()
      local progress = require('ruby-lsp.progress')
      local id = progress.start('Discovering tests...')

      assert.is_nil(id)
      assert.equals(0, #helpers.notifications)
      assert.equals(0, #echo_calls)
    end)

    it('finish does nothing', function()
      local progress = require('ruby-lsp.progress')
      progress.finish(1, 'Done', true)

      assert.equals(0, #echo_calls)
    end)
  end)

  describe('when enabled', function()
    it('start calls nvim_echo with progress kind', function()
      local progress = require('ruby-lsp.progress')
      local id = progress.start('Discovering tests...')

      assert.is_not_nil(id)
      assert.equals(1, #echo_calls)
      assert.same({ { 'Discovering tests...' } }, echo_calls[1].chunks)
      assert.equals('progress', echo_calls[1].opts.kind)
      assert.equals('ruby-lsp.nvim', echo_calls[1].opts.source)
      assert.equals('ruby-lsp.nvim', echo_calls[1].opts.title)
      assert.equals('running', echo_calls[1].opts.status)
      assert.equals(0, #helpers.notifications)
    end)

    it('update calls nvim_echo with echo id', function()
      local progress = require('ruby-lsp.progress')
      local id = progress.start('Discovering tests...')
      progress.update(id, 'Discovering: foo_test.rb')

      assert.equals(2, #echo_calls)
      assert.same({ { 'Discovering: foo_test.rb' } }, echo_calls[2].chunks)
      assert.equals(1, echo_calls[2].opts.id)
      assert.equals('running', echo_calls[2].opts.status)
    end)

    it('update is a no-op when id is nil', function()
      local progress = require('ruby-lsp.progress')
      progress.update(nil, 'something')

      assert.equals(0, #echo_calls)
    end)

    it('finish calls nvim_echo with success status', function()
      local progress = require('ruby-lsp.progress')
      local id = progress.start('Discovering tests...')
      progress.finish(id, 'Tests discovered', true)

      assert.equals(2, #echo_calls)
      assert.same({ { 'Tests discovered' } }, echo_calls[2].chunks)
      assert.equals(1, echo_calls[2].opts.id)
      assert.equals('success', echo_calls[2].opts.status)
    end)

    it('finish calls nvim_echo with failed status', function()
      local progress = require('ruby-lsp.progress')
      local id = progress.start('Discovering tests...')
      progress.finish(id, 'Test discovery failed', false)

      assert.equals(2, #echo_calls)
      assert.same({ { 'Test discovery failed' } }, echo_calls[2].chunks)
      assert.equals('failed', echo_calls[2].opts.status)
    end)

    it('finish is a no-op when id is nil', function()
      local progress = require('ruby-lsp.progress')
      progress.finish(nil, 'Done', true)

      assert.equals(0, #echo_calls)
    end)

    it('finish cleans up echo id mapping', function()
      local progress = require('ruby-lsp.progress')
      local id = progress.start('Discovering tests...')
      progress.finish(id, 'Done', true)

      -- Second finish with same id should be a no-op (echo_id was cleaned up)
      progress.finish(id, 'Done again', true)

      assert.equals(2, #echo_calls)
    end)
  end)
end)
