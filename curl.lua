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
local libcurl = ffi.load("curl")

ffi.cdef [[
const char* curl_easy_strerror(int);
void* curl_slist_append(void*, const char*);
void curl_slist_free_all(void*);
int  curl_global_init(long);
void curl_global_cleanup(void);
void* curl_easy_init(void);
void curl_easy_cleanup(void*);
int curl_easy_setopt(void*, int, ...);
int curl_easy_perform(void*);
]]

local function curl_global_init()
  local CURL_GLOBAL_SSL = 1
  local rc = libcurl.curl_global_init(CURL_GLOBAL_SSL)
  if rc ~= 0 then
    local err = ffi.string(libcurl.curl_easy_strerror(rc))
    error("Failed to global init curl: " .. err)
  end
  return ffi.gc(ffi.new("int[1]"), function()
    libcurl.curl_global_cleanup()
  end)
end

local const = {
  value = {},
  cast = {},
}

local CurlGlobal = {
  _finalizer = curl_global_init(),
  CURLOPT_URL = { -- 1147
    [const.value] = 10002,
    [const.cast] = function(arg)
      return ffi.cast("char*", arg)
    end,
  },
  CURLOPT_WRITEFUNCTION = { -- 1175
    [const.value] = 20011,
    [const.cast] = function(arg)
      local cb = function(ptr, size, nmemb)
        local len = tonumber(size) * tonumber(nmemb)
        local ok = pcall(arg, ffi.string(ptr, len))
        return ok and len or 0
      end
      local type = "size_t(*)(char*, size_t, size_t, void*)"
      return ffi.cast(type, cb)
    end,
  },
  CURLOPT_POSTFIELDS = { -- 1196
    [const.value] = 10015,
    [const.cast] = function(arg)
      return ffi.cast("char*", arg)
    end,
  },
  CURLOPT_HTTPHEADER = { -- 1233
    [const.value] = 10023,
    [const.cast] = function(arg)
      return ffi.cast("void*", arg.slist)
    end,
  },
  CURLOPT_FOLLOWLOCATION = { -- 1322
    [const.value] = 52,
    [const.cast] = function(arg)
      return ffi.cast("long", arg)
    end,
  },
  CURLOPT_POSTFIELDSIZE = { -- 1351
    [const.value] = 60,
    [const.cast]  = function(arg)
      return ffi.cast("long", arg)
    end,
  },
}

local Slist = {}
Slist.__index = Slist

function CurlGlobal.slist()
  local result = { slist = nil }
  setmetatable(result, Slist)
  return result
end

function Slist:append(s)
  local slist = libcurl.curl_slist_append(self.slist, s)
  if slist == nil then
    error("Failed to append slist")
  end
  if self.slist ~= nil then
    ffi.gc(self.slist, nil)
  end
  self.slist = ffi.gc(slist, libcurl.curl_slist_free_all)
  return self
end

function Slist:free_all()
  if self.slist == nil then return end
  local slist = ffi.gc(self.slist, nil)
  libcurl.curl_slist_free_all(slist)
  self.slist = nil
end

local Curl = {}
Curl.__index = Curl

function CurlGlobal.easy_init()
  local curl = libcurl.curl_easy_init()
  if curl == nil then
    error("Failed to easy init curl")
  end
  local result = {
    curl = ffi.gc(curl, libcurl.curl_easy_cleanup)
  }
  setmetatable(result, Curl)
  return result
end

function Curl:easy_setopt(opt, val)
  local option = opt[const.value]
  local parameter = opt[const.cast](val)
  local rc = libcurl.curl_easy_setopt(self.curl, option, parameter)
  if rc ~= 0 then
    local err = ffi.string(libcurl.curl_easy_strerror(rc))
    error("Failed to easy setopt curl: " .. err)
  end
  self._refs = self._refs or {}
  self._refs[opt[const.value]] = { val, parameter }
end

function Curl:easy_perform()
  local rc = libcurl.curl_easy_perform(self.curl)
  if rc ~= 0 then
    local err = ffi.string(libcurl.curl_easy_strerror(rc))
    error("Failed to easy perform curl: " .. err)
  end
end

function Curl:easy_cleanup()
  if self.curl == nil then return end
  local curl = ffi.gc(self.curl, nil)
  libcurl.curl_easy_cleanup(curl)
  self._refs = nil
  self.curl = nil
end

return CurlGlobal
