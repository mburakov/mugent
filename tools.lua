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
local util = require("util")

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
  local names = type(name) == "string" and { name } or name

  for _, n in ipairs(names) do
    registry.handlers[n] = handler
  end

  table.insert(registry.tools, {
    type = "function",
    ["function"] = {
      name = names[1],
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
  local ok, result = pcall(registry.handlers[name], args)
  if not ok then return "error: " .. tostring(result) end
  return result
end

tools:register(
  "read",
  "Read and return the contents of a text file on the local disk. Lines are " ..
  "prefixed with their 1-based number as `<number>: <line>`, matching the " ..
  "numbering the `write` tool expects.\nProvide just `path` to read the " ..
  "whole file, or add `offset` (1-based start line) and `count` (lines to " ..
  "read) to read a section.\nExample: read 20 lines from line 100 by " ..
  "setting `offset` to 100 and `count` to 20.",
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
    util.check(offset >= 1, "offset must be >= 1")
    util.check(not count or count >= 1, "count must be >= 1")
    local file = util.check(io.open(args.path, "r"))

    local lines = {}
    local lineno = 0
    for line in file:lines() do
      lineno = lineno + 1
      if lineno >= offset then
        table.insert(lines, string.format("%d: %s", lineno, line))
        if count and #lines >= count then break end
      end
    end
    file:close()

    return table.concat(lines, "\n")
  end
)

tools:register(
  "write",
  "Write text to a file on the local disk.\n1. Overwrite/Create: Provide " ..
  "`path` and `data` (no `offset` or `count`) to replace the entire " ..
  "file.\n2. Replace Range: Provide `path`, `offset` (1-based start line), " ..
  "`count` (number of lines to remove), and `data` (text to insert).\n3. " ..
  "Insert: Provide `path`, `offset`, and `data` with `count: 0` to insert " ..
  "text before the offset without deleting any lines.\n4. Delete: Provide " ..
  "`path`, `offset`, and `count` while omitting `data`.\n5. Append: Use a " ..
  "negative `offset` to target the end of the file.\nAlways `read` the file " ..
  "first to verify line numbers before performing range-based " ..
  "operations.\nExample: replace lines 5-7 by setting `offset` to 5, " ..
  "`count` to 3, and `data` to the new text.",
  {
    path = tools.property(
      "string", "Path to the file to write.", true),
    data = tools.property(
      "string", "Lines to write. Omit to delete the selected lines."),
    offset = tools.property(
      "integer", "First line to operate on, counting from 1. First line by " ..
      "default; negative refers to the end of the file, e.g. for appending."),
    count = tools.property(
      "integer", "Lines to replace starting at offset. Through end of file " ..
      "by default; 0 inserts before offset without replacing; negative " ..
      "replaces through end of file."),
  },
  function(args)
    local offset = math.floor(args.offset or 1)
    local count = math.floor(args.count or -1)
    util.check(offset ~= 0, "offset must be nonzero")

    local lines = {}
    local file = io.open(args.path, "r")
    if file then
      for line in file:lines() do
        table.insert(lines, line)
      end
      file:close()
    end

    local data = {}
    if offset < 0 then offset = #lines + 1 end
    if args.data and args.data ~= "" then
      for line in (args.data .. "\n"):gmatch("(.-)\n") do
        table.insert(data, line)
      end
    end

    local result = {}
    local last = count < 0 and #lines or (offset + count - 1)
    for index = 1, math.min(offset - 1, #lines) do
      table.insert(result, lines[index])
    end
    for _, line in ipairs(data) do
      table.insert(result, line)
    end
    for index = last + 1, #lines do
      table.insert(result, lines[index])
    end

    local out = util.check(io.open(args.path, "w"))
    if #result > 0 then
      out:write(table.concat(result, "\n"), "\n")
    end
    out:close()

    return ("ok: wrote %d lines to %s"):format(#result, args.path)
  end
)

tools:register(
  { "exec", "run", "shell" },
  "Execute a shell command via the system shell and return its standard " ..
  "output.\nStandard error is not captured; append `2>&1` to the command if " ..
  "you need it merged into the output. Runs non-interactively with no " ..
  "timeout, so never run commands that wait for input or block forever. " ..
  "Quote or escape shell metacharacters (backticks, dollar signs, " ..
  "asterisks, semicolons, pipes, and quotes) unless you intend the shell to " ..
  "interpret them. Returns `(no output)` if the command printed nothing to " ..
  "stdout.\nExample: set `command` to `ls -la` to list files.",
  {
    command = tools.property("string", "The shell command to execute.", true),
  },
  function(args)
    local pipe = util.check(io.popen(args.command))
    local output = pipe:read("*a")
    pipe:close()
    return output ~= "" and output or "(no output)"
  end
)

tools:register(
  "fetch",
  "Fetch the content of a URL from the internet. Follows redirects and " ..
  "returns the raw response body (e.g. HTML or JSON) as text.\nReturns " ..
  "`(empty response)` if the body is empty.\nExample: set `url` to " ..
  "`https://example.com/data.json`.",
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

    util.check(ok, err)
    local body = table.concat(response)
    return body ~= "" and body or "(empty response)"
  end
)

tools:register(
  "pcall",
  "Execute arbitrary Lua code, wrapped in `pcall`, in the same Lua " ..
  "environment as the current model loop.\nMultiline source is allowed; use " ..
  "a `return` statement to surface values. The result follows `pcall` " ..
  "convention (a success boolean followed by the return values or an " ..
  "error), serialized as a JSON array.\nExample: setting `code` to `return " ..
  "6 * 7` yields `[true,42]`.",
  {
    code = tools.property("string", "Lua code to execute.", true)
  },
  function(args)
    local fun = util.check(loadstring(args.code))
    local ok, encoded = pcall(json.stringify, { pcall(fun) })
    util.check(ok, "cannot serialize result: " .. tostring(encoded))
    return encoded
  end
)

return tools
