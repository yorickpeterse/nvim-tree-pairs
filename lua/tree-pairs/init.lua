local api = vim.api
local ts = vim.treesitter
local utils = require('nvim-treesitter.ts_utils')
local parsers = require('nvim-treesitter.parsers')
local M = {}

local MODES = { 'n', 'x', 'o' }

local function match()
  local root = ts.get_node()

  if not root then
    return
  end

  local head = root:child(0)
  local tail = root:child(root:child_count() - 1)
  local pos = api.nvim_win_get_cursor(0)
  local cursor_row = pos[1] - 1
  local cursor_col = pos[2]

  -- The head and the tail might be the same for certain nodes (e.g. Rust
  -- booleans), in which case we use the fallback approach so you can easily
  -- jump between the start and the end of such nodes.
  if head and tail and not head:equal(tail) then
    -- This approach allows you to e.g. jump from an "if" to a matching "end",
    -- regardless of whether the cursor is on the "i" or "f".
    if ts.is_in_node_range(tail, cursor_row, cursor_col) then
      utils.goto_node(head, false)
    else
      utils.goto_node(tail, true)
    end
  else
    -- This approach checks if the cursor is at exactly the first or last
    -- character in the node. This is used as a fallback for nodes without
    -- children, such as a boolean literal. This way if the cursor is at "t" in
    -- "true", you can jump to the "e" and the other way around.
    local start_row, start_col, _ = root:start()
    local end_row, end_col, _ = root:end_()

    if cursor_row == end_row and cursor_col == end_col - 1 then
      api.nvim_win_set_cursor(0, { start_row + 1, start_col })
    else
      -- End columns point to a position _after_ the end of the node, so we have
      -- to subtract 1.
      api.nvim_win_set_cursor(0, { end_row + 1, end_col - 1 })
    end
  end
end

function M.setup()
  require('nvim-treesitter').define_modules({
    pairs = {
      enable = true,
      attach = function(buf)
        local opts = {
          desc = 'Jump to the opposite end of the current Tree-sitter node',
          buffer = buf,
        }

        for _, mode in ipairs(MODES) do
          vim.keymap.set(mode, '%', match, opts)
        end
      end,
      detach = function(buf)
        for _, mode in ipairs(MODES) do
          vim.keymap.del(mode, '%', { buffer = buf })
        end
      end,
    },
  })
end

return M
