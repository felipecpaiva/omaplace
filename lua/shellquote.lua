-- Turn an argv list into one safely quoted shell command string.
local M = {}

-- Every element is wrapped in single quotes and each inner ' is written as '\''.
-- Returns nil and a reason for a non-string element or a NUL byte (a shell cannot carry one).
function M.join(argv)
  if type(argv) ~= "table" then return nil, "argv must be a list" end
  local n = 0
  for _ in pairs(argv) do n = n + 1 end
  if n ~= #argv then return nil, "argv has holes or extra keys" end
  if n == 0 then return nil, "empty" end
  local out = {}
  for i = 1, #argv do
    local s = argv[i]
    if type(s) ~= "string" then return nil, "argument " .. i .. " is not a string" end
    if s:find("\0", 1, true) then return nil, "argument " .. i .. " has a NUL byte" end
    out[i] = "'" .. s:gsub("'", "'\\''") .. "'"
  end
  return table.concat(out, " ")
end

return M
