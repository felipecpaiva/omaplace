-- Plain Lua check:  lua lua/tests/test_glue_plans.lua   (fake hl, a fixture HOME and runtime, made-up windows)
-- Desktop plans (design 14.7, 14.8): snap on open, order run > rule > plan > memory, reports, login.json, desktops().
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()
local Memory = dofile(dir .. "/../memory.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local home = dir .. "/fixtures/home-plans"
local state = home .. "/.local/state/omaplace"
local runtime = dir .. "/fixtures/runtime"
local rt = runtime .. "/omaplace"
local function clean()
  for _, n in ipairs({ "plans.lua", "memory.lua", "memory.lua.tmp" }) do os.remove(state .. "/" .. n) end
  for _, n in ipairs({ "status.json", "status.json.tmp", "plan-moves.json", "plan-moves.json.tmp", "login.json",
    "login.json.tmp", "desktops-r1.json", "desktops-r1.json.tmp" }) do
    os.remove(rt .. "/" .. n)
  end
end
clean()
local sig = "inst_a"
local real_getenv = os.getenv
os.getenv = function(k)
  if k == "HOME" then return home end
  if k == "XDG_RUNTIME_DIR" then return runtime end
  if k == "HYPRLAND_INSTANCE_SIGNATURE" then return sig end
  return real_getenv(k)
end
local printed = {}
local real_print = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
local function logged(text)
  for _, l in ipairs(printed) do
    if l:find(text, 1, true) then return true end
  end
  return false
end

local function read(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local t = f:read("a")
  f:close()
  return t
end
local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
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
    floating = false, fullscreen = 0, tags = {}, pid = 100 + next_id }
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
-- Hyprland, faked: workspaces 11..20 are on DP-2, the rest on the panel; 12 and 4 are floating desktops.
local floating_ws = { [12] = true, [4] = true, [1] = true }
local function land(w, id)
  w.workspace = { id = id, tiled_layout = "dwindle" }
  w.monitor = (id >= 11 and id <= 20) and ext or panel
  w.tags = {}
  if floating_ws[id] then w.tags[1] = FLOAT; w.floating = true end
end
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
    land(w, tonumber(a.workspace))
    moves[#moves + 1] = { ws = a.workspace, follow = a.follow }
    fake.emit("window.move_to_workspace", w)
  elseif call.name == "window.move" then
    w.at = { x = a.x, y = a.y }
  elseif call.name == "window.resize" then
    w.size = { x = a.x, y = a.y }
  elseif call.name == "window.float" then
    w.floating = a.action == "on"
  elseif call.name == "window.fullscreen" then
    w.fullscreen = a.action == "set" and 1 or 0
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
local function reset() fake.dispatched, moves = {}, {} end
local function user_move(w, id) -- a move by hand: Hyprland moves it and tells Lua
  land(w, id)
  fake.emit("window.move_to_workspace", w)
end
local function load(fresh)
  if fresh then _G.omaplace = nil end
  dofile(dir .. "/../omaplace.lua")
  _G.omaplace._m.now_ms = function() return fake.now end
end
local function moves_file() return read(rt .. "/plan-moves.json") or "" end
local function n_moves() local n = 0; for _ in moves_file():gmatch('"kind"') do n = n + 1 end; return n end

-- made-up plans, the shape js/PlansFile.js writes
local PLANS = [[
return { plans = {
  { scene = "desk-2", home_monitor = "Example Corp EX27", home_slot = 2, layout = "columns:2", mode = "floating",
    open_at_login = true, windows = {
      { class = "org.example.Editor", context = "", rect = { 0, 0, 0.5, 1 }, floating = true, snap = true },
      { class = "org.example.Chat", context = "", rect = { 0.5, 0, 0.5, 1 }, floating = true, snap = true },
      { class = "org.example.Shared", context = "", rect = { 0, 0, 1, 1 }, floating = true, snap = false },
      { class = "org.example.Notes", context = "", rect = { 0, 0, 1, 1 }, floating = true, snap = true } } },
  { scene = "desk-3", home_monitor = "", home_slot = 3, layout = "tiled", mode = "tiled", open_at_login = false,
    windows = { { class = "org.example.Term", context = "", rect = { 0, 0, 1, 1 }, floating = false, snap = true } } },
  { scene = "desk-4", home_monitor = "Example Panel", home_slot = 4, layout = "full", mode = "", open_at_login = false,
    windows = { { class = "org.example.Video", context = "", rect = { 0, 0, 1, 1 }, floating = false, snap = true,
      fullscreen = 1 } } },
  { scene = "desk-5", home_monitor = "Gone Monitor", home_slot = 5, layout = "tiled", mode = "tiled", open_at_login = false,
    windows = { { class = "org.example.Ghost", context = "", rect = { 0, 0, 1, 1 }, floating = false, snap = true } } },
} }
]]

-- no plans.lua: silent, no plan subscriptions, idle
load(true)
local M = _G.omaplace._m
eq(logged("plans"), false, "a missing plans.lua is not logged")
eq(#(fake.handlers["window.active"] or {}), 0, "no plans: no active subscription")
eq(select(2, _G.omaplace.reload_plans()), "no_file", "reload_plans without a file")

-- plans.lua written by the service, then reload_plans: subscribed, login.json written once for this instance
write(state .. "/plans.lua", PLANS)
eq(_G.omaplace.reload_plans(), true, "plans loaded")
eq(#fake.handlers["window.active"], 1, "active subscribed")
eq(#fake.handlers["window.close"], 1, "close subscribed")
local login = read(rt .. "/login.json")
eq(login, '{"instance":"inst_a","plans":["desk-2"]}\n', "login.json names the instance and the ticked plan")
eq(fake.pending_timers(), 0, "idle after loading plans")

-- a planned app opened by hand lands on its desktop (DP-2 slot 2 = 12), floating, at its zone after the settle
reset()
local ed = new_window("org.example.Editor", 3)
fake.emit("window.open", ed)
eq(ed.workspace.id, 12, "moved to the plan's desktop")
eq(moves[1].follow, false, "silent move")
eq(ed.floating, true, "floating")
eq(count("window.resize"), 0, "no rect before the settle")
fake.advance(1100)
eq(ed.at.x, 2000, "left half of DP-2: x")
eq(ed.size.x, 1000, "left half: width")
eq(ed.size.y, 1000, "full height")
fake.advance(40)
eq(fake.pending_timers(), 0, "idle after placing")
eq(n_moves(), 0, "own moves are not reported")

-- the second window of the class is left alone
reset()
local ed2 = new_window("org.example.Editor", 3)
fake.emit("window.open", ed2)
eq(ed2.workspace.id, 3, "second window not moved")
eq(#fake.dispatched, 0, "nothing dispatched for it")
eq(fake.pending_timers(), 0, "no timer for it")
close(ed2)

-- snap = false is not snapped, and app memory does not place a planned app either
Memory.update(M.memory, { kind = "placed", class = "org.example.Shared", fp = { identity = "Example Panel" }, slot = 7,
  floating = false }, "scene", 1)
reset()
local sh = new_window("org.example.Shared", 3)
fake.emit("window.open", sh)
eq(sh.workspace.id, 3, "snap = false: not moved")
eq(#fake.dispatched, 0, "and memory left it alone")
close(sh)

-- app memory is used for an app with no plan
Memory.update(M.memory, { kind = "placed", class = "org.example.Mail", fp = { identity = "Example Panel" }, slot = 7,
  floating = false }, "scene", 1)
reset()
local mail = new_window("org.example.Mail", 3)
fake.emit("window.open", mail)
eq(mail.workspace.id, 7, "memory places an unplanned app")
close(mail)
-- a plan beats memory for a planned app
Memory.update(M.memory, { kind = "placed", class = "org.example.Chat", fp = { identity = "Example Panel" }, slot = 7,
  floating = false }, "scene", 1)
reset()
local chat = new_window("org.example.Chat", 3)
fake.emit("window.open", chat)
eq(chat.workspace.id, 12, "plan beats memory")
fake.advance(1140)
eq(chat.at.x, 3000, "right half of DP-2")

-- a user rule wins: Notes has a rule (slot 2) and is in a plan; not snapped
reset()
local notes = new_window("org.example.Notes", 2)
fake.emit("window.open", notes)
eq(#fake.dispatched, 0, "rule wins: nothing dispatched")
eq(fake.pending_timers(), 0, "rule wins: no timer")
close(notes)

-- monitor missing: no snap, one log line
reset()
printed = {}
local ghost = new_window("org.example.Ghost", 3)
fake.emit("window.open", ghost)
eq(#fake.dispatched, 0, "missing monitor: not snapped")
eq(logged("desk-5: desktop not found"), true, "logged by scene and class")
close(ghost)

-- a tiled plan moves the workspace only (focused monitor, slot 3 = 3; opened on 6)
reset()
local term = new_window("org.example.Term", 6)
fake.emit("window.open", term)
eq(term.workspace.id, 3, "tiled plan: moved")
fake.advance(1200)
eq(count("window.resize") + count("window.float"), 0, "tiled plan: no rect, no float")
close(term)

-- full plan: moved, then maximized (fullscreen state 1)
reset()
local vid = new_window("org.example.Video", 3)
fake.emit("window.open", vid)
eq(vid.workspace.id, 4, "full plan: moved")
eq(count("window.fullscreen"), 0, "maximized only after the settle")
fake.advance(1100)
local fs
for _, c in ipairs(fake.dispatched) do
  if c.name == "window.fullscreen" then fs = c.args end
end
eq(fs and fs.mode, "maximized", "fullscreen mode maximized")
eq(fs and fs.action, "set", "set, not toggle")
eq(vid.fullscreen, 1, "window maximized")
close(vid)

-- a run ticket wins over the plan
_G.omaplace.open({ run = "p1", target = { fp = {}, slot = 1 }, existing = "new", layout = "floating", windows = {
  { class = "org.example.Term", order = 1, rect = { 0, 0, 1, 1 }, mode = "launch", launch = { "term" } } } })
fake.advance(150)
local term2 = new_window("org.example.Term", 6)
fake.emit("window.open", term2)
eq(term2.workspace.id, 1, "run ticket wins")
fake.advance(3000)
eq(_G.omaplace.status().state, "done", "run done")
close(term2)
eq(n_moves(), 0, "a run's moves are not plan reports")

-- desktop move by hand: reported once, again only after coming back
reset()
user_move(ed, 13)
eq(n_moves(), 1, "desktop move reported")
local mf = moves_file()
eq(mf:find('"kind":"desktop"', 1, true) ~= nil, true, "kind desktop")
eq(mf:find('"scene":"desk-2"', 1, true) ~= nil, true, "scene named")
eq(mf:find('"window":1', 1, true) ~= nil, true, "window index")
eq(mf:find('"identity":"Example Corp EX27"', 1, true) ~= nil, true, "target monitor identity")
eq(mf:find('"slot":3', 1, true) ~= nil, true, "target slot")
eq(mf:find("Made up title", 1, true), nil, "no title in the report")
user_move(ed, 14)
eq(n_moves(), 1, "second move away not reported again")
user_move(ed, 12)
eq(n_moves(), 1, "coming back is not a report")
user_move(ed, 15)
eq(n_moves(), 2, "after coming back, a new move is reported")
user_move(ed, 12)

-- zone drift (D23): checked when focus leaves the window
local other = new_window("org.example.Other", 12)
fake.emit("window.active", ed)
ed.at = { x = 2010, y = 5 } -- 0.5 and 0.5 percent: within 2 percent
fake.emit("window.active", other)
eq(n_moves(), 2, "within 2 percent: no report")
fake.emit("window.active", ed)
ed.at = { x = 2100, y = 0 } -- 5 percent
fake.emit("window.active", other)
eq(n_moves(), 3, "drift reported on focus loss")
eq(moves_file():find('"kind":"zone"', 1, true) ~= nil, true, "kind zone")
eq(moves_file():find('"rect":[0.05,0,0.5,1]', 1, true) ~= nil, true, "the new rect as fractions")
fake.emit("window.active", ed)
fake.emit("window.active", other)
eq(n_moves(), 3, "once per window")
ed.at = { x = 2000, y = 0 }
fake.emit("window.active", ed)
fake.emit("window.active", other)
eq(n_moves(), 3, "back in the zone: nothing")
ed.at = { x = 2300, y = 0 }
fake.emit("window.active", ed)
fake.emit("window.active", other)
eq(n_moves(), 4, "drift again after returning: reported again")
fake.emit("window.active", nil) -- focus to nothing: fine
eq(fake.pending_timers(), 0, "reports arm no timer")

-- closing forgets the window
close(ed)
eq(M.snapped[ed.address], nil, "closed: forgotten")

-- a reload keeps reports and does not write login.json again
write(rt .. "/login.json", '{"instance":"inst_a","plans":["desk-2"],"marker":1}\n')
load()
eq(#fake.handlers["window.active"], 1, "one active handler after a reload")
eq(#fake.handlers["window.open"], 1, "one open handler after a reload")
eq(read(rt .. "/login.json"):find("marker", 1, true) ~= nil, true, "reload: login.json not written again")
eq(_G.omaplace.reload_config(), true, "reload_config")
eq(read(rt .. "/login.json"):find("marker", 1, true) ~= nil, true, "reload_config: not written again")
-- a new Lua state in the same instance reads the file and leaves it
load(true)
eq(read(rt .. "/login.json"):find("marker", 1, true) ~= nil, true, "same instance, new Lua state: not written")
-- a new instance (a new login) writes it again
sig = "inst_b"
load(true)
eq(read(rt .. "/login.json"), '{"instance":"inst_b","plans":["desk-2"]}\n', "new login: written for the new instance")
local seq_before = _G.omaplace._m.plan_moves.seq
eq(seq_before, 0, "a new Lua state starts the move ids again")

-- bad or oversize plans.lua: ignored with a log line, never raising; the plans loaded before stay
for _, bad in ipairs({ "return { plans = ", "return 5", "while true do end", "return { nope = 1 }",
  "return {} --" .. string.rep("x", 1048577), "error('boom')" }) do
  write(state .. "/plans.lua", bad)
  printed = {}
  local ok, why = _G.omaplace.reload_plans()
  eq(ok, nil, "bad plans refused")
  eq(why, "bad_plans", "reason bad_plans")
  eq(#printed, 1, "one log line")
  eq(printed[1]:find("plans.lua", 1, true) ~= nil, true, "the line names plans.lua")
end
eq(#_G.omaplace._m.plans.plans, 4, "plans loaded before are kept")
-- a fresh load with a bad file: no plans, no raise
load(true)
eq(_G.omaplace._m.plans, nil, "fresh load with a bad file: no plans")
eq(#_G.omaplace._m.plan_subs, 0, "and no subscriptions")
write(state .. "/plans.lua", PLANS)
_G.omaplace.reload_plans()

-- handlers never raise
local m2 = _G.omaplace._m
m2.snapped["0xbad"] = { scene = "desk-2", window = 1, class = "x", context = "", ws = 12, rect = { 0, 0, 1, 1 },
  floating = true, placed = true }
m2.last_active = "0xbad"
local real_get = fake.hl.get_windows
fake.hl.get_windows = function() error("boom") end
printed = {}
fake.emit("window.active", { address = "0x1" })
fake.emit("window.close", {})
fake.emit("window.move_to_workspace", { address = "0xbad" })
fake.emit("window.open", { initial_class = "org.example.Editor", address = "0xnew", workspace = { id = 3 } })
fake.hl.get_windows = real_get
eq(logged("plan handler failed"), true, "a failing plan handler is logged")
eq(logged("window.open handler failed"), true, "a failing open is logged")
fake.emit("window.open", "not a window")
fake.emit("window.active", 42)

-- desktops(): every monitor's slots, also as a file for the service
local d = _G.omaplace.desktops()
eq(#d.monitors, 2, "two monitors")
eq(d.monitors[1].name, "DP-2", "by connector name")
eq(d.monitors[1].identity, "Example Corp EX27", "identity")
eq(d.monitors[1].slots[2].workspace, 12, "DP-2 slot 2 is 12")
eq(d.monitors[2].focused, true, "panel focused")
eq(_G.omaplace.desktops("r1") ~= nil, true, "desktops with a request id")
eq(read(rt .. "/desktops-r1.json"):find('"workspace":12', 1, true) ~= nil, true, "answer file written")
eq(select(2, _G.omaplace.desktops("../x")), "bad_req", "bad request id refused")

clean()
print = real_print
os.getenv = real_getenv
print(string.format("test_glue_plans: %d checks ok", checks))
