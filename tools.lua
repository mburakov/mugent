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

local tools = {}

local registry = {
  tools = {},
  handlers = {},
  aliases = {},
}

function tools:register(tool)
  registry.handlers[tool.name] = tool.handler
  table.insert(registry.tools, {
    type = "function",
    ["function"] = {
      name = tool.name,
      description = tool.description,
      parameters = tool.parameters,
    }
  })
  for _, alias in ipairs(tool.aliases or {}) do
    registry.aliases[alias] = tool.name
  end
end

function tools:get()
  return registry.tools
end

function tools:call(name, args)
  if not registry.handlers[name] then
    local real_name = registry.aliases[name]
    if real_name then
      return string.format(
        "Unknown tool `%s`. Did you mean to call `%s`?",
        name, real_name)
    end

    local available = {}
    for _, t in ipairs(registry.tools) do
      table.insert(available,
        string.format("`%s`", t["function"].name))
    end
    return string.format(
      "Unknown tool `%s`. Available tools: %s.",
      name, table.concat(available, ", "))
  end

  local ok, result = pcall(registry.handlers[name], args)
  if not ok then return "error: " .. tostring(result) end
  return result
end

tools:register(require("tools.edit"))
tools:register(require("tools.exec"))
tools:register(require("tools.fetch"))
tools:register(require("tools.pcall"))
tools:register(require("tools.read"))
tools:register(require("tools.write"))

return tools
