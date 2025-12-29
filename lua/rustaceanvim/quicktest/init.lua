---@mod rustaceanvim.quicktest
---
---@brief [[
---
---A |quicktest| adapter for rust, powered by rustaceanvim.
---
---If you add this to quicktest:
---
--->
---require('quicktest').setup {
---    -- ...,
---    adapters = {
---      -- ...,
---      require('rustaceanvim.quicktest')
---    },
---}
---<
---
---this plugin will configure itself to use |quicktest|
---as a test executor, and |quicktest| will use rust-analyzer
---for test discovery and command construction.
---
---@brief ]]

local cargo = require('rustaceanvim.cargo')
local config = require('rustaceanvim.config.internal')
local trans = require('rustaceanvim.neotest.trans')
local Job = require('plenary.job')

---@class QuicktestAdapter
local M = {
  name = 'rustaceanvim',
}

---@class rustaceanvim.quicktest.RunParams
---@field runnable rustaceanvim.RARunnable
---@field bufnr integer
---@field cursor_pos integer[]
---@field opts AdapterRunOpts
---@field cwd string

---Get the root directory for a file
---@param bufnr integer
---@return string | nil
local function get_root(bufnr)
  local file_name = vim.api.nvim_buf_get_name(bufnr)
  return cargo.get_config_root_dir(config.server, file_name)
end

