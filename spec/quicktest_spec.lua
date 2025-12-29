describe('rustaceanvim.quicktest', function()
  describe('adapter', function()
    it('has required fields', function()
      local adapter = require('rustaceanvim.quicktest')
      
      assert.truthy(adapter.name)
      assert.equals('rustaceanvim', adapter.name)
      assert.truthy(adapter.build_line_run_params)
      assert.truthy(adapter.build_file_run_params)
      assert.truthy(adapter.build_dir_run_params)
      assert.truthy(adapter.build_all_run_params)
      assert.truthy(adapter.run)
      assert.truthy(adapter.title)
      assert.truthy(adapter.is_enabled)
    end)

    it('is_enabled returns true for Rust files', function()
      local adapter = require('rustaceanvim.quicktest')
      
      -- Create a temporary buffer with a .rs file
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, '/tmp/test.rs')
      
      local enabled = adapter.is_enabled(bufnr, 'line')
      assert.is_true(enabled)
      
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('is_enabled returns false for non-Rust files', function()
      local adapter = require('rustaceanvim.quicktest')
      
      -- Create a temporary buffer with a .lua file
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(bufnr, '/tmp/test.lua')
      
      local enabled = adapter.is_enabled(bufnr, 'line')
      assert.is_false(enabled)
      
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('title generates correct title', function()
      local adapter = require('rustaceanvim.quicktest')
      
      local params = {
        runnable = {
          label = 'test my_test',
        },
        bufnr = 0,
        cursor_pos = { 1, 0 },
        opts = {},
        cwd = '/tmp',
      }
      
      local title = adapter.title(params)
      assert.equals('Running: test my_test', title)
    end)
  end)
end)
