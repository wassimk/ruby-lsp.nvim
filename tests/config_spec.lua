local config = require('ruby-lsp.config')

describe('config', function()
  before_each(function()
    config.setup()
  end)

  describe('defaults', function()
    it('uses split executor by default', function()
      assert.equals('split', config.get().executor)
    end)

    it('uses horizontal split direction by default', function()
      assert.equals('horizontal', config.get().split.direction)
    end)

    it('uses split size 15 by default', function()
      assert.equals(15, config.get().split.size)
    end)

    it('uses float toggleterm direction by default', function()
      assert.equals('float', config.get().toggleterm.direction)
    end)

    it('has close_on_exit false for toggleterm by default', function()
      assert.is_false(config.get().toggleterm.close_on_exit)
    end)

    it('has keep_open true for tasks by default', function()
      assert.is_true(config.get().task.keep_open)
    end)

    it('auto-configures DAP by default', function()
      assert.is_true(config.get().dap.auto_configure)
    end)

    it('uses ruby DAP adapter by default', function()
      assert.equals('ruby', config.get().dap.adapter)
    end)
  end)

  describe('setup', function()
    it('deep merges partial options', function()
      config.setup({ executor = 'toggleterm' })

      assert.equals('toggleterm', config.get().executor)
      assert.equals('horizontal', config.get().split.direction)
    end)

    it('deep merges nested options without clobbering siblings', function()
      config.setup({ split = { size = 20 } })

      assert.equals(20, config.get().split.size)
      assert.equals('horizontal', config.get().split.direction)
    end)

    it('resets to defaults when called with no args', function()
      config.setup({ executor = 'toggleterm' })
      config.setup()

      assert.equals('split', config.get().executor)
    end)

    it('does not share state between setup calls', function()
      config.setup({ split = { size = 30 } })
      config.setup()

      assert.equals(15, config.get().split.size)
    end)

    it('accepts a custom function as executor', function()
      local fn = function() end
      config.setup({ executor = fn })

      assert.equals(fn, config.get().executor)
    end)
  end)
end)
