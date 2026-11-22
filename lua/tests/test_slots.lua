-- Plain Lua check:  lua lua/tests/test_slots.lua
local dir = arg[0]:match("^(.*)/") or "."
local Slots = dofile(dir .. "/../slots.lua")
local fake = dofile(dir .. "/fake_hl.lua").new()

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

fake.set_monitors({ { name = "eDP-1" }, { name = "DP-2" } })
local pm = Slots.with(fake.o)
eq(pm.mode(), "per_monitor", "mode with o")
eq(pm.workspace_id({ name = "eDP-1" }, 3), 3, "first block")
eq(pm.workspace_id({ name = "DP-2" }, 3), 13, "second block")
eq(pm.workspace_id({ name = "DP-2" }, 10), 20, "slot 10 ends the block")
eq(pm.slot_of(13), 3, "slot_of 13")
eq(pm.slot_of(20), 10, "slot_of 20")
eq(pm.slot_of(1), 1, "slot_of 1")
eq(pm.slot_of(21), 1, "slot_of 21")
eq(pm.slot_of(0), nil, "slot_of 0")
eq(pm.slot_of(2.5), nil, "slot_of a float")

local gl = Slots.with(nil)
eq(gl.mode(), "global", "mode without o")
eq(gl.workspace_id({ name = "DP-2" }, 7), 7, "global id is the slot")
eq(gl.slot_of(7), 7, "global slot_of")
eq(Slots.with({}).mode(), "global", "o without workspaces")
eq(Slots.with({ workspaces = {} }).mode(), "global", "workspaces without workspace_id")

-- D50: Hyprland's workspace rules (hyprmoncfg): laptop 1 to 3 by description, HDMI 4 to 6, DP-1 7 to 9
local plan = { monitors = { ["desc:Example Panel"] = { 1, 2, 3 }, ["HDMI-A-1"] = { 4, 5, 6 }, ["DP-1"] = { 7, 8, 9 } } }
local off = { workspaces = { enabled = false, workspace_id = function() return 99 end } }
local r = Slots.with(off, plan)
eq(r.mode(), "rules", "rules win")
eq(r.workspace_id({ name = "eDP-1", description = "Example Panel" }, 2), 2, "laptop by its description")
eq(r.workspace_id({ name = "HDMI-A-1" }, 1), 4, "HDMI desktop 1 is workspace 4")
eq(r.workspace_id({ name = "DP-1" }, 3), 9, "DP-1 desktop 3 is workspace 9")
eq(r.workspace_id({ name = "DP-1" }, 4), nil, "DP-1 has 3 desktops")
eq(r.slot_of(8), 2, "workspace 8 is desktop 2 of its monitor")
eq(r.slot_of(4), 1, "workspace 4 is desktop 1")
eq(Slots.with(off).mode(), "global", "Omarchy numbering turned off and no rules: plain ids")
eq(Slots.with(off).workspace_id({ name = "DP-1" }, 2), 2, "not Omarchy's 12")
eq(Slots.with(fake.o, { monitors = {} }).mode(), "per_monitor", "no rules: Omarchy's model")
local mixed = Slots.with(fake.o, { monitors = { ["DP-1"] = { 7, 8 } } })
eq(mixed.workspace_id({ name = "DP-2" }, 3), 13, "a monitor without rules keeps Omarchy's model")

for _, bad in ipairs({ 0, 11, 1.5, "3" }) do
  local id, err = pm.workspace_id({ name = "eDP-1" }, bad)
  eq(id, nil, "bad slot refused")
  eq(type(err), "string", "bad slot explained")
end

local broken = Slots.with({ workspaces = { workspace_id = function() error("boom") end } })
local id, err = broken.workspace_id({ name = "x" }, 1)
eq(id, nil, "a failing Omarchy call gives nil")
eq(err:find("boom") ~= nil, true, "reason kept")
eq(Slots.with({ workspaces = { workspace_id = function() return "x" end } }).workspace_id({}, 1), nil, "non-integer id refused")

print("test_slots ok (" .. checks .. " checks)")
