local api = vim.api
local ts = vim.treesitter
local fn = vim.fn
local M = {}
local AUGROUP = api.nvim_create_augroup('tree-pairs', {})

-- The modes for which to enable the mapping, along with their fallback
-- strategies.
local MODES = {
  n = function()
    vim.cmd('execute ":normal \\<Plug>(MatchitNormalForward)"')
  end,
  x = function()
    vim.cmd('execute ":normal \\<Plug>(MatchitVisualForward)"')
  end,
  o = function()
    vim.cmd('execute ":normal \\<Plug>(MatchitOperationForward)"')
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

-- File types for which to _not_ enable the plugin.
local DISABLE_FT = {
  netrw = true,
}

local function node_range(node)
  local start_row, start_col, end_row, end_col = node:range(false)

  -- Certain parsers (e.g. Markdown) don't report column numbers. In such cases
  -- we treat the last column of the current line as the end column.
  if end_col == 0 then
    end_col = fn.col({ end_row, '$' }) - 1
  else
    end_col = end_col - 1
  end

  return start_row, start_col, end_row, end_col
end

local function jump_to_node(node, jump_to_end)
  local start_row, start_col, end_row, end_col = node_range(node)

  -- This is needed so that in operator pending mode we don't miss any
  -- characters.
  if api.nvim_get_mode().mode == 'no' then
    vim.cmd('normal! v')
  end

  if jump_to_end then
    api.nvim_win_set_cursor(0, { end_row + 1, end_col })
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
  local has_parser, parser = pcall(ts.get_parser, buf)

  if not has_parser then
    return fallback()
  end

  local pos = api.nvim_win_get_cursor(0)
  local cursor_row = pos[1] - 1
  local cursor_col = pos[2]
  local line = api.nvim_get_current_line()

  if #line > 0 then
    if cursor_col == #line then
      -- In visual mode it's possible to move the cursor to the newline at the
      -- end (= beyond the last line character). In this case Tree-sitter's
      -- parse() method returns the parent/surrounding node, rather than
      -- whatever node is directly to the left of the cursor.
      cursor_col = cursor_col - 1

      while
        cursor_col > 0 and line:sub(cursor_col + 1, cursor_col + 1):match('%s')
      do
        cursor_col = cursor_col - 1
      end
    elseif line:sub(1, cursor_col + 1):match('^%s$') then
      -- If the cursor is instead in between leading whitespace and the first
      -- non-whitespace character, we treat that first non-whitespace character
      -- as the start, matching the behaviour of matchit.
      local pos = line:find('%S')

      if pos then
        cursor_col = pos - 1
      end
    end
  end

  -- We need to make sure the range is parsed first, otherwise getting the root
  -- node might not work reliably when using injected languages.
  parser:parse({ cursor_row, cursor_col })

  local root = parser:named_node_for_range(
    { cursor_row, cursor_col, cursor_row, cursor_col },
    { ignore_injections = false }
  )

  if not root then
    return fallback()
  end

  if FALLBACK[root:type()] then
    return fallback()
  end

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
    local start_row, start_col, end_row, end_col = node_range(root)

    if cursor_row == end_row and cursor_col == end_col then
      api.nvim_win_set_cursor(0, { start_row + 1, start_col })
    else
      -- End columns point to a position _after_ the end of the node, so we have
      -- to subtract 1.
      api.nvim_win_set_cursor(0, { end_row + 1, end_col })
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

      if DISABLE_FT[vim.bo[buf].ft] then
        return
      end

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
