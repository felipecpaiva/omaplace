-- Plain Lua check:  lua lua/tests/test_glue_auto.lua   (fake hl, a fixture HOME and runtime, made-up windows)
-- Auto app memory (WP10): scenes bound to workspaces, moves between bound workspaces reported in moves.json.
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()
local Memory = dofile(dir .. "/../memory.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- The state folder is a fixture in the repo (its .gitignore keeps what the test writes out of git).
local home = dir .. "/fixtures/home-auto"
local state = home .. "/.local/state/omaplace"
local runtime = dir .. "/fixtures/runtime"
local function clean()
  for _, n in ipairs({ "memory.lua", "memory.lua.tmp" }) do os.remove(state .. "/" .. n) end
  for _, n in ipairs({ "status.json", "status.json.tmp", "moves.json", "moves.json.tmp" }) do os.remove(runtime .. "/omaplace/" .. n) end
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

local function read_memory()
  local f = io.open(state .. "/memory.lua", "r")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return Memory.decode(t)
end

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


local function moves_text()
  local f = io.open(runtime .. "/omaplace/moves.json", "r")
  if not f then return "" end
  local t = f:read("a")
  f:close()
  return t
end
local function events_in(text) return select(2, text:gsub('"from_scene"', "")) end

load(true)
local M = _G.omaplace._m
eq(#fake.handlers["window.move_to_workspace"], 1, "auto: move subscribed")

local function run(id, scene, slot, wins)
  _G.omaplace.open({ run = id, scene = scene, target = { fp = {}, slot = slot }, existing = "new", layout = "floating",
    windows = wins })
end
-- scene "work" on desktop 1 (Chat, Notes), scene "play" on desktop 2 (Term, a Chrome profile)
run("a1", "work", 1, {
  { class = "org.example.Chat", order = 1, rect = { 0.5, 0, 0.5, 1 }, mode = "launch", launch = { "chat" } },
  { class = "org.example.Notes", order = 2, rect = { 0, 0, 0.5, 1 }, mode = "launch", launch = { "notes" } } })
fake.advance(300)
local chat = new_window("org.example.Chat", 3)
fake.emit("window.open", chat)
local notes = new_window("org.example.Notes", 3)
fake.emit("window.open", notes)
fake.advance(2000)
eq(_G.omaplace.status().state, "done", "run a1 done")
eq(Memory.bound(read_memory(), 1).scene, "work", "scene bound to desktop 1, saved in memory.lua")
eq(#Memory.bound(read_memory(), 1).apps, 2, "the scene's apps are kept")
eq(moves_text(), "", "a run writes no moves")

run("a2", "play", 2, {
  { class = "org.example.Term", order = 1, rect = { 0, 0, 1, 0.5 }, mode = "launch", launch = { "term" } },
  { class = "google-chrome", context = "Profile 1", order = 2, rect = { 0, 0.5, 1, 0.5 }, mode = "launch", launch = { "chrome" } } })
fake.advance(300)
local term = new_window("org.example.Term", 3)
fake.emit("window.open", term)
local chrome = new_window("google-chrome", 3, { tags = { FLOAT, "omaplace-ctx=" .. "50726f66696c652031" } })
fake.emit("window.open", chrome)
fake.advance(2000)
eq(_G.omaplace.status().state, "done", "run a2 done")
eq(Memory.bound(read_memory(), 2).scene, "play", "second scene bound to desktop 2")
eq(chat.workspace.id, 1, "Chat on desktop 1")
eq(term.workspace.id, 2, "Term on desktop 2")
eq(fake.pending_timers(), 0, "idle after the runs")

-- a move between two bound desktops: one event after the settle, no title
reset()
chat.workspace = { id = 2 }
fake.emit("window.move_to_workspace", chat)
chat.at = { x = 1000, y = 0 } -- Omarchy re-arranges it after the event
eq(moves_text(), "", "nothing before the debounce")
fake.advance(2000)
local text = moves_text()
eq(events_in(text), 1, "one event")
eq(text:find('"class":"org.example.Chat"', 1, true) ~= nil, true, "class")
eq(text:find('"from_scene":"work"', 1, true) ~= nil, true, "from scene")
eq(text:find('"to_scene":"play"', 1, true) ~= nil, true, "to scene")
eq(text:find('"floating":true', 1, true) ~= nil, true, "floating")
eq(text:find('"order":3', 1, true) ~= nil, true, "left to right rank on desktop 2 (after Term and Chrome at x 10)")
eq(text:find('"context":""', 1, true) ~= nil, true, "context")
eq(text:find('"rect":[0.5,', 1, true) ~= nil, true, "rect read after the settle")
eq(text:find("Made up title", 1, true), nil, "no title in moves.json")
eq(text:sub(1, 1) .. text:sub(-2, -2), "[]", "a JSON array")
local mem = read_memory()
eq(Memory.lookup(mem, "org.example.Chat").slot, 2, "app memory also has the new place")
eq(#Memory.bound(mem, 1).apps, 1, "Chat left the work scene")
eq(#Memory.bound(mem, 2).apps, 3, "and joined the play scene")
eq(fake.pending_timers(), 0, "idle after the report")
for _, l in ipairs(printed) do eq(l:find("Made up title", 1, true), nil, "no title in the log") end

-- a Chrome profile window keeps its context
reset()
chrome.workspace = { id = 1 }
fake.emit("window.move_to_workspace", chrome)
fake.advance(2000)
text = moves_text()
eq(events_in(text), 2, "second event appended")
eq(text:find('"context":"Profile 1"', 1, true) ~= nil, true, "profile context in the event")

-- a move to an unbound desktop writes no event, but app memory follows
reset()
notes.workspace = { id = 7 }
fake.emit("window.move_to_workspace", notes)
fake.advance(2000)
eq(events_in(moves_text()), 2, "no event for an unbound target")
eq(Memory.lookup(read_memory(), "org.example.Notes").slot, 7, "app memory has the new desktop")

-- a window of no bound scene moving between bound desktops writes nothing
reset()
local other = new_window("org.example.Other", 1)
fake.emit("window.open", other)
other.workspace = { id = 2 }
fake.emit("window.move_to_workspace", other)
fake.advance(2000)
eq(events_in(moves_text()), 2, "an app of no scene writes nothing")

-- at most 50 pending events, oldest dropped
for i = 1, 55 do
  local w = (i % 2 == 1) and term or chat
  local to = w.workspace.id == 1 and 2 or 1
  M.memory.bound["1"].apps[#M.memory.bound["1"].apps + 1] = "org.example.Term"
  M.memory.bound["2"].apps[#M.memory.bound["2"].apps + 1] = "org.example.Chat"
  w.workspace = { id = to }
  fake.emit("window.move_to_workspace", w)
  fake.advance(2000)
end
eq(#M.moves <= 50, true, "capped at 50")
eq(events_in(moves_text()), #M.moves, "the file holds the pending events")

-- drop a binding when its desktop is empty
for _, w in ipairs({ term, chrome, chat, other }) do close(w) end
fake.windows = { notes }
fake.advance(2000)
eq(Memory.bound(read_memory(), 1), nil, "desktop 1 empty: binding dropped")
eq(Memory.bound(read_memory(), 2), nil, "desktop 2 empty: binding dropped")
eq(fake.pending_timers(), 0, "idle after the drop")

-- auto off (last_place): moves between bound desktops write nothing
M.settings.app_memory = "auto"
Memory.bind(M.memory, 1, "work", { "org.example.Notes" })
Memory.bind(M.memory, 2, "play", {})
local before = events_in(moves_text())
M.settings.app_memory = "last_place"
M.sync_memory()
notes.workspace = { id = 2 }
fake.emit("window.move_to_workspace", notes)
fake.advance(2000)
eq(events_in(moves_text()), before, "last_place writes no event")
M.settings.app_memory = "scene"
M.sync_memory()
eq(#fake.handlers["window.move_to_workspace"], 0, "scene: unsubscribed")
eq(fake.pending_timers(), 0, "idle at the end")

-- last_place does not bind a run's scene (only auto does); a binding left over goes when its desktop empties
M.settings.app_memory = "last_place"
M.sync_memory()
fake.windows = {}
M.memory.bound = {}
run("a9", "solo", 5, {
  { class = "org.example.Chat", order = 1, rect = { 0.5, 0, 0.5, 1 }, mode = "launch", launch = { "chat" } } })
fake.advance(300)
local solo = new_window("org.example.Chat", 3)
fake.emit("window.open", solo)
fake.advance(2000)
eq(_G.omaplace.status().state, "done", "run a9 done")
eq(next(M.memory.bound), nil, "last_place: the scene is not bound")
Memory.bind(M.memory, 31, "stale", { "org.example.Chat" })
close(solo)
fake.advance(2000)
eq(next(M.memory.bound), nil, "last_place: a binding of an empty desktop expires")
eq(next(Memory.bound(read_memory(), 31) or {}), nil, "and is gone from the file")
M.settings.app_memory = "scene"
M.sync_memory()

clean()
print = real_print
os.getenv = real_getenv
print(string.format("test_glue_auto: %d checks ok", checks))
