-- Turn live windows and monitors into a snapshot (design 5.5). Pure: no hl, no files, no clock.
-- Never reads or writes a title. `pid` is runtime only: it is in the capture answer so the service can ask
-- procinfo.sh for a terminal's folder, and the service never stores it (scenes and sessions have no pid field).
local G = dofile((debug.getinfo(1, "S").source:match("^@(.*)/") or ".") .. "/geometry.lua")
local M = {}

M.CTX_PREFIX = "omaplace-ctx="
M.MINIMIZED = "^omarchy%-minimized%-from%-(%d+)$"

-- A context (profile or folder) as a tag-safe hex string, and back.
function M.ctx_hex(ctx)
  return (tostring(ctx):gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

function M.ctx_unhex(hex)
  if type(hex) ~= "string" or #hex % 2 ~= 0 or hex:find("[^0-9a-f]") then return nil end
  return (hex:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
end

-- Tags as a list of strings (Hyprland may give a table or a space separated string). A trailing `*` (dynamic tag
-- in hyprctl output) is dropped.
function M.tags_of(w)
  local t, out = w.tags, {}
  if type(t) == "string" then
    for s in t:gmatch("%S+") do out[#out + 1] = s end
  elseif type(t) == "table" then
    for _, s in ipairs(t) do out[#out + 1] = tostring(s) end
  end
  for i, s in ipairs(out) do out[i] = s:gsub("%*$", "") end
  return out
end

-- The context a window was tagged with when omaplace claimed it, or nil.
function M.context_of(w)
  for _, tag in ipairs(M.tags_of(w)) do
    if tag:sub(1, #M.CTX_PREFIX) == M.CTX_PREFIX then return M.ctx_unhex(tag:sub(#M.CTX_PREFIX + 1)) end
  end
end

-- The workspace a minimized window came from (Omarchy's tag), or nil.
function M.home_of(w)
  for _, tag in ipairs(M.tags_of(w)) do
    local id = tag:match(M.MINIMIZED)
    if id then return math.tointeger(tonumber(id)) end
  end
end

-- "a, b c" -> { a = true, b = true, c = true }, lower case.
function M.ignore_set(text)
  local set = {}
  for cls in tostring(text or ""):gmatch("[^%s,]+") do set[cls:lower()] = true end
  return set
end

local function xy(v)
  if type(v) ~= "table" then return 0, 0 end
  return tonumber(v.x or v[1]) or 0, tonumber(v.y or v[2]) or 0
end

local function round4(v) return math.floor(v * 10000 + 0.5) / 10000 end

-- snapshot(windows, monitors, opts)
--   windows   hl.get_windows() items (initial_class, at, size, floating, fullscreen, workspace, monitor, tags, pid)
--   monitors  hl.get_monitors() items
--   opts      slot_of(id), is_floating(id), fingerprint(monitor, all), usable(monitor), ignore (list or set of classes),
--             scope ("all" or "focused"), workspace (the focused workspace id, for scope "focused"),
--             kind, saved_at, mode (copied to the header)
function M.snapshot(windows, monitors, opts)
  opts = opts or {}
  local ignore = opts.ignore or {}
  if ignore[1] then
    local set = {}
    for _, c in ipairs(ignore) do set[tostring(c):lower()] = true end
    ignore = set
  end

  local mons, index, areas = {}, {}, {}
  local list = {}
  for _, m in ipairs(monitors or {}) do
    if not m.is_mirror then list[#list + 1] = m end
  end
  table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
  for i, m in ipairs(list) do
    mons[i] = { fp = opts.fingerprint and opts.fingerprint(m, monitors) or { identity = m.description or m.name } }
    index[m.name] = i - 1
    local ok, area = pcall(opts.usable or G.usable, m)
    areas[m.name] = ok and type(area) == "table" and area or { x = m.x or 0, y = m.y or 0, w = m.width or 1, h = m.height or 1 }
  end

  local picked = {}
  for _, w in ipairs(windows or {}) do
    local ws = w.workspace or {}
    local ws_id, minimized = math.tointeger(ws.id), false
    if (ws.name or ""):sub(1, 8) == "special:" or (ws_id and ws_id < 0) then
      ws_id = M.home_of(w)
      minimized = ws_id ~= nil
    end
    local cls = w.initial_class or ""
    local mon = w.monitor and w.monitor.name
    local wanted = ws_id and ws_id > 0 and cls ~= "" and not ignore[cls:lower()] and index[mon] ~= nil
    if wanted and opts.scope == "focused" then wanted = ws_id == opts.workspace end
    if wanted then
      local x, y = xy(w.at)
      local sw, sh = xy(w.size)
      local f = G.to_frac(areas[mon], { x = x, y = y, w = sw, h = sh })
      picked[#picked + 1] = {
        ws = ws_id, x = x, y = y,
        out = {
          class = cls, monitor = index[mon], slot = opts.slot_of and opts.slot_of(ws_id) or ws_id,
          rect = { round4(f[1]), round4(f[2]), round4(f[3]), round4(f[4]) },
          floating = w.floating == true or (opts.is_floating ~= nil and opts.is_floating(ws_id) == true),
          fullscreen = math.tointeger(w.fullscreen) or 0, minimized = minimized,
          context = M.context_of(w), pid = math.tointeger(w.pid),
        },
      }
    end
  end

  -- Left to right (x, then y) within one workspace; the sort is stable on ties by input position.
  for i, p in ipairs(picked) do p.i = i end
  table.sort(picked, function(a, b)
    if a.ws ~= b.ws then return a.ws < b.ws end
    if a.x ~= b.x then return a.x < b.x end
    if a.y ~= b.y then return a.y < b.y end
    return a.i < b.i
  end)
  local out, rank, last = {}, 0, nil
  for _, p in ipairs(picked) do
    rank = p.ws == last and rank + 1 or 1
    last = p.ws
    p.out.order = rank
    out[#out + 1] = p.out
  end
  return { schema = 1, kind = opts.kind or "capture", saved_at = opts.saved_at, mode = opts.mode,
    monitors = mons, windows = out }
end

return M
