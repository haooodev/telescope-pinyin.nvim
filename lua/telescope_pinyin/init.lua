local M = {}

local builtin = require("telescope.builtin")
local make_entry = require("telescope.make_entry")
local config = require("telescope_pinyin.config")

-- Cache layout:
--
-- cache[command .. args][input] = converted_pinyin
local cache = {}

local function notify(message, level)
  vim.notify(
    "telescope-pinyin: " .. message,
    level or vim.log.levels.ERROR
  )
end

local function normalize_pinyin(text)
  return vim.trim(text or ""):gsub("%s+", " ")
end

local function require_executable(command)
  if vim.fn.executable(command) == 1 then
    return true
  end

  notify(("executable not found: %s"):format(command))
  return false
end

---Parse go-pinyin's default output:
---
---  original<TAB>pinyin
---@param line string
---@return string original
---@return string pinyin
local function parse_line(line)
  local original, pinyin = line:match("^(.-)\t(.*)$")

  if not original then
    return line, ""
  end

  return original, normalize_pinyin(pinyin)
end

---@param opts table
---@return string[]?
local function get_args(opts)
  local value = opts.pinyin and opts.pinyin.args or nil

  if value == nil then
    return {}
  end

  local args

  if type(value) == "string" then
    args = vim.split(value, "%s+", {
      trimempty = true,
    })
  elseif type(value) == "table" then
    args = vim.deepcopy(value)
  else
    notify("pinyin.args must be a string or a list of strings")
    return nil
  end

  for _, arg in ipairs(args) do
    if type(arg) ~= "string" then
      notify("every item in pinyin.args must be a string")
      return nil
    end

    -- The original text is needed to recover the real filename from
    -- original<TAB>pinyin.
    if arg == "-only" or arg == "--only" then
      notify("pinyin.args cannot contain -only")
      return nil
    end
  end

  return args
end

---@param command string
---@param args string[]
---@return string[]
local function argv(command, args)
  local result = { command }
  vim.list_extend(result, args)
  return result
end

