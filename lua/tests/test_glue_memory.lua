-- Plain Lua check:  lua lua/tests/test_glue_memory.lua   (fake hl, a fixture HOME and runtime, made-up windows)
-- App memory (F5): scene and last_place modes, the first-window rule, rules beat memory, no rect on a tiled desktop.
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()
local Memory = dofile(dir .. "/../memory.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- The state folder is a fixture in the repo (its .gitignore keeps what the test writes out of git).
local home = dir .. "/fixtures/home-memory"
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

-- load with no memory file: empty memory, one log line, idle
load(true)
local M = _G.omaplace._m
eq(#printed, 1, "one log line")
eq(printed[1]:find("no memory.lua yet", 1, true) ~= nil, true, "missing file logged")
eq(fake.pending_timers(), 0, "idle after load")
eq(#(fake.handlers["window.close"] or {}), 0, "scene mode: no close subscription")
eq(#(fake.handlers["window.move_to_workspace"] or {}), 0, "scene mode: no move subscription")

-- idle: a window with no memory is left alone at once
fake.emit("window.open", new_window("org.example.Stray", 3))
eq(#fake.dispatched, 0, "nothing dispatched for an unknown app")
eq(fake.pending_timers(), 0, "no timer for an unknown app")
fake.windows = {}

-- scene: a run places Chat (floating, right half of workspace 1) and Notes (its rule desktop, workspace 2)
_G.omaplace.open({ run = "m1", target = { fp = {}, slot = 1 }, existing = "new", layout = "floating", windows = {
  { class = "org.example.Chat", order = 1, rect = { 0.5, 0, 0.5, 1 }, mode = "launch", launch = { "chat" } },
  { class = "org.example.Notes", order = 2, rect = { 0, 0, 0.5, 1 }, mode = "launch", launch = { "notes" },
    desktop = { monitor = "", slot = 2 } },
} })
fake.advance(300) -- both launched (one per 150 ms tick)
local chat = new_window("org.example.Chat", 3)
fake.emit("window.open", chat)
local notes = new_window("org.example.Notes", 3)
fake.emit("window.open", notes)
fake.advance(2000)
eq(_G.omaplace.status().state, "done", "run done")
local mem = read_memory()
eq(mem ~= nil, true, "memory.lua written at the run end")
eq(Memory.lookup(mem, "org.example.Chat").slot, 1, "Chat remembered on slot 1")
eq(Memory.lookup(mem, "org.example.Chat").rect[1], 0.5, "Chat rect is the scene's")
eq(Memory.lookup(mem, "org.example.Chat").floating, true, "Chat floating")
eq(Memory.lookup(mem, "org.example.Chat").fp.identity, "Example Panel", "Chat monitor")
eq(Memory.lookup(mem, "org.example.Notes").slot, 2, "Notes remembered on its rule desktop")
eq(fake.pending_timers(), 0, "idle after the run")

-- scene mode: closing records nothing and arms nothing
close(chat)
close(notes)
eq(fake.pending_timers(), 0, "no timer on close in scene mode")

-- a hand-opened first window goes back: silent move to slot 1, tagged, rect after the settle
reset()
local chat2 = new_window("org.example.Chat", 3)
fake.emit("window.open", chat2)
eq(chat2.workspace.id, 1, "moved to the remembered desktop")
eq(moves[1].follow, false, "silent move")
eq(has(chat2, "omaplace-slot=memory"), true, "tagged like a run")
eq(count("window.resize"), 0, "no rect before the settle")
fake.advance(1100)
eq(count("window.resize"), 1, "rect after the settle")
eq(chat2.at.x, 1000, "right half x")
eq(chat2.size.x, 1000, "right half width")
fake.advance(40)
eq(fake.pending_timers(), 0, "idle after placing")

-- a second window of the same class is left alone
reset()
local chat3 = new_window("org.example.Chat", 3)
fake.emit("window.open", chat3)
eq(chat3.workspace.id, 3, "second window not moved")
eq(#fake.dispatched, 0, "nothing dispatched for a second window")
eq(fake.pending_timers(), 0, "no timer for a second window")
fake.windows = {}

-- a special workspace is never touched
reset()
fake.emit("window.open", new_window("org.example.Chat", -98, { workspace = { id = -98, name = "special:scratch" } }))
eq(#fake.dispatched, 0, "special workspace left alone")
fake.windows = {}

-- rule desktop beats memory: Notes has a rule (slot 2) and memory says slot 2, so only the rect is applied
reset()
local notes2 = new_window("org.example.Notes", 2) -- the rule already put it there
fake.emit("window.open", notes2)
eq(#moves, 0, "not moved: the rule's desktop")
eq(has(notes2, "omaplace-slot=memory"), true, "tagged")
fake.advance(1140)
eq(notes2.size.x, 1000, "rect applied on the same floating desktop")
fake.windows = {}
-- memory on another desktop than the rule: the rule wins and no rect
Memory.update(M.memory, { kind = "placed", class = "org.example.Notes", fp = Memory.lookup(M.memory, "org.example.Chat").fp,
  slot = 5, rect = { 0, 0, 1, 1 }, floating = true }, "scene", 1)
reset()
local notes3 = new_window("org.example.Notes", 2)
fake.emit("window.open", notes3)
eq(notes3.workspace.id, 2, "rule desktop kept")
eq(#fake.dispatched, 0, "nothing dispatched")
eq(fake.pending_timers(), 0, "no rect timer")
fake.windows = {}

-- a tiled target: moved, but never a rect, even when memory says floating
Memory.update(M.memory, { kind = "placed", class = "org.example.Term", fp = Memory.lookup(M.memory, "org.example.Chat").fp,
  slot = 4, rect = { 0, 0, 0.5, 1 }, floating = true }, "scene", 1)
reset()
-- a floating window on a tiled desktop (no Omarchy floating tag) still gets no rect
local term = new_window("org.example.Term", 3, { floating = true, tags = {} })
fake.emit("window.open", term)
eq(term.workspace.id, 4, "moved to slot 4")
fake.advance(1200)
eq(count("window.resize"), 0, "no rect on a tiled desktop")
eq(fake.pending_timers(), 0, "idle")
fake.windows = {}

-- a context entry never places an untagged window (D18 rule 5)
Memory.update(M.memory, { kind = "placed", class = "google-chrome", context = "Profile 1",
  fp = Memory.lookup(M.memory, "org.example.Chat").fp, slot = 6, floating = false }, "scene", 1)
reset()
fake.emit("window.open", new_window("google-chrome", 3))
eq(#fake.dispatched, 0, "untagged browser window left alone")
fake.windows = {}

-- last_place: close and move are recorded, for the class's last window only
M.settings.app_memory = "last_place"
M.sync_memory()
eq(#fake.handlers["window.close"], 1, "close subscribed")
eq(#fake.handlers["window.move_to_workspace"], 1, "move subscribed")
eq(fake.pending_timers(), 0, "subscribing arms nothing")
reset()
local mail1 = new_window("org.example.Mail", 6, { at = { x = 0, y = 0 }, size = { x = 1000, y = 500 } })
local mail2 = new_window("org.example.Mail", 7)
fake.emit("window.open", mail1)
fake.emit("window.open", mail2)
eq(#fake.dispatched, 0, "no memory yet for Mail")
close(mail2)
eq(fake.pending_timers(), 0, "not the last window: nothing armed")
close(mail1)
eq(fake.pending_timers(), 1, "last window closed: one debounce")
fake.advance(1999)
eq(Memory.lookup(read_memory(), "org.example.Mail"), nil, "not saved before the debounce")
fake.advance(1)
local m = Memory.lookup(read_memory(), "org.example.Mail")
eq(m and m.slot, 6, "last window's desktop saved")
eq(m and m.rect[3], 0.5, "last window's rect saved")
eq(fake.pending_timers(), 0, "idle after the save")
-- it comes back there when opened by hand; memory's own move is not recorded as a user's move, even when the
-- settle is longer than the debounce (the window is still where the app opened it when the debounce fires)
M.settings.settle_ms = 3000
reset()
local mail3 = new_window("org.example.Mail", 3)
fake.emit("window.open", mail3)
eq(mail3.workspace.id, 6, "reopened on its last desktop")
eq(fake.pending_timers(), 1, "only the settle timer: its own move arms no debounce")
fake.advance(3040)
eq(mail3.size.x, 1000, "at its last size")
eq(Memory.lookup(read_memory(), "org.example.Mail").rect[3], 0.5, "rect not overwritten by its own move")
eq(fake.pending_timers(), 0, "idle")
M.settings.settle_ms = 1100
-- a move to another desktop is read when the debounce fires
mail3.workspace = { id = 8 }
fake.emit("window.move_to_workspace", mail3)
mail3.at = { x = 1000, y = 0 } -- Omarchy re-arranges it after the event
fake.advance(2000)
m = Memory.lookup(read_memory(), "org.example.Mail")
eq(m.slot, 8, "move saved")
eq(m.rect[1], 0.5, "the place after the re-arrange")
-- auto behaves like last_place
M.settings.app_memory = "auto"
M.sync_memory()
eq(#fake.handlers["window.close"], 1, "auto: still one close subscription")
close(mail3)
fake.advance(2000)
eq(Memory.lookup(read_memory(), "org.example.Mail").slot, 8, "auto records the close")
-- back to scene: the subscriptions go
M.settings.app_memory = "scene"
M.sync_memory()
eq(#fake.handlers["window.close"], 0, "scene: close unsubscribed")

-- off: nothing is placed or recorded
M.settings.app_memory = "off"
reset()
local chat4 = new_window("org.example.Chat", 3)
fake.emit("window.open", chat4)
eq(#fake.dispatched, 0, "off: not placed")
eq(fake.pending_timers(), 0, "off: no timer")
fake.windows = {}
_G.omaplace.open({ run = "m2", target = { fp = {}, slot = 9 }, existing = "new", layout = "floating", windows = {
  { class = "org.example.Late", order = 1, rect = { 0, 0, 1, 1 }, mode = "launch", launch = { "late" } } } })
fake.emit("window.open", new_window("org.example.Late", 3))
fake.advance(2000)
eq(Memory.lookup(read_memory(), "org.example.Late"), nil, "off: a run is not remembered")
M.settings.app_memory = "scene"
fake.windows = {}

-- a window that closes without workspace or monitor still records, from its last known place (robustness: checked
-- live, a real close carries both)
do
  local m2 = _G.omaplace._m
  m2.settings.app_memory = "last_place"
  m2.sync_memory()
  reset()
  local ghost = new_window("org.example.Ghost", 9)
  fake.emit("window.open", ghost)
  ghost.workspace = { id = 12 }
  fake.emit("window.move_to_workspace", ghost) -- no advance: only the fallback can know desktop 12 at the close
  for i, x in ipairs(fake.windows) do
    if x == ghost then table.remove(fake.windows, i) end
  end
  ghost.workspace, ghost.monitor = nil, nil
  fake.emit("window.close", ghost)
  fake.advance(2000)
  local g = Memory.lookup(read_memory(), "org.example.Ghost")
  eq(g and g.slot, 2, "closed with nil workspace and monitor: recorded from its last place (desktop 12 is slot 2)")
  eq(m2.places[ghost.address], nil, "the address is forgotten after the close")
  -- never seen, nothing known: nothing recorded, no failure
  local unseen = { initial_class = "org.example.Unseen", class = "org.example.Unseen", address = "0xdead", tags = {} }
  fake.emit("window.close", unseen)
  eq(fake.pending_timers(), 0, "an unknown window with no place arms nothing")
  eq(Memory.lookup(read_memory(), "org.example.Unseen"), nil, "and records nothing")
  m2.settings.app_memory = "scene"
  m2.sync_memory()
end

-- a reload keeps the memory and the subscriptions stay single
load()
eq(Memory.lookup(_G.omaplace._m.memory, "org.example.Term") ~= nil, true, "reload keeps memory not yet on disk")
eq(#fake.handlers["window.open"], 1, "one open handler after reload")

-- a new Lua state with a bad file: empty memory and one log line
local f = io.open(state .. "/memory.lua", "w")
f:write("return { apps = ")
f:close()
printed = {}
load(true)
eq(#printed, 1, "one log line for a bad file")
eq(printed[1]:find("not used", 1, true) ~= nil, true, "bad file logged")
eq(next(_G.omaplace._m.memory.apps), nil, "empty memory")
eq(fake.pending_timers(), 0, "idle at the end")

clean()
print = real_print
os.getenv = real_getenv
print(string.format("test_glue_memory: %d checks ok", checks))
