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

local json = {
  null = {} -- sentinel returned for JSON null (distinct from Lua nil)
}

---@alias value boolean|string|number|table the JSON value (null is json.null)

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
        or byte == 0x0a      -- line feed
        or byte == 0x0d      -- carriage return
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
---@return table array the parsed array (JSON null kept as json.null)
---@return integer index byte offset just past the closing bracket
local function parse_array(text, index)
  index = skip_whitespace(text, index + 1)
  local array = {}
  if string.byte(text, index) == 0x5d then -- closing bracket
    return array, index + 1
  end
  local count = 0
  while true do
    count = count + 1
    array[count], index = parse_value(text, index)
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
---@return table object the parsed object (JSON null kept as json.null)
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
    object[key] = value -- json.null retained; duplicate keys: last one wins
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
---@return value value the parsed value (json.null for JSON null)
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
      return json.null, index + 4
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

-- The set of characters that JSON requires (or permits) to be escaped inside a
-- string, mapped to their escape sequences. Built once at load time: the seven
-- short forms plus a \u00xx form for every other C0 control character.
local escapes = {
  ['"'] = '\\"',
  ['\\'] = '\\\\',
  ['\b'] = '\\b',
  ['\f'] = '\\f',
  ['\n'] = '\\n',
  ['\r'] = '\\r',
  ['\t'] = '\\t',
}
for byte = 0, 0x1f do
  local char = string.char(byte)
  if not escapes[char] then
    escapes[char] = string.format("\\u%04x", byte)
  end
end

-- Pattern matching every byte that must be escaped: NUL, the other C0 controls
-- (0x01-0x1f), the double quote, and the backslash. Bytes >= 0x80 pass through
-- untouched, so well-formed UTF-8 is emitted verbatim (valid per RFC 8259).
local escape_pattern = '[%z\1-\31"\\]'

-- Doubles can represent every integer up to 2^53 exactly; beyond that the "%d"
-- path would print digits the number does not actually hold.
local max_exact_integer = 2 ^ 53

local encode_value -- forward declaration for mutual recursion with tables

---Serialize a string as a quoted, escaped JSON string into the buffer.
---@param text string
---@param buffer string[] fragment accumulator
---@param count integer number of fragments currently in the buffer
---@return integer count updated fragment count
local function encode_string(text, buffer, count)
  count = count + 1
  -- The parenthesized gsub discards its second result (the substitution count)
  -- so only the rewritten string reaches the concatenation.
  buffer[count] = '"' .. (string.gsub(text, escape_pattern, escapes)) .. '"'
  return count
end

---Serialize a number, rejecting the non-finite values JSON cannot represent.
---@param number number
---@return string text the shortest faithful decimal rendering
local function encode_number(number)
  if number ~= number then
    error("json: cannot serialize NaN", 0)
  elseif number == math.huge or number == -math.huge then
    error("json: cannot serialize infinity", 0)
  elseif number == math.floor(number)
      and number >= -max_exact_integer and number <= max_exact_integer then
    return string.format("%d", number) -- exact integer: no decimal point
  end
  return string.format("%.14g", number)
end

---Serialize a Lua table as either a JSON array or object.
---A table is treated as an array when its keys are exactly the contiguous
---integers 1..#t; the empty table and any table with non-sequence keys become
---an object. Object keys must be strings.
---@param tbl table
---@param buffer string[] fragment accumulator
---@param count integer number of fragments currently in the buffer
---@param seen table<table, true> tables currently open on the recursion stack
---@return integer count updated fragment count
local function encode_table(tbl, buffer, count, seen)
  -- Cycle detection: `seen` holds the tables currently open on the recursion
  -- stack. Re-entering an open table closes a cycle, which has no JSON form.
  -- The mark is cleared on exit (below), so `seen` only ever holds ancestors;
  -- a table reached again by a sibling path (a DAG, not a cycle) serializes
  -- twice rather than erroring.
  if seen[tbl] then
    error("json: circular reference", 0)
  end
  seen[tbl] = true
  local length = #tbl
  local keys = 0
  for _ in pairs(tbl) do keys = keys + 1 end
  if length > 0 and length == keys then
    -- Dense array: keys are precisely 1..length.
    count = count + 1
    buffer[count] = "["
    for index = 1, length do
      if index > 1 then
        count = count + 1
        buffer[count] = ","
      end
      count = encode_value(tbl[index], buffer, count, seen)
    end
    count = count + 1
    buffer[count] = "]"
  elseif keys == 0 then
    count = count + 1
    buffer[count] = "{}" -- empty table renders as an empty object
  else
    -- Object: any table that is not a clean array (this also rejects mixed
    -- array/hash tables, whose integer keys trip the string-key check below).
    count = count + 1
    buffer[count] = "{"
    local first = true
    for key, value in pairs(tbl) do
      if type(key) ~= "string" then
        error("json: object keys must be strings, got " .. type(key), 0)
      end
      if first then
        first = false
      else
        count = count + 1
        buffer[count] = ","
      end
      count = encode_string(key, buffer, count)
      count = count + 1
      buffer[count] = ":"
      count = encode_value(value, buffer, count, seen)
    end
    count = count + 1
    buffer[count] = "}"
  end
  seen[tbl] = nil -- closed: no longer an ancestor of anything still to come
  return count
end

---Serialize any supported value, dispatching on its type.
---@param value value
---@param buffer string[] fragment accumulator
---@param count integer number of fragments currently in the buffer
---@param seen table<table, true> tables currently open on the recursion stack
---@return integer count updated fragment count
encode_value = function(value, buffer, count, seen)
  if value == json.null then
    count = count + 1
    buffer[count] = "null"
    return count
  end
  local kind = type(value)
  if kind == "string" then
    return encode_string(value, buffer, count)
  elseif kind == "number" then
    count = count + 1
    buffer[count] = encode_number(value)
    return count
  elseif kind == "boolean" then
    count = count + 1
    buffer[count] = value and "true" or "false"
    return count
  elseif kind == "table" then
    return encode_table(value, buffer, count, seen)
  end
  error("json: cannot serialize " .. kind, 0)
end

---Serialize a Lua value to a compact JSON document.
---Accepts strings, finite numbers, booleans, json.null, and tables (arrays or
---string-keyed objects). Fragments are accumulated in a buffer and joined once,
---so the cost is linear in the output size rather than quadratic.
---@param value value the value to encode (json.null for JSON null)
---@return string json the encoded document
---@nodiscard
function json.stringify(value)
  local buffer = {}
  encode_value(value, buffer, 0, {})
  return table.concat(buffer)
end

return json
