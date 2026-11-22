-- Plain Lua check:  lua lua/tests/test_capture.lua   (made-up windows only)
local dir = arg[0]:match("^(.*)/") or "."
local Capture = dofile(dir .. "/../capture.lua")
local Monitors = dofile(dir .. "/../monitors.lua")
local Geometry = dofile(dir .. "/../geometry.lua")
local Json = dofile(dir .. "/../json.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local function mon(name, desc, x, focused)
  return { name = name, description = desc, make = "Example Corp", model = desc, width = 2000, height = 1000, scale = 1,
    transform = 0, x = x, y = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 }, focused = focused or false }
end
local panel, ext = mon("eDP-1", "Example Panel", 0, true), mon("DP-2", "Example Corp EX27", 2000)
local function win(cls, ws, m, x, y, w, h, extra)
  local t = { initial_class = cls, class = cls, title = "Made up title " .. cls, initial_title = "Made up",
    workspace = { id = ws, name = tostring(ws) }, monitor = m, at = { x = x, y = y }, size = { x = w, y = h },
    floating = true, fullscreen = 0, tags = {}, pid = 4242, address = "0xa" .. cls }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

local windows = {
  win("org.example.Right", 1, panel, 1000, 0, 1000, 1000),
  win("org.example.Left", 1, panel, 0, 0, 1000, 500),
  win("org.example.LeftLow", 1, panel, 0, 500, 1000, 500, { tags = { "omaplace-ctx=" .. Capture.ctx_hex("Profile 1") } }),
  win("org.example.Other", 12, ext, 2000, 0, 2000, 1000, { floating = false }),
  win("org.example.Mini", -99, panel, 10, 10, 100, 100,
    { workspace = { id = -99, name = "special:minimized" }, tags = { "omarchy-minimized-from-1" } }),
  win("org.example.Scratch", -98, panel, 0, 0, 10, 10, { workspace = { id = -98, name = "special:scratch" } }),
  win("org.example.Ignored", 1, panel, 0, 0, 10, 10),
}

local opts = {
  slot_of = function(id) return ((id - 1) % 10) + 1 end,
  is_floating = function(id) return id == 1 end,
  fingerprint = Monitors.fingerprint, usable = Geometry.usable,
  ignore = { "ORG.EXAMPLE.IGNORED" }, scope = "all", kind = "capture", saved_at = 1700000000, mode = "per_monitor",
}
local snap = Capture.snapshot(windows, { panel, ext }, opts)
eq(snap.schema, 1, "schema")
eq(#snap.monitors, 2, "two monitors")
eq(snap.monitors[1].fp.last_connector, "DP-2", "monitors sorted by connector")
eq(#snap.windows, 5, "special and ignored left out, minimized kept")

local by = {}
for _, w in ipairs(snap.windows) do by[w.class] = w end
eq(by["org.example.Left"].order, 1, "leftmost, top first")
eq(by["org.example.LeftLow"].order, 2, "same x, lower second")
eq(by["org.example.Right"].order, 4, "rightmost last (minimized at x 10 is third)")
eq(by["org.example.Mini"].order, 3, "minimized ranked in its home workspace")
eq(by["org.example.Other"].order, 1, "own workspace, own order")
eq(by["org.example.Right"].monitor, 1, "panel is index 1")
eq(by["org.example.Other"].monitor, 0, "external is index 0")
eq(by["org.example.Other"].slot, 2, "slot from workspace 12")
eq(by["org.example.Right"].rect[1], 0.5, "rect x fraction")
eq(by["org.example.Right"].rect[3], 0.5, "rect w fraction")
eq(by["org.example.Other"].rect[1], 0, "rect relative to its monitor")
eq(by["org.example.Other"].floating, false, "tiled window on a tiled workspace")
eq(by["org.example.Mini"].minimized, true, "minimized flag")
eq(by["org.example.Mini"].slot, 1, "minimized slot is its home")
eq(by["org.example.Mini"].floating, true, "home workspace floating")
eq(by["org.example.LeftLow"].context, "Profile 1", "context decoded from the tag")
eq(by["org.example.Left"].context, nil, "no tag, no context")
eq(by["org.example.Left"].pid, 4242, "pid kept for the runtime answer")

local text = Json.encode(snap)
eq(text:find("title", 1, true), nil, "no title anywhere")
eq(text:find("Made up", 1, true), nil, "no title text anywhere")
eq(text:find("0xa", 1, true), nil, "no address")

-- focused scope: only workspace 1
opts.scope, opts.workspace = "focused", 1
local f = Capture.snapshot(windows, { panel, ext }, opts)
eq(#f.windows, 4, "focused workspace only (with its minimized window)")

-- bad input does not raise
eq(#Capture.snapshot(nil, nil, nil).windows, 0, "nil input")
eq(#Capture.snapshot({ { workspace = { id = 1 } } }, { panel }, {}).windows, 0, "window without class")

-- helpers
eq(Capture.ctx_unhex(Capture.ctx_hex("Profile 1")), "Profile 1", "hex round trip")
eq(Capture.ctx_unhex("zz"), nil, "bad hex")
eq(Capture.ctx_unhex("abc"), nil, "odd hex")
eq(Capture.context_of({ tags = "omaplace-ctx=" .. Capture.ctx_hex("x") .. "*" }), "x", "string tags, dynamic star")
eq(Capture.home_of({ tags = { "omarchy-minimized-from-13" } }), 13, "home tag")
local set = Capture.ignore_set("a, B  c")
eq(set.a and set.b and set.c, true, "ignore set")
eq(Capture.ignore_set("")["omaplace-settings"], true, "the settings app is always ignored (D39)")
local own = Capture.snapshot({ win("omaplace-settings", 1, panel, 0, 0, 800, 600) }, { panel, ext }, opts)
eq(#own.windows, 0, "the settings window is never captured")

-- a window a pixel larger than the usable area (a tiled border, seen live) is saved inside 0..1
local over = Capture.snapshot({ win("org.example.Big", 1, panel, -1, -1, 2003, 1002) }, { panel, ext }, opts)
local r = over.windows[1].rect
eq(r[1] >= 0 and r[2] >= 0 and r[1] + r[3] <= 1 and r[2] + r[4] <= 1, true, "rect clamped inside the monitor")

print(string.format("test_capture: %d checks ok", checks))
