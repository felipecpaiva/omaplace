-- Plain Lua check:  lua lua/tests/test_rules.lua
local dir = arg[0]:match("^(.*)/") or "."
local Rules = dofile(dir .. "/../rules.lua")
local Monitors = dofile(dir .. "/../monitors.lua")
local Slots = dofile(dir .. "/../slots.lua")
local fake = dofile(dir .. "/fake_hl.lua").new()

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local function mon(name, desc, focused)
  return { name = name, description = desc, make = "Example Corp", model = "EX27", width = 2560, height = 1440,
    scale = 1, transform = 0, focused = focused or false }
end
local live = { mon("eDP-1", "Example Panel", true), mon("DP-2", "Example Corp EX27") }
fake.set_monitors(live)
local ws_id = Slots.with(fake.o).workspace_id
local focused = live[1]

local function build(rules, mons, previous, policy)
  return Rules.build(rules, mons or live, Monitors.resolve, ws_id, focused, previous, policy)
end
local function rule(t)
  local r = { app = "org.example.App", monitor = "", slot = 1, follow = false, enabled = true }
  for k, v in pairs(t) do r[k] = v end
  return r
end

-- rule to the slot of a named monitor, silent when follow is false
local specs = build({ editor = rule({ app = "org.example.Editor", monitor = "Example Corp EX27", slot = 3 }) })
eq(#specs, 1, "one spec")
eq(specs[1].name, "omaplace-rule-editor", "name")
eq(specs[1].match.initial_class, "org.example.Editor", "match")
eq(specs[1].workspace, "13 silent", "second block slot 3, silent")
eq(specs[1].enabled, true, "enabled")

-- follow = true switches to the workspace
specs = build({ a = rule({ monitor = "Example Corp EX27", slot = 3, follow = true }) })
eq(specs[1].workspace, "13", "follow has no silent")

-- twin monitors: the second twin is " #2"
local twins = { mon("DP-1", "Example Corp EX27", true), mon("DP-2", "Example Corp EX27") }
fake.set_monitors(twins)
specs = build({ t1 = rule({ monitor = "Example Corp EX27", slot = 2 }), t2 = rule({ monitor = "Example Corp EX27 #2", slot = 2 }) }, twins)
eq(specs[1].workspace, "2 silent", "first twin")
eq(specs[2].workspace, "12 silent", "second twin")
fake.set_monitors(live)

-- missing monitor: disabled with the default policy, focused when asked
local missing = { x = rule({ monitor = "Gone Corp ZZ1", slot = 2 }) }
specs = build(missing)
eq(specs[1].enabled, false, "missing monitor disabled")
eq(specs[1].workspace, nil, "no workspace when disabled")
specs = build(missing, nil, nil, "focused")
eq(specs[1].enabled, true, "policy focused uses focused monitor")
eq(specs[1].workspace, "2 silent", "focused monitor workspace")

-- empty monitor uses the focused one; no focused monitor disables
specs = build({ x = rule({ slot = 4 }) })
eq(specs[1].workspace, "4 silent", "empty monitor means focused")
focused = nil
specs = build({ x = rule({ slot = 4 }) })
eq(specs[1].enabled, false, "no focused monitor disables")
focused = live[2]
specs = build({ x = rule({ slot = 4 }) })
eq(specs[1].workspace, "14 silent", "focused changes the answer")
focused = live[1]

-- disabled in config, and a rule with no app
eq(build({ x = rule({ enabled = false }) })[1].enabled, false, "enabled = false")
eq(build({ x = rule({ app = "" }) })[1].enabled, false, "no app")

-- a slot that has no id disables (bad slot)
eq(build({ x = rule({ slot = 11 }) })[1].enabled, false, "bad slot")

-- stable order by name
specs = build({ zed = rule({}), alpha = rule({}), mid = rule({}) })
eq(specs[1].name .. specs[2].name .. specs[3].name, "omaplace-rule-alphaomaplace-rule-midomaplace-rule-zed", "sorted")

-- renamed and removed rules are reported
local _, vanished = build({ newname = rule({}) }, nil, { "omaplace-rule-oldname", "omaplace-rule-newname" })
eq(#vanished, 1, "one vanished")
eq(vanished[1], "omaplace-rule-oldname", "old name reported")
_, vanished = build({}, nil, nil)
eq(#vanished, 0, "no previous, nothing vanished")
_, vanished = build(nil, nil, { "omaplace-rule-a" })
eq(#vanished, 1, "nil rules still reports")

print(string.format("test_rules: %d checks ok", checks))
