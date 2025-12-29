---@type rustaceanvim.TestExecutor
---@diagnostic disable-next-line: missing-fields
local M = {}

---@param opts rustaceanvim.TestExecutor.Opts
M.execute_command = function(_, _, _, opts)
  ---@type rustaceanvim.TestExecutor.Opts
  opts = vim.tbl_deep_extend('force', { bufnr = 0 }, opts or {})
  if type(opts.runnable) ~= 'table' then
    vim.notify('rustaceanvim quicktest executor called without a runnable. This is a bug!', vim.log.levels.ERROR)
    return
  end
  
  -- Get the location from the runnable
  local location = opts.runnable.location
  if location then
    -- Move cursor to the test location
    local start_row = location.targetRange.start.line
    local start_col = location.targetRange.start.character
    vim.api.nvim_win_set_cursor(0, { start_row + 1, start_col })
  end
  
  -- Run quicktest at the current cursor position
  ---@diagnostic disable-next-line: undefined-field
  require('quicktest').run_line()
end

return M
