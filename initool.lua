#!/usr/bin/env lua

local function trim(s)
  return (s:gsub("^[ \t\r\n]+", ""):gsub("[ \t\r\n]+$", ""))
end

local function to_lower(s)
  return string.lower(s)
end

local function starts_with(s, c)
  return s ~= "" and s:sub(1, 1) == c
end

local function is_section_header(s)
  return #s >= 3 and s:sub(1, 1) == "[" and s:sub(-1) == "]"
end

local function unquote(s)
  if #s >= 2 and s:sub(1, 1) == '"' and s:sub(-1) == '"' then
    return s:sub(2, -2)
  end
  return s
end

local function quote_if_needed(s)
  if s:find("[ =]") then
    return '"' .. s .. '"'
  end
  return s
end

local IniFile = {}
IniFile.__index = IniFile

function IniFile.new(path)
  local self = setmetatable({}, IniFile)
  self.path = path
  self.lines = {}
  self.section_lines = {}
  self.key_lines = {}
  self.data = {}
  self:load()
  return self
end

function IniFile:get(section, key)
  local sec = to_lower(section)
  local k = to_lower(key)
  if self.data[sec] and self.data[sec][k] ~= nil then
    return self.data[sec][k]
  end
  error("Error: key not found")
end

function IniFile:set(section, key, value)
  local sec_lower = to_lower(section)
  local key_lower = to_lower(key)
  local val = value

  if self.section_lines[sec_lower] == nil then
    if #self.lines > 0 and trim(self.lines[#self.lines]) ~= "" then
      table.insert(self.lines, "")
    end
    table.insert(self.lines, "[" .. section .. "]")
    table.insert(self.lines, key .. " = " .. quote_if_needed(val))
    self:write()
    return
  end

  local section_line = self.section_lines[sec_lower]
  if self.key_lines[sec_lower] == nil then
    self.key_lines[sec_lower] = {}
  end
  local keys = self.key_lines[sec_lower]

  if keys[key_lower] ~= nil then
    local line_no = keys[key_lower]
    local line = self.lines[line_no]
    local pos = line:find("=", 1, true)
    local lhs
    if pos then
      lhs = trim(line:sub(1, pos - 1))
    else
      lhs = trim(line)
    end
    self.lines[line_no] = lhs .. " = " .. quote_if_needed(val)
    self:write()
    return
  end

  local insert_at = section_line + 1
  while insert_at <= #self.lines do
    local t = trim(self.lines[insert_at])
    if starts_with(t, "[") then
      if insert_at > section_line + 1 and trim(self.lines[insert_at - 1]) == "" then
        insert_at = insert_at - 1
      end
      break
    end
    insert_at = insert_at + 1
  end

  table.insert(self.lines, insert_at, key .. " = " .. quote_if_needed(val))
  self:write()
end

function IniFile:delete(section, key)
  local sec_lower = to_lower(section)
  local key_lower = to_lower(key)

  if self.key_lines[sec_lower] == nil then
    error("Error: section not found")
  end

  local keys = self.key_lines[sec_lower]
  local line_no = keys[key_lower]
  if line_no == nil then
    error("Error: key not found")
  end

  table.remove(self.lines, line_no)

  if self.data[sec_lower] then
    self.data[sec_lower][key_lower] = nil
  end
  keys[key_lower] = nil

  for _, sec_keys in pairs(self.key_lines) do
    for k, lineno in pairs(sec_keys) do
      if lineno > line_no then
        sec_keys[k] = lineno - 1
      end
    end
  end

  for sec, lineno in pairs(self.section_lines) do
    if lineno > line_no then
      self.section_lines[sec] = lineno - 1
    end
  end

  self:write()
end

function IniFile:load()
  local f = io.open(self.path, "r")
  if not f then
    error("Error: cannot open file " .. self.path)
  end

  self.lines = {}
  for line in f:lines() do
    table.insert(self.lines, line)
  end
  f:close()

  self.section_lines = {}
  self.key_lines = {}
  self.data = {}

  local current_section = ""
  for lineno, line in ipairs(self.lines) do
    local t = trim(line)
    if t ~= "" and not starts_with(t, ";") then
      if is_section_header(t) then
        current_section = to_lower(trim(t:sub(2, -2)))
        self.section_lines[current_section] = lineno
      elseif current_section ~= "" then
        local pos = t:find("=", 1, true)
        if pos then
          local k = to_lower(trim(t:sub(1, pos - 1)))
          local v = unquote(trim(t:sub(pos + 1)))
          if self.data[current_section] == nil then
            self.data[current_section] = {}
          end
          self.data[current_section][k] = v
          if self.key_lines[current_section] == nil then
            self.key_lines[current_section] = {}
          end
          self.key_lines[current_section][k] = lineno
        end
      end
    end
  end
end

function IniFile:write()
  local f = io.open(self.path, "w")
  if not f then
    error("Error: cannot write file " .. self.path)
  end

  for _, line in ipairs(self.lines) do
    f:write(line)
    f:write("\n")
  end
  f:close()
end

local function usage(argv0)
  io.stderr:write(
    "\nUsage:\n"
      .. "  " .. argv0 .. " -g, --get <file> <section> <key>\n"
      .. "  " .. argv0 .. " -s, --set <file> <section> <key> <value>\n"
      .. "  " .. argv0 .. " -d, --del <file> <section> <key>\n\n"
  )
end

local function main(argv)
  local ok, err = pcall(function()
    if #argv < 1 then
      usage(arg and arg[-1] or "initool.lua")
      os.exit(1)
    end

    local command = argv[1]
    local argv0 = arg and arg[-1] or "initool.lua"

    if command == "--get" or command == "-g" then
      if #argv ~= 4 then
        io.stderr:write("Usage: " .. argv0 .. " --get <file> <section> <key>\n")
        os.exit(1)
      end
      local ini = IniFile.new(argv[2])
      io.write(ini:get(argv[3], argv[4]))
      return
    end

    if command == "--set" or command == "-s" then
      if #argv ~= 5 then
        io.stderr:write("Usage: " .. argv0 .. " --set <file> <section> <key> <value>\n")
        os.exit(1)
      end
      local ini = IniFile.new(argv[2])
      ini:set(argv[3], argv[4], argv[5])
      io.write("Updated [" .. argv[3] .. "] " .. argv[4] .. " = " .. argv[5] .. "\n")
      return
    end

    if command == "--del" or command == "-d" then
      if #argv ~= 4 then
        io.stderr:write("Usage: " .. argv0 .. " --del <file> <section> <key>\n")
        os.exit(1)
      end
      local ini = IniFile.new(argv[2])
      ini:delete(argv[3], argv[4])
      io.write("Deleted [" .. argv[3] .. "] " .. argv[4] .. "\n")
      return
    end

    io.stderr:write("Unknown command: " .. command .. "\n")
    os.exit(1)
  end)

  if not ok then
    io.stderr:write(tostring(err) .. "\n")
    return 1
  end
  return 0
end

-- Build argv like python: argv[1] is command, etc.
local argv = {}
for i = 1, #arg do
  argv[i] = arg[i]
end

os.exit(main(argv))

