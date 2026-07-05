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

local commands = require("commands")
local curl = require("curl")
local json = require("json")
local readline = require("readline")
local tools = require("tools")
local util = require("util")

local ollama_api_key = os.getenv("OLLAMA_API_KEY")
local ollama_api_url = assert(os.getenv("OLLAMA_API_URL"))
local ollama_model = assert(os.getenv("OLLAMA_MODEL"))
local ollama_num_ctx = os.getenv("OLLAMA_NUM_CTX")

local header = curl.slist()
header:append("Content-Type: application/json")
if ollama_api_key then
  header:append("Authorization: Bearer " .. ollama_api_key)
end

local callback_context = {
  pending = "",
  content = {},
  tool_calls = {},
}

local request = curl.easy_init()
request:easy_setopt(curl.CURLOPT_URL, ollama_api_url)
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
      if #callback_context.content == 0 then io.write('assistant> ') end
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

local function init_messages()
  local messages = {}
  local agents_files = util.find_agents_files()
  if #agents_files > 0 then
    table.insert(messages, {
      role = "system",
      content = table.concat(agents_files, "\n\n"),
    })
  end
  return messages
end

local messages = init_messages()
commands.register("clear", {}, function()
  messages = init_messages()
  return "Context cleared."
end)

commands.register("save", { "filename" }, function(args)
  local fname = args.filename
  util.check(fname and fname ~= "", "filename required")
  local f = util.check(io.open(fname, "w"))
  f:write(json.stringify(messages))
  f:close()
  return "Messages saved to " .. fname
end)

commands.register("load", { "filename" }, function(args)
  local fname = args.filename
  util.check(fname and fname ~= "", "filename required")
  local f = util.check(io.open(fname, "r"))
  local content = f:read("*all")
  f:close()
  local decoded = json.parse(content)
  messages = util.check(type(decoded) == "table",
    "invalid message format in file")
  return "Messages loaded from " .. fname
end)

local function chat()
  local options
  if ollama_num_ctx then
    options = {
      num_ctx = tonumber(ollama_num_ctx),
    }
  end

  request:easy_setopt(curl.CURLOPT_POSTFIELDS, json.stringify {
    model = ollama_model,
    messages = messages,
    tools = tools:get(),
    options = options,
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
    io.write("\n")
    for _, call in ipairs(tool_calls) do
      local funcall = call["function"]
      local sargs = json.stringify(funcall.arguments)
      io.write("tool> " .. funcall.name .. " " .. sargs .. "\n")
      local result = tools:call(funcall.name, funcall.arguments)
      io.write(tostring(result) .. "\n")
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
  local line = readline.readline("user> ")
  if line == nil then break end
  if line:sub(1, 1) == "/" then
    local ok, res = commands.execute(line)
    if not ok then
      io.write("error: " .. res .. "\n")
    else
      io.write(res .. "\n")
    end
  else
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
end
