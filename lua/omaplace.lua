-- omaplace: placement rules (design 6.1) and scenes (6.2, 6.3) for Omarchy. The only file (with place.lua) that
-- calls hl, and the only one that reads or writes files.
-- Load:  pcall(dofile, <plugin folder>/lua/omaplace.lua)   Settings: ~/.config/omaplace/config.toml
-- Idle cost: no timer is armed until a monitor event arrives, and then only one one-shot (500 ms debounce). A scene
-- run arms one-shot timers only while it is live; window.open returns at once when no run is live.
-- A re-armed debounce switches the old timer off (HL.Timer:set_enabled) and also bumps a generation number, so a
-- timer that fires anyway does nothing.
local M = { version = "0.1.0" }

local dir = (debug.getinfo(1, "S").source:match("^@(.*)/") or ".")
local Config = dofile(dir .. "/config.lua")
local Monitors = dofile(dir .. "/monitors.lua")
local Slots = dofile(dir .. "/slots.lua")
local Rules = dofile(dir .. "/rules.lua")
local Capture = dofile(dir .. "/capture.lua")
local Tickets = dofile(dir .. "/tickets.lua")
local Place = dofile(dir .. "/place.lua")
local Json = dofile(dir .. "/json.lua")
local Shellquote = dofile(dir .. "/shellquote.lua")
local Geometry = dofile(dir .. "/geometry.lua")

M.debounce_ms = 500
M.applied = {} -- spec names declared so far, so a vanished rule can be switched off
M.enabled = {} -- spec name -> enabled flag, for status()
M.settings = Config.load("").settings
M.rules = {}

-- The previous load of this file (a config reload runs it again in the same Lua state) hands over what it declared.
local old = rawget(_G, "omaplace")
local old_m = type(old) == "table" and type(old._m) == "table" and old._m or nil
if old_m and type(old_m.applied) == "table" then M.applied = old_m.applied end
-- If the Lua state survived the reload, drop the old event subscriptions and timer before adding fresh ones.
if old_m then
  for _, sub in ipairs(old_m.subs or {}) do pcall(sub.remove, sub) end
  if old_m.timer then pcall(old_m.timer.set_enabled, old_m.timer, false) end
end
M.subs = {}

local function log(text) print("omaplace: " .. tostring(text)) end

local function config_path() return (os.getenv("HOME") or "") .. "/.config/omaplace/config.toml" end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local function load_config()
  local cfg = Config.load(read_file(config_path()) or "")
  for _, w in ipairs(cfg.warnings) do log("config: " .. w) end
  M.settings, M.rules = cfg.settings, cfg.rules
end

local function focused_of(live)
  for _, m in ipairs(live) do
    if m.focused then return m end
  end
end

