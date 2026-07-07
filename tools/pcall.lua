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

local json = require("json")

local name = "pcall"

local description =
    "Execute arbitrary Lua code, wrapped in `pcall`, in the same Lua " ..
    "environment as the current model loop. Multiline source is allowed; " ..
    "use a `return` statement to surface values. The result follows `pcall` " ..
    "convention (a success boolean followed by the return values or an " ..
    "error), serialized as a JSON array."

local parameters = {
  type = "object",
  properties = {
    code = {
      type = "string",
      description = "Lua code to execute.",
    },
  },
  required = { "code" },
}

local function handler(args)
  local code = type(args.code) == "string" and args.code or nil
  assert(code and code ~= "", "`code` is required")

  local fun = assert(loadstring(args.code))
  return assert(json.stringify({ pcall(fun) }))
end

return {
  name = name,
  description = description,
  parameters = parameters,
  handler = handler,
}
