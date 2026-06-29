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

local commands = {}

local registry = {}

function commands.register(name, args, handler)
  registry[name] = {
    args = args or {},
    handler = handler,
  }
end

local function is_whitespace(c)
  return c == 0x20 -- space
      or c == 0x09 -- horizontal tab
end

local function tokenize(str)
  local tokens = {}
  local i, len = 1, #str

  while i <= len do
    local c = string.byte(str, i)
    if is_whitespace(c) then
      i = i + 1
    else
      local buf = {}
      while i <= len do
        c = string.byte(str, i)
        if is_whitespace(c) then
          break
        elseif c == 0x5c then -- backslash
          if i + 1 > len then
            return nil, "trailing backslash in arguments"
          end
          table.insert(buf, string.sub(str, i + 1, i + 1))
          i = i + 2
        elseif c == 0x27 then -- single quote
          i = i + 1
          local close = string.find(str, "'", i, true)
          if not close then
            return nil, "unterminated single quote in arguments"
          end
          table.insert(buf, string.sub(str, i, close - 1))
          i = close + 1
        elseif c == 0x22 then -- double quote
          i = i + 1
          local start = i
          while true do
            if i > len then
              return nil, "unterminated double quote in arguments"
            end
            c = string.byte(str, i)
            if c == 0x22 then -- double quote
              if i > start then
                table.insert(buf, string.sub(str, start, i - 1))
              end
              i = i + 1
              break
            elseif c == 0x5c then -- backslash
              if i > start then
                table.insert(buf, string.sub(str, start, i - 1))
              end
              if i + 1 > len then
                return nil, "unterminated double quote in arguments"
              end
              table.insert(buf, string.sub(str, i + 1, i + 1))
              i = i + 2
              start = i
            else
              i = i + 1
            end
          end
        else
          local start = i
          i = i + 1
          while i <= len do
            c = string.byte(str, i)
            if is_whitespace(c)
                or c == 0x5c  -- backslash
                or c == 0x27  -- single quote
                or c == 0x22  -- double quote
            then
              break
            end
            i = i + 1
          end
          table.insert(buf, string.sub(str, start, i - 1))
        end
      end
      table.insert(tokens, table.concat(buf))
    end
  end

  return tokens
end

function commands.execute(line)
  local cmd_name, rest = line:match("^/(%S+)%s*(.*)$")
  if not cmd_name then
    return false, "Invalid command format. Use /command [args]"
  end

  local entry = registry[cmd_name]
  if not entry then
    return false, "Unknown command: /" .. cmd_name
  end

  local tokens, err = tokenize(rest)
  if not tokens then
    return false, err
  end

  if #tokens > #entry.args then
    return false, string.format(
      "Too many arguments for /%s (expected at most %d, got %d)",
      cmd_name, #entry.args, #tokens)
  end

  local args = {}
  for idx, arg in ipairs(entry.args) do
    args[arg] = tokens[idx]
  end

  return pcall(entry.handler, args)
end

return commands
