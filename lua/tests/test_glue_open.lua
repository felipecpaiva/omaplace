-- Plain Lua check:  lua lua/tests/test_glue_open.lua   (fake hl, a fixture HOME, a fixture runtime folder)
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()
local Capture = dofile(dir .. "/../capture.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- The runtime folder is a fixture in the repo (its .gitignore keeps what the test writes out of git).
local runtime = dir .. "/fixtures/runtime"
local written = { "capture-q1.json", "capture-q2.json", "status.json", "status.json.tmp", "plan-r11.lua", "plan-bad.lua",
  "plan-evil.lua", "plan-num.lua", "plan-bin.lua" }
local function clean()
  for _, name in ipairs(written) do os.remove(runtime .. "/omaplace/" .. name) end
end
clean() -- a failed earlier run may have left files
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "HOME" then return dir .. "/fixtures/home-none" end
  if k == "XDG_RUNTIME_DIR" then return runtime end
  return real_getenv(k)
end
local printed = {}
local real_print = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

local function read(name)
  local f = io.open(runtime .. "/omaplace/" .. name, "r")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t
end

_G.hl, _G.o = fake.hl, fake.o
local function mon(name, desc, x, ws, focused)
  return { name = name, description = desc, make = "Example Corp", model = desc, width = 2000, height = 1000, scale = 1,
    transform = 0, x = x, y = 0, reserved = { top = 0, bottom = 0, left = 0, right = 0 }, focused = focused or false,
    active_workspace = { id = ws } }
end
local panel, ext = mon("eDP-1", "Example Panel", 0, 1, true), mon("DP-2", "Example Corp EX27", 2000, 11)
fake.set_monitors({ panel, ext })

-- Hyprland, faked: dispatches change the fake windows the way the real ones would.
local next_id = 0
local function new_window(cls, ws, extra)
  next_id = next_id + 1
  local w = { initial_class = cls, class = cls, title = "Made up title", address = "0x" .. next_id, stable_id = next_id,
    workspace = { id = ws }, monitor = panel, at = { x = 10, y = 10 }, size = { x = 300, y = 200 }, floating = true,
    fullscreen = 0, tags = {}, pid = 100 + next_id }
  for k, v in pairs(extra or {}) do w[k] = v end
  fake.windows[#fake.windows + 1] = w
  return w
end
local moves, focus = {}, {}
fake.hl.dispatch = function(call)
  fake.dispatched[#fake.dispatched + 1] = call
  local a = call.args or {}
  local w
  for _, x in ipairs(fake.windows) do
    if "address:" .. x.address == a.window then w = x end
  end
  if call.name == "window.swap" then
    local t
    for _, x in ipairs(fake.windows) do
      if "address:" .. x.address == a.target then t = x end
    end
    w.at, t.at = t.at, w.at
    return
  end
  if call.name == "window.move" and a.workspace then
    w.workspace = { id = tonumber(a.workspace) }
    moves[#moves + 1] = { ws = a.workspace, follow = a.follow }
  elseif call.name == "window.move" then
    w.at = { x = a.x, y = a.y }
  elseif call.name == "window.resize" then
    if not w.refuse then w.size = { x = a.x, y = a.y } end
  elseif call.name == "window.tag" then
    local sign, name = a.tag:sub(1, 1), a.tag:sub(2)
    for i = #w.tags, 1, -1 do
      if w.tags[i] == name then table.remove(w.tags, i) end
    end
    if sign == "+" then w.tags[#w.tags + 1] = name end
  elseif call.name == "focus" then
    focus[#focus + 1] = a.workspace
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
local function load()
  dofile(dir .. "/../omaplace.lua")
  _G.omaplace._m.now_ms = function() return fake.now end
end
load()

-- idle: no run, no timers; a new window is ignored at once
eq(type(_G.omaplace.open), "function", "open in the api")
eq(fake.pending_timers(), 0, "idle after load")
fake.emit("window.open", new_window("org.example.Stray", 1))
eq(fake.pending_timers(), 0, "idle after a window opens")
eq(#fake.dispatched, 0, "nothing dispatched")
eq(_G.omaplace.status().state, "idle", "status idle")
fake.windows = {}

-- capture: the file has classes and places, never a title or address
local cw = new_window("org.example.Editor", 1, { at = { x = 0, y = 0 }, size = { x = 1000, y = 1000 },
  tags = { "omarchy-floating-workspace" } })
new_window("org.example.Far", 11, { monitor = ext })
eq(_G.omaplace.capture("q1", "focused"), true, "capture ok")
local cap = read("capture-q1.json")
eq(cap ~= nil, true, "capture file written")
eq(cap:find("title", 1, true), nil, "no title field")
eq(cap:find("Made up", 1, true), nil, "no title text")
eq(cap:find("0x", 1, true), nil, "no address")
eq(cap:find('"class":"org.example.Editor"', 1, true) ~= nil, true, "class there")
eq(cap:find("org.example.Far", 1, true), nil, "focused scope only")
eq(cap:find('"rect":[0,0,0.5,1]', 1, true) ~= nil, true, "rect fraction")
eq(read("capture-q1.json.tmp"), nil, "no temp file left")
_G.omaplace.capture("q2", "all")
eq(read("capture-q2.json"):find("org.example.Far", 1, true) ~= nil, true, "scope all")
eq(_G.omaplace.capture("../x", "all"), nil, "bad request id refused")
eq(fake.pending_timers(), 0, "capture arms nothing")

-- move mode on a floating desktop: the open window is moved to the target, then placed at its rect after the settle
cw.workspace = { id = 3 }
local id = _G.omaplace.open({ run = "r1", target = { fp = {}, slot = 0 }, existing = "move", layout = "floating",
  windows = { { class = "org.example.Editor", order = 1, rect = { 0.5, 0, 0.5, 1 }, floating = true, mode = "launch",
    launch = { "uwsm-app", "--", "org.example.Editor.desktop" } } } })
eq(id, "r1", "run id")
eq(#fake.exec_log, 0, "nothing launched: the window was moved")
eq(cw.workspace.id, 1, "moved to the current desktop")
eq(moves[#moves].follow, false, "silent move")
eq(has(cw, "omaplace-slot=r1/1"), true, "slot tag")
eq(read("status.json"):find('"state":"moved"', 1, true) ~= nil, true, "status: moved")
eq(read("status.json"):find('"state":"running"', 1, true) ~= nil, true, "status: running while the put waits")
fake.advance(1099)
eq(count("window.resize"), 0, "no put before the settle")
fake.advance(1)
eq(count("window.resize"), 1, "resize after the settle")
eq(cw.at.x, 1000, "moved to x")
eq(cw.size.x, 1000, "sized")
fake.advance(40)
eq(read("status.json"):find('"state":"done"', 1, true) ~= nil, true, "status: done")
eq(fake.pending_timers(), 0, "idle after the run")
eq(_G.omaplace.status().state, "done", "status() matches")

-- launch mode with rules: rule apps go to their desktops and the focus follows the last one
fake.windows, moves, focus, fake.dispatched = {}, {}, {}, {}
id = _G.omaplace.open({ run = "r2", target = { fp = {}, slot = 0 }, existing = "new", layout = "floating", windows = {
  { class = "org.example.Mail", order = 1, rect = { 0, 0, 0.5, 1 }, mode = "launch", launch = { "uwsm-app", "--", "org.example.Mail.desktop" } },
  { class = "org.example.Notes", order = 2, rect = { 0.5, 0, 0.5, 1 }, mode = "launch", launch = { "notes", "it's" },
    desktop = { monitor = "Example Corp EX27", slot = 2, follow = false } },
  { class = "org.example.Chat", order = 3, rect = { 0, 0, 1, 1 }, mode = "launch", launch = { "chat" },
    desktop = { monitor = "", slot = 4 } },
} })
eq(id, "r2", "second run starts")
eq(fake.exec_log[1], "'uwsm-app' '--' 'org.example.Mail.desktop'", "launch argv quoted")
eq(select(2, _G.omaplace.open({ run = "r3", windows = {} })), "busy", "second open is busy")
fake.advance(150)
eq(fake.exec_log[2], "'notes' 'it'\\''s'", "second tick launches the next")
fake.advance(150)
eq(#fake.exec_log, 3, "third tick")
fake.advance(150)
eq(#fake.exec_log, 3, "nothing more to launch")
local mail = new_window("org.example.Mail", 1)
fake.emit("window.open", mail)
local notes = new_window("org.example.Notes", 1)
fake.emit("window.open", notes)
local chat = new_window("org.example.Chat", 1)
fake.emit("window.open", chat)
eq(mail.workspace.id, 1, "scene app stays on the target")
eq(notes.workspace.id, 12, "rule app on its monitor and slot")
eq(chat.workspace.id, 4, "rule app on the focused monitor's slot 4")
eq(moves[#moves].ws, "4", "last move is the last rule app")
eq(moves[#moves].follow, true, "focus follows the last rule app")
fake.emit("window.open", mail) -- the same window again (a second event) is not claimed twice
fake.advance(1100)
fake.advance(40)
eq(mail.size.x, 1000, "scene app placed at its rect")
eq(notes.size.x, 300, "no rect on a desktop that is not floating")
eq(_G.omaplace.status().state, "done", "run done")
eq(focus[#focus], "4", "view ends on the last rule desktop")
local st = read("status.json")
eq(st:find('"state":"placed"', 1, true) ~= nil, true, "status: placed")
eq(st:find("Made up", 1, true), nil, "status has no title")
eq(fake.pending_timers(), 0, "idle again")

-- expiry: an app that never opens a window is reported not_reopened, the run is partial
fake.windows = {}
_G.omaplace.open({ run = "r4", target = { fp = {}, slot = 0 }, layout = "floating",
  windows = { { class = "org.example.Single", mode = "launch", launch = { "single" } } } })
eq(read("status.json"):find('"since":', 1, true) ~= nil, true, "waiting item has since")
fake.advance(19999)
eq(_G.omaplace.status().state, "running", "still waiting")
fake.advance(1)
eq(_G.omaplace.status().items[1].state, "not_reopened", "expired")
eq(_G.omaplace.status().state, "partial", "partial")
eq(fake.pending_timers(), 0, "idle")

-- tiled: one at a time in order, no rects
fake.windows, fake.exec_log, fake.dispatched = {}, {}, {}
_G.omaplace.open({ run = "r5", target = { fp = {}, slot = 0 }, layout = "tiled", existing = "new", windows = {
  { class = "a.A", order = 1, rect = { 0, 0, 0.5, 1 }, mode = "launch", launch = { "a" } },
  { class = "b.B", order = 2, rect = { 0.5, 0, 0.5, 1 }, mode = "launch", launch = { "b" } },
} })
fake.advance(1000)
eq(#fake.exec_log, 1, "second waits for the first")
fake.emit("window.open", new_window("b.B", 1))
eq(#fake.exec_log, 1, "an early b window does not unblock")
fake.emit("window.open", new_window("a.A", 1, { floating = false }))
eq(#fake.exec_log, 2, "first claimed, second launched")
fake.emit("window.open", new_window("b.B", 1, { floating = false }))
fake.advance(2000)
eq(count("window.resize"), 0, "no rects on a tiled desktop")
eq(_G.omaplace.status().state, "done", "tiled run done")

-- two Chrome profiles to two desktops; an untagged Chrome window is left alone
fake.windows, fake.exec_log, moves = {}, {}, {}
local stray = new_window("google-chrome", 5)
_G.omaplace.open({ run = "r6", target = { fp = {}, slot = 0 }, layout = "floating", existing = "move", windows = {
  { class = "google-chrome", context = "Default", mode = "launch", launch = { "google-chrome", "--profile-directory=Default" },
    desktop = { monitor = "", slot = 2 } },
  { class = "google-chrome", context = "Profile 1", mode = "launch", launch = { "google-chrome", "--profile-directory=Profile 1" },
    desktop = { monitor = "", slot = 3 } },
} })
eq(stray.workspace.id, 5, "untagged Chrome window not moved")
eq(#fake.exec_log, 1, "one profile at a time")
fake.advance(500)
local d1 = new_window("google-chrome", 1)
fake.emit("window.open", d1)
fake.advance(1999)
eq(#fake.exec_log, 1, "class not quiet yet")
fake.advance(1)
eq(fake.exec_log[2], "'google-chrome' '--profile-directory=Profile 1'", "second profile after the quiet window")
local p1 = new_window("google-chrome", 1)
fake.emit("window.open", p1)
eq(d1.workspace.id, 2, "Default profile on its desktop")
eq(p1.workspace.id, 3, "Profile 1 on its desktop")
eq(has(p1, "omaplace-ctx=" .. Capture.ctx_hex("Profile 1")), true, "context tag")
fake.advance(2000)
eq(_G.omaplace.status().state, "done", "profiles run done")

-- tiled reorder (S8): windows that landed 1, 3, 2 are swapped into order; then the view goes back to the target
fake.windows, fake.exec_log, fake.dispatched, focus = {}, {}, {}, {}
_G.omaplace.open({ run = "r6b", target = { fp = {}, slot = 0 }, layout = "tiled", existing = "new", windows = {
  { class = "t.One", order = 1, mode = "launch", launch = { "one" } },
  { class = "t.Two", order = 2, mode = "launch", launch = { "two" } },
  { class = "t.Three", order = 3, mode = "launch", launch = { "three" } },
} })
local one = new_window("t.One", 1, { floating = false, at = { x = 0, y = 0 } })
fake.emit("window.open", one)
local two = new_window("t.Two", 1, { floating = false, at = { x = 1000, y = 0 } })
fake.emit("window.open", two)
local three = new_window("t.Three", 1, { floating = false, at = { x = 500, y = 0 } })
fake.emit("window.open", three)
eq(count("window.swap"), 1, "one swap")
eq(two.at.x < three.at.x, true, "two now left of three")
eq(focus[#focus], "1", "view back on the target at the end")
eq(_G.omaplace.status().state, "done", "reordered run done")

-- the target shows tiled windows: the run is sequential even if the plan says floating
fake.windows, fake.exec_log = {}, {}
new_window("t.Old", 1, { floating = false })
_G.omaplace.open({ run = "r6c", target = { fp = {}, slot = 0 }, layout = "floating", existing = "new", windows = {
  { class = "t.A", mode = "launch", launch = { "a" } }, { class = "t.B", mode = "launch", launch = { "b" } },
} })
fake.advance(500)
eq(#fake.exec_log, 1, "tiled target seen: one at a time")
fake.advance(20000)
fake.advance(20000)
eq(_G.omaplace.status().state, "partial", "both expired")

-- a moved window that is gone before its turn fails, the run is partial
fake.windows = {}
local soon_gone = new_window("t.Gone", 3, { floating = false })
local blocker = new_window("t.First", 3, { floating = false })
fake.exec_log = {}
_G.omaplace.open({ run = "r6d", target = { fp = {}, slot = 0 }, layout = "tiled", existing = "move", windows = {
  { class = "t.Launch", order = 1, mode = "launch", launch = { "l" } },
  { class = "t.Gone", order = 2, mode = "launch", launch = { "g" } },
} })
eq(blocker.workspace.id, 3, "unrelated window untouched")
fake.windows = { blocker }
fake.emit("window.open", new_window("t.Launch", 1, { floating = false }))
eq(_G.omaplace.status().items[2].state, "failed", "gone window failed")
eq(_G.omaplace.status().items[2].reason, "gone", "reason gone")
eq(_G.omaplace.status().state, "partial", "partial")
eq(soon_gone.workspace.id, 3, "never moved")

-- an app that refuses its size is reported, not shown as placed
fake.windows = {}
_G.omaplace.open({ run = "r6e", target = { fp = {}, slot = 0 }, layout = "floating", existing = "new", windows = {
  { class = "t.Stiff", rect = { 0, 0, 0.5, 1 }, mode = "launch", launch = { "stiff" } } } })
fake.emit("window.open", new_window("t.Stiff", 1, { refuse = true, tags = { "omarchy-floating-workspace" } }))
fake.advance(1100 + 40 * 3)
eq(_G.omaplace.status().items[1].state, "failed", "size refused is failed")
eq(_G.omaplace.status().items[1].reason, "size_refused", "reason")
eq(fake.pending_timers(), 0, "idle")

-- a dispatch that raises once does not leave the run live (later opens are not busy)
fake.windows = {}
local real_dispatch = fake.hl.dispatch
fake.hl.dispatch = function() fake.hl.dispatch = real_dispatch; error("rejected") end
_G.omaplace.open({ run = "r6f", target = { fp = {}, slot = 0 }, layout = "floating", existing = "new", windows = {
  { class = "t.Boom", rect = { 0, 0, 1, 1 }, mode = "launch", launch = { "boom" } } } })
fake.emit("window.open", new_window("t.Boom", 1))
eq(_G.omaplace.status().items[1].state, "failed", "raise fails the slot")
eq(_G.omaplace.status().state, "partial", "run ended")
eq(_G.omaplace.open({ run = "r6g", windows = {} }), "r6g", "not stuck busy")

-- interrupted: a reload during a run stops it and says so
fake.windows, fake.exec_log = {}, {}
_G.omaplace.open({ run = "r7", target = { fp = {}, slot = 0 }, layout = "floating",
  windows = { { class = "org.example.Late", mode = "launch", launch = { "late" } } } })
load()
eq(read("status.json"):find('"state":"interrupted"', 1, true) ~= nil, true, "status file interrupted")
eq(_G.omaplace.status().state, "interrupted", "status() interrupted")
eq(fake.pending_timers(), 0, "old run timer switched off")
fake.emit("window.open", new_window("org.example.Late", 1))
eq(#fake.handlers["window.open"], 1, "one window.open handler after reload")
eq(fake.pending_timers(), 0, "no run, nothing armed")
eq(select(1, _G.omaplace.open({ run = "r8", windows = {} })), "r8", "a new run may start after the reload")

-- a stale running status from a Lua state that is gone
local f = io.open(runtime .. "/omaplace/status.json", "w")
f:write('{"items":[],"run":"r9","state":"running"}\n')
f:close()
_G.omaplace = nil
load()
eq(read("status.json"), '{"items":[],"run":"r9","state":"interrupted"}\n', "stale run marked interrupted on load")

-- bad plans
eq(select(2, _G.omaplace.open(nil)), "bad_plan", "nil plan")
eq(select(2, _G.omaplace.open({ run = "a b", windows = {} })), "bad_plan", "bad run id")
eq(_G.omaplace.open({ run = "r10", target = { fp = { identity = "Missing" } }, windows = {} }), "r10",
  "unknown monitor falls back to focused (missing_monitor_scene = focused)")

-- open_file: the service writes big plans to a file (a hyprctl argument is capped at 128 kB)
local function plan_file(name, text)
  local path = runtime .. "/omaplace/" .. name
  local pf = io.open(path, "w")
  pf:write(text)
  pf:close()
  return path
end
local good = plan_file("plan-r11.lua", 'return { run = "r11", target = { fp = {}, slot = 0 }, layout = "floating", windows = {} }')
eq(_G.omaplace.open_file(good), "r11", "good plan file")
eq(select(2, _G.omaplace.open_file(runtime .. "/omaplace/plan-none.lua")), "no_file", "missing file")
local bad = plan_file("plan-bad.lua", "return { run = ")
eq(select(2, _G.omaplace.open_file(bad)), "bad_plan", "syntax error")
local evil = plan_file("plan-evil.lua", 'os.execute("true") return { run = "r12", windows = {} }')
eq(select(2, _G.omaplace.open_file(evil)), "bad_plan", "no os in the plan environment")
local num = plan_file("plan-num.lua", "return 42")
eq(select(2, _G.omaplace.open_file(num)), "bad_plan", "not a table")
local binary = plan_file("plan-bin.lua", string.dump(function() return {} end))
eq(select(2, _G.omaplace.open_file(binary)), "bad_plan", "binary chunk refused")
eq(select(2, _G.omaplace.open_file("/etc/hostname")), "bad_path", "only plan files in the runtime folder")
eq(select(2, _G.omaplace.open_file(runtime .. "/omaplace/../omaplace/plan-r11.lua")), "bad_path", "no dot dot")

clean()
print = real_print
os.getenv = real_getenv
print(string.format("test_glue_open: %d checks ok", checks))
