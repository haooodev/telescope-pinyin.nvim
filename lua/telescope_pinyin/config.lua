local M = {}

local defaults = {
  command = "go-pinyin",

  pinyin = {
    args = {},
    display = true,
    separator = "   ",
    highlight = "TelescopePinyin",
  },

  -- Per-picker defaults are merged after the extension defaults and before
  -- options passed directly to the exported picker.
  pickers = {},
}

local values = vim.deepcopy(defaults)

function M.setup(opts)
  values = vim.tbl_deep_extend(
    "force",
    vim.deepcopy(defaults),
    opts or {}
  )
end

function M.resolve(name, opts)
  local extension_opts = vim.deepcopy(values)
  local picker_opts = vim.deepcopy(
    extension_opts.pickers[name] or {}
  )

  extension_opts.pickers = nil

  return vim.tbl_deep_extend(
    "force",
    extension_opts,
    picker_opts,
    opts or {}
  )
end

return M