---Get runnables from rust-analyzer
---@param bufnr integer
---@return rustaceanvim.RARunnable[] | nil
local function get_runnables(bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local lsp_client = require('rustaceanvim.rust_analyzer').get_client_for_file(file_path, 'experimental/runnables')
  if not lsp_client then
    return nil
  end

  local params = {
    textDocument = {
      uri = vim.uri_from_fname(file_path),
    },
    position = nil,
  }

  local result, err = lsp_client.request_sync('experimental/runnables', params, 10000, bufnr)
  if err or not result or not result.result then
    return nil
  end

  return result.result
end

---Find runnable at cursor position
---@param bufnr integer
---@param cursor_pos integer[]
---@return rustaceanvim.RARunnable | nil
local function find_runnable_at_cursor(bufnr, cursor_pos)
  local runnables = get_runnables(bufnr)
  if not runnables or #runnables == 0 then
    return nil
  end

  local row = cursor_pos[1]
  
  -- Find the smallest runnable that contains the cursor
  local best_match = nil
  local best_size = math.huge
  
  for _, runnable in ipairs(runnables) do
    local location = runnable.location
    if location then
      local start_row = location.targetRange.start.line + 1
      local end_row = location.targetRange['end'].line + 1
      local size = end_row - start_row
      
      if start_row <= row and row <= end_row and size < best_size then
        -- Only include test runnables
        local cargoArgs = runnable.args and runnable.args.cargoArgs or {}
        if #cargoArgs > 0 and vim.startswith(cargoArgs[1], 'test') then
          best_match = runnable
          best_size = size
        end
      end
    end
  end
  
  return best_match
end

---Find all test runnables in a file
---@param bufnr integer
---@return rustaceanvim.RARunnable[]
local function find_file_runnables(bufnr)
  local runnables = get_runnables(bufnr)
  if not runnables then
    return {}
  end
  
  local test_runnables = {}
  for _, runnable in ipairs(runnables) do
    local cargoArgs = runnable.args and runnable.args.cargoArgs or {}
    if #cargoArgs > 0 and vim.startswith(cargoArgs[1], 'test') then
      -- Prefer file-level or module-level tests
      if vim.startswith(runnable.label, 'test-mod') or vim.startswith(runnable.label, 'cargo test -p') then
        table.insert(test_runnables, runnable)
      end
    end
  end
  
  -- If no module-level tests, return the first test runnable
  if #test_runnables == 0 and runnables[1] then
    local cargoArgs = runnables[1].args and runnables[1].args.cargoArgs or {}
    if #cargoArgs > 0 and vim.startswith(cargoArgs[1], 'test') then
      return { runnables[1] }
    end
  end
  
  return test_runnables
end

---Build parameters for line run
---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return rustaceanvim.quicktest.RunParams | nil, string | nil
function M.build_line_run_params(bufnr, cursor_pos, opts)
  local runnable = find_runnable_at_cursor(bufnr, cursor_pos)
  if not runnable then
    return nil, 'No test found at cursor'
  end
  
  local cwd = get_root(bufnr) or vim.fn.getcwd()
  
  return {
    runnable = runnable,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
    cwd = cwd,
  }, nil
end

---Build parameters for file run
---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return rustaceanvim.quicktest.RunParams | nil, string | nil
function M.build_file_run_params(bufnr, cursor_pos, opts)
  local runnables = find_file_runnables(bufnr)
  if #runnables == 0 then
    return nil, 'No tests found in file'
  end
  
  local cwd = get_root(bufnr) or vim.fn.getcwd()
  
  -- Use the first runnable (typically module-level)
  return {
    runnable = runnables[1],
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
    cwd = cwd,
  }, nil
end

---Build parameters for directory run
---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return rustaceanvim.quicktest.RunParams | nil, string | nil
function M.build_dir_run_params(bufnr, cursor_pos, opts)
  local runnables = get_runnables(bufnr)
  if not runnables then
    return nil, 'No runnables found'
  end
  
  local cwd = get_root(bufnr) or vim.fn.getcwd()
  
  -- Find a package-level test runnable
  for _, runnable in ipairs(runnables) do
    if vim.startswith(runnable.label, 'cargo test -p') then
      return {
        runnable = runnable,
        bufnr = bufnr,
        cursor_pos = cursor_pos,
        opts = opts,
        cwd = cwd,
      }, nil
    end
  end
  
  return nil, 'No package-level test found'
end

---Build parameters for all tests run
---@param bufnr integer
---@param cursor_pos integer[]
---@param opts AdapterRunOpts
---@return rustaceanvim.quicktest.RunParams | nil, string | nil
function M.build_all_run_params(bufnr, cursor_pos, opts)
  local cwd = get_root(bufnr) or vim.fn.getcwd()
  
  -- Create a synthetic runnable for all tests
  local runnable = {
    label = 'cargo test --workspace',
    args = {
      workspaceRoot = cwd,
      cargoArgs = { 'test', '--workspace' },
      executableArgs = {},
    },
  }
  
  return {
    runnable = runnable,
    bufnr = bufnr,
    cursor_pos = cursor_pos,
    opts = opts,
    cwd = cwd,
  }, nil
end

---Run tests
---@param params rustaceanvim.quicktest.RunParams
---@param send fun(data: CmdData)
---@return integer
function M.run(params, send)
  local exe, args, cwd, env = require('rustaceanvim.runnables').get_command(params.runnable)
  
  -- Add additional args if provided
  if params.opts.additional_args then
    args = vim.list_extend(args, params.opts.additional_args)
  end
  
  local job = Job:new({
    command = exe,
    args = args,
    cwd = cwd or params.cwd,
    env = env,
    on_stdout = function(_, data)
      send({ type = 'stdout', raw = data, output = data })
    end,
    on_stderr = function(_, data)
      send({ type = 'stderr', raw = data, output = data })
    end,
    on_exit = function(_, return_val)
      send({ type = 'exit', code = return_val })
    end,
  })
  
  job:start()
  
  ---@type integer
  ---@diagnostic disable-next-line: assign-type-mismatch
  local pid = job.pid
  
  return pid
end

---Generate title for the test run
---@param params rustaceanvim.quicktest.RunParams
---@return string
function M.title(params)
  return 'Running: ' .. params.runnable.label
end

---Check if adapter is enabled for buffer
---@param bufnr integer
---@param type RunType
---@return boolean
function M.is_enabled(bufnr, type)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return vim.endswith(bufname, '.rs')
end

return M
