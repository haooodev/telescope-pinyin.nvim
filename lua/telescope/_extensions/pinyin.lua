local telescope = require("telescope")
local config = require("telescope_pinyin.config")
local pinyin = require("telescope_pinyin")

return telescope.register_extension({
  setup = function(extension_config, _)
    config.setup(extension_config)

    vim.api.nvim_set_hl(0, "TelescopePinyin", {
      link = "TelescopeResultsComment",
      default = true,
    })
  end,

  exports = {
    -- Default command:
    --   :Telescope pinyin
    pinyin = pinyin.find_files,

    -- Named pickers:
    --   :Telescope pinyin find_files
    --   :Telescope pinyin buffers
    find_files = pinyin.find_files,
    git_files = pinyin.git_files,
    buffers = pinyin.buffers,
    git_status = pinyin.git_status,
    oldfiles = pinyin.oldfiles,
    quickfix = pinyin.quickfix,
    diagnostics = pinyin.diagnostics,

    clear_cache = pinyin.clear_cache,
  },
})
