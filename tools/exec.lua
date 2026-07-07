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

local name = "exec"

local description =
    "Execute a shell command via the system shell and return its standard " ..
    "output. Standard error is not captured; append `2>&1` to the command " ..
    "if you need it merged into the output. Quote or escape shell " ..
    "metacharacters (backticks, dollar signs, asterisks, semicolons, pipes, " ..
    "and quotes) unless you intend the shell to interpret them. Returns " ..
    "`(no output)` if the command printed nothing to stdout."

local parameters = {
  type = "object",
  properties = {
    command = {
      type = "string",
      description = "The shell command to execute.",
    },
  },
  required = { "command" },
}

local function handler(args)
  local command = type(args.command) == "string" and args.command or nil
  assert(command and command ~= "", "`command` is required")

  local pipe = assert(io.popen(args.command))
  local output = pipe:read("*a")
  pipe:close()

  return output ~= "" and output or "(no output)"
end

return {
  name = name,
  description = description,
  parameters = parameters,
  handler = handler,
}
