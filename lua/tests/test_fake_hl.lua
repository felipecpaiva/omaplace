-- Plain Lua check:  lua lua/tests/test_fake_hl.lua
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()
local hl = fake.hl

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- events
local seen = {}
hl.on("monitor.added", function(m) seen[#seen + 1] = "a:" .. m end)
hl.on("monitor.added", function(m) seen[#seen + 1] = "b:" .. m end)
fake.emit("monitor.added", "x")
fake.emit("nobody.listens")
eq(table.concat(seen, ","), "a:x,b:x", "handlers run in order")

-- window rules: stored by name, replaced in place, disabled by enabled = false
hl.window_rule({ name = "one", match = { class = "a" }, workspace = 1 })
hl.window_rule({ name = "two", match = { class = "b" }, workspace = 2 })
hl.window_rule({ name = "one", match = { class = "a" }, workspace = 5 })
eq(fake.rules.one.workspace, 5, "replaced")
eq(#fake.rule_order, 2, "no duplicate")
eq(fake.active_rules()[1].workspace, 5, "kept its place")
hl.window_rule({ name = "two", enabled = false })
eq(#fake.active_rules(), 1, "disabled rule is off")
eq(pcall(hl.window_rule, { workspace = 1 }), false, "a rule needs a name")

-- monitors, windows, exec, dispatch
fake.set_monitors({ { name = "eDP-1" }, { name = "DP-2" } })
fake.set_windows({ { class = "w" } })
eq(#hl.get_monitors(), 2, "monitors")
eq(hl.get_windows()[1].class, "w", "windows")
hl.exec_cmd("echo hi")
eq(fake.exec_log[1], "echo hi", "exec recorded")
hl.dispatch(hl.dsp.workspace.change_id({ workspace = "3", id = 13 }))
eq(fake.dsp_calls[1].name, "workspace.change_id", "dsp name recorded")
eq(fake.dsp_calls[1].args.id, 13, "dsp args recorded")
eq(fake.dispatched[1].name, "workspace.change_id", "dispatch recorded")

-- timers: one shot, in time order, cancellable, nested timers fire when due
local order = {}
hl.timer(300, function() order[#order + 1] = "c" end)
hl.timer(100, function()
  order[#order + 1] = "a"
  hl.timer(100, function() order[#order + 1] = "nested" end)
end)
local gone = hl.timer(200, function() order[#order + 1] = "gone" end)
gone.cancel()
fake.advance(99)
eq(#order, 0, "not due yet")
fake.advance(1)
eq(table.concat(order, ","), "a", "first fires at 100")
fake.advance(500)
eq(table.concat(order, ","), "a,nested,c", "time order, nested included, cancelled one silent")
fake.advance(1000)
eq(#order, 3, "one shot")

-- fake Omarchy workspaces: block per monitor * 10 + slot
eq(fake.o.workspaces.workspace_id({ name = "eDP-1" }, 4), 4, "first monitor")
eq(fake.o.workspaces.workspace_id({ name = "DP-2" }, 4), 14, "second monitor")

print("test_fake_hl ok (" .. checks .. " checks)")
