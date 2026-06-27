#!/usr/bin/env luajit
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

local curl = require("curl")
local json = require("json")
local readline = require("readline")

local data = json.stringify {
  model = "gemma4:31b-cloud",
  prompt = readline.readline("> "),
}

local function write_cb(str)
  for line in string.gmatch(str, "[^\n\r]+") do
    local output = json.parse(line)
    io.write(assert(output).response)
  end
end

local header = curl.slist()
local pat = os.getenv("OLLAMA_API_KEY")
header:append("Authorization: Bearer " .. pat)

local request = curl.easy_init()
request:easy_setopt(curl.CURLOPT_URL, "https://ollama.com/api/generate")
request:easy_setopt(curl.CURLOPT_HTTPHEADER, header)
request:easy_setopt(curl.CURLOPT_POSTFIELDS, data)
request:easy_setopt(curl.CURLOPT_WRITEFUNCTION, write_cb)
request:easy_perform()
