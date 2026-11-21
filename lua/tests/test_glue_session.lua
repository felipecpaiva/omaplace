-- Plain Lua check:  lua lua/tests/test_glue_session.lua   (fake hl, a fixture HOME and runtime, made-up windows)
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- The state folder is a fixture in the repo (its .gitignore keeps what the test writes out of git).
local home = dir .. "/fixtures/home-session"
local state = home .. "/.local/state/omaplace"
local names = { "sessions.json" }
for i = 1, 8 do names[#names + 1] = "session-inst" .. i .. ".json" end
local function clean()
  for _, n in ipairs(names) do os.remove(state .. "/" .. n); os.remove(state .. "/" .. n .. ".tmp") end
end
clean()

local sig = "inst1"
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "HOME" then return home end
  if k == "XDG_RUNTIME_DIR" then return dir .. "/fixtures/runtime" end
  if k == "HYPRLAND_INSTANCE_SIGNATURE" then return sig end
  return real_getenv(k)
end
local printed = {}
local real_print = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local function read(name)
  local f = io.open(state .. "/" .. name, "r")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t
end

_G.hl, _G.o = fake.hl, fake.o
local panel = { name = "eDP-1", description = "Example Panel", make = "Example Corp", model = "EX1", width = 2000,
  height = 1000, scale = 1, transform = 0, x = 0, y = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 },
  focused = true, active_workspace = { id = 1 } }
fake.set_monitors({ panel })
local function win(cls, ws)
  return { initial_class = cls, class = cls, title = "Made up title", address = "0x1", workspace = { id = ws },
    monitor = panel, at = { x = 0, y = 0 }, size = { x = 1000, y = 1000 }, floating = false, fullscreen = 0,
    tags = {}, pid = 4242 }
end
fake.set_windows({ win("org.example.Editor", 1), win("org.example.Mail", 2) })

local function load()
  dofile(dir .. "/../omaplace.lua")
  _G.omaplace._m.now_ms = function() return fake.now end
end
local function count(event) return #(fake.handlers[event] or {}) end
load()

-- load: subscribed, nothing armed, the state folder already exists so no mkdir
eq(count("window.close"), 1, "close subscribed")
eq(count("window.active"), 1, "active subscribed")
eq(count("window.move_to_workspace"), 1, "move subscribed")
eq(count("monitor.layout_changed"), 2, "rule and session handlers")
eq(fake.pending_timers(), 0, "idle after load")
eq(#fake.exec_log, 0, "no mkdir for an existing folder")

-- five events give one timer and one write, 15 s after the last
for _, e in ipairs({ "window.open", "window.active", "window.move_to_workspace", "window.active", "monitor.added" }) do
  fake.emit(e)
  fake.advance(1000)
end
eq(fake.pending_timers(), 1, "one timer at most")
fake.advance(13999)
eq(read("session-inst1.json"), nil, "not before the debounce")
fake.advance(1)
local text = read("session-inst1.json")
eq(text ~= nil, true, "written after 15 s")
eq(fake.pending_timers(), 0, "nothing armed after the write")
eq(text:find('"pid"', 1, true), nil, "no pid key")
eq(text:find('"title"', 1, true), nil, "no title key")
eq(text:find("Made up title", 1, true), nil, "no title text")
eq(text:find('"kind":"session"', 1, true) ~= nil, true, "kind session")
eq(text:find("org.example.Mail", 1, true) ~= nil, true, "all workspaces, not only the focused one")
local idx = _G.omaplace.sessions()
eq(#idx, 1, "index has this instance")
eq(idx[1].instance, "inst1", "index name")
eq(type(idx[1].saved_at), "number", "index saved_at")

-- a close burst writes nothing for 60 s, even with a write armed before it
os.remove(state .. "/session-inst1.json")
fake.emit("window.open")
fake.advance(10000)
fake.emit("window.close"); fake.emit("window.active")
fake.emit("window.close"); fake.emit("window.active")
fake.emit("window.close")
eq(fake.pending_timers(), 0, "the freeze switches the armed timer off")
eq(_G.omaplace.session_save_now(), nil, "save now refuses in a freeze")
fake.emit("window.active") -- focus moves on while windows close: scheduled at the end of the freeze
fake.advance(59999)
eq(read("session-inst1.json"), nil, "nothing written during the freeze")
-- close-all: the desktop is empty when the freeze ends, so the last good file is kept
fake.set_windows({})
fake.advance(1)
eq(read("session-inst1.json"), nil, "an empty desktop is never written")
fake.set_windows({ win("org.example.Editor", 1) })

-- save now ignores the debounce
fake.emit("window.open")
eq(_G.omaplace.session_save_now(), true, "save now writes")
eq(read("session-inst1.json") ~= nil, true, "file there at once")
eq(fake.pending_timers(), 0, "save now disarms the pending write")

-- a second instance (a new boot) writes its own file and goes first in the index
local first = read("session-inst1.json")
for i = 2, 7 do
  sig = "inst" .. i
  load()
  eq(_G.omaplace.session_save_now(), true, "instance " .. i .. " saved")
end
eq(read("session-inst1.json"), nil, "instance 1 pruned (keep 5)")
eq(read("session-inst2.json"), nil, "instance 2 pruned")
eq(read("session-inst3.json") ~= nil, true, "instance 3 kept")
idx = _G.omaplace.sessions()
eq(#idx, 5, "index keeps 5")
eq(idx[1].instance, "inst7", "newest first")
eq(idx[5].instance, "inst3", "oldest kept last")
eq(first ~= nil, true, "instance 1 had a file before the prune")

-- a reload of the same instance does not add it twice, and does not overwrite another instance's file
local inst6 = read("session-inst6.json")
load()
fake.set_windows({ win("org.example.Notes", 3) })
_G.omaplace.session_save_now()
eq(#_G.omaplace.sessions(), 5, "no duplicate entry")
eq(_G.omaplace.sessions()[1].instance, "inst7", "still first")
eq(read("session-inst6.json"), inst6, "instance 6 file untouched")

-- a reload leaves one session handler per event
load()
eq(count("window.close"), 1, "no double register")

-- an odd signature is made safe for a file name
sig = "a/../b c"
load()
_G.omaplace.session_save_now()
eq(read("session-a____b_c.json") ~= nil, true, "signature sanitised")
os.remove(state .. "/session-a____b_c.json")
names[#names + 1] = "session-a____b_c.json"

-- session = "off" registers nothing and arms nothing
sig = "inst8"
home = dir .. "/fixtures/home-session-off"
eq(_G.omaplace.reload_config(), true, "reload with session off")
eq(count("window.close"), 0, "unsubscribed on reload")
fake.emit("window.open")
eq(fake.pending_timers(), 0, "nothing armed")
load()
eq(count("window.close"), 0, "a fresh load with session off registers nothing")
eq(count("window.active"), 0, "no active handler")
home = dir .. "/fixtures/home-session"
eq(_G.omaplace.reload_config(), true, "reload with session on again")
eq(count("window.close"), 1, "subscribed again")

-- handlers never raise
_G.omaplace._m.on_session_event = function() error("boom") end
printed = {}
fake.emit("window.open")
eq(#printed >= 1 and printed[1]:find("session handler failed", 1, true) ~= nil, true, "error caught and logged")

clean()
print = real_print
os.getenv = real_getenv
print(string.format("test_glue_session: %d checks ok", checks))
