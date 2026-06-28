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
local libreadline = ffi.load("readline")

ffi.cdef [[
char* readline(const char*);
void free(void*);
]]

local Readline = {}

function Readline.readline(prompt)
  local buffer = libreadline.readline(prompt)
  if buffer == nil then
    return nil
  end
  local line = ffi.string(buffer)
  ffi.C.free(buffer)
  return line
end

return Readline
