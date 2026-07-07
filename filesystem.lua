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
void free(void*);
]]

local filesystem = {}

function filesystem.getcwd()
  local buf = ffi.gc(
    ffi.C.get_current_dir_name(), ffi.C.free)
  return ffi.string(buf)
end

return filesystem
