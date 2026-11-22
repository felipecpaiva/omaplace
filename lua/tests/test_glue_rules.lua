-- Plain Lua check:  lua lua/tests/test_glue_rules.lua   (fake hl, a fixture HOME, never the real ~/.config)
local dir = arg[0]:match("^(.*)/") or "."
local fake = dofile(dir .. "/fake_hl.lua").new()

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local real_getenv = os.getenv
local home = dir .. "/fixtures/home-rules"
-- XDG_RUNTIME_DIR points at a folder that does not exist, so nothing is read from or written to the real one.
os.getenv = function(k)
  if k == "HOME" then return home end
  if k == "XDG_RUNTIME_DIR" then return dir .. "/fixtures/no-such-runtime" end
  return real_getenv(k)
end
local printed = {}
local real_print = print
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end

_G.hl, _G.o = fake.hl, fake.o
local function mon(name, desc, focused)
  return { name = name, description = desc, make = "Example Corp", model = "EX27", width = 2560, height = 1440,
    scale = 1, transform = 0, focused = focused or false }
end
local panel, ext = mon("eDP-1", "Example Panel", true), mon("DP-2", "Example Corp EX27")
fake.set_monitors({ panel, ext })

local function count(event) return #(fake.handlers[event] or {}) end
local function rule(name) return fake.rules["omaplace-rule-" .. name] end

-- load: no timers, rules declared, API there
dofile(dir .. "/../omaplace.lua")
eq(type(_G.omaplace), "table", "global api")
eq(_G.omaplace.version, "0.1.0", "version")
eq(fake.pending_timers(), 0, "idle: no timer after load")
eq(rule("editor").workspace, "13 silent", "editor on slot 3 of the second block")
eq(rule("editor").enabled, true, "editor enabled")
eq(rule("editor").match.initial_class, "org.example.Editor", "editor match")
eq(rule("notes").workspace, "2", "notes: focused monitor, follow")
eq(count("monitor.added") + count("monitor.removed") + count("monitor.layout_changed") + count("monitor.focused"), 4, "four handlers")

