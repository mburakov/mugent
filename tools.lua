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
  local ok, result = pcall(registry.handlers[name], args)
  if not ok then return "error: " .. tostring(result) end
  return result
end

tools:register(
  "read",
  "Read the contents of a text file verbatim. Returns the whole file by " ..
  "default. Optionally pass `offset` and `limit` to read only a section.",
  {
    path = tools.property(
      "string", "Path to the file to read.", true),
    offset = tools.property(
      "integer", "First line to read, counting from 1. First line by default."),
    limit = tools.property(
      "integer", "Maximum number of lines to read. To end of file by default."),
  },
  function(args)
    util.check(
      type(args.path) == "string" and args.path ~= "", "path is required")
    local offset = args.offset and math.floor(args.offset) or 1
    local limit = args.limit and math.floor(args.limit) or nil
    util.check(offset >= 1, "offset must be >= 1")
    util.check(not limit or limit >= 1, "limit must be >= 1")
    local file = util.check(io.open(args.path, "r"))

    local lines = {}
    local lineno = 0
    for line in file:lines() do
      lineno = lineno + 1
      if lineno >= offset then
        table.insert(lines, line)
        if limit and #lines >= limit then break end
      end
    end

    file:close()
    return table.concat(lines, "\n")
  end
)

tools:register(
  "write",
  "Write content to a file. Creates the file if it doesn't exist, " ..
  "overwrites if it does. Automatically creates parent directories.",
  {
    path = tools.property(
      "string", "Path to the file to write.", true),
    content = tools.property(
      "string", "Full content to write to the file.", true),
  },
  function(args)
    util.check(
      type(args.path) == "string" and args.path ~= "", "path is required")
    util.check(type(args.content) == "string", "content must be a string")

    local dir = args.path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
      os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
    end

    local out = util.check(io.open(args.path, "w"))
    out:write(args.content)
    out:close()

    return ("ok: wrote %d bytes to %s"):format(#args.content, args.path)
  end
)

tools:register(
  "edit",
  "Edit a single file using exact text replacement. Every change must match " ..
  "a unique, non-overlapping region of the original file. If two changes " ..
  "affect the same block or nearby lines, merge them into one edit instead " ..
  "of emitting overlapping edits. Do not include large unchanged regions " ..
  "just to connect distant changes.",
  {
    path = tools.property(
      "string", "Path to the file to edit.", true),
    edits = tools.property(
      "array", "One or more targeted replacements. Each edit is matched " ..
      "against the original file, not incrementally. Do not include " ..
      "overlapping or nested edits. If two changes touch the same block " ..
      "or nearby lines, merge them into one edit instead.", true),
  },
  function(args)
    local path = args.path
    util.check(type(path) == "string" and path ~= "", "path is required")
    local edits = args.edits
    util.check(type(edits) == "table" and #edits > 0,
      "edits must be a non-empty array of [old_text, new_text]")
    local file = util.check(io.open(path, "r"))
    local body = file:read("*a")
    file:close()

    local matched = {}
    for i, e in ipairs(edits) do
      local old = e.oldText
      local new = e.newText
      util.check(type(old) == "string" and old ~= "",
        ("edits[%d]: oldText must be a non-empty string"):format(i))
      util.check(type(new) == "string",
        ("edits[%d]: newText must be a string"):format(i))

      local first, count, scan = nil, 0, 1
      while true do
        local s = string.find(body, old, scan, true)
        if not s then break end
        first = first or s
        count = count + 1
        scan = s + #old
      end
      util.check(first, ("edits[%d]: old_text not found in %s"):format(i, path))
      util.check(count == 1, string.format(
        "edits[%d]: old_text is not unique in %s (%d matches); add " ..
        "surrounding context", i, path, count))
      table.insert(matched, {
        start = first,
        len = #old,
        new = new,
        index = i
      })
    end

    table.sort(matched, function(a, b)
      return a.start < b.start
    end)
    for i = 2, #matched do
      local prev, cur = matched[i - 1], matched[i]
      util.check(prev.start + prev.len <= cur.start, string.format(
        "edits[%d] and edits[%d] overlap in %s; merge them into one edit",
        prev.index, cur.index, path))
    end

    local result, pos = {}, 1
    for _, m in ipairs(matched) do
      table.insert(result, string.sub(body, pos, m.start - 1))
      table.insert(result, m.new)
      pos = m.start + m.len
    end

    table.insert(result, string.sub(body, pos))
    local updated = table.concat(result)
    util.check(updated ~= body, "edits produced no change to " .. path)

    local out = util.check(io.open(path, "w"))
    out:write(updated)
    out:close()

    return ("ok: applied %d edit(s) to %s"):format(#matched, path)
  end
)

tools:register(
  "exec",
  "Execute a shell command via the system shell and return its standard " ..
  "output.\nStandard error is not captured; append `2>&1` to the command if " ..
  "you need it merged into the output. Runs non-interactively with no " ..
  "timeout, so never run commands that wait for input or block forever. " ..
  "Quote or escape shell metacharacters (backticks, dollar signs, " ..
  "asterisks, semicolons, pipes, and quotes) unless you intend the shell to " ..
  "interpret them. Returns `(no output)` if the command printed nothing to " ..
  "stdout.",
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
  "`(empty response)` if the body is empty.",
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
  "error), serialized as a JSON array.",
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
