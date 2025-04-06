# nvim-tree-pairs

A NeoVim plugin that uses Tree-sitter to allow jumping between the matching
opposing end of a Tree-sitter node, such as brackets, quotes, and more.

[![A recording of using the plugin](https://asciinema.org/a/654974.svg)](https://asciinema.org/a/654974)

# What does it do?

- If the cursor is on the start or end of a Tree-sitter node (e.g. a `{`), jump
  to the other end
- If the cursor is somewhere in the middle of a Tree-sitter node, jump to the
  end of the node

# Why?

When using Tree-sitter, the `%` motion of NeoVim doesn't always work reliably,
as it requires syntax information not present when using Tree-sitter. This is
most notable when you're jumping between matching brackets (e.g. `{` and `}`),
but there are a lot of lines in between, as in this case `%` might jump to some
random location in the middle.

This plugin solves this issue by using Tree-sitter when enabled, falling back to
the default `%` behaviour if Tree-sitter isn't enabled. When Tree-sitter is
available, you can jump between the start and end of any Tree-sitter node. Take
this Lua code for example:

```lua
example
```

When you place the cursor on the `e` in `example` and press `%`, the cursor
jumps to the closing `e`. If you then press `%` again, it jumps back to the
starting `e`.

# Requirements

- NeoVim `main`, 0.9.5 _might_ also work but I haven't verified this

# Installation

Add `yorickpeterse/nvim-tree-pairs` using your favourite package manager, then
add the following somewhere to your `init.lua`:

```lua
require('tree-pairs').setup()
```

This creates a "pairs" Tree-sitter module that's enabled automatically. You can
disable it (if needed) using `:TSDisable pairs`.

# Limitations

This plugin doesn't have any language specific handling or Tree-sitter queries,
meaning it can't handle jumping from e.g. the Lua `then` keyword to the next
`elseif` keyword. This is by design, as the intent of this plugin is to be as
simple as possible. Patches that apply language specific handling won't be
accepted.

# License

All source code in this repository is licensed under the Mozilla Public License
version 2.0, unless stated otherwise. A copy of this license can be found in the
file "LICENSE".
