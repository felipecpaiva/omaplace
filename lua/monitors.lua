-- Monitor fingerprints and the ordered fallback that finds a monitor again (design 5.1). Pure.
-- A monitor is a table like hl.get_monitors() items: name, description, make, model, serial, width, height,
-- scale, transform, is_mirror, focused.
local M = {}

-- 32 bit FNV-1a as 8 hex digits. The serial itself is never kept.
local function fnv1a(s)
  local h = 0x811c9dc5
  for i = 1, #s do
    h = ((h ~ s:byte(i)) * 0x01000193) & 0xffffffff
  end
  return string.format("%08x", h)
end

-- Omarchy's own rule (monitor-workspaces.lua `internal`): eDP, LVDS and DSI connectors are the laptop panel.
local function is_internal(monitor)
  local n = monitor.name or ""
  return (n:match("^eDP") or n:match("^LVDS") or n:match("^DSI")) ~= nil
end

local function described(monitor)
  local d = monitor.description or ""
  return d ~= "" and d or monitor.name
end

-- Omarchy's identity: the description, with " #2", " #3" for monitors that describe themselves the same,
-- numbered in connector name order. Mirrors are not counted.
local function identity_of(monitor, all)
  local same = {}
  for _, m in ipairs(all or {}) do
    if not m.is_mirror and described(m) == described(monitor) then same[#same + 1] = m end
  end
  table.sort(same, function(a, b) return a.name < b.name end)
  for i, m in ipairs(same) do
    if m.name == monitor.name then return i == 1 and described(monitor) or (described(monitor) .. " #" .. i) end
  end
  return described(monitor)
end

-- Hyprland's Lua monitor has no make or model field (hyprctl's JSON has them; checked live 2026-11-21), only a
-- description of "make model serial". So the model key is `model` when present, else the description without the serial.
local function model_of(monitor, serial)
  if (monitor.model or "") ~= "" then return monitor.model end
  local d = monitor.description or ""
  if serial ~= "" and d:sub(-#serial - 1) == " " .. serial then d = d:sub(1, -#serial - 2) end
  return d
end

function M.fingerprint(monitor, all_monitors)
  local serial = monitor.serial or ""
  local twins = 0
  for _, m in ipairs(all_monitors or {}) do
    if not m.is_mirror and described(m) == described(monitor) then twins = twins + 1 end
  end
  return {
    twin = twins > 1 or nil, -- the identity was shared with another screen when this was saved
    identity = identity_of(monitor, all_monitors),
    make = monitor.make or "",
    model = model_of(monitor, serial),
    serial_hash = serial ~= "" and fnv1a(serial) or "",
    internal = is_internal(monitor),
    width = monitor.width, height = monitor.height,
    scale = monitor.scale, transform = monitor.transform or 0,
    last_connector = monitor.name,
  }
end

-- Pixel size with rotation applied, so a monitor turned on its side still looks like itself.
local function shape(w, h, transform)
  if (transform or 0) % 2 == 1 then return h, w end
  return w, h
end

local function near(a, b, tol) return math.abs(a - b) <= tol * math.abs(b) end

-- Distance between two shapes, or nil when they are not the same class (aspect within 2 percent, size within 10).
local function shape_gap(fp, lfp)
  local fw, fh = shape(fp.width, fp.height, fp.transform)
  local lw, lh = shape(lfp.width, lfp.height, lfp.transform)
  if not (fw and fh and lw and lh) or fh <= 0 or lh <= 0 then return nil end
  if not near(fw / fh, lw / lh, 0.02) or not near(lw, fw, 0.10) or not near(lh, fh, 0.10) then return nil end
  return math.abs(lw - fw) / fw + math.abs(lh - fh) / fh
end

-- Find the live monitor for a stored fingerprint. Returns `monitor, how`, where how is one of
-- "identity", "serial", "model", "internal", "shape", "focused"; or nil, "skip" when nothing matches
-- and `policy` is "skip" (or not "focused"). Ties go to the lowest connector name.
function M.resolve(fp, live, policy)
  local list, fps = {}, {}
  for _, m in ipairs(live or {}) do
    if not m.is_mirror then list[#list + 1] = m end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  for i, m in ipairs(list) do fps[i] = M.fingerprint(m, live) end
  if type(fp) ~= "table" then return nil, "skip" end

  local function first(pred)
    for i, m in ipairs(list) do
      if pred(fps[i], m) then return m end
    end
  end

  -- Omarchy keeps a twin's identity while it stays plugged in, so a recomputed " #2" can be wrong. First look
  -- for the connector this monitor had last time (same description, any " #N"). Otherwise fall back to the
  -- recomputed identity. A serialless twin whose connector is gone is not guessed at by identity, model or
  -- shape: the screen left behind could be a different one.
  local m
  local lost_twin = fp.twin and (fp.serial_hash or "") == ""
  if type(fp.identity) == "string" then
    local base = fp.identity:gsub(" #%d+$", "")
    for _, mon in ipairs(list) do
      local d = described(mon)
      if mon.name == fp.last_connector and (d == fp.identity or d == base) then return mon, "identity" end
    end
    if not lost_twin then
      m = first(function(l) return l.identity == fp.identity end)
      if m then return m, "identity" end
    end
  end
  -- an empty serial hash must never match: two monitors without serials are not the same monitor
  m = first(function(l)
    return (fp.serial_hash or "") ~= "" and l.serial_hash == fp.serial_hash and l.make == fp.make and l.model == fp.model
  end)
  if m then return m, "serial" end
  local same, count = nil, 0
  if not lost_twin and ((fp.make or "") ~= "" or (fp.model or "") ~= "") then
    for i, l in ipairs(fps) do
      if l.make == fp.make and l.model == fp.model then count = count + 1; same = same or list[i] end
    end
    if count == 1 then return same, "model" end
  end
  if fp.internal then
    m = first(function(l) return l.internal end)
    if m then return m, "internal" end
  end
  local best, best_gap
  for i, l in ipairs(fps) do
    local gap = not lost_twin and shape_gap(fp, l)
    if gap and (not best_gap or gap < best_gap) then best, best_gap = list[i], gap end
  end
  if best then return best, "shape" end
  if policy == "focused" then
    m = first(function(_, mon) return mon.focused end)
    if m then return m, "focused" end
  end
  return nil, "skip"
end

return M
