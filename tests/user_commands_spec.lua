local helpers = require('helpers')
local user_commands = require('ruby-lsp.user_commands')

describe('user_commands', function()
  local bufnr, requests, response

  local function client()
    return {
      id = 1,
      name = 'ruby_lsp',
      offset_encoding = 'utf-16',
      request = function(_, method, params, handler, buf)
        table.insert(requests, { method = method, params = params, bufnr = buf })
        handler(response.err, response.result)
        return true
      end,
    }
  end

  local function run(cmd)
    vim.api.nvim_set_current_buf(bufnr)
    vim.cmd(cmd)
  end

  before_each(function()
    helpers.setup_mocks()
    requests = {}
    response = {}
    bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, '/tmp/ruby_lsp_nvim_spec/app.rb')
    vim.api.nvim_set_current_buf(bufnr)
    user_commands.attach(client(), bufnr)
  end)

  after_each(function()
    vim.fn.setqflist({})
    vim.cmd('cclose')
    vim.cmd('silent! only')
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    helpers.teardown_mocks()
  end)

  it('creates the three commands in the buffer', function()
    local cmds = vim.api.nvim_buf_get_commands(bufnr, {})
    assert.is_not_nil(cmds.RubyLspShowDependencies)
    assert.is_not_nil(cmds.RubyLspShowSyntaxTree)
    assert.is_not_nil(cmds.RubyLspDiscoverTests)
  end)

  describe('RubyLspShowDependencies', function()
    before_each(function()
      response.result = {
        { name = 'rails', version = '8.0.0', dependency = true, path = '/gems/rails' },
        { name = 'rack', version = '3.0.0', dependency = false, path = '/gems/rack' },
      }
    end)

    it('lists only direct dependencies without all', function()
      run('RubyLspShowDependencies')
      local qf = vim.fn.getqflist()
      assert.equals(1, #qf)
      assert.equals('rails (8.0.0) - true', qf[1].text)
      assert.equals('rubyLsp/workspace/dependencies', requests[1].method)
    end)

    it('lists every dependency with all', function()
      run('RubyLspShowDependencies all')
      local qf = vim.fn.getqflist()
      assert.equals(2, #qf)
      assert.equals('rack (3.0.0) - false', qf[2].text)
    end)
  end)

  describe('RubyLspDiscoverTests', function()
    it('lists nested tests in the quickfix list', function()
      local uri = vim.uri_from_fname('/tmp/ruby_lsp_nvim_spec/app_test.rb')
      response.result = {
        {
          label = 'ParentTest',
          uri = uri,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 9, character = 0 } },
          children = {
            {
              label = 'test_child',
              uri = uri,
              range = { start = { line = 4, character = 2 }, ['end'] = { line = 6, character = 0 } },
              children = {},
            },
          },
        },
      }
      run('RubyLspDiscoverTests')
      local qf = vim.fn.getqflist()
      assert.equals(2, #qf)
      assert.equals('ParentTest', qf[1].text)
      assert.equals(1, qf[1].lnum)
      assert.equals(1, qf[1].col)
      assert.equals('test_child', qf[2].text)
      assert.equals(5, qf[2].lnum)
      assert.equals(3, qf[2].col)
      assert.equals('rubyLsp/discoverTests', requests[1].method)
    end)
  end)

  describe('RubyLspShowSyntaxTree', function()
    it('opens the syntax tree in a scratch split', function()
      response.result = { ast = 'ProgramNode\n  StatementsNode\n' }
      run('RubyLspShowSyntaxTree')
      local buf = vim.api.nvim_get_current_buf()
      assert.are_not.equal(bufnr, buf)
      assert.equals('nofile', vim.bo[buf].buftype)
      assert.equals('wipe', vim.bo[buf].bufhidden)
      assert.is_false(vim.bo[buf].swapfile)
      assert.equals('', vim.bo[buf].filetype)
      assert.same({ 'ProgramNode', '  StatementsNode' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.equals('rubyLsp/textDocument/showSyntaxTree', requests[1].method)
    end)
  end)

  describe('request errors', function()
    it('notifies on request errors', function()
      response.err = { code = -32603, message = 'boom' }
      run('RubyLspShowDependencies')
      run('RubyLspShowSyntaxTree')
      run('RubyLspDiscoverTests')
      assert.equals(3, #helpers.notifications)
      for _, n in ipairs(helpers.notifications) do
        assert.matches('^ruby%-lsp: ', n.msg)
        assert.matches('boom', n.msg)
        assert.equals(vim.log.levels.ERROR, n.level)
      end
      assert.equals(0, #vim.fn.getqflist())
    end)
  end)
end)