---@param command string
---@param args string[]
---@return string
local function shell_command(command, args)
  local escaped = {
    vim.fn.shellescape(command),
  }

  for _, arg in ipairs(args) do
    escaped[#escaped + 1] = vim.fn.shellescape(arg)
  end

  return table.concat(escaped, " ")
end

---@param command string
---@param args string[]
---@return string
local function cache_namespace(command, args)
  return command .. "\0" .. table.concat(args, "\0")
end

---@param text string
---@param command string
---@param args string[]
---@return string
local function to_pinyin(text, command, args)
  text = tostring(text or "")

  if text == "" then
    return ""
  end

  local namespace = cache_namespace(command, args)
  cache[namespace] = cache[namespace] or {}

  if cache[namespace][text] ~= nil then
    return cache[namespace][text]
  end

  local result = vim.system(
    argv(command, args),
    {
      stdin = text .. "\n",
      text = true,
    }
  ):wait()

  if result.code ~= 0 then
    cache[namespace][text] = ""
    return ""
  end

  local first_line = vim.split(
    result.stdout or "",
    "\n",
    { plain = true }
  )[1] or ""

  local _, pinyin = parse_line(first_line)

  cache[namespace][text] = pinyin
  return pinyin
end

---@param texts string[]
---@param command string
---@param args string[]
---@return table<string, string>
local function batch_to_pinyin(texts, command, args)
  local result_map = {}
  local unique = {}
  local input = {}

  for _, text in ipairs(texts) do
    text = tostring(text or "")

    if text ~= "" and not unique[text] then
      unique[text] = true
      input[#input + 1] = text
    end
  end

  if #input == 0 then
    return result_map
  end

  local result = vim.system(
    argv(command, args),
    {
      stdin = table.concat(input, "\n") .. "\n",
      text = true,
    }
  ):wait()

  if result.code ~= 0 then
    notify(
      "go-pinyin failed: " .. vim.trim(result.stderr or ""),
      vim.log.levels.WARN
    )
    return result_map
  end

  for _, line in ipairs(vim.split(
    result.stdout or "",
    "\n",
    {
      plain = true,
      trimempty = true,
    }
  )) do
    local original, pinyin = parse_line(line)

    if original ~= "" and pinyin ~= "" then
      result_map[original] = pinyin
    end
  end

  return result_map
end

---@param entry table
---@param pinyin string
---@param opts table
---@return table
local function append_display(entry, pinyin, opts)
  pinyin = normalize_pinyin(pinyin)

  if pinyin == "" or opts.pinyin.display == false then
    return entry
  end

  local original_display = entry.display
  local separator = opts.pinyin.separator or "   "
  local highlight = opts.pinyin.highlight or "TelescopePinyin"

  entry.display = function(self, picker)
    local display
    local highlights

    if type(original_display) == "function" then
      display, highlights = original_display(self, picker)
    else
      display = original_display
    end

    display = display
      or tostring(self.value or self.path or self.filename or "")

    highlights = vim.list_extend({}, highlights or {})

    local start_byte = #display + #separator
    local rendered = display .. separator .. pinyin

    highlights[#highlights + 1] = {
      { start_byte, start_byte + #pinyin },
      highlight,
    }

    return rendered, highlights
  end

  return entry
end

---@param original_maker function
---@param get_text fun(entry: table, raw: any): string?
---@param opts table
---@param command string
---@param args string[]
---@return function
local function wrap_entry_maker(
  original_maker,
  get_text,
  opts,
  command,
  args
)
  return function(raw)
    local entry = original_maker(raw)

    if not entry then
      return nil
    end

    local text = get_text(entry, raw)

    if not text or text == "" then
      return entry
    end

    local pinyin = to_pinyin(text, command, args)

    if pinyin == "" then
      return entry
    end

    entry.ordinal = table.concat({
      tostring(entry.ordinal or text),
      pinyin,
    }, " ")

    return append_display(entry, pinyin, opts)
  end
end

---@param opts table
---@return function
local function piped_file_entry_maker(opts)
  local original_maker = make_entry.gen_from_file(opts)

  return function(line)
    local filename, pinyin = parse_line(line)
    local entry = original_maker(filename)

    if not entry then
      return nil
    end

    if pinyin ~= "" then
      entry.ordinal = table.concat({
        tostring(entry.ordinal or filename),
        pinyin,
      }, " ")

      append_display(entry, pinyin, opts)
    end

    return entry
  end
end

---@param name string
---@param opts? table
---@return table?
---@return string[]?
---@return string?
local function prepare(name, opts)
  opts = config.resolve(name, opts)
  opts.pinyin = opts.pinyin or {}

  local command = opts.command or "go-pinyin"

  if not require_executable(command) then
    return nil
  end

  local args = get_args(opts)

  if not args then
    return nil
  end

  return opts, args, command
end

function M.find_files(opts)
  local args
  local command

  opts, args, command = prepare("find_files", opts)

  if not opts or vim.fn.executable("fd") ~= 1 then
    if opts then
      notify("executable not found: fd")
    end
    return
  end

  local converter = shell_command(command, args)

  opts.find_command = opts.find_command or {
    "sh",
    "-c",
    "fd --type f --color never --strip-cwd-prefix"
      .. " --hidden --exclude .git | "
      .. converter,
  }

  opts.entry_maker = piped_file_entry_maker(opts)

  builtin.find_files(opts)
end

function M.git_files(opts)
  local args
  local command

  opts, args, command = prepare("git_files", opts)

  if not opts or vim.fn.executable("git") ~= 1 then
    if opts then
      notify("executable not found: git")
    end
    return
  end

  local converter = shell_command(command, args)

  opts.git_command = opts.git_command or {
    "sh",
    "-c",
    "git -c core.quotepath=false ls-files"
      .. " --cached --others --exclude-standard | "
      .. converter,
  }

  opts.entry_maker = piped_file_entry_maker(opts)

  builtin.git_files(opts)
end

function M.buffers(opts)
  local args
  local command

  opts, args, command = prepare("buffers", opts)

  if not opts then
    return
  end

  local Path = require("plenary.path")
  local cwd = opts.cwd or vim.uv.cwd()

  local filenames = {}
  local absolute_by_filename = {}
  local max_bufnr = 0

  -- Use the same normalized path style that Telescope's buffer entry maker
  -- exposes as entry.filename. The visible Pinyin suffix therefore stays
  -- relative instead of showing the full absolute path.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.buflisted(bufnr) == 1 then
      max_bufnr = math.max(max_bufnr, bufnr)

      local absolute = vim.api.nvim_buf_get_name(bufnr)

      if absolute ~= "" then
        local filename = Path:new(absolute):normalize(cwd)

        filenames[#filenames + 1] = filename
        absolute_by_filename[filename] = absolute
      end
    end
  end

  -- Telescope's native buffer display performs arithmetic with this option.
  -- A custom entry maker must provide it before gen_from_buffer() is created.
  opts.bufnr_width = opts.bufnr_width
    or math.max(1, #tostring(max_bufnr))

  local converted = batch_to_pinyin(
    filenames,
    command,
    args
  )

  local pinyin_map = {}

  for filename, pinyin in pairs(converted) do
    pinyin_map[filename] = pinyin

    local absolute = absolute_by_filename[filename]
    if absolute then
      pinyin_map[absolute] = pinyin
    end
  end

  local original_maker = make_entry.gen_from_buffer(opts)

  opts.entry_maker = function(raw)
    local entry = original_maker(raw)

    if not entry then
      return nil
    end

    local filename = entry.filename or entry.value or ""
    local absolute = entry.path or ""

    local pinyin = pinyin_map[absolute]
      or pinyin_map[filename]
      or ""

    if pinyin == "" then
      return entry
    end

    local original_ordinal = entry.ordinal

    entry.ordinal = table.concat({
      tostring(original_ordinal or filename),
      pinyin,
    }, " ")

    return append_display(entry, pinyin, opts)
  end

  builtin.buffers(opts)
end

function M.git_status(opts)
  local args
  local command

  opts, args, command = prepare("git_status", opts)

  if not opts then
    return
  end

  opts.entry_maker = wrap_entry_maker(
    make_entry.gen_from_git_status(opts),
    function(entry)
      return entry.filename or entry.path or entry.value
    end,
    opts,
    command,
    args
  )

  builtin.git_status(opts)
end

function M.oldfiles(opts)
  local args
  local command

  opts, args, command = prepare("oldfiles", opts)

  if not opts then
    return
  end

  opts.entry_maker = wrap_entry_maker(
    make_entry.gen_from_file(opts),
    function(entry)
      return entry.filename or entry.path or entry.value
    end,
    opts,
    command,
    args
  )

  builtin.oldfiles(opts)
end

function M.quickfix(opts)
  local args
  local command

  opts, args, command = prepare("quickfix", opts)

  if not opts then
    return
  end

  opts.entry_maker = wrap_entry_maker(
    make_entry.gen_from_quickfix(opts),
    function(entry)
      return entry.filename
    end,
    opts,
    command,
    args
  )

  builtin.quickfix(opts)
end

function M.diagnostics(opts)
  local args
  local command

  opts, args, command = prepare("diagnostics", opts)

  if not opts then
    return
  end

  opts.entry_maker = wrap_entry_maker(
    make_entry.gen_from_diagnostics(opts),
    function(entry)
      return entry.filename
    end,
    opts,
    command,
    args
  )

  builtin.diagnostics(opts)
end

function M.clear_cache()
  cache = {}
end

return M
