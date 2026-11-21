-- JSON encoder (no decoder). Keys are sorted so the output is stable. An empty table is `[]`;
-- wrap one in `M.object` to get `{}`.
local M = {}

local OBJECT = { __json = "object" }

-- Mark a table as an object, so an empty one encodes as {}.
function M.object(t)
  return setmetatable(t or {}, OBJECT)
end

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return escapes[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function number(n)
  if n ~= n or n == math.huge or n == -math.huge then return "null" end
  if math.type(n) == "integer" then return string.format("%d", n) end
  return string.format("%.14g", n)
end

local function is_array(t)
  if getmetatable(t) == OBJECT then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return true end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local function enc(v, depth)
  local kind = type(v)
  if v == nil then return "null" end
  if kind == "string" then return quote(v) end
  if kind == "number" then return number(v) end
  if kind == "boolean" then return tostring(v) end
  if kind ~= "table" then error("cannot encode a " .. kind, 0) end
  if depth > 64 then error("nested too deep", 0) end
  local parts = {}
  if is_array(v) then
    for i = 1, #v do parts[i] = enc(v[i], depth + 1) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for i, k in ipairs(keys) do
    local val = v[k]
    if val == nil then val = v[tonumber(k)] end
    parts[i] = quote(k) .. ":" .. enc(val, depth + 1)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- Returns the JSON text, or nil and a reason (function values, nesting deeper than 64).
function M.encode(value)
  local ok, out = pcall(enc, value, 0)
  if not ok then return nil, out end
  return out
end

return M
