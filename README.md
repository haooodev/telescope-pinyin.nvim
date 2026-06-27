# telescope-pinyin.nvim

A Telescope extension that adds Chinese Pinyin to file-oriented picker search
keys and optionally renders the converted Pinyin as faint auxiliary text.

## Requirements

- Neovim with `vim.system()`
- `nvim-telescope/telescope.nvim`
- `nvim-lua/plenary.nvim`
- `go-pinyin`
- `fd` for `find_files`
- `git` for Git pickers

On Arch Linux:

```bash
sudo pacman -S --needed fd ripgrep make gcc go
go install github.com/twio142/go-pinyin@latest
```

Ensure Go's binary directory is in `PATH`:

```bash
export PATH="$PATH:$(go env GOPATH)/bin"
```

## Plugin structure

```text
telescope-pinyin.nvim/
└── lua/
    ├── telescope_pinyin/
    │   ├── config.lua
    │   └── init.lua
    └── telescope/
        └── _extensions/
            └── pinyin.lua
```

## lazy.nvim

Then add it as a dependency of Telescope:

```lua
{
  "nvim-telescope/telescope.nvim",

  dependencies = {
    "nvim-lua/plenary.nvim",

    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "make",
    },

    {"haooodev/telescope-pinyin.nvim" }

  },

  config = function()
    local telescope = require("telescope")

    telescope.setup({
      extensions = {
        fzf = {
          fuzzy = true,
          override_generic_sorter = true,
          override_file_sorter = true,
          case_mode = "smart_case",
        },

        pinyin = {
          command = "go-pinyin",

          pinyin = {
            args = {},
            display = true,
            separator = "   ",
            highlight = "TelescopePinyin",
          },

          pickers = {
            buffers = {
              sort_mru = true,
              ignore_current_buffer = true,
            },

            find_files = {
              hidden = true,
            },
          },
        },
      },
    })

    telescope.load_extension("fzf")
    telescope.load_extension("pinyin")
  end,
}
```

## Commands

```vim
:Telescope pinyin
:Telescope pinyin find_files
:Telescope pinyin git_files
:Telescope pinyin buffers
:Telescope pinyin git_status
:Telescope pinyin oldfiles
:Telescope pinyin quickfix
:Telescope pinyin diagnostics
```

The default `:Telescope pinyin` export opens `find_files`.

## Lua API

```lua
local pinyin = require("telescope").extensions.pinyin

pinyin.find_files()

pinyin.buffers({
  sort_mru = true,
  ignore_current_buffer = true,
})

pinyin.git_status({
  pinyin = {
    args = { "-initials" },
  },
})
```

## Per-picker go-pinyin arguments

Each call can override the extension defaults:

```lua
require("telescope").extensions.pinyin.find_files({
  pinyin = {
    args = { "-initials" },
  },
})
```

The argument may also be a string:

```lua
pinyin = {
  args = "-initials",
}
```

Examples:

```lua
pinyin = { args = {} }
pinyin = { args = { "-initials" } }
pinyin = { args = { "-xiaohe" } }
```

`-only` is intentionally rejected because the extension needs
`original<TAB>pinyin` to recover the real filename.

## Display options

```lua
pinyin = {
  display = true,
  separator = "   ",
  highlight = "TelescopePinyin",
}
```

Search with Pinyin but hide the auxiliary suffix:

```lua
pinyin = {
  display = false,
}
```

The extension creates `TelescopePinyin` as a default link to
`TelescopeResultsComment`. A colorscheme or user config can override it:

```lua
vim.api.nvim_set_hl(0, "TelescopePinyin", {
  link = "Comment",
})
```

## Notes

- `find_files` and `git_files` pipe the full candidate stream through one
  `go-pinyin` process.
- `buffers` converts all listed buffer filenames in one batch.
- Other structured pickers currently convert candidates lazily and cache the
  result.
- The extension only changes `entry.ordinal` and `entry.display`; the real
  file path, previewer and default actions stay with Telescope.
