-- App memory (F5, design 6.3): the remembered place of each app, keyed on class plus context (D18). Pure: no hl, no
-- files, no clock (the caller passes `now`). The glue writes encode()'s text to ~/.local/state/omaplace/memory.lua and
-- reads it back with decode(), which loads it as text in an empty environment.
--
-- A place: { class, context, fp (monitor fingerprint), slot (1..10), rect ({x, y, w, h} fractions, or nil),
-- floating, n (order of last update, for the cap), saved_at (unix s, display only) }.
local M = {}

M.CAP = 200
M.MAX_TEXT = 1048576

-- Which events each `app_memory` mode records. "auto" also reports scene moves (the glue does that, not this module).
local RECORDS = {
  scene = { placed = true },
  last_place = { placed = true, closed = true, moved = true },
  auto = { placed = true, closed = true, moved = true },
}

function M.new() return { schema = 1, seq = 0, apps = {}, bound = {} } end

-- No context is the empty context; a context entry never answers for an untagged window (D18 rule 5).
function M.key(class, context)
  local ctx = type(context) == "string" and context or ""
  return ctx == "" and tostring(class) or (tostring(class) .. "\n" .. ctx)
end

local function finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end

local function clean_rect(r)
  if type(r) ~= "table" then return nil end
  for i = 1, 4 do
    if not finite(r[i]) then return nil end
  end
  return { r[1], r[2], r[3], r[4] }
end

-- Monitor fingerprints are flat: keep string, boolean and finite number fields only.
local function clean_fp(fp)
  if type(fp) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(fp) do
    if type(k) == "string" and (type(v) == "string" or type(v) == "boolean" or finite(v)) then out[k] = v end
  end
  return out
end

-- A checked copy of a place, or nil when it cannot be used.
local function clean_place(p)
  if type(p) ~= "table" or type(p.class) ~= "string" or p.class == "" then return nil end
  local slot = math.tointeger(p.slot)
  local fp = clean_fp(p.fp)
  if not slot or slot < 1 or slot > 10 or not fp then return nil end
  local ctx = type(p.context) == "string" and p.context ~= "" and p.context or nil
  return { class = p.class, context = ctx, fp = fp, slot = slot, rect = clean_rect(p.rect), floating = p.floating == true }
end

local function drop_oldest(mem)
  local count, oldest, oldest_n = 0, nil, nil
  for k, e in pairs(mem.apps) do
    count = count + 1
    if not oldest_n or e.n < oldest_n or (e.n == oldest_n and k < oldest) then oldest, oldest_n = k, e.n end
  end
  if count <= M.CAP then return false end
  mem.apps[oldest] = nil
  return true
end

-- update(mem, event, mode, now): record event.kind "placed" (a run placed the app), "closed" (a window closed) or
-- "moved" (a window moved to another workspace) when `mode` records that kind. closed and moved count only for the
-- app's last window: `others` is how many other windows of the class are open. Returns true when mem changed.
function M.update(mem, event, mode, now)
  local kinds = RECORDS[mode]
  if type(mem) ~= "table" or type(event) ~= "table" or not kinds or not kinds[event.kind] then return false end
  if event.kind ~= "placed" and (math.tointeger(event.others) or 0) > 0 then return false end
  local place = clean_place(event)
  if not place then return false end
  mem.seq = (math.tointeger(mem.seq) or 0) + 1
  place.n = mem.seq
  place.saved_at = math.tointeger(now)
  mem.apps[M.key(place.class, place.context)] = place
  while drop_oldest(mem) do end
  return true
end

function M.lookup(mem, class, context)
  if type(mem) ~= "table" or type(mem.apps) ~= "table" or type(class) ~= "string" then return nil end
  return mem.apps[M.key(class, context)]
end

-- ---------------------------------------------------------------- bound scenes (auto mode)
-- bound[tostring(workspace id)] = { scene = name, apps = { key(class, context), ... } }: a scene open on that workspace
-- and the apps it holds. String keys, so encode() writes it as a table with named keys.
M.MAX_BOUND = 100
M.MAX_APPS = 100
local SCENE_RE = "^[%w_%-]+$"

