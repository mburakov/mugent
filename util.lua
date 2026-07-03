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

local ffi = require("ffi")

ffi.cdef [[
char* get_current_dir_name();
]]

local util = {}

function util.getcwd()
  local buf = ffi.gc(
    ffi.C.get_current_dir_name(), ffi.C.free)
  return ffi.string(buf)
end

function util.check(cond, msg)
  if not cond then
    error(msg, 0)
  end
  return cond
end

function util.find_agents_files()
  local dir = util.getcwd()
  local parts = {}
  while true do
    local f = io.open(dir .. "/AGENTS.md", "r")
    if f then
      table.insert(parts, f:read("*a"))
      f:close()
    end
    if dir == "" then break end
    dir = dir:match("^(.*)/") or ""
  end

  local ordered = {}
  for i = #parts, 1, -1 do
    table.insert(ordered, parts[i])
  end
  return ordered
end

return util
