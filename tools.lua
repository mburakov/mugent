--
-- Copyright (C) 2026 Mikhail Burakov. This file is part of mugent.
--
-- mugent is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- mugent is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with mugent.  If not, see <https://www.gnu.org/licenses/>.
--

local curl = require("curl")
local json = require("json")

local tools = {}

local registry = {
  tools = {},
  handlers = {},
}

function tools.property(type, description, required, enum)
  return {
    type = type,
    description = description,
    required = required,
    enum = enum,
  }
end

local function transform(properties)
  local result = {}
  local required = {}
  for k, v in pairs(properties) do
    result[k] = {
      type = v.type,
      description = v.description,
      enum = v.enum,
    }
    if v.required then
      table.insert(required, k)
    end
  end
  if #required == 0 then
    required = nil
  end
  return result, required
end

function tools:register(name, description, properties, handler)
  local required
  properties, required = transform(properties)
  registry.handlers[name] = handler
  table.insert(registry.tools, {
    type = "function",
    ["function"] = {
      name = name,
      parameters = {
        type = "object",
        properties = properties,
        required = required,
      },
      description = description,
    }
  })
end

function tools:get()
  return registry.tools
end

function tools:call(name, args)
  return registry.handlers[name](args)
end

tools:register(
  "read",
  "Read and return the contents of a file on the local disk. " ..
  "Optional offset and count can be provided to read a section of the file.",
  {
    path = tools.property(
      "string", "Path to the file to read.", true),
    offset = tools.property(
      "integer", "First line to read counting from 1. First by default."),
    count = tools.property(
      "integer", "Number of lines to read. Till end of file by default."),
  },
  function(args)
    local offset = math.floor(args.offset or 1)
    local count = args.count and math.floor(args.count)
    if offset < 1 then return "error: offset must be >= 1" end
    if count and count < 1 then return "error: count must be >= 1" end

    local file, err = io.open(args.path, "r")
    if not file then return "error: " .. tostring(err) end

    local lines = {}
    local lineno = 0
    for line in file:lines() do
      lineno = lineno + 1
      if lineno >= offset then
        table.insert(lines, line)
        if count and #lines >= count then break end
      end
    end
    file:close()

    return table.concat(lines, "\n")
  end
)

tools:register(
  "write",
  "Write a file on the local disk, creating it if needed. Offset and count " ..
  "select a line range to replace; omit both to replace the whole file, or " ..
  "omit data to delete the range.",
  {
    path = tools.property(
      "string", "Path to the file to write.", true),
    data = tools.property(
      "string", "Lines to write. Omit to delete the selected lines."),
    offset = tools.property(
      "integer", "First line to replace, counting from 1. First by default."),
    count = tools.property(
      "integer", "Number of lines to replace. Till end of file by default."),
  },
  function(args)
    local offset = math.floor(args.offset or 1)
    local count = args.count and math.floor(args.count)
    if offset < 1 then return "error: offset must be >= 1" end
    if count and count < 1 then return "error: count must be >= 1" end

    local lines = {}
    local file = io.open(args.path, "r")
    if file then
      for line in file:lines() do
        table.insert(lines, line)
      end
      file:close()
    end

    local data = {}
    if args.data and args.data ~= "" then
      for line in (args.data .. "\n"):gmatch("(.-)\n") do
        table.insert(data, line)
      end
    end

    local last = count and (offset + count - 1) or #lines
    local result = {}
    for index = 1, math.min(offset - 1, #lines) do
      table.insert(result, lines[index])
    end
    for _, line in ipairs(data) do
      table.insert(result, line)
    end
    for index = last + 1, #lines do
      table.insert(result, lines[index])
    end

    local out, err = io.open(args.path, "w")
    if not out then return "error: " .. tostring(err) end
    if #result > 0 then
      out:write(table.concat(result, "\n"), "\n")
    end
    out:close()

    return ("ok: wrote %d lines to %s"):format(#result, args.path)
  end
)

tools:register(
  "exec",
  "Execute an arbitrary shell command and return the output.",
  {
    command = tools.property("string", "The shell command to execute.", true),
  },
  function(args)
    local pipe, err = io.popen(args.command .. " 2>&1")
    if not pipe then return "error: " .. tostring(err) end
    local output = pipe:read("*a")
    pipe:close()
    return output ~= "" and output or "(no output)"
  end
)

tools:register(
  "fetch",
  "Fetch the content of a URL from the internet.",
  {
    url = tools.property("string", "The URL to fetch.", true),
  },
  function(args)
    local request = curl.easy_init()
    local response = {}

    request:easy_setopt(curl.CURLOPT_URL, args.url)
    request:easy_setopt(curl.CURLOPT_FOLLOWLOCATION, 1)
    request:easy_setopt(curl.CURLOPT_WRITEFUNCTION, function(chunk)
      table.insert(response, chunk)
    end)

    local ok, err = pcall(request.easy_perform, request)
    request:easy_cleanup()

    if not ok then return "error: " .. tostring(err) end
    local body = table.concat(response)
    return body ~= "" and body or "(empty response)"
  end
)

tools:register(
  "pcall",
  "Execute arbitrary Lua code, wrapped in pcall, in the same Lua " ..
  "environment as the current model loop. Multiline source is allowed; " ..
  "use a `return` statement to surface values. The result follows pcall " ..
  "convention, serialized as a JSON array.",
  {
    code = tools.property("string", "Lua code to execute.", true)
  },
  function(args)
    local fun, err = loadstring(args.code)
    if not fun then return "error: " .. tostring(err) end

    local ok, encoded = pcall(json.stringify, { pcall(fun) })
    if not ok then
      return "error: cannot serialize result: " .. tostring(encoded)
    end
    return encoded
  end
)

return tools