local function clean_apps(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for _, k in ipairs(list) do
    if type(k) == "string" and k ~= "" and #out < M.MAX_APPS then out[#out + 1] = k end
  end
  return out
end

-- Bind `scene` to workspace `ws`. Returns false for a bad id, name, or when the table is full.
function M.bind(mem, ws, scene, apps)
  local id = math.tointeger(ws)
  if type(mem) ~= "table" or not id or id < 1 or type(scene) ~= "string" or #scene > 40 or not scene:match(SCENE_RE) then
    return false
  end
  mem.bound = type(mem.bound) == "table" and mem.bound or {}
  local n = 0
  for _ in pairs(mem.bound) do n = n + 1 end
  if n >= M.MAX_BOUND and not mem.bound[tostring(id)] then return false end
  mem.bound[tostring(id)] = { scene = scene, apps = clean_apps(apps) }
  return true
end

function M.unbind(mem, ws)
  local id = math.tointeger(ws)
  if type(mem) ~= "table" or type(mem.bound) ~= "table" or not id or mem.bound[tostring(id)] == nil then return false end
  mem.bound[tostring(id)] = nil
  return true
end

function M.bound(mem, ws)
  local id = math.tointeger(ws)
  if type(mem) ~= "table" or type(mem.bound) ~= "table" or not id then return nil end
  return mem.bound[tostring(id)]
end

-- ---------------------------------------------------------------- text

-- Same escaping as js/LuaLiteral.js: backslash, quote, newline and every control byte, so no text ends the string.
local function quote(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    if c == "\\" then return "\\\\" elseif c == '"' then return '\\"' elseif c == "\n" then return "\\n" end
    return string.format("\\%03d", c:byte())
  end) .. '"'
end

local function enc(v)
  local t = type(v)
  if t == "string" then return quote(v) end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if not finite(v) then error("not a finite number") end
    if math.type(v) == "integer" then return string.format("%d", v) end
    return string.format("%.14g", v) -- decimal (not %q hex floats), short enough to read
  end
  if t ~= "table" then error("cannot encode " .. t) end
  local n = #v
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  if n == #keys then -- a list
    local parts = {}
    for i = 1, n do parts[i] = enc(v[i]) end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  for _, k in ipairs(keys) do
    if type(k) ~= "string" then error("mixed table") end
  end
  table.sort(keys)
  local parts = {}
  for i, k in ipairs(keys) do parts[i] = "[" .. quote(k) .. "] = " .. enc(v[k]) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- The memory as `return { ... }` text, or nil and an error.
function M.encode(mem)
  local ok, text = pcall(enc, { schema = 1, seq = math.tointeger(mem.seq) or 0, apps = mem.apps or {}, bound = mem.bound or {} })
  if not ok then return nil, tostring(text) end
  return "return " .. text .. "\n"
end

-- Run a loaded chunk with an instruction budget, so a file with an endless loop is refused. The hook is removed
-- afterwards. Returns pcall's results.
M.MAX_INSTRUCTIONS = 1000000
function M.run_limited(chunk)
  if not debug or not debug.sethook then return pcall(chunk) end
  local prev_hook, prev_mask, prev_count = debug.gethook()
  debug.sethook(function() error("instruction budget used up", 0) end, "", M.MAX_INSTRUCTIONS)
  local res = table.pack(pcall(chunk))
  debug.sethook(prev_hook, prev_mask or "", prev_count or 0)
  return table.unpack(res, 1, res.n)
end

-- Text back to memory, loaded as text only in an empty environment. Bad entries are dropped. nil and an error when
-- the text cannot be used at all (the message never quotes the text).
function M.decode(text)
  if type(text) ~= "string" then return nil, "no text" end
  if #text > M.MAX_TEXT then return nil, "too big" end
  local chunk = load(text, "memory", "t", {})
  if not chunk then return nil, "does not parse" end
  local ok, t = M.run_limited(chunk)
  if not ok or type(t) ~= "table" or type(t.apps) ~= "table" then return nil, "not a memory table" end
  local mem = M.new()
  for k, e in pairs(t.apps) do
    local place = clean_place(e)
    if place and k == M.key(place.class, place.context) then
      place.n = math.tointeger(e.n) or 0
      place.saved_at = math.tointeger(e.saved_at)
      mem.apps[k] = place
      if place.n > mem.seq then mem.seq = place.n end
    end
  end
  while drop_oldest(mem) do end
  if type(t.bound) == "table" then
    for k, e in pairs(t.bound) do
      local id = type(k) == "string" and k:match("^%d+$") and math.tointeger(tonumber(k))
      if id and type(e) == "table" then M.bind(mem, id, e.scene, e.apps) end
    end
  end
  return mem
end

return M
