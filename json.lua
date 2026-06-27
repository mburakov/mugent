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

local bit = require("bit")

local json = {}

---@alias value nil|boolean|string|number|table

local parse_value

---Raise a parse error annotated with the input line and column; never returns.
---@param text string the document being parsed
---@param index integer byte offset at which the error was detected
---@param message string human-readable description of the problem
local function fail(text, index, message)
  local line, last_newline = 1, 0
  local limit = index - 1
  if limit > #text then limit = #text end
  for position = 1, limit do
    if string.byte(text, position) == 0x0a then
      line = line + 1
      last_newline = position
    end
  end
  error(string.format("json: %s at line %d, column %d (byte %d)",
    message, line, index - last_newline, index), 0)
end

---Skip RFC 8259 insignificant whitespace (space, tab, LF, CR).
---@param text string
---@param index integer byte offset to start scanning from
---@return integer index first non-whitespace offset (may be #text+1)
local function skip_whitespace(text, index)
  while true do
    local byte = string.byte(text, index)
    if byte == 0x09          -- horizontal tab
        or byte == 0x0a      -- carriage return
        or byte == 0x0d      -- line feed
        or byte == 0x20 then -- space
      index = index + 1
    else
      return index
    end
  end
end

---Decode a single hexadecimal digit.
---@param byte integer|nil a byte value, or nil at end of input
---@return integer|nil nibble digit value 0-15, or nil if not hex
local function hex_value(byte)
  if byte == nil then return nil end
  if byte >= 0x30 and byte <= 0x39 then return byte - 0x30 end      -- 0-9
  if byte >= 0x41 and byte <= 0x46 then return byte - 0x41 + 10 end -- A-F
  if byte >= 0x61 and byte <= 0x66 then return byte - 0x61 + 10 end -- a-f
  return nil
end

---Read exactly four hexadecimal digits.
---@param text string
---@param index integer byte offset of the first hex digit
---@return integer codepoint the value encoded by the four digits
---@return integer index byte offset just past the four digits
local function read_four_hex(text, index)
  local nibble1 = hex_value(string.byte(text, index))
  local nibble2 = hex_value(string.byte(text, index + 1))
  local nibble3 = hex_value(string.byte(text, index + 2))
  local nibble4 = hex_value(string.byte(text, index + 3))
  if not (nibble1 and nibble2 and nibble3 and nibble4) then
    fail(text, index, "invalid \\u escape (expected four hex digits)")
  end
  local codepoint =
      nibble1 * 0x1000 + nibble2 * 0x100 + nibble3 * 0x10 + nibble4
  return codepoint, index + 4
end

---Encode a single Unicode codepoint as UTF-8.
---@param codepoint integer
---@return string utf8 the UTF-8 byte sequence for the codepoint
local function encode_utf8(codepoint)
  if codepoint <= 0x7f then
    return string.char(codepoint)
  elseif codepoint <= 0x7ff then
    return string.char(bit.bor(0xc0, bit.rshift(codepoint, 6)),
      bit.bor(0x80, bit.band(codepoint, 0x3f)))
  elseif codepoint <= 0xffff then
    return string.char(bit.bor(0xe0, bit.rshift(codepoint, 12)),
      bit.bor(0x80, bit.band(bit.rshift(codepoint, 6), 0x3f)),
      bit.bor(0x80, bit.band(codepoint, 0x3f)))
  else
    return string.char(bit.bor(0xf0, bit.rshift(codepoint, 18)),
      bit.bor(0x80, bit.band(bit.rshift(codepoint, 12), 0x3f)),
      bit.bor(0x80, bit.band(bit.rshift(codepoint, 6), 0x3f)),
      bit.bor(0x80, bit.band(codepoint, 0x3f)))
  end
end

---Parse a JSON string starting at the opening double quote.
---@param text string
---@param index integer byte offset of the opening double quote
---@return string value the decoded string
---@return integer index byte offset just past the closing quote
local function parse_string(text, index)
  local start = index + 1 -- first content byte
  local cursor = start
  local parts             -- nil until the string contains an escape
  local count = 0
  while true do
    local byte = string.byte(text, cursor)
    if byte == nil then
      fail(text, index, "unterminated string")
    elseif byte == 0x22 then -- double quotes
      local segment = string.sub(text, start, cursor - 1)
      if parts then
        count = count + 1
        parts[count] = segment
        return table.concat(parts), cursor + 1
      end
      return segment, cursor + 1 -- common case: no escapes, single substring
    elseif byte == 0x5c then     -- backslash: decode an escape
      if not parts then parts = {} end
      count = count + 1
      parts[count] = string.sub(text, start, cursor - 1)
      local escape = string.byte(text, cursor + 1)
      if escape == 0x75 then -- lowercase u
        local codepoint, next_index = read_four_hex(text, cursor + 2)
        if codepoint >= 0xd800 and codepoint <= 0xdbff then
          -- High surrogate: a low surrogate \uXXXX must follow.
          if string.byte(text, next_index) ~= 0x5c              -- backslash
              or string.byte(text, next_index + 1) ~= 0x75 then -- lowercase u
            fail(text, cursor, "unpaired high surrogate")
          end
          local low_surrogate, low_surrogate_end =
              read_four_hex(text, next_index + 2)
          if low_surrogate < 0xdc00 or low_surrogate > 0xdfff then
            fail(text, next_index, "invalid low surrogate")
          end
          codepoint = 0x10000 + (codepoint - 0xd800) * 0x400
              + (low_surrogate - 0xdc00)
          next_index = low_surrogate_end
        elseif codepoint >= 0xdc00 and codepoint <= 0xdfff then
          fail(text, cursor, "unexpected low surrogate")
        end
        count = count + 1
        parts[count] = encode_utf8(codepoint)
        cursor = next_index
      else
        local decoded
        if escape == 0x22 then     -- double quotes
          decoded = '"'
        elseif escape == 0x5c then -- backslash
          decoded = '\\'
        elseif escape == 0x2f then -- slash or divide
          decoded = '/'
        elseif escape == 0x62 then -- lowercase b
          decoded = '\b'
        elseif escape == 0x66 then -- lowercase f
          decoded = '\f'
        elseif escape == 0x6e then -- lowercase n
          decoded = '\n'
        elseif escape == 0x72 then -- lowercase r
          decoded = '\r'
        elseif escape == 0x74 then -- lowercase t
          decoded = '\t'
        end
        if not decoded then
          fail(text, cursor, "invalid escape sequence")
        end
        count = count + 1
        parts[count] = decoded
        cursor = cursor + 2
      end
      start = cursor
    elseif byte < 0x20 then
      fail(text, cursor, "control character must be escaped")
    else
      cursor = cursor + 1
    end
  end
end

---Parse a JSON number.
---@param text string
---@param index integer byte offset of the first byte ('-' or a digit)
---@return number value the parsed number
---@return integer index byte offset just past the number
local function parse_number(text, index)
  local start = index
  local byte = string.byte(text, index)
  if byte == 0x2d then -- hyphen-minus
    index = index + 1
    byte = string.byte(text, index)
  end
  -- Integer part: a lone 0, or [1-9][0-9]*  (no leading zeros).
  if byte == 0x30 then -- zero
    index = index + 1
    byte = string.byte(text, index)
    if byte and byte >= 0x30 and byte <= 0x39 then -- 0-9
      fail(text, index, "numbers may not have leading zeros")
    end
  elseif byte and byte >= 0x31 and byte <= 0x39 then -- 1-9
    index = index + 1
    byte = string.byte(text, index)
    while byte and byte >= 0x30 and byte <= 0x39 do -- 0-9
      index = index + 1
      byte = string.byte(text, index)
    end
  else
    fail(text, index, "invalid number")
  end
  -- Optional fractional part: '.' followed by one or more digits.
  if byte == 0x2e then -- full stop
    index = index + 1
    byte = string.byte(text, index)
    if not (byte and byte >= 0x30 and byte <= 0x39) then -- 0-9
      fail(text, index, "digit expected after decimal point")
    end
    while byte and byte >= 0x30 and byte <= 0x39 do -- 0-9
      index = index + 1
      byte = string.byte(text, index)
    end
  end
  -- Optional exponent: (e|E) [+|-] one or more digits.
  if byte == 0x65 or byte == 0x45 then -- lowercase or uppercase e
    index = index + 1
    byte = string.byte(text, index)
    if byte == 0x2b or byte == 0x2d then -- plus sign or hyphen-minus
      index = index + 1
      byte = string.byte(text, index)
    end
    if not (byte and byte >= 0x30 and byte <= 0x39) then -- 0-9
      fail(text, index, "digit expected in exponent")
    end
    while byte and byte >= 0x30 and byte <= 0x39 do -- 0-9
      index = index + 1
      byte = string.byte(text, index)
    end
  end
  -- The substring is now a valid JSON number; let tonumber do the conversion
  -- (correct for exponents and large magnitudes, single call per number).
  return tonumber(string.sub(text, start, index - 1)), index
end

---Parse a JSON array starting at the opening bracket.
---@param text string
---@param index integer byte offset of the opening bracket
---@return table array the parsed array (null elements omitted)
---@return integer index byte offset just past the closing bracket
local function parse_array(text, index)
  index = skip_whitespace(text, index + 1)
  local array = {}
  if string.byte(text, index) == 0x5d then -- closing bracket
    return array, index + 1
  end
  local count = 0
  while true do
    local value
    value, index = parse_value(text, index)
    if value ~= nil then -- drop null elements; keep the array contiguous
      count = count + 1
      array[count] = value
    end
    index = skip_whitespace(text, index)
    local byte = string.byte(text, index)
    if byte == 0x5d then     -- closing bracket
      return array, index + 1
    elseif byte == 0x2c then -- comma
      index = skip_whitespace(text, index + 1)
    else
      fail(text, index, "expected ',' or ']' in array")
    end
  end
end

---Parse a JSON object starting at the opening brace.
---@param text string
---@param index integer byte offset of the opening brace
---@return table object the parsed object (null-valued keys omitted)
---@return integer index byte offset just past the closing brace
local function parse_object(text, index)
  index = skip_whitespace(text, index + 1)
  local object = {}
  if string.byte(text, index) == 0x7d then -- closing brace
    return object, index + 1
  end
  while true do
    if string.byte(text, index) ~= 0x22 then -- double quotes
      fail(text, index, "expected string key in object")
    end
    local key
    key, index = parse_string(text, index)
    index = skip_whitespace(text, index)
    if string.byte(text, index) ~= 0x3a then -- colon
      fail(text, index, "expected ':' after object key")
    end
    local value
    value, index = parse_value(text, skip_whitespace(text, index + 1))
    object[key] = value -- duplicate keys: last one wins (permitted by the RFC)
    index = skip_whitespace(text, index)
    local byte = string.byte(text, index)
    if byte == 0x7d then     -- closing brace
      return object, index + 1
    elseif byte == 0x2c then -- comma
      index = skip_whitespace(text, index + 1)
    else
      fail(text, index, "expected ',' or '}' in object")
    end
  end
end

---Parse any JSON value.
---@param text string
---@param index integer byte offset of the first byte of the value
---@return value value the parsed value (nil for JSON null)
---@return integer index byte offset just past the value
parse_value = function(text, index)
  local byte = string.byte(text, index)
  if byte == 0x7b then     -- opening brace
    return parse_object(text, index)
  elseif byte == 0x5b then -- opening bracket
    return parse_array(text, index)
  elseif byte == 0x22 then -- double quote
    return parse_string(text, index)
  elseif byte == 0x74 then -- lowercase t
    if string.sub(text, index, index + 3) == "true" then
      return true, index + 4
    end
    fail(text, index, "invalid literal")
  elseif byte == 0x66 then -- lowercase f
    if string.sub(text, index, index + 4) == "false" then
      return false, index + 5
    end
    fail(text, index, "invalid literal")
  elseif byte == 0x6e then -- lowercase n
    if string.sub(text, index, index + 3) == "null" then
      return nil, index + 4
    end
    fail(text, index, "invalid literal")
  elseif byte == 0x2d or (byte and byte >= 0x30 and byte <= 0x39) then
    return parse_number(text, index)
  else
    fail(text, index,
      byte and "unexpected character" or "unexpected end of input")
  end
end

---Parse a JSON document, raising an error on any deviation from RFC 8259.
---@param text string
---@return value value the decoded document
---@nodiscard
function json.parse(text)
  if type(text) ~= "string" then
    error("json: parse expects a string, got " .. type(text), 2)
  end
  local index = skip_whitespace(text, 1)
  if string.byte(text, index) == nil then
    fail(text, index, "unexpected end of input")
  end
  local value, next_index = parse_value(text, index)
  next_index = skip_whitespace(text, next_index)
  if string.byte(text, next_index) ~= nil then
    fail(text, next_index, "trailing characters after JSON value")
  end
  return value
end

return json
