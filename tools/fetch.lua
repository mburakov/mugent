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

local name = "fetch"

local description =
  "Fetch the content of a URL from the internet. Follows redirects and " ..
  "returns the raw response body (e.g. HTML or JSON) as text. Returns " ..
  "`(empty response)` if the body is empty."

local parameters = {
  type = "object",
  properties = {
    url = {
      type = "string",
      description = "URL of the content to fetch."
    },
  },
  required = { "url" }
}

local function handler(args)
  local request = curl.easy_init()
  local response = {}

  request:easy_setopt(curl.CURLOPT_URL, args.url)
  request:easy_setopt(curl.CURLOPT_FOLLOWLOCATION, 1)
  request:easy_setopt(curl.CURLOPT_WRITEFUNCTION, function(chunk)
    table.insert(response, chunk)
  end)

  local ok, err = pcall(request.easy_perform, request)
  request:easy_cleanup()

  assert(ok, err)
  local body = table.concat(response)
  return body ~= "" and body or "(empty response)"
end

return {
  name = name,
  description = description,
  parameters = parameters,
  handler = handler,
}
