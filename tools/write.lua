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

local filesystem = require("filesystem")

local name = "write"

local description =
    "Write content to a file. Creates the file if it doesn't exist, " ..
    "overwrites if it does. Automatically creates parent directories."

local parameters = {
  type = "object",
  properties = {
    path = {
      type = "string",
      description = "Path to the file to write.",
    },
    content = {
      type = "string",
      description = "Full content to write to the file.",
    },
  },
  required = { "path", "content" },
}

local function handler(args)
  local path = type(args.path) == "string" and args.path or nil
  assert(path and path ~= "", "`path` is required")
  local content = type(args.content) == "string" and args.content or nil
  assert(content, "`content` must be a string")

  filesystem.mkdir_p(filesystem.dirname(path))
  local file = assert(io.open(path, "w"))
  file:write(content)
  file:close()

  return ("ok: wrote %d bytes to %s"):format(#content, path)
end

return {
  name = name,
  description = description,
  parameters = parameters,
  handler = handler,
}