-- status shows names and flags only
local st = _G.omaplace.status()
eq(#st.rules, 2, "status lists two rules")
eq(st.rules[1].name, "omaplace-rule-editor", "status name")
eq(st.rules[1].enabled, true, "status flag")
eq(st.rules[1].match, nil, "status carries no app")

-- a rule's desktop made on the wrong monitor (Hyprland makes it on the focused one) is moved to its own monitor
local function moves()
  local out = {}
  for _, c in ipairs(fake.dispatched) do
    if c.name == "workspace.move" then out[#out + 1] = c.args end
  end
  return out
end
fake.workspaces[13] = { id = 13, monitor = { name = "eDP-1" } }
fake.emit("window.open", { address = "0xa", initial_class = "org.example.Editor", workspace = { id = 13 } })
eq(#moves(), 1, "desktop 13 sent home once")
eq(moves()[1].workspace, "13", "desktop 13 moved")
eq(moves()[1].monitor, "DP-2", "to the rule's monitor")
fake.workspaces[13].monitor.name = "DP-2"
fake.emit("window.open", { address = "0xb", initial_class = "org.example.Editor", workspace = { id = 13 } })
eq(#moves(), 1, "already on its monitor: no move")
fake.workspaces[4] = { id = 4, monitor = { name = "DP-2" } }
fake.emit("window.open", { address = "0xc", initial_class = "other", workspace = { id = 4 } })
eq(#moves(), 1, "a desktop no rule names is left alone")
fake.workspaces = {}

-- a second load (config reload) does not register handlers twice
dofile(dir .. "/../omaplace.lua")
eq(count("monitor.added"), 1, "no double register: added")
eq(count("monitor.focused"), 1, "no double register: focused")

-- monitor.removed, then the debounce rebuild disables the rule
fake.set_monitors({ panel })
fake.emit("monitor.removed", ext)
eq(rule("editor").enabled, true, "not yet: debounce waits")
fake.advance(499)
eq(rule("editor").enabled, true, "still waiting at 499 ms")
fake.advance(1)
eq(rule("editor").enabled, false, "disabled after 500 ms")
eq(rule("notes").enabled, true, "other rule untouched")
eq(fake.pending_timers(), 0, "idle again")

-- monitor.added brings it back
fake.set_monitors({ panel, ext })
fake.emit("monitor.added", ext)
fake.advance(500)
eq(rule("editor").enabled, true, "re-enabled")
eq(rule("editor").workspace, "13 silent", "same workspace")

-- five quick events, one rebuild
local calls = 0
local base = fake.hl.window_rule
fake.hl.window_rule = function(spec) if spec.name == "omaplace-rule-editor" then calls = calls + 1 end return base(spec) end
for i = 1, 5 do
  fake.emit("monitor.layout_changed")
  fake.advance(100)
end
eq(calls, 0, "no rebuild while events keep coming")
fake.advance(500)
eq(calls, 1, "one rebuild after the last event")
fake.advance(5000)
eq(calls, 1, "nothing more")
eq(fake.pending_timers(), 0, "no timer left")

-- config reload: a changed file changes the slot; a renamed rule is switched off
home = dir .. "/fixtures/home-rules2"
eq(_G.omaplace.reload_config(), true, "reload ok")
eq(rule("editor").workspace, "14 silent", "slot 4 now")
eq(rule("notes").enabled, false, "notes gone from the file, switched off")
eq(#_G.omaplace.status().rules, 1, "status lists one rule")

-- missing config file: defaults, no rules, no error
home = dir .. "/fixtures/home-none"
printed = {}
eq(_G.omaplace.reload_config(), true, "missing file is fine")
eq(rule("editor").enabled, false, "all rules off")
eq(#printed, 0, "nothing printed for a missing file")

-- a handler that fails is caught and logged with the prefix
fake.hl.window_rule = function() error("boom") end
home = dir .. "/fixtures/home-rules"
fake.set_monitors({ panel, ext })
local got, err = pcall(function() _G.omaplace.reload_config() end)
eq(got, true, "reload_config never raises")
printed = {}
fake.emit("monitor.added", ext)
fake.advance(500)
eq(#printed >= 1 and printed[1]:sub(1, 10), "omaplace: ", "error logged with prefix")

-- one rejected spec does not stop the others, and its name is still known so it can be switched off later
local declared = {}
fake.hl.window_rule = function(spec)
  if spec.name == "omaplace-rule-editor" then error("rejected") end
  declared[#declared + 1] = spec.name
end
_G.omaplace.reload_config()
eq(declared[1], "omaplace-rule-notes", "the rule after a rejected one is still declared")
local names = {}
for _, r in ipairs(_G.omaplace.status().rules) do names[r.name] = r.enabled end
eq(names["omaplace-rule-editor"], false, "rejected rule is known and shown off")

-- a focus change rebuilds only when some rule follows focus (empty monitor); the fixture's notes rule does
local rebuilds = 0
fake.hl.window_rule = function() rebuilds = rebuilds + 1 end
fake.emit("monitor.focused", ext)
fake.advance(500)
eq(rebuilds > 0, true, "focus change rebuilds when a rule follows focus")
home = dir .. "/fixtures/home-rules2"
_G.omaplace.reload_config()
local follows = _G.omaplace._m.follows_focus()
rebuilds = 0
fake.emit("monitor.focused", panel)
fake.advance(500)
eq(rebuilds > 0, follows, "focus change rebuilds only if a rule follows focus")

-- a reload leaves exactly one live subscription per event
dofile(dir .. "/../omaplace.lua")
dofile(dir .. "/../omaplace.lua")
eq(count("monitor.removed"), 1, "two reloads: still one handler")

print = real_print
os.getenv = real_getenv
print(string.format("test_glue_rules: %d checks ok", checks))
