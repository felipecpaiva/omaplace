-- Pure rect math for omaplace. `usable`, `place_frac`, `logical_size` and `transfer` are copied unchanged
-- from omagnet (lua/geometry.lua, last changed in commit 856de02). `to_frac` is new. Parity is checked by
-- lua/tests/test_geometry.lua against lua/tests/fixtures/geometry-golden.lua (made by tools/gen-geometry-golden.sh).
-- An area is {x, y, w, h} in logical pixels. A fraction is {x, y, w, h} of the usable area.
local G = {}

local function round(v) return math.floor(v + 0.5) end

-- The same for a fraction {x, y, w, h} of the area (a custom position or a zone).
function G.place_frac(area, f, opts)
  local l, t = round(area.x + f[1] * area.w), round(area.y + f[2] * area.h)
  local r, b = round(area.x + (f[1] + f[3]) * area.w), round(area.y + (f[2] + f[4]) * area.h)
  local m = math.max(0, math.floor((opts and opts.margin) or 0))
  if m == 0 then return { x = l, y = t, w = math.max(1, r - l), h = math.max(1, b - t) } end
  local tight = not (opts and opts.edge_tight == false)
  local lo, hi = math.floor(m / 2), m - math.floor(m / 2) -- on a shared edge the far window (right or bottom) insets by hi, the near one by lo
  local function inset(on_screen_edge, interior)
    if on_screen_edge then return tight and 0 or m end
    return interior
  end
  -- A tolerance, not ==: custom positions such as 0.1 + 0.9 do not add up to exactly 1 in floating point.
  local function at(v, edge) return math.abs(v - edge) < 1e-9 end
  local il, it = inset(at(f[1], 0), hi), inset(at(f[2], 0), hi)
  local ir, ib = inset(at(f[1] + f[3], 1), lo), inset(at(f[2] + f[4], 1), lo)
  local x, y = l + il, t + it
  return { x = x, y = y, w = math.max(1, (r - ir) - x), h = math.max(1, (b - ib) - y) }
end

-- Move rect `r` from one usable area to another, keeping its relative place and size, and keep it inside
-- the new area. Used for "next display".
function G.transfer(r, from, to)
  local fx, fy = (r.x - from.x) / math.max(1, from.w), (r.y - from.y) / math.max(1, from.h)
  local fw, fh = r.w / math.max(1, from.w), r.h / math.max(1, from.h)
  local w, h = math.max(1, math.min(to.w, round(fw * to.w))), math.max(1, math.min(to.h, round(fh * to.h)))
  local x = math.min(to.x + to.w - w, math.max(to.x, round(to.x + fx * to.w)))
  local y = math.min(to.y + to.h - h, math.max(to.y, round(to.y + fy * to.h)))
  return { x = x, y = y, w = w, h = h }
end

-- space the bar reserves. Same formula as Omarchy's own place() in workspace-modes.lua.
-- `reserve` (optional {top, bottom, left, right}) takes extra space off the area, for a dock that
-- reserves nothing itself.
function G.usable(mon, reserve)
  local w, h = mon.width, mon.height
  if mon.transform % 2 == 1 then w, h = h, w end
  w, h = math.floor(w / mon.scale), math.floor(h / mon.scale)
  local r = mon.reserved
  local e = reserve or {}
  local left, top = r.left + (e.left or 0), r.top + (e.top or 0)
  local right, bottom = r.right + (e.right or 0), r.bottom + (e.bottom or 0)
  return { x = mon.x + left, y = mon.y + top, w = w - left - right, h = h - top - bottom }
end

-- The logical size of a monitor (scale and rotation applied), not counting any reserved bar space.
function G.logical_size(mon)
  local w, h = mon.width, mon.height
  if mon.transform % 2 == 1 then w, h = h, w end
  return math.floor(w / mon.scale), math.floor(h / mon.scale)
end

-- Inverse of place_frac with margin 0: the fraction {x, y, w, h} of `area` that a rect covers.
function G.to_frac(area, rect)
  local w, h = math.max(1, area.w), math.max(1, area.h)
  return { (rect.x - area.x) / w, (rect.y - area.y) / h, rect.w / w, rect.h / h }
end

return G
