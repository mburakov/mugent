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

local header = curl.slist()
header:append("Authorization: Bearer " ..
  os.getenv("OLLAMA_API_KEY"))
header:append("Content-Type: application/json")

local callback_context = {
  pending = "",
  content = {},
}

local request = curl.easy_init()
request:easy_setopt(curl.CURLOPT_URL, "https://ollama.com/api/chat")
request:easy_setopt(curl.CURLOPT_HTTPHEADER, header)
request:easy_setopt(curl.CURLOPT_WRITEFUNCTION, function(chunk)
  callback_context.pending = callback_context.pending .. chunk
  while true do
    local stop = string.find(callback_context.pending, "\n", 1, true)
    if not stop then break end
    local line = string.sub(callback_context.pending, 1, stop - 1)
    callback_context.pending = string.sub(callback_context.pending, stop + 1)
    local message = json.parse(line).message
    local content = message and message.content
    if content == nil then error(chunk) end
    table.insert(callback_context.content, content)
    io.write(content)
    io.flush()
  end
end)

local messages = {}

while true do
  local line = readline.readline("> ")
  if line == nil then
    io.write("\n")
    break
  end

  table.insert(messages, { role = "user", content = line })
  request:easy_setopt(curl.CURLOPT_POSTFIELDS, json.stringify {
    model = "gemma4:cloud",
    messages = messages,
  })

  local ok, err = pcall(request.easy_perform, request)
  if ok then
    local content = table.concat(callback_context.content)
    table.insert(messages, { role = "assistant", content = content })
    callback_context.content = {}
    io.write("\n")
  else
    io.write("error: " .. tostring(err) .. "\n")
    table.remove(messages)
  end
end
