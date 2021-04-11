local Job = require("flutter-tools.job")
local ui = require("flutter-tools/ui")
local utils = require("flutter-tools/utils")
local executable = require("flutter-tools/executable")

local api = vim.api
local fn = vim.fn

local M = {
  ---@type Job
  emulator_job = nil
}

local EMULATOR = 1
local DEVICE = 2

---@param result string[]
---@param type integer
local function get_devices(result, type)
  local devices = {}
  for _, line in pairs(result) do
    local device = M.parse(line, type)
    if device then
      table.insert(devices, device)
    end
  end
  return devices
end

---Highlight each device/emulator in the popup window
---@param highlights table
---@param line string
---@param device table
local function add_device_highlights(highlights, line, device)
  return ui.get_line_highlights(
    line,
    {
      {
        word = device.name,
        highlight = "Type"
      },
      {
        word = device.platform,
        highlight = "Comment"
      }
    },
    highlights
  )
end

---@param line string
---@param device_type number
function M.parse(line, device_type)
  local parts = vim.split(line, "•")
  local is_emulator = device_type == EMULATOR
  local name_index = not is_emulator and 1 or 2
  local id_index = not is_emulator and 2 or 1
  if #parts == 4 then
    return {
      name = vim.trim(parts[name_index]),
      id = vim.trim(parts[id_index]),
      platform = vim.trim(parts[3]),
      system = vim.trim(parts[4]),
      type = device_type
    }
  end
end

--- Parse a list of lines looking for devices
--- return the parsed list and the found devices if any
---@param result string[]
---@param device_type integer
---@return string[]
---@return table
function M.extract_device_props(result, device_type)
  device_type = device_type or DEVICE
  local lines = {}
  local highlights = {}
  local devices_by_line = {}
  local devices = get_devices(result, device_type)
  if #devices > 0 then
    for _, device in pairs(devices) do
      local name = utils.display_name(device.name, device.platform)
      devices_by_line[name] = device
      add_device_highlights(highlights, name, device)
      table.insert(lines, name)
    end
  else
    for _, item in pairs(result) do
      table.insert(lines, item)
    end
  end
  return lines, devices_by_line, highlights
end

local function setup_window(devices, buf, _)
  if not vim.tbl_isempty(devices) then
    api.nvim_buf_set_var(buf, "devices", devices)
  end
  api.nvim_buf_set_keymap(
    buf,
    "n",
    "<CR>",
    ":lua __flutter_tools_select_device()<CR>",
    {silent = true, noremap = true}
  )
end

function _G.__flutter_tools_select_device()
  if not vim.b.devices then
    return utils.echomsg("Sorry there is no device on this line")
  end
  local lnum = fn.line(".")
  local line = api.nvim_buf_get_lines(0, lnum - 1, lnum, false)
  local device = vim.b.devices[fn.trim(line[1])]
  if device then
    if device.type == EMULATOR then
      M.launch_emulator(device)
    else
      require("flutter-tools.commands").run(device)
    end
    api.nvim_win_close(0, true)
  end
end
-----------------------------------------------------------------------------//
-- Emulators
-----------------------------------------------------------------------------//

---@param result string[]
local function handle_launch(err, result)
  if err then
    ui.notify(result)
  end
end

function M.close_emulator()
  if M.emulator_job then
    M.emulator_job:close()
  end
end

---@param emulator table
function M.launch_emulator(emulator)
  if not emulator then
    return
  end
  executable.with(
    "emulators --launch " .. emulator.id,
    function(cmd)
      M.emulator_job =
        Job:new {
        cmd = cmd,
        on_exit = handle_launch
      }:sync()
    end
  )
end

---@param err boolean
---@param result string[]
local function show_emulators(err, result)
  if err then
    return utils.echomsg(result)
  end
  local lines, emulators, highlights = M.extract_device_props(result, EMULATOR)
  if #lines > 0 then
    ui.popup_create(
      {
        title = "Flutter emulators",
        lines = lines,
        highlights = highlights,
        on_create = function(buf, _)
          setup_window(emulators, buf)
        end
      }
    )
  end
end

function M.list_emulators()
  executable.with(
    "emulators",
    function(cmd)
      Job:new {
        cmd = cmd,
        on_exit = show_emulators
      }:sync()
    end
  )
end

-----------------------------------------------------------------------------//
-- Devices
-----------------------------------------------------------------------------//
---@param err boolean
---@param result table list of devices
local function show_devices(err, result)
  if err then
    return utils.echomsg(result)
  end
  local lines, devices, highlights = M.extract_device_props(result, DEVICE)
  if #lines > 0 then
    ui.popup_create(
      {
        title = "Flutter devices",
        lines = lines,
        highlights = highlights,
        on_create = function(buf, _)
          setup_window(devices, buf)
        end
      }
    )
  end
end

function M.list_devices()
  executable.with(
    "devices",
    function(cmd)
      Job:new {
        cmd = cmd,
        on_exit = show_devices,
        on_stderr = function(result)
          if result then
            utils.echomsg(result)
          end
        end
      }:sync()
    end
  )
end

return M
