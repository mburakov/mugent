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

local name = "edit"

local aliases = {
  "Edit", "MultiEdit", "str_replace_based_edit_tool", "apply_patch", "replace",
  "replace_string_in_file", "insert_edit_into_file", "edit_file",
}

local description =
    "Edit a single file using exact text replacement. Every change must " ..
    "match a unique, non-overlapping region of the original file. If two " ..
    "changes affect the same block or nearby lines, merge them into one " ..
    "edit instead of emitting overlapping edits. Do not include large " ..
    "unchanged regions just to connect distant changes."

local parameters = {
  type = "object",
  properties = {
    path = {
      type = "string",
      description = "Path to the file to edit."
    },
    edits = {
      type = "array",
      description = "List of edit operations.",
      items = {
        type = "object",
        properties = {
          old = {
            type = "string",
            description = "Exact text to find; must be unique in the file.",
          },
          new = {
            type = "string",
            description = "Replacement text.",
          },
        },
        required = { "old", "new" },
      },
    },
  },
  required = { "path", "edits" },
}

local function handler(args)
  local path = type(args.path) == "string" and args.path or nil
  assert(path and path ~= "", "`path` is required")
  local edits = type(args.edits) == "table" and args.edits or nil
  assert(edits and #edits > 0, "`edits` is required")
  local file = assert(io.open(path, "r"))
  local body = file:read("*a")
  file:close()

  local matched = {}
  for i, e in ipairs(edits) do
    local old = type(e.old) == "string" and e.old or nil
    assert(old and old ~= "",
      ("`edits[%d].old` must be a non-empty string"):format(i))
    local new = type(e.new) == "string" and e.new or nil
    assert(new, ("`edits[%d].new` must be a string"):format(i))

    local first, count, scan = nil, 0, 1
    while true do
      local s = string.find(body, old, scan, true)
      if not s then break end
      first = first or s
      count = count + 1
      scan = s + #old
    end

    assert(first, ("`edits[%d].old` not found in `%s`"):format(i, path))
    assert(count == 1, string.format(
      "`edits[%d].old` is not unique in `%s` (%d matches); add " ..
      "surrounding context", i, path, count))
    table.insert(matched, {
      start = first,
      len = #old,
      new = new,
      index = i
    })
  end

  table.sort(matched, function(a, b)
    return a.start < b.start
  end)
  for i = 2, #matched do
    local prev, cur = matched[i - 1], matched[i]
    assert(prev.start + prev.len <= cur.start, string.format(
      "`edits[%d]` and `edits[%d]` overlap in `%s`; merge them into one edit",
      prev.index, cur.index, path))
  end

  local result, pos = {}, 1
  for _, m in ipairs(matched) do
    table.insert(result, string.sub(body, pos, m.start - 1))
    table.insert(result, m.new)
    pos = m.start + m.len
  end

  table.insert(result, string.sub(body, pos))
  local updated = table.concat(result)
  assert(updated ~= body, ("edits produced no change to `%s`"):format(path))

  local out = assert(io.open(path, "w"))
  out:write(updated)
  out:close()

  return ("ok: applied %d edit(s) to %s"):format(#matched, path)
end

return {
  name = name,
  description = description,
  parameters = parameters,
  handler = handler,
  aliases = aliases,
}
