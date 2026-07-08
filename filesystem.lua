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
int mkdir(const char *pathname, unsigned int mode);
char* dirname(char *path);
char* realpath(const char *path, char *resolved_path);
void free(void*);
int* __errno_location(void);
]]

local filesystem = {}

function filesystem.getcwd()
  local buf = ffi.gc(
    ffi.C.get_current_dir_name(), ffi.C.free)
  return ffi.string(buf)
end

function filesystem.dirname(path)
  local buf = ffi.new("char[?]", #path + 1)
  ffi.copy(buf, path)
  return ffi.string(ffi.C.dirname(buf))
end

local function realpath(path)
  local resolved = ffi.C.realpath(path, nil)
  if resolved == nil then return nil end
  return ffi.string(ffi.gc(resolved, ffi.C.free))
end

function filesystem.mkdir_p(dir)
  if dir == "" or dir == "." or dir == "/" then return end
  if realpath(dir) then return end
  filesystem.mkdir_p(filesystem.dirname(dir))
  if ffi.C.mkdir(dir, 0x1FF) ~= 0 and        -- 0777
      ffi.C.__errno_location()[0] ~= 17 then -- EEXIST
    error(string.format("mkdir failed for %q: errno=%d",
      dir, ffi.C.__errno_location()[0]))
  end
end

return filesystem
