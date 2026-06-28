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
local tools = require("tools")

local header = curl.slist()
header:append("Authorization: Bearer " ..
  os.getenv("OLLAMA_API_KEY"))
header:append("Content-Type: application/json")

local callback_context = {
  pending = "",
  content = {},
  tool_calls = {},
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
    if message.content and message.content ~= "" then
      table.insert(callback_context.content, message.content)
      io.write(message.content)
      io.flush()
    end
    if message.tool_calls then
      for _, call in ipairs(message.tool_calls) do
        table.insert(callback_context.tool_calls, call)
      end
    end
  end
end)

local messages = {}
local function chat()
  request:easy_setopt(curl.CURLOPT_POSTFIELDS, json.stringify {
    model = "gemma4:cloud",
    messages = messages,
    tools = tools:get(),
  })

  request:easy_perform()
  local content = table.concat(callback_context.content)
  local tool_calls = callback_context.tool_calls
  callback_context.content = {}
  callback_context.tool_calls = {}
  return content, tool_calls
end

local function run_turn()
  while true do
    local content, tool_calls = chat()
    table.insert(messages, {
      role = "assistant",
      content = content,
      tool_calls = #tool_calls > 0 and tool_calls or nil,
    })
    if #tool_calls == 0 then break end
    for _, call in ipairs(tool_calls) do
      local funcall = call["function"]
      local result = tools:call(funcall.name, funcall.arguments)
      table.insert(messages, {
        role = "tool",
        tool_name = funcall.name,
        content = result,
      })
    end
  end
  io.write("\n")
end

while true do
  local line = readline.readline("> ")
  if line == nil then break end

  local mark = #messages
  table.insert(messages, { role = "user", content = line })
  local ok, err = pcall(run_turn)
  if not ok then
    io.write("error: " .. tostring(err) .. "\n")
    while #messages > mark do
      table.remove(messages)
    end
  end
end
