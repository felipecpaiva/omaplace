-- Plain Lua check:  lua lua/tests/test_glue_rule_rect.lua   (fake hl, a fixture HOME and runtime, made-up windows)
-- A rule with keep_rect (D27): its first window on the rule's desktop is put at the rule's rect, only when floating.
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- The state folder is a fixture in the repo (its .gitignore keeps what the test writes out of git).
local home = dir .. "/fixtures/home-rect"
local state = home .. "/.local/state/omaplace"
local runtime = dir .. "/fixtures/runtime"
local function clean()
  for _, n in ipairs({ "memory.lua", "memory.lua.tmp" }) do os.remove(state .. "/" .. n) end
  for _, n in ipairs({ "status.json", "status.json.tmp" }) do os.remove(runtime .. "/omaplace/" .. n) end
end
clean()
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "HOME" then return home end
  if k == "XDG_RUNTIME_DIR" then return runtime end
  return real_getenv(k)
end
local printed = {}
local real_print = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

_G.hl, _G.o = fake.hl, fake.o
local function mon(name, desc, x, ws, focused)
  return { name = name, description = desc, make = "Example Corp", model = desc, width = 2000, height = 1000, scale = 1,
    transform = 0, x = x, y = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 }, focused = focused or false,
    active_workspace = { id = ws } }
end
local panel, ext = mon("eDP-1", "Example Panel", 0, 3, true), mon("DP-2", "Example Corp EX27", 2000, 11)
fake.set_monitors({ panel, ext })

local FLOAT = "omarchy-floating-workspace"
local next_id = 0
local function new_window(cls, ws, extra)
  next_id = next_id + 1
  local w = { initial_class = cls, class = cls, title = "Made up title", address = "0x" .. next_id, stable_id = next_id,
    workspace = { id = ws, tiled_layout = "dwindle" }, monitor = panel, at = { x = 10, y = 10 }, size = { x = 300, y = 200 },
    floating = true, fullscreen = 0, tags = { FLOAT }, pid = 100 + next_id }
  for k, v in pairs(extra or {}) do w[k] = v end
  fake.windows[#fake.windows + 1] = w
  return w
end
local function close(w)
  for i, x in ipairs(fake.windows) do
    if x == w then table.remove(fake.windows, i) end
  end
  fake.emit("window.close", w)
end
-- Hyprland, faked: dispatches change the fake windows the way the real ones would.
local moves = {}
fake.hl.dispatch = function(call)
  fake.dispatched[#fake.dispatched + 1] = call
  local a = call.args or {}
  local w
  for _, x in ipairs(fake.windows) do
    if "address:" .. x.address == a.window then w = x end
  end
  if not w then return end
  if call.name == "window.move" and a.workspace then
    w.workspace = { id = tonumber(a.workspace), tiled_layout = "dwindle" }
    moves[#moves + 1] = { ws = a.workspace, follow = a.follow }
    fake.emit("window.move_to_workspace", w)
  elseif call.name == "window.move" then
    w.at = { x = a.x, y = a.y }
  elseif call.name == "window.resize" then
    w.size = { x = a.x, y = a.y }
  elseif call.name == "window.tag" then
    local sign, name = a.tag:sub(1, 1), a.tag:sub(2)
    for i = #w.tags, 1, -1 do
      if w.tags[i] == name then table.remove(w.tags, i) end
    end
    if sign == "+" then w.tags[#w.tags + 1] = name end
  end
end
local function count(name)
  local n = 0
  for _, c in ipairs(fake.dispatched) do
    if c.name == name then n = n + 1 end
  end
  return n
end
local function has(w, tag)
  for _, t in ipairs(w.tags) do
    if t == tag then return true end
  end
  return false
end
local function load(fresh)
  if fresh then _G.omaplace = nil end -- a new Lua state (Hyprland restart), not a reload
  dofile(dir .. "/../omaplace.lua")
  _G.omaplace._m.now_ms = function() return fake.now end
end
local function reset() fake.dispatched, moves = {}, {} end

load(true)
-- desktop 12 is slot 2 of the second monitor (DP-2, x 2000, 2000 by 1000)
local chat = new_window("org.example.Chat", 12)
fake.emit("window.open", chat)
eq(count("window.resize"), 0, "no rect before the settle")
fake.advance(1500)
eq(count("window.resize"), 1, "rect after the settle")
eq(chat.at.x >= 2900 and chat.at.x <= 3050, true, "right half of DP-2 (x " .. tostring(chat.at.x) .. ")")
eq(chat.size.x >= 900 and chat.size.x <= 1000, true, "half the width (w " .. tostring(chat.size.x) .. ")")

-- a second window of the app is left alone
reset()
local chat2 = new_window("org.example.Chat", 12)
fake.emit("window.open", chat2)
fake.advance(1500)
eq(count("window.resize"), 0, "second window: no rect")
close(chat2)
close(chat)

-- on a tiled desktop (no floating tag) there is no rect (D13)
reset()
local tiled = new_window("org.example.Chat", 12, { floating = false, tags = {} })
fake.emit("window.open", tiled)
fake.advance(1500)
eq(count("window.resize"), 0, "tiled: no rect")
close(tiled)

-- on another desktop than the rule's (moved there by hand before the settle): nothing
reset()
local away = new_window("org.example.Chat", 5)
fake.emit("window.open", away)
fake.advance(1500)
eq(count("window.resize"), 0, "not on the rule's desktop: no rect")

print = real_print
os.getenv = real_getenv
clean()
print(string.format("test_glue_rule_rect: %d checks ok", checks))
