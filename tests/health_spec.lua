local helpers = require('helpers')
local config = require('ruby-lsp.config')
local health = require('ruby-lsp.health')

describe('health', function()
  local reports, originals

  before_each(function()
    helpers.setup_mocks()
    config.setup()
    reports = {}
    originals = {
      health = vim.health,
      has = rawget(vim.fn, 'has'),
    }
    local function record(kind)
      return function(msg)
        table.insert(reports, { kind = kind, msg = msg })
      end
    end
    vim.health = {
      start = function() end,
      ok = record('ok'),
      info = record('info'),
      warn = record('warn'),
      error = record('error'),
    }
  end)

  after_each(function()
    vim.health = originals.health
    rawset(vim.fn, 'has', originals.has)
    helpers.teardown_mocks()
  end)

  describe('Neovim version', function()
    it('reports ok when Neovim meets the minimum', function()
      vim.fn.has = function()
        return 1
      end
      health.check()

      assert.equals('ok', reports[1].kind)
      assert.equals('Neovim ' .. tostring(vim.version()):gsub('%+.*$', ''), reports[1].msg)
    end)

    it('reports an error when Neovim is too old', function()
      vim.fn.has = function()
        return 0
      end
      health.check()

      assert.equals('error', reports[1].kind)
      assert.truthy(reports[1].msg:find('is too old %(minimum: 0.12%)'))
    end)
  end)
end)
