local api = vim.api
local ts = vim.treesitter
local parsers = require('nvim-treesitter.parsers')
local M = {}
local AUGROUP = api.nvim_create_augroup('tree-pairs', {})

-- The modes for which to enable the mapping, along with their fallback
-- strategies.
local MODES = {
  n = function()
    vim.fn['matchit#Match_wrapper']('', 1, 'n')
  end,
  x = function()
    vim.fn['matchit#Match_wrapper']('', 1, 'v')
  end,
  o = function()
    vim.fn['matchit#Match_wrapper']('', 1, 'o')
  end,
}

-- The node types for which to fall back to using matchit.
local FALLBACK = {
  attribute_value = true,
  block_comment = true,
  line_comment = true,
  string_content = true,
  string_fragment = true,
}

-- The symbols to check for when falling back to using matchit.
local PAIRS = {
  ['['] = true,
  ['('] = true,
  ['{'] = true,
  ['<'] = true,
  [']'] = true,
  [')'] = true,
  ['}'] = true,
  ['>'] = true,
  ['"'] = true,
  ["'"] = true,
  ['`'] = true,
}

local function jump_to_node(node, jump_to_end)
  local start_row, start_col, end_row, end_col = node:range(false)

  -- This is needed so that in operator pending mode we don't miss any
  -- characters.
  if api.nvim_get_mode().mode == 'no' then
    vim.cmd('normal! v')
  end

  if jump_to_end then
    api.nvim_win_set_cursor(0, { end_row + 1, end_col - 1 })
  else
    api.nvim_win_set_cursor(0, { start_row + 1, start_col })
  end
end

local function char_under_cursor()
  local pos = api.nvim_win_get_cursor(0)
  local row = pos[1] - 1
  local col = pos[2]

  return api.nvim_buf_get_text(0, row, col, row, col + 1, {})[1]
end

local function match(buf, fallback)
  local has_parser, _ = pcall(vim.treesitter.get_parser, buf)

  if not has_parser then
    if PAIRS[char_under_cursor()] then
      fallback()
    end

    return
  end

  local root = ts.get_node()

  if not root then
    if PAIRS[char_under_cursor()] then
      fallback()
    end

    return
  end

  if FALLBACK[root:type()] then
    if PAIRS[char_under_cursor()] then
      return fallback()
    end
  end

  local pos = api.nvim_win_get_cursor(0)
  local cursor_row = pos[1] - 1
  local cursor_col = pos[2]
  local head = root:child(0)
  local tail = root:child(root:child_count() - 1)

  -- For certain languages, start/end characters (e.g. the
  -- quotes in a string) are separate nodes inside a parent node. An example is
  -- Python, which parses strings as
  -- `(string (string_start) (string_content) (string_end))`. This approach
  -- tries to handle such cases, without the need for Tree-sitter queries.
  if not head and not tail and PAIRS[char_under_cursor()] then
    local parent = root:parent()

    if parent then
      root = parent
      head = parent:child(0)
      tail = parent:child(root:child_count() - 1)
    end
  end

  -- The head and the tail might be the same for certain nodes (e.g. Rust
  -- booleans), in which case we use the fallback approach so you can easily
  -- jump between the start and the end of such nodes.
  if head and tail and not head:equal(tail) then
    -- This approach allows you to e.g. jump from an "if" to a matching "end",
    -- regardless of whether the cursor is on the "i" or "f".
    if ts.is_in_node_range(tail, cursor_row, cursor_col) then
      jump_to_node(head, false)
    else
      jump_to_node(tail, true)
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
  api.nvim_create_autocmd('FileType', {
    group = AUGROUP,
    pattern = '*',
    desc = 'Sets up tree-pairs for a buffer',
    callback = function()
      local buf = api.nvim_get_current_buf()
      local opts = {
        desc = 'Jump to the opposite end of the current Tree-sitter node',
        buffer = buf,
      }

      for mode, fallback in pairs(MODES) do
        vim.keymap.set(mode, '%', function()
          match(buf, fallback)
        end, opts)
      end
    end,
  })
end

return M
