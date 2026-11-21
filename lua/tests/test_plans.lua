-- Plain Lua check:  lua lua/tests/test_plans.lua   (pure, made-up plans)
local dir = arg[0]:match("^(.*)/") or "."
local Plans = dofile(dir .. "/../plans.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local function win(class, extra)
  local w = { class = class, context = "", rect = { 0, 0, 0.5, 1 }, floating = true, snap = true }
  for k, v in pairs(extra or {}) do w[k] = v end
  return w
end

-- validate: bad input never raises
eq(Plans.validate(nil), nil, "nil refused")
eq(select(2, Plans.validate({})), "not a plans table", "no plans list refused")
eq(#Plans.validate({ plans = {} }).plans, 0, "empty list is fine")

local set = Plans.validate({ plans = {
  { scene = "desk-2", home_monitor = "Example Corp EX27", home_slot = 2, layout = "columns:2", mode = "floating",
    open_at_login = true, windows = { win("org.example.Editor"), win("org.example.Chat", { rect = { 0.5, 0, 0.5, 1 } }),
      win("org.example.Editor", { rect = { 0.5, 0, 0.5, 1 } }) } },
  { scene = "desk-3", home_monitor = "", home_slot = 3, layout = "tiled", mode = "tiled",
    windows = { win("org.example.Term", { floating = false }), win("org.example.Off", { snap = false }),
      { class = "", rect = { 0, 0, 1, 1 } }, win("google-chrome", { context = "Profile 1" }) } },
  { scene = "desk-4", home_slot = 4, layout = "full", mode = "", windows = { win("org.example.Chat", { fullscreen = 1 }) } },
  { scene = "bad name!", home_slot = 1, windows = {} },
  { scene = "no-slot", home_slot = 0, windows = {} },
  { scene = "bad-rect", home_slot = 5, windows = { win("org.example.Nan", { rect = { 0, 0, 0 / 0, 1 } }) } },
  "not a table",
} })
eq(#set.plans, 4, "four good plans (bad-rect keeps its plan)")
eq(#set.skipped, 3, "bad plans skipped and listed")
eq(set.plans[1].open_at_login, true, "open_at_login read")
eq(set.plans[2].open_at_login, false, "open_at_login defaults off")
eq(set.plans[3].home_monitor, "", "missing monitor is empty (focused)")
eq(set.plans[2].windows[3].snap, false, "a bad window keeps its index and never snaps")
eq(#set.plans[2].windows, 4, "window index kept")

-- lookup
local p, i, w = Plans.lookup(set, "org.example.Editor", nil)
eq(p and p.scene, "desk-2", "editor in desk-2")
eq(i, 1, "first entry of the class")
eq(w.rect[1], 0, "its rect")
eq(Plans.lookup(set, "org.example.Chat"), nil, "same app in two plans: not snapped")
eq(Plans.held(set, "org.example.Chat"), true, "but it is held by a plan")
eq(Plans.lookup(set, "org.example.Off"), nil, "snap = false: not snapped")
eq(Plans.held(set, "org.example.Off"), true, "snap = false is still held")
eq(Plans.lookup(set, "org.example.Stray"), nil, "unknown class")
eq(Plans.held(set, "org.example.Stray"), false, "unknown class not held")
eq(Plans.lookup(set, "google-chrome"), nil, "untagged browser window does not match a profile")
eq(select(2, Plans.lookup(set, "google-chrome", "Profile 1")), 4, "tagged browser window matches its profile")
eq(Plans.lookup(set, "org.example.Nan"), nil, "a window with a bad rect never snaps")
eq(Plans.lookup(nil, "x"), nil, "no set")

-- login
local names = Plans.login_plans(set)
eq(#names, 1, "one plan opens at login")
eq(names[1], "desk-2", "the ticked one")

-- drift (D23)
eq(Plans.drifted({ 0, 0, 0.5, 1 }, { 0, 0, 0.5, 1 }), false, "exact")
eq(Plans.drifted({ 0.019, 0, 0.5, 0.985 }, { 0, 0, 0.5, 1 }), false, "within 2 percent")
eq(Plans.drifted({ 0.03, 0, 0.5, 1 }, { 0, 0, 0.5, 1 }), true, "x off by 3 percent")
eq(Plans.drifted({ 0, 0, 0.5, 0.9 }, { 0, 0, 0.5, 1 }), true, "height off by 10 percent")
eq(Plans.drifted(nil, { 0, 0, 1, 1 }), false, "no rect: no drift")

-- desktops
local live = {
  { name = "eDP-1", description = "Example Panel", focused = true },
  { name = "DP-2", description = "Example Corp EX27" },
  { name = "DP-3", description = "Mirror", is_mirror = true },
}
local d = Plans.desktops(live, function(m, s) return m.name == "DP-2" and 10 + s or s end,
  function(m) return m.description end)
eq(#d.monitors, 2, "mirror left out")
eq(d.monitors[1].name, "DP-2", "sorted by connector")
eq(d.monitors[1].identity, "Example Corp EX27", "identity")
eq(d.monitors[1].slots[2].workspace, 12, "slot 2 of DP-2 is 12")
eq(#d.monitors[2].slots, 10, "ten slots")
eq(d.monitors[2].focused, true, "focused flag")
local d2 = Plans.desktops(live, function(m, s) if m.name == "DP-2" then error("boom") end return s end, function() return "x" end)
eq(#d2.monitors[1].slots, 0, "a failing workspace_id gives no slots, no raise")

-- by_scene and match_run (a run's windows come sorted by order)
eq(Plans.by_scene(set, "desk-3").home_slot, 3, "plan by scene name")
eq(Plans.by_scene(set, "nope"), nil, "unknown scene")
local p2 = Plans.by_scene(set, "desk-2") -- Editor {0,0,.5,1}, Chat {.5,0,.5,1}, Editor {.5,0,.5,1}
local m = Plans.match_run(p2, {
  { class = "org.example.Chat", context = "", rect = { 0.5, 0, 0.5, 1 } },
  { class = "org.example.Editor", context = "", rect = { 0.5, 0, 0.5, 1 } },
  { class = "org.example.Editor", context = "", rect = { 0.3, 0, 0.5, 1 } },
  { class = "org.example.Stray", context = "" },
})
eq(m[1], 2, "Chat is window 2")
eq(m[2], 3, "the Editor with the right-half rect is window 3")
eq(m[3], 1, "the other Editor takes the one left")
eq(m[4], nil, "a class not in the plan is not matched")
eq(Plans.match_run(Plans.by_scene(set, "desk-3"), { { class = "google-chrome", context = "" } })[1], nil,
  "an untagged browser does not match a profile window")

print(string.format("test_plans: %d checks ok", checks))
