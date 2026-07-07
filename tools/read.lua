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

local name = 'read'

local description =
    "Read the contents of a text file verbatim. Returns the whole file by " ..
    "default. Optionally pass `offset` and `limit` to read only a section."

local parameters = {
  type = "object",
  properties = {
    path = {
      type = "string",
      description = "Path to the file to read.",
    },
    offset = {
      type = "integer",
      description = "First line to read, counting from 1. " ..
          "Defaults to the beginning of the file.",
    },
    limit = {
      type = "integer",
      description = "Maximum number of lines to read. " ..
          "Defaults to the end of the file.",
    },
  },
  required = { "path" },
}

local function handler(args)
  local path = type(args.path) == "string" and args.path or nil
  assert(path and path ~= "", "`path` is required")
  local offset = args.offset and math.floor(args.offset) or 1
  assert(offset >= 1, "`offset` must be >= 1")
  local limit = args.limit and math.floor(args.limit) or nil
  assert(not limit or limit >= 1, "`limit` must be >= 1")
  local file = assert(io.open(path, "r"))

  local lines = {}
  local lineno = 0
  for line in file:lines() do
    lineno = lineno + 1
    if lineno >= offset then
      table.insert(lines, line)
      if limit and #lines >= limit then
        break
      end
    end
  end

  file:close()
  return table.concat(lines, "\n")
end

return {
  name = name,
  description = description,
  parameters = parameters,
  handler = handler,
}
