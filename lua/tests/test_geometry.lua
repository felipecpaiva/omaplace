-- Plain Lua check:  lua lua/tests/test_geometry.lua
local dir = arg[0]:match("^(.*)/") or "."
local G = dofile(dir .. "/../geometry.lua")
local gold = dofile(dir .. "/fixtures/geometry-golden.lua")

local checks = 0
local function same_rect(got, want, name)
  checks = checks + 1
  assert(got.x == want.x and got.y == want.y and got.w == want.w and got.h == want.h,
    string.format("%s: got %d,%d %dx%d want %d,%d %dx%d", name, got.x, got.y, got.w, got.h, want.x, want.y, want.w, want.h))
end

for i, v in ipairs(gold.usable) do
  same_rect(G.usable(v.mon, v.reserve), v.area, "usable " .. i)
  local w, h = G.logical_size(v.mon)
  checks = checks + 1
  assert(w == v.logical[1] and h == v.logical[2], "logical_size " .. i)
end
for i, v in ipairs(gold.place_frac) do
  same_rect(G.place_frac(v.area, v.frac, { margin = v.margin, edge_tight = v.edge_tight }), v.rect, "place_frac " .. i)
end
for i, v in ipairs(gold.transfer) do
  same_rect(G.transfer(v.rect, v.from, v.to), v.out, "transfer " .. i)
end
assert(#gold.usable > 90 and #gold.place_frac > 500 and #gold.transfer > 90, "golden file is not empty")

-- to_frac: a whole area is 1, and rect -> fraction -> rect gives the same rect for every golden area
local A = { x = 10, y = 26, w = 1000, h = 500 }
local f = G.to_frac(A, { x = 510, y = 276, w = 500, h = 250 })
assert(f[1] == 0.5 and f[2] == 0.5 and f[3] == 0.5 and f[4] == 0.5, "to_frac quarter")
local whole = G.to_frac(A, A)
assert(whole[1] == 0 and whole[2] == 0 and whole[3] == 1 and whole[4] == 1, "to_frac whole")
for i, v in ipairs(gold.place_frac) do
  if v.margin == 0 then
    local back = G.place_frac(v.area, G.to_frac(v.area, v.rect), nil)
    same_rect(back, v.rect, "round trip " .. i)
  end
end
-- and fraction -> rect -> fraction is within one pixel
for _, area in ipairs({ { x = 0, y = 26, w = 1920, h = 1054 }, { x = 3, y = 0, w = 2049, h = 777 } }) do
  for _, fr in ipairs({ { 0.1, 0.2, 0.7, 0.65 }, { 1 / 3, 0, 1 / 3, 1 } }) do
    local g = G.to_frac(area, G.place_frac(area, fr))
    for k = 1, 4 do
      checks = checks + 1
      assert(math.abs(g[k] - fr[k]) <= 1 / math.min(area.w, area.h), "fraction drift " .. k)
    end
  end
end
-- a zero sized area does not divide by zero
assert(G.to_frac({ x = 0, y = 0, w = 0, h = 0 }, { x = 0, y = 0, w = 1, h = 1 })[3] == 1, "zero area")

print("test_geometry ok (" .. checks .. " checks)")