-- Declare every rule again under its own name (hl.window_rule replaces in place) and switch off the ones that went.
function M.rebuild()
  local ok, live = pcall(hl.get_monitors)
  if not ok or type(live) ~= "table" then return nil, "no monitors" end
  local slots = Slots.with(rawget(_G, "o"))
  local specs, vanished = Rules.build(
    M.rules, live, Monitors.resolve, slots.workspace_id, focused_of(live), M.applied, M.settings.missing_monitor_rule)
  M.enabled = {}
  M.applied = {}
  for _, spec in ipairs(specs) do
    -- record the name first: if Hyprland rejects one spec, the rest are still declared and the name can be switched off
    M.applied[#M.applied + 1] = spec.name
    local ok_rule, err = pcall(hl.window_rule, spec)
    M.enabled[spec.name] = ok_rule and spec.enabled
    if not ok_rule then log("rule " .. spec.name .. " rejected: " .. tostring(err)) end
  end
  for _, name in ipairs(vanished) do pcall(hl.window_rule, { name = name, enabled = false }) end
  return true
end

function M.reload_config()
  local ok, err = pcall(function() load_config(); assert(M.rebuild()) end)
  if not ok then log("reload failed: " .. tostring(err)); return nil, tostring(err) end
  return true
end

-- The rules, plus the current or last run (the same run, state and items as status.json; state "idle" if none).
function M.status()
  local rules = {}
  for _, name in ipairs(M.applied) do rules[#rules + 1] = { name = name, enabled = M.enabled[name] == true } end
  local out = { version = M.version, rules = rules, state = "idle", items = {} }
  if M.run then
    local st = M.run_status(M.run)
    out.run, out.state, out.items = st.run, st.state, st.items
  end
  return out
end

-- Many monitor events in a row (plugging a dock sends several) become one rebuild, 500 ms after the last.
M.debounce_gen = 0
local function rebuild_soon()
  M.debounce_gen = M.debounce_gen + 1
  local gen = M.debounce_gen
  if M.timer then pcall(M.timer.set_enabled, M.timer, false) end
  M.timer = hl.timer(function()
    M.timer = nil
    if gen ~= M.debounce_gen then return end
    local ok, err = pcall(M.rebuild)
    if not ok then log("rebuild failed: " .. tostring(err)) end
  end, { type = "oneshot", timeout = M.debounce_ms })
end
M.rebuild_soon = rebuild_soon

-- ---------------------------------------------------------------- scenes: capture and runs (design 6.2, 6.3)

M.FLOAT_TAG = "omarchy-floating-workspace"
M.SLOT_PREFIX = "omaplace-slot="

-- Milliseconds since boot (wall clock; os.clock is CPU time and stands still while idle). Tests replace it.
function M.now_ms()
  local f = io.open("/proc/uptime", "r")
  if not f then return os.time() * 1000 end
  local s = f:read("n") or 0
  f:close()
  return math.floor(s * 1000)
end

local function runtime_dir() return (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omaplace" end

-- Lua cannot make a folder, so ask Hyprland to (async). Called at load and again if a write finds it missing.
local function ensure_dir()
  local d = runtime_dir()
  local f = io.open(d, "r")
  if f then f:close(); return end
  pcall(hl.exec_cmd, "mkdir -p -m 700 " .. Shellquote.join({ d }))
end

-- Write a whole file through a temp file and a rename, so a reader never sees half of it.
local function write_atomic(name, text)
  local path = runtime_dir() .. "/" .. name
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then ensure_dir(); log("cannot write " .. name); return nil, "write_failed" end
  local ok_w = f:write(text)
  f:close()
  if not ok_w then os.remove(tmp); return nil, "write_failed" end
  local ok_r, err = os.rename(tmp, path)
  if not ok_r then os.remove(tmp); log("cannot write " .. name .. ": " .. tostring(err)); return nil, "write_failed" end
  return true
end

local function has_tag(w, tag)
  for _, t in ipairs(Capture.tags_of(w)) do
    if t == tag then return true end
  end
  return false
end

local function later(ms, fn)
  return hl.timer(function()
    local ok, err = pcall(fn)
    if not ok then log("timer failed: " .. tostring(err)) end
  end, { type = "oneshot", timeout = math.max(1, math.floor(ms)) })
end

-- capture(req_id, scope): write capture-<req_id>.json (design 5.5). scope "focused" (default) or "all".
function M.capture(req_id, scope)
  if type(req_id) ~= "string" or #req_id > 64 or not req_id:match("^[%w_%-]+$") then return nil, "bad_req" end
  local live, wins = hl.get_monitors(), hl.get_windows()
  local floating = {}
  for _, w in ipairs(wins) do
    if w.workspace and has_tag(w, M.FLOAT_TAG) then floating[w.workspace.id] = true end
  end
  local focused = focused_of(live)
  local slots = Slots.with(rawget(_G, "o"))
  local snap = Capture.snapshot(wins, live, {
    slot_of = slots.slot_of, is_floating = function(id) return floating[id] == true end,
    fingerprint = Monitors.fingerprint, usable = Geometry.usable, ignore = Capture.ignore_set(M.settings.ignore),
    scope = scope == "all" and "all" or "focused",
    workspace = focused and focused.active_workspace and focused.active_workspace.id,
    kind = "capture", saved_at = os.time(), mode = slots.mode(),
  })
  local text, err = Json.encode(snap)
  if not text then log("capture encode failed: " .. tostring(err)); return nil, "failed" end
  return write_atomic("capture-" .. req_id .. ".json", text .. "\n")
end

local ITEM_STATE = { waiting = "waiting", launched = "waiting", expired = "not_reopened", skipped = "skipped", failed = "failed" }

local function run_status(run)
  local items = {}
  for _, s in ipairs(run.book.slots) do
    local item = { class = s.class, state = ITEM_STATE[s.state] or (s.existing and "moved" or "placed") }
    if item.state == "waiting" then item.since = run.wall0 + ((s.started_at or run.t0) - run.t0) // 1000 end
    if s.reason then item.reason = s.reason end
    items[#items + 1] = item
  end
  return { run = run.id, state = run.state, items = items }
end

M.run_status = run_status

local function write_status(run)
  local text = Json.encode(run_status(run))
  if text then write_atomic("status.json", text .. "\n") end
end

local function stop_timer(run)
  run.gen = run.gen + 1
  if run.timer then pcall(run.timer.set_enabled, run.timer, false) end
  run.timer = nil
end

local function finish(run)
  if not run.live then return end
  run.live = false
  stop_timer(run)
  local placed, missed = 0, {}
  for _, s in ipairs(run.book.slots) do
    if s.state == "claimed" then placed = placed + 1 else missed[#missed + 1] = s.class .. " " .. s.state end
  end
  run.state = #missed == 0 and "done" or "partial"
  write_status(run)
  log(string.format("run %s %s: %d placed%s", run.id, run.state, placed,
    #missed > 0 and (", not placed: " .. table.concat(missed, ", ")) or ""))
end

local step

-- One put finished (or was not needed). The run ends when every slot is final and no put is still pending.
local function settled(run)
  run.pending = run.pending - 1
  if run.live and run.pending == 0 and Tickets.finished(run.book) then finish(run) end
end

local function tag(w, text) hl.dispatch(hl.dsp.window.tag({ tag = text, window = w })) end

-- A window took slot `s`: tag it, send it to its workspace (focus follows a rule desktop, D9), then place it at
-- its rect if it ends up floating on a floating workspace (D13: never a rect on a tiled one).
local function apply(run, s, w, fresh)
  local info = run.info[s.n]
  info.address = w.address
  for _, t in ipairs(Capture.tags_of(w)) do
    if t:sub(1, #M.SLOT_PREFIX) == M.SLOT_PREFIX then tag(w, "-" .. t) end
  end
  tag(w, "+" .. M.SLOT_PREFIX .. run.id .. "/" .. s.n)
  if s.context ~= "" then tag(w, "+" .. Capture.CTX_PREFIX .. Capture.ctx_hex(s.context)) end
  local moved = Place.to_workspace(w, info.target.ws, not info.target.follow)
  if not info.rect then return end
  run.pending = run.pending + 1
  local address = w.address
  local function put_now()
    local now_w = Place.find(address)
    if not (now_w and now_w.floating and (info.float_target or has_tag(now_w, M.FLOAT_TAG))) then return settled(run) end
    local ok, area = pcall(Geometry.usable, info.target.mon)
    if not ok then return settled(run) end
    Place.put(now_w, Geometry.place_frac(area, info.rect), function() settled(run) end)
  end
  -- Omarchy re-arranges a moved window about 1 s later, and a new app may still resize itself: wait (settle_ms).
  if moved or fresh then later(M.settings.settle_ms, put_now) else put_now() end
end

local function start_slot(run, s)
  local info = run.info[s.n]
  if s.existing then
    local w = Place.find(info.address)
    if not w then return Tickets.fail(run.book, s.n, "gone") end
    return apply(run, s, w, false)
  end
  if s.mode ~= "launch" then return end -- place_only: wait for the app's own window
  local cmd = Shellquote.join(info.launch)
  if not cmd then return Tickets.fail(run.book, s.n, "bad_launch") end
  local ok = pcall(hl.exec_cmd, cmd)
  if not ok then Tickets.fail(run.book, s.n, "launch_failed") end
end

local function arm(run, at, now)
  stop_timer(run)
  if not at then return end
  local gen = run.gen
  run.timer = later(at - now, function()
    if run.gen ~= gen or not run.live then return end
    run.timer = nil
    step(run)
  end)
end

-- Expire late slots, start what may start now, then finish or arm one timer for the next deadline.
step = function(run)
  if not run.live then return end
  local now = M.now_ms()
  Tickets.expire(run.book, now)
  while true do
    local batch = Tickets.next_launches(run.book, now)
    if #batch == 0 then break end
    for _, s in ipairs(batch) do start_slot(run, s) end
  end
  if run.pending == 0 and Tickets.finished(run.book) then return finish(run) end
  arm(run, Tickets.next_wake(run.book, now), now)
  write_status(run)
end

local function valid_rect(r)
  if type(r) ~= "table" or #r ~= 4 then return nil end
  for i = 1, 4 do
    if type(r[i]) ~= "number" then return nil end
  end
  return r
end

-- Where each plan window goes: { mon, ws, follow }, or nil when its monitor cannot be found.
local function targets(plan, live, slots)
  local focused = focused_of(live)
  local function ws_of(mon, slot)
    if not mon then return nil end
    if slot == 0 then return mon.active_workspace and mon.active_workspace.id end
    return slots.workspace_id(mon, slot)
  end
  local main
  if plan.kind ~= "session" then
    local fp = type(plan.target) == "table" and plan.target.fp or nil
    local mon = focused
    if type(fp) == "table" and (fp.identity or "") ~= "" then mon = Monitors.resolve(fp, live, M.settings.missing_monitor_scene) end
    local ws = ws_of(mon, math.tointeger(type(plan.target) == "table" and plan.target.slot) or 0)
    if not ws then return nil, "no_monitor" end
    main = { mon = mon, ws = ws, follow = false }
  end
  return function(w)
    -- Rules win (D9): the rule's desktop, and the focus follows.
    local d = w.desktop
    if type(d) == "table" then
      local mon = focused
      if (d.monitor or "") ~= "" then mon = Monitors.resolve({ identity = d.monitor }, live, M.settings.missing_monitor_rule) end
      local ws = mon and ws_of(mon, math.tointeger(d.slot) or -1)
      if ws then return { mon = mon, ws = ws, follow = true } end
    end
    if main then return main end
    local fp = type(plan.monitors) == "table" and plan.monitors[(math.tointeger(w.monitor) or -1) + 1]
    local mon = fp and Monitors.resolve(fp, live, "focused")
    local ws = mon and ws_of(mon, math.tointeger(w.slot) or -1)
    return ws and { mon = mon, ws = ws, follow = false } or nil
  end, main
end

local function start_run(plan)
  if type(plan) ~= "table" or type(plan.run) ~= "string" or #plan.run > 64 or not plan.run:match("^[%w_%-%.]+$")
    or type(plan.windows) ~= "table" then
    return nil, "bad_plan"
  end
  local live = hl.get_monitors()
  local slots = Slots.with(rawget(_G, "o"))
  local target_of, main = targets(plan, live, slots)
  if not target_of then return nil, main end
  local now = M.now_ms()
  local layout = plan.layout == "floating" and "floating" or "tiled"
  local book = Tickets.new(plan.windows, now, {
    expiry_ms = (math.tointeger(plan.expiry_s) or M.settings.expiry_seconds) * 1000,
    tick_ms = M.settings.launch_tick_ms, quiet_ms = M.settings.context_quiet_ms,
    sequential = layout ~= "floating" and M.settings.tiled_order,
  })
  local run = { id = plan.run, live = true, state = "running", book = book, info = {}, t0 = now, wall0 = os.time(),
    pending = 0, gen = 0 }
  for i, w in ipairs(plan.windows) do
    local t = type(w) == "table" and target_of(w) or nil
    run.info[i] = { target = t, launch = w.launch, rect = valid_rect(w.rect),
      float_target = t ~= nil and layout == "floating" and (main == nil or t.ws == main.ws) }
    if not t and book.slots[i].state ~= "skipped" then Tickets.fail(book, i, "no_monitor") end
  end
  M.run = run
  -- Move pass (D10): open windows take their slots by class and context, in plan order.
  if (plan.existing or M.settings.existing_default) == "move" then
    local wins = {}
    for _, w in ipairs(hl.get_windows()) do wins[#wins + 1] = w end
    table.sort(wins, function(a, b) return (a.stable_id or 0) < (b.stable_id or 0) end)
    for _, w in ipairs(wins) do
      local ws = w.workspace or {}
      local special = (ws.id or 0) < 0 and not Capture.home_of(w)
      if not special and (w.initial_class or "") ~= "" then
        local s = Tickets.claim(book, { class = w.initial_class, context = Capture.context_of(w), existing = true }, now)
        if s then run.info[s.n].address = w.address end
      end
    end
  end
  step(run)
  return run.id
end

-- open(plan): start a run (design 5.4). Returns the run id, or nil and busy | bad_plan | no_monitor | failed.
function M.open(plan)
  if M.run and M.run.live then return nil, "busy" end
  local ok, id, err = pcall(start_run, plan)
  if not ok then
    log("open failed: " .. tostring(id))
    if M.run and M.run.live then M.run.live = false; stop_timer(M.run) end
    return nil, "failed"
  end
  return id, err
end

-- open_file(path): the same as open(plan) for a plan the service wrote to
-- $XDG_RUNTIME_DIR/omaplace/plan-<run>.lua (`return { ... }`), because one hyprctl argument is capped at 128 kB.
-- The file is loaded as text only, in an empty environment: it can build a table and nothing else.
function M.open_file(path)
  local prefix = runtime_dir() .. "/plan-"
  if type(path) ~= "string" or path:sub(1, #prefix) ~= prefix or path:find("/", #prefix + 1, true)
    or not path:match("%.lua$") then
    return nil, "bad_path"
  end
  local text = read_file(path)
  if not text then return nil, "no_file" end
  local chunk, err = load(text, "plan", "t", {})
  if not chunk then log("plan file: " .. tostring(err)); return nil, "bad_plan" end
  local ok, plan = pcall(chunk)
  if not ok then log("plan file: " .. tostring(plan)); return nil, "bad_plan" end
  if type(plan) ~= "table" then return nil, "bad_plan" end
  return M.open(plan)
end

-- A new window: only looked at while a run is live.
function M.on_window_open(w)
  local run = M.run
  if not (run and run.live) or type(w) ~= "table" then return end
  local mine = M.SLOT_PREFIX .. run.id .. "/"
  for _, t in ipairs(Capture.tags_of(w)) do
    if t:sub(1, #mine) == mine then return end -- already claimed by this run
  end
  local cls = w.initial_class or ""
  if cls == "" then return end
  local s = Tickets.claim(run.book, { class = cls, context = Capture.context_of(w) }, M.now_ms())
  if s then apply(run, s, w, true) end
  step(run)
end

-- A reload during a run: the old run stops (same Lua state) and status.json says interrupted (also when the Lua
-- state is new and only the file remembers the run).
local function interrupt_stale(prev)
  if prev and prev.run and prev.run.live then
    prev.run.live = false
    prev.run.gen = prev.run.gen + 1
    if prev.run.timer then pcall(prev.run.timer.set_enabled, prev.run.timer, false) end
    prev.run.state = "interrupted"
    M.run = prev.run
  end
  local text = read_file(runtime_dir() .. "/status.json")
  if text and text:find('"state":"running"', 1, true) then
    write_atomic("status.json", (text:gsub('"state":"running"', '"state":"interrupted"')))
    log("a scene run was interrupted by a reload")
  end
end

-- _m is internal: the next load of this file reads them (see above).
_G.omaplace = { version = M.version, reload_config = M.reload_config, status = M.status, open = M.open,
  open_file = M.open_file, capture = M.capture, _m = M, _rebuild_soon = rebuild_soon }

ensure_dir()
interrupt_stale(old_m)

local ok, err = pcall(function() load_config(); assert(M.rebuild()) end)
if not ok then log("load failed: " .. tostring(err)) end

-- Only rules with an empty monitor follow focus, so a focus change rebuilds only when such a rule exists.
local function follows_focus()
  for _, rule in pairs(M.rules) do
    if rule.enabled and (rule.monitor or "") == "" then return true end
  end
  return false
end

-- Fresh subscriptions on every load (old ones were removed above); they call through _G.omaplace.
for _, event in ipairs({ "monitor.added", "monitor.removed", "monitor.layout_changed", "monitor.focused" }) do
  local sub = hl.on(event, function()
    local handled, e = pcall(function()
      if event == "monitor.focused" and not _G.omaplace._m.follows_focus() then return end
      _G.omaplace._rebuild_soon()
    end)
    if not handled then log(event .. " handler failed: " .. tostring(e)) end
  end)
  if sub then M.subs[#M.subs + 1] = sub end
end
M.follows_focus = follows_focus

local open_sub = hl.on("window.open", function(w)
  local handled, e = pcall(function() _G.omaplace._m.on_window_open(w) end)
  if not handled then log("window.open handler failed: " .. tostring(e)) end
end)
if open_sub then M.subs[#M.subs + 1] = open_sub end

return M
