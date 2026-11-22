-- omaplace: placement rules (design 6.1) and scenes (6.2, 6.3) for Omarchy. The only file (with place.lua) that
-- calls hl, and the only one that reads or writes files.
-- Load:  pcall(dofile, <plugin folder>/lua/omaplace.lua)   Settings: ~/.config/omaplace/config.toml
-- Idle cost: no timer is armed until a monitor event arrives, and then only one one-shot (500 ms debounce). A scene
-- run arms one-shot timers only while it is live. With no run live, window.open only looks the class up in app
-- memory (F5) and arms one settle timer when it places a remembered floating window.
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
local Policy = dofile(dir .. "/sessionpolicy.lua")
local Memory = dofile(dir .. "/memory.lua")
local Plans = dofile(dir .. "/plans.lua")

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
  for _, sub in ipairs(old_m.session_subs or {}) do pcall(sub.remove, sub) end
  for _, sub in ipairs(old_m.memory_subs or {}) do pcall(sub.remove, sub) end
  for _, sub in ipairs(old_m.plan_subs or {}) do pcall(sub.remove, sub) end
  if old_m.timer then pcall(old_m.timer.set_enabled, old_m.timer, false) end
  if old_m.session_timer then pcall(old_m.session_timer.set_enabled, old_m.session_timer, false) end
  if old_m.memory_timer then pcall(old_m.memory_timer.set_enabled, old_m.memory_timer, false) end
end
M.subs = {}
M.session_subs = {}
M.memory_subs = {}
M.memory_moved = {} -- addresses moved to another workspace, read when the memory debounce fires
M.memory_own = {} -- addresses memory itself just moved: their one move event is not a user's move
-- auto mode: the workspace each window was last seen on, the workspace a moved window came from, and the pending
-- events of moves.json (kept across a reload so the file is not reset)
M.places = old_m and type(old_m.places) == "table" and old_m.places or {} -- address -> last place, for a close that arrives without workspace or monitor
M.last_ws = old_m and type(old_m.last_ws) == "table" and old_m.last_ws or {}
M.auto_from = {}
M.moves = old_m and type(old_m.moves) == "table" and old_m.moves or {}
M.MAX_MOVES = 50
-- a freeze survives a reload of this file (a close-all can come with one)
M.session_state = old_m and type(old_m.session_state) == "table" and old_m.session_state or Policy.new()
M.session_state.first_at = nil -- the old timer is switched off by a reload: no write is owed
-- desktop plans (design 14.7, 14.8): snapped windows, their pending reports and the login check survive a reload
M.plan_subs = {}
M.plan_own = {} -- addresses a plan snap just moved: their one move event is not a user's move
M.plans = old_m and old_m.plans or nil
M.snapped = old_m and type(old_m.snapped) == "table" and old_m.snapped or {} -- address -> the plan window it snapped to
M.plan_moves = old_m and type(old_m.plan_moves) == "table" and old_m.plan_moves or nil -- else seeded from the file at load
M.MAX_PLAN_MOVES = 20
M.PLUGIN_DIR = dir:match("^(.*)/lua$") or (dir .. "/..") -- the folder that holds bin/omaplace
M.NOTIFY_GLYPH = "\u{F0770}"
M.last_active = old_m and old_m.last_active or nil
M.login_checked = old_m and old_m.login_checked or false

local function log(text) print("omaplace: " .. tostring(text)) end

local function config_path() return (os.getenv("HOME") or "") .. "/.config/omaplace/config.toml" end

-- max (bytes): read at most max + 1, so a huge file is noticed without being loaded whole.
local function read_file(path, max)
  local f = io.open(path, "r")
  if not f then return nil end
  local text = f:read(max and (max + 1) or "a")
  f:close()
  return text
end

local function state_dir()
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  return home .. "/.local/state/omaplace"
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
  local specs, vanished, places = Rules.build(
    M.rules, live, Monitors.resolve, slots.workspace_id, focused_of(live), M.applied, M.settings.missing_monitor_rule)
  M.rule_places, M.rule_homes = places, {}
  for _, p in pairs(places) do M.rule_homes[p.ws] = p.monitor end
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

-- A session or memory failure never stops the rules.
local function sync_session_safe()
  local ok, err = pcall(function() M.sync_session() end)
  if not ok then log("session setup failed: " .. tostring(err)) end
  local ok_m, err_m = pcall(function() M.sync_memory() end)
  if not ok_m then log("memory setup failed: " .. tostring(err_m)) end
end

function M.reload_config()
  local ok, err = pcall(function() load_config(); sync_session_safe(); assert(M.rebuild()); M.reload_plans() end)
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

-- nil when XDG_RUNTIME_DIR is unset: a shared /tmp would let other users plant plan files, so nothing runs (logged once).
local warned_runtime = false
local function runtime_dir()
  local base = os.getenv("XDG_RUNTIME_DIR")
  if not base or base == "" then
    if not warned_runtime then warned_runtime = true; log("XDG_RUNTIME_DIR is not set: scenes are off") end
    return nil
  end
  return base .. "/omaplace"
end

-- Lua cannot make a folder, so ask Hyprland to (async). Called at load and again if a write finds it missing.
local function make_dir(d)
  if not d then return end
  local f = io.open(d, "r")
  if f then f:close(); return end
  pcall(hl.exec_cmd, "mkdir -p -m 700 " .. Shellquote.join({ d }))
end

local function ensure_dir() make_dir(runtime_dir()) end

-- Write a whole file in folder dir_ through a temp file and a rename, so a reader never sees half of it.
local function write_in(dir_, name, text)
  local path = dir_ .. "/" .. name
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then make_dir(dir_); log("cannot write " .. name); return nil, "write_failed" end
  local ok_w = f:write(text)
  f:close()
  if not ok_w then os.remove(tmp); return nil, "write_failed" end
  local ok_r, err = os.rename(tmp, path)
  if not ok_r then os.remove(tmp); log("cannot write " .. name .. ": " .. tostring(err)); return nil, "write_failed" end
  return true
end

local function write_atomic(name, text)
  local dir_ = runtime_dir()
  if not dir_ then return nil, "no_runtime" end
  return write_in(dir_, name, text)
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

-- ---------------------------------------------------------------- app memory, core (F5, design 6.3)
-- ~/.local/state/omaplace/memory.lua is written only here, through a temp file and a rename.

M.MEMORY_DEBOUNCE_MS = 2000
M.MEMORY_TAG = "omaplace-slot=memory"

-- app_memory "off" is not in config.lua yet (only scene, last_place, auto); the glue already honours it.
local function memory_on() return M.memory ~= nil and M.settings.app_memory ~= "off" end

local function load_memory()
  local d = state_dir()
  local text = d and read_file(d .. "/memory.lua", Memory.MAX_TEXT)
  if not text then log("app memory: no memory.lua yet, starting empty"); return Memory.new() end
  local mem, err = Memory.decode(text)
  if not mem then log("app memory: memory.lua not used (" .. tostring(err) .. "), starting empty"); return Memory.new() end
  return mem
end

local function save_memory()
  local d = state_dir()
  if not d or not M.memory then return end
  local text, err = Memory.encode(M.memory)
  if not text then log("memory encode failed: " .. tostring(err)); return end
  write_in(d, "memory.lua", text)
end

-- One window's place the way a snapshot sees it (special workspaces, minimized and ignored classes give nil).
local function place_of(w)
  local live = hl.get_monitors()
  local slots = Slots.with(rawget(_G, "o"))
  local snap = Capture.snapshot({ w }, live, {
    slot_of = slots.slot_of, is_floating = function() return has_tag(w, M.FLOAT_TAG) end,
    fingerprint = Monitors.fingerprint, usable = Geometry.usable, ignore = Capture.ignore_set(M.settings.ignore),
    scope = "all",
  })
  local p = snap.windows[1]
  if not p or p.minimized then return nil end
  p.fp = snap.monitors[p.monitor + 1].fp
  return p
end

-- How many other windows of `class` are open (the event's own window is left out by address).
local function others_of(class, address)
  local n = 0
  for _, x in ipairs(hl.get_windows()) do
    if x.initial_class == class and x.address ~= address then n = n + 1 end
  end
  return n
end

-- Keep the window's latest place by address (only while memory records, removed on close).
local function track(w)
  if #M.memory_subs == 0 or not w.address then return end
  local p = place_of(w)
  if p then M.places[w.address] = p end
end

local function remember(kind, w)
  local p = place_of(w)
  if not p and kind == "closed" and w.address and M.places[w.address] then
    p = {}
    for k, v in pairs(M.places[w.address]) do p[k] = v end
  end
  if not p then return false end
  p.kind, p.others = kind, others_of(p.class, w.address)
  return Memory.update(M.memory, p, M.settings.app_memory, os.time())
end

-- The live desktops as a snapshot (design 5.5). scope "focused" or "all".
local function snapshot_of(scope, kind)
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
    scope = scope,
    workspace = focused and focused.active_workspace and focused.active_workspace.id,
    kind = kind, saved_at = os.time(), mode = slots.mode(),
  })
  return snap
end

-- capture(req_id, scope): write capture-<req_id>.json (design 5.5). scope "focused" (default) or "all".
function M.capture(req_id, scope)
  if type(req_id) ~= "string" or #req_id > 64 or not req_id:match("^[%w_%-]+$") then return nil, "bad_req" end
  if not runtime_dir() then return nil, "no_runtime" end
  local snap = snapshot_of(scope == "all" and "all" or "focused", "capture")
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

-- Tiled targets: dwindle splits the focused window, so put the run's windows in saved order with swaps (S8).
local function reorder(run)
  local by_ws = {}
  for _, s in ipairs(run.book.slots) do
    local info = run.info[s.n]
    local w = s.state == "claimed" and info.address and Place.find(info.address)
    -- only dwindle was checked live; any other layout (or an unknown one) is left alone
    if w and not w.floating and w.workspace and w.workspace.id == info.target.ws
      and w.workspace.tiled_layout == "dwindle" then
      local x, y = 0, 0
      if type(w.at) == "table" then x, y = tonumber(w.at.x or w.at[1]) or 0, tonumber(w.at.y or w.at[2]) or 0 end
      local list = by_ws[info.target.ws] or {}
      by_ws[info.target.ws] = list
      list[#list + 1] = { id = w.address, x = x, y = y, order = s.n }
    end
  end
  for _, list in pairs(by_ws) do
    for _, pair in ipairs(Tickets.swaps(list)) do
      hl.dispatch(hl.dsp.window.swap({ window = "address:" .. pair[1], target = "address:" .. pair[2] }))
    end
  end
end

local function conclude(run)
  if not run.live then return end
  run.live = false
  stop_timer(run)
  if run.deadline then pcall(run.deadline.set_enabled, run.deadline, false) end
  if run.layout ~= "floating" then
    local ok, err = pcall(reorder, run)
    if not ok then log("reorder failed: " .. tostring(err)) end
  end
  -- An app can open on another workspace and pull the view along (S9): put the view on the target, or on the last
  -- rule desktop (D9).
  if run.focus_ws then pcall(hl.dispatch, hl.dsp.focus({ workspace = tostring(run.focus_ws) })) end
  local placed, missed = 0, {}
  for _, s in ipairs(run.book.slots) do
    if s.state == "claimed" then placed = placed + 1 else missed[#missed + 1] = s.class .. " " .. s.state end
  end
  run.state = (#missed == 0 and not run.forced) and "done" or "partial"
  if memory_on() then
    local ok_m, err_m = pcall(function()
      local changed = false
      for _, s in ipairs(run.book.slots) do
        local info = run.info[s.n]
        local w = s.state == "claimed" and info.address and Place.find(info.address)
        local p = w and place_of(w)
        if p then
          p.kind, p.class, p.context = "placed", s.class, s.context ~= "" and s.context or nil
          if info.rect and p.floating then p.rect = info.rect end -- the scene's own fractions, not a rounded read back
          changed = Memory.update(M.memory, p, M.settings.app_memory, os.time()) or changed
          track(w)
          if w.workspace and M.settings.app_memory == "auto" then M.last_ws[w.address] = w.workspace.id end
        end
      end
      -- a binding lives only while its workspace has windows, and only auto mode removes it again
      if run.scene and placed > 0 and M.settings.app_memory == "auto" and Memory.bind(M.memory, run.scene_ws, run.scene, run.apps) then changed = true end
      if changed then save_memory() end
    end)
    if not ok_m then log("memory update failed: " .. tostring(err_m)) end
  end
  local ok_p, err_p = pcall(function() M.track_run(run) end)
  if not ok_p then log("plan tracking failed: " .. tostring(err_p)) end
  write_status(run)
  log(string.format("run %s %s: %d placed%s", run.id, run.state, placed,
    #missed > 0 and (", not placed: " .. table.concat(missed, ", ")) or ""))
end

-- Omarchy re-arranges tiled windows about 1 s after the last one opens, so a tiled run waits settle_ms before it
-- reads positions to reorder (and before it ends).
local function finish(run)
  if not run.live or run.finishing then return end
  local claimed = 0
  for _, sl in ipairs(run.book.slots) do
    if sl.state == "claimed" then claimed = claimed + 1 end
  end
  if run.layout ~= "floating" and claimed > 1 then -- fewer than two windows: nothing to put in order
    run.finishing = true
    stop_timer(run)
    if pcall(later, M.settings.settle_ms, function() conclude(run) end) then return end
  end
  conclude(run)
end

local step

-- One put finished (or was not needed). The run ends when every slot is final and no put is still pending.
local function settled(run, n, ok, reason)
  if ok == false and n then Tickets.fail(run.book, n, reason or "not_placed") end
  run.pending = run.pending - 1
  if run.live and run.pending == 0 and Tickets.finished(run.book) then finish(run) end
end

local function tag(w, text) hl.dispatch(hl.dsp.window.tag({ tag = text, window = Place.sel(w) })) end

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
  local moved = Place.to_workspace(w, info.target.ws, not info.target.follow, info.target.mon and info.target.mon.name)
  if info.target.follow then run.focus_ws = info.target.ws end
  if not info.rect then return end
  local address = w.address
  local function put_inner()
    if not run.live then return settled(run) end
    local now_w = Place.find(address)
    if not now_w then return settled(run, s.n, false, "gone") end
    -- a `full` plan window: maximized after placing, like a snap (fullscreen state 1 keeps the bar, S11)
    local function maximize(x)
      if info.fullscreen and x then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = Place.sel(x) }))
      end
    end
    -- not floating there (a tiled desktop): no rect, and that is not an error (D13)
    if not (now_w.floating and (info.float_target or has_tag(now_w, M.FLOAT_TAG))) then
      maximize(now_w)
      return settled(run)
    end
    local area = Geometry.usable(info.target.mon)
    Place.put(now_w, Geometry.place_frac(area, info.rect), function(ok, reason)
      maximize(Place.find(address))
      settled(run, s.n, ok, reason)
    end)
  end
  -- a raise must not leave the run waiting for a put that never ends
  local function put_now()
    local ok, err = pcall(put_inner)
    if not ok then log("place failed: " .. tostring(err)); settled(run, s.n, false, "error") end
  end
  -- Omarchy re-arranges a moved window about 1 s later, and a new app may still resize itself: wait (settle_ms).
  -- pending is raised only once the timer exists: a raise from `later` must not leave the run waiting forever
  if moved or fresh then
    later(M.settings.settle_ms, put_now)
    run.pending = run.pending + 1
  else
    run.pending = run.pending + 1
    put_now()
  end
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
local function step_inner(run)
  if not run.live then return end
  local now = M.now_ms()
  Tickets.expire(run.book, now)
  while true do
    local batch = Tickets.next_launches(run.book, now)
    if #batch == 0 then break end
    for _, s in ipairs(batch) do
      local ok, err = pcall(start_slot, run, s)
      if not ok then log("start failed: " .. tostring(err)); Tickets.fail(run.book, s.n, "error") end
    end
  end
  if run.pending == 0 and Tickets.finished(run.book) then return finish(run) end
  arm(run, Tickets.next_wake(run.book, now), now)
  write_status(run)
end

-- A raise anywhere in a step ends the run (partial) instead of leaving it live and every later open busy.
step = function(run)
  local ok, err = pcall(step_inner, run)
  if ok then return end
  log("run step failed: " .. tostring(err))
  for _, s in ipairs(run.book.slots) do
    if s.state == "waiting" or s.state == "launched" then Tickets.fail(run.book, s.n, "error") end
  end
  run.pending = 0
  pcall(conclude, run)
  run.live = false
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
  -- What the target shows now beats the plan: Omarchy tags every window on a floating workspace; a tiled window
  -- without the tag means tiled. An empty target keeps the plan's layout.
  if main then
    local seen
    for _, w in ipairs(hl.get_windows()) do
      if w.workspace and w.workspace.id == main.ws then
        if has_tag(w, M.FLOAT_TAG) then seen = "floating"; break end
        if not w.floating then seen = "tiled" end
      end
    end
    layout = seen or layout
  end
  local expiry_s = math.max(1, math.min(600, math.tointeger(plan.expiry_s) or M.settings.expiry_seconds))
  local book = Tickets.new(plan.windows, now, {
    expiry_ms = expiry_s * 1000,
    tick_ms = M.settings.launch_tick_ms, quiet_ms = M.settings.context_quiet_ms,
    sequential = layout ~= "floating" and M.settings.tiled_order,
  })
  local run = { id = plan.run, live = true, state = "running", book = book, info = {}, t0 = now, wall0 = os.time(),
    pending = 0, gen = 0, layout = layout, focus_ws = main and main.ws }
  -- the scene this run opens and the workspace it opens it on, bound when the run ends (auto app memory)
  if type(plan.scene) == "string" and main then
    run.scene, run.scene_ws, run.apps = plan.scene, main.ws, {}
    for _, w in ipairs(plan.windows) do
      if type(w) == "table" and type(w.class) == "string" then -- plain table: a plan window
        run.apps[#run.apps + 1] = Memory.key(w.class, type(w.context) == "string" and w.context or "")
      end
    end
  end
  for i, w in ipairs(plan.windows) do
    local t = type(w) == "table" and target_of(w) or nil -- plain table: a plan window
    run.info[i] = { target = t, launch = w.launch, rect = valid_rect(w.rect), fullscreen = w.fullscreen == 1,
      float_target = t ~= nil and layout == "floating" and (main == nil or t.ws == main.ws) }
    if not t and book.slots[i].state ~= "skipped" then Tickets.fail(book, i, "no_monitor") end
  end
  M.run = run
  -- One overall limit per run: whatever is still pending then is given up and the run ends partial.
  run.deadline = later(expiry_s * 1000 + M.settings.settle_ms + 2000, function()
    if not run.live then return end
    run.forced = true
    for _, s in ipairs(book.slots) do
      if s.state == "waiting" or s.state == "launched" or s.state == "claimed" and run.pending > 0 then
        Tickets.fail(book, s.n, "timeout")
      end
    end
    run.pending = 0
    conclude(run)
  end)
  -- Move pass (D10): open windows take their slots by class and context, in plan order.
  if (plan.existing or M.settings.existing_default) == "move" then
    local wins = {}
    for _, w in ipairs(hl.get_windows()) do wins[#wins + 1] = w end
    table.sort(wins, function(a, b) return (a.stable_id or 0) < (b.stable_id or 0) end)
    -- a re-place after "Update plan" (D24) moves only the windows tracked for this plan
    local only = plan.only_tracked == true and plan.scene
    for _, w in ipairs(wins) do
      local ws = w.workspace or {}
      local special = (ws.id or 0) < 0 and not Capture.home_of(w)
      local e = M.snapped[w.address]
      if not special and (w.initial_class or "") ~= "" and (not only or (e and e.scene == only)) then
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
  if not runtime_dir() then return nil, "no_runtime" end
  if M.run and M.run.live then return nil, "busy" end
  local ok, id, err = pcall(start_run, plan)
  if not ok then
    log("open failed: " .. tostring(id))
    if M.run and M.run.live then
      M.run.live = false
      stop_timer(M.run)
      if M.run.deadline then pcall(M.run.deadline.set_enabled, M.run.deadline, false) end
    end
    return nil, "failed"
  end
  return id, err
end

-- Load a `return { ... }` file as text only, in an empty environment, under the instruction budget: it can build a
-- table and nothing else. nil and a reason that never quotes the text (it can hold folders and arguments).
local MAX_LITERAL = 1048576
local function load_literal(path, name)
  local text = read_file(path, MAX_LITERAL)
  if not text then return nil, "no_file" end
  if #text > MAX_LITERAL then return nil, "is over 1 MB" end
  local chunk = load(text, name, "t", {})
  if not chunk then return nil, "does not parse" end
  local ok, t = Memory.run_limited(chunk)
  if not ok then return nil, "failed to run" end
  if type(t) ~= "table" then return nil, "is not a table" end
  return t
end

-- open_file(path): the same as open(plan) for a plan the service wrote to
-- $XDG_RUNTIME_DIR/omaplace/plan-<run>.lua (`return { ... }`), because one hyprctl argument is capped at 128 kB.
function M.open_file(path)
  local base = runtime_dir()
  if not base then return nil, "no_runtime" end
  local prefix = base .. "/plan-"
  if type(path) ~= "string" or path:sub(1, #prefix) ~= prefix or path:find("/", #prefix + 1, true)
    or not path:match("%.lua$") then
    return nil, "bad_path"
  end
  local plan, why = load_literal(path, "plan")
  if why == "no_file" then return nil, why end
  if not plan then log("plan file " .. why); return nil, "bad_plan" end
  return M.open(plan)
end

-- ---------------------------------------------------------------- app memory, events (F5, design 6.3)

-- An enabled placement rule for this class (rules match initial_class only, so context plays no part).
local function has_rule(cls)
  for name, rule in pairs(M.rules) do
    if rule.app == cls and M.enabled["omaplace-rule-" .. name] then return true end -- rules.lua's spec name
  end
  return false
end

-- A rule with keep_rect (D27): its first window, once on the rule's desktop, is put at the rule's rect after settle_ms,
-- only when it floats there (D13). True when the rule owns the rect, so plans and app memory keep out of it.
local function place_from_rule(w)
  local cls = w.initial_class or ""
  if cls == "" or not M.rule_places then return false end
  for name, rule in pairs(M.rules) do
    local p, rect = M.rule_places[name], Rules.rect_of(rule)
    if rule.app == cls and p and rect and M.enabled["omaplace-rule-" .. name] then
      local ws = w.workspace
      if not ws or ws.id ~= p.ws or others_of(cls, w.address) > 0 then return false end
      local address = w.address
      later(M.settings.settle_ms, function()
        local now_w = Place.find(address)
        if not (now_w and now_w.floating and has_tag(now_w, M.FLOAT_TAG)) then return end
        local mon
        for _, m in ipairs(hl.get_monitors()) do
          if m.name == p.monitor then mon = m end
        end
        if not mon then return end
        Place.put(now_w, Geometry.place_frac(Geometry.usable(mon), rect), function(ok, reason)
          if not ok then log("rule place of " .. cls .. " failed: " .. tostring(reason)) end
        end)
      end)
      return true
    end
  end
  return false
end
M.place_from_rule = place_from_rule

-- A window opened by hand while no run is live goes to its remembered place when it is the first window of its
-- class, not on a special workspace. A rule's desktop wins (D9); the rect only on a floating desktop (D13).
local function place_from_memory(w)
  if not memory_on() then return end
  local cls = w.initial_class or ""
  if cls == "" then return end
  local entry = Memory.lookup(M.memory, cls, Capture.context_of(w))
  if not entry then return end
  local ws = w.workspace
  if not ws or (ws.id or 0) < 0 or (ws.name or ""):sub(1, 8) == "special:" then return end
  if others_of(cls, w.address) > 0 then return end
  local mon = Monitors.resolve(entry.fp, hl.get_monitors(), M.settings.missing_monitor_scene)
  local target = mon and Slots.with(rawget(_G, "o")).workspace_id(mon, entry.slot)
  if not target then return end
  if has_rule(cls) then
    if target ~= ws.id then return end -- the rule put it on another desktop: leave it there, no rect
  else
    -- set before the move (its event can come during the dispatch): a long settle_ms would let the debounce read
    -- the window before the put and overwrite the rect
    if ws.id ~= target and #M.memory_subs > 0 then M.memory_own[w.address] = true end
    Place.to_workspace(w, target, true, mon.name)
  end
  tag(w, "+" .. M.MEMORY_TAG)
  if not (entry.floating and entry.rect) then return end
  local address, rect = w.address, entry.rect
  -- Omarchy re-arranges a moved window about 1 s later, and a new app may still resize itself: wait (settle_ms).
  later(M.settings.settle_ms, function()
    local now_w = Place.find(address)
    if not (now_w and now_w.floating and has_tag(now_w, M.FLOAT_TAG)) then return end
    Place.put(now_w, Geometry.place_frac(Geometry.usable(mon), rect), function(ok, reason)
      if not ok then log("memory place of " .. cls .. " failed: " .. tostring(reason)) end
    end)
  end)
end
M.place_from_memory = place_from_memory

-- ---- auto mode: a window moved from one bound workspace to another (design 6.3, `auto`)

-- Left-to-right rank of `w` among the windows on its workspace (ties by y, then address). Classes in `ignore` do not count.
local function rank_on(w)
  local ignore = Capture.ignore_set(M.settings.ignore)
  local function xy(x)
    local at = x.at or {}
    return tonumber(at.x) or 0, tonumber(at.y) or 0
  end
  local wx, wy = xy(w)
  local rank = 1
  for _, x in ipairs(hl.get_windows()) do
    local ws = x.workspace
    if ws and ws.id == w.workspace.id and x.address ~= w.address and not ignore[(x.initial_class or ""):lower()] then
      local xx, xyv = xy(x)
      if xx < wx or (xx == wx and (xyv < wy or (xyv == wy and tostring(x.address) < tostring(w.address)))) then
        rank = rank + 1
      end
    end
  end
  return rank
end

local function drop_first(list, key)
  for i, k in ipairs(list) do
    if k == key then table.remove(list, i); return true end
  end
  return false
end

local function push_move(ev)
  M.moves[#M.moves + 1] = ev
  while #M.moves > M.MAX_MOVES do table.remove(M.moves, 1) end
  local text, err = Json.encode(M.moves)
  if not text then log("moves encode failed: " .. tostring(err)); return end
  write_atomic("moves.json", text .. "\n")
end

-- Report the move of `w` (now on its new workspace) when it left a bound workspace for another bound one. `from` is the
-- workspace it was last seen on; when that is unknown, the one other bound workspace that holds the app. Returns true
-- when the bound apps changed (the caller saves). Never writes a title.
local function report_move(w, from)
  local to = w.workspace and math.tointeger(w.workspace.id)
  local cls = w.initial_class or ""
  if not to or to < 1 or cls == "" then return false end
  local ctx = Capture.context_of(w) or ""
  local key = Memory.key(cls, ctx)
  local bt = Memory.bound(M.memory, to)
  if not bt then return false end
  local bf = from and Memory.bound(M.memory, from)
  if not from then
    local found, count = nil, 0
    for id, b in pairs(M.memory.bound or {}) do
      if id ~= tostring(to) and b.scene ~= bt.scene then
        for _, k in ipairs(b.apps) do
          if k == key then found, count, from = b, count + 1, tonumber(id); break end
        end
      end
    end
    bf = count == 1 and found or nil
  end
  if not bf or from == to or bf.scene == bt.scene or not drop_first(bf.apps, key) then return false end
  local has = false
  for _, k in ipairs(bt.apps) do has = has or k == key end
  if not has then bt.apps[#bt.apps + 1] = key end
  local p = place_of(w)
  if p then
    push_move({ class = cls, context = ctx, from_scene = bf.scene, to_scene = bt.scene, rect = p.rect,
      floating = p.floating, order = rank_on(w), at = M.now_ms() })
  end
  return true
end

-- A workspace with no window left is not a scene any more.
local function unbind_empty()
  local full = {}
  for _, x in ipairs(hl.get_windows()) do
    if x.workspace and x.workspace.id then full[tostring(x.workspace.id)] = true end
  end
  local drop = {}
  for id in pairs(M.memory.bound or {}) do
    if not full[id] then drop[#drop + 1] = id end
  end
  for _, id in ipairs(drop) do Memory.unbind(M.memory, id) end
  return #drop > 0
end

-- One debounce for close and move (last_place, auto): a close is read at once (the window is gone later), a move
-- when the timer fires (after Omarchy re-arranged it). One save per burst.
local function arm_memory_save()
  M.memory_gen = (M.memory_gen or 0) + 1
  local gen = M.memory_gen
  if M.memory_timer then pcall(M.memory_timer.set_enabled, M.memory_timer, false) end
  M.memory_timer = later(M.MEMORY_DEBOUNCE_MS, function()
    if gen ~= M.memory_gen then return end
    M.memory_timer = nil
    local changed = M.memory_dirty == true
    M.memory_dirty = false
    local moved = M.memory_moved
    M.memory_moved = {}
    local from_of = M.auto_from
    M.auto_from = {}
    for address in pairs(moved) do
      local w = Place.find(address)
      if w then
        changed = remember("moved", w) or changed
        if M.settings.app_memory == "auto" then
          local ok, did = pcall(report_move, w, from_of[address])
          if ok then changed = did or changed else log("move report failed: " .. tostring(did)) end
        end
      end
    end
    changed = unbind_empty() or changed
    if changed then save_memory() end
  end)
end

function M.on_memory_event(event, w)
  local tw = type(w)
  if not memory_on() or (tw ~= "table" and tw ~= "userdata") then return end
  local auto = M.settings.app_memory == "auto"
  local from
  if event == "window.close" then
    if w.address then M.memory_own[w.address] = nil; M.last_ws[w.address] = nil end
    if remember("closed", w) then M.memory_dirty = true; arm_memory_save() end
    if w.address then M.places[w.address] = nil end
    if next(M.memory.bound or {}) then arm_memory_save() end -- the workspace may be empty now
    return
  end
  track(w)
  if auto and w.address and w.workspace then -- where it was before this move, and where it is now
    from, M.last_ws[w.address] = M.last_ws[w.address], w.workspace.id
  end
  if w.address and M.memory_own[w.address] then
    M.memory_own[w.address] = nil
  elseif not (M.run and M.run.live) and w.address then -- a run's own moves are recorded when it ends
    M.memory_moved[w.address] = true
    if from then M.auto_from[w.address] = M.auto_from[w.address] or from end
    arm_memory_save()
  end
end

-- Subscribe to close and move only in the modes that record them (at load and on reload_config).
function M.sync_memory()
  local on = M.settings.app_memory == "last_place" or M.settings.app_memory == "auto"
  if on == (#M.memory_subs > 0) then return end
  for _, sub in ipairs(M.memory_subs) do pcall(sub.remove, sub) end
  M.memory_subs = {}
  if not on then return end
  for _, event in ipairs({ "window.close", "window.move_to_workspace" }) do
    local sub = hl.on(event, function(w)
      local handled, e = pcall(function() _G.omaplace._m.on_memory_event(event, w) end)
      if not handled then log(event .. " memory handler failed: " .. tostring(e)) end
    end)
    if sub then M.memory_subs[#M.memory_subs + 1] = sub end
  end
end

-- A new window: claimed by a live run, or else placed from app memory.
function M.on_window_open(w)
  local run = M.run
  -- Hyprland hands windows over as userdata (HL.Window), the tests as tables: accept both, nothing else.
  local tw = type(w)
  if tw ~= "table" and tw ~= "userdata" then return end
  if (w.initial_class or "") == Capture.ALWAYS_IGNORED then return end -- the settings app (D39)
  if M.settings.app_memory == "auto" and w.address and w.workspace then M.last_ws[w.address] = w.workspace.id end
  track(w)
  if w.workspace then Place.home(w.workspace.id, (M.rule_homes or {})[w.workspace.id]) end -- a rule's desktop
  if not (run and run.live) then
    if place_from_rule(w) then return end -- a rule's own rect wins over a plan and app memory (D9, D27)
    if M.place_from_plan(w) then return end -- a planned app is the plan's, never memory's (D20)
    return place_from_memory(w)
  end
  local mine = M.SLOT_PREFIX .. run.id .. "/"
  for _, t in ipairs(Capture.tags_of(w)) do
    if t:sub(1, #mine) == mine then return end -- already claimed by this run
  end
  local cls = w.initial_class or ""
  if cls == "" then return end
  local s = Tickets.claim(run.book, { class = cls, context = Capture.context_of(w) }, M.now_ms())
  if s then
    local ok, err = pcall(apply, run, s, w, true)
    if not ok then log("apply failed: " .. tostring(err)); Tickets.fail(run.book, s.n, "error") end
  end
  step(run)
end

-- A reload during a run: the old run stops (same Lua state) and status.json says interrupted (also when the Lua
-- state is new and only the file remembers the run).
local function interrupt_stale(prev)
  if prev and prev.run and prev.run.live then
    prev.run.live = false
    prev.run.gen = prev.run.gen + 1
    if prev.run.timer then pcall(prev.run.timer.set_enabled, prev.run.timer, false) end
    if prev.run.deadline then pcall(prev.run.deadline.set_enabled, prev.run.deadline, false) end
    prev.run.state = "interrupted"
    M.run = prev.run
  end
  local base = runtime_dir()
  local text = base and read_file(base .. "/status.json")
  if text and text:find('"state":"running"', 1, true) then
    write_atomic("status.json", (text:gsub('"state":"running"', '"state":"interrupted"')))
    log("a scene run was interrupted by a reload")
  end
end

-- ---------------------------------------------------------------- session snapshots (design 6.4)
-- One file per Hyprland instance, so a new boot never overwrites the previous boot's last session. sessions.json
-- lists the instances newest first (Lua cannot list a folder), and only this file writes either.

local warned_instance = false
local function instance()
  local sig = (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""):gsub("[^A-Za-z0-9_]", "_"):sub(1, 128)
  if sig == "" and not warned_instance then
    warned_instance = true
    log("HYPRLAND_INSTANCE_SIGNATURE is not set: session snapshots are off")
  end
  return sig ~= "" and sig or nil
end

-- sessions.json is written only below, by Json.encode with sorted keys, so a pattern reads it back.
local function read_index(d)
  local out = {}
  for name, at in (read_file(d .. "/sessions.json") or ""):gmatch('{"instance":"([A-Za-z0-9_]+)","saved_at":(%d+)}') do
    out[#out + 1] = { instance = name, saved_at = math.tointeger(tonumber(at)) }
  end
  return out
end

-- Write session-<instance>.json now (no debounce, no freeze check) and put this instance first in the index;
-- instances beyond session_keep lose their file. A desktop with no windows is never written (close-all).
function M.session_save()
  local d, inst = state_dir(), instance()
  if not d or not inst then return nil, "no_instance" end
  local snap = snapshot_of("all", "session")
  if #snap.windows == 0 then return nil, "empty" end
  for _, w in ipairs(snap.windows) do w.pid = nil end -- runtime only, never stored
  local text, err = Json.encode(snap)
  if not text then log("session encode failed: " .. tostring(err)); return nil, "failed" end
  local ok_w, werr = write_in(d, "session-" .. inst .. ".json", text .. "\n")
  if not ok_w then return nil, werr end
  local list = { { instance = inst, saved_at = snap.saved_at } }
  local index = read_index(d)
  -- the newest other instance (the previous login) is never pruned, whatever session_keep says
  local newest
  for _, e in ipairs(index) do
    if e.instance ~= inst and (not newest or e.saved_at > newest.saved_at) then newest = e end
  end
  for _, e in ipairs(index) do
    if e.instance ~= inst then
      if e == newest or #list < M.settings.session_keep then
        list[#list + 1] = e
      else
        os.remove(d .. "/session-" .. e.instance .. ".json")
      end
    end
  end
  return write_in(d, "sessions.json", Json.encode(list) .. "\n")
end

-- One live debounce timer for the whole session: each arm replaces it (see arm_session).
-- at = nil only disarms. session_at is the time the write is owed, so an early wake-up just re-arms.
local arm_session
local function on_session_timer()
  local ok_t, err_t = pcall(function()
    if not M.session_at then return end
    local t = M.now_ms()
    if t < M.session_at then return arm_session(M.session_at, t) end
    M.session_at = nil
    if Policy.frozen(M.session_state, t) then return arm_session(M.session_state.frozen_until, t) end
    Policy.fired(M.session_state)
    local ok_s, err = M.session_save()
    if not ok_s and err ~= "empty" then log("session save failed: " .. tostring(err)) end
  end)
  if not ok_t then log("timer failed: " .. tostring(err_t)) end
end

function arm_session(at, now)
  if not at then
    M.session_at = nil
    if M.session_timer then pcall(M.session_timer.set_enabled, M.session_timer, false) end
    return
  end
  M.session_at = at
  local ms = math.max(1, math.floor(at - now))
  -- A fired one-shot HL.Timer cannot be re-armed (set_timeout and set_enabled(true) do nothing; checked live
  -- 2026-11-21), so every arm makes a fresh timer and switches the old one off. session_at guards stale fires.
  if M.session_timer then pcall(M.session_timer.set_enabled, M.session_timer, false) end
  M.session_timer = hl.timer(on_session_timer, { type = "oneshot", timeout = ms })
end

function M.on_session_event(kind)
  local now = M.now_ms()
  local r = Policy.on_event(M.session_state, kind, now)
  if r.action == "schedule" then
    arm_session(r.at, now)
  elseif r.action == "freeze" and M.session_at then
    arm_session(r.until_ms, now) -- a pending write moves to the end of the freeze
  end
end

-- session_save_now(): ignores the debounce, not the freeze. true, or nil and frozen | empty | no_instance | write_failed.
function M.session_save_now()
  if Policy.frozen(M.session_state, M.now_ms()) then return nil, "frozen" end
  arm_session(nil)
  Policy.fired(M.session_state)
  return M.session_save()
end

-- sessions(): the index, newest first: { { instance = "...", saved_at = <unix s> }, ... }.
function M.sessions()
  local d = state_dir()
  return d and read_index(d) or {}
end

M.SESSION_EVENTS = { "window.open", "window.close", "window.move_to_workspace", "window.active", "monitor.added",
  "monitor.removed", "monitor.layout_changed" }

-- Subscribe or unsubscribe to match the `session` setting (at load and on reload_config).
function M.sync_session()
  M.session_state.debounce_ms = M.settings.session_debounce_s * 1000
  local on = M.settings.session == "on"
  if on == (#M.session_subs > 0) then return end
  for _, sub in ipairs(M.session_subs) do pcall(sub.remove, sub) end
  M.session_subs = {}
  if not on then arm_session(nil); return end
  for _, event in ipairs(M.SESSION_EVENTS) do
    local sub = hl.on(event, function()
      local handled, e = pcall(function() _G.omaplace._m.on_session_event(event) end)
      if not handled then log(event .. " session handler failed: " .. tostring(e)) end
    end)
    if sub then M.session_subs[#M.session_subs + 1] = sub end
  end
end

-- ---------------------------------------------------------------- desktop plans (design 14.7, 14.8, D20, D21, D23)
-- ~/.local/state/omaplace/plans.lua is written by the service only; Lua reads it and writes plan-moves.json and
-- login.json in the runtime folder. A new window: run ticket > user rule (D9) > plan > app memory.

-- Report a hand move of a snapped window (kind "desktop" or "zone"). The last MAX_PLAN_MOVES stay in the file. A
-- tiled window has no `rect` key (the encoder writes no null). Never writes a title.
local function report_plan_move(e, kind, w)
  local p = place_of(w)
  if not p then return false end
  local mv = M.plan_moves
  mv.seq = mv.seq + 1
  mv.list[#mv.list + 1] = { id = mv.seq, scene = e.scene, window = e.window, class = e.class, context = e.context,
    kind = kind, to = { identity = p.fp.identity, slot = p.slot, rect = p.floating and p.rect or nil, floating = p.floating } }
  while #mv.list > M.MAX_PLAN_MOVES do table.remove(mv.list, 1) end
  local text, err = Json.encode({ seq = mv.seq, moves = mv.list })
  if not text then log("plan moves encode failed: " .. tostring(err)); return false end
  if write_atomic("plan-moves.json", text .. "\n") ~= true then return false end
  -- Lua sends the notification itself: the service's watch can miss a renamed-in file. Async, class and scene only.
  local cmd = Shellquote.join({ "omarchy-notification-send", "-g", M.NOTIFY_GLYPH, "omaplace",
    e.class .. " moved. Update the plan " .. e.scene .. "?",
    "--action", "Update plan", M.PLUGIN_DIR .. "/bin/omaplace", "plan-update", tostring(mv.seq) })
  if cmd then pcall(hl.exec_cmd, cmd) end
  return true
end

-- The monitor and workspace of a plan's home desktop, or nil (an empty home_monitor is the focused one, as for rules).
local function plan_target(plan)
  local live = hl.get_monitors()
  local mon = plan.home_monitor == "" and focused_of(live) or Monitors.resolve({ identity = plan.home_monitor }, live, "skip")
  return mon, mon and Slots.with(rawget(_G, "o")).workspace_id(mon, plan.home_slot)
end

-- A window opened while no run is live. Returns true when a plan holds its class and context (snapped or not), so app
-- memory stays out. Snaps only the first window of the class, snap = true entries, no user rule, a desktop that resolves.
function M.place_from_plan(w)
  local cls = w.initial_class or ""
  if not M.plans or cls == "" then return false end
  local ctx = Capture.context_of(w)
  if not Plans.held(M.plans, cls, ctx) then return false end
  local plan, index, pw = Plans.lookup(M.plans, cls, ctx)
  if not plan or has_rule(cls) then return true end
  local ws = w.workspace
  if not ws or (ws.id or 0) < 0 or (ws.name or ""):sub(1, 8) == "special:" or others_of(cls, w.address) > 0 then
    return true
  end
  local mon, target = plan_target(plan)
  if not target then log("plan " .. plan.scene .. ": desktop not found, " .. cls .. " not snapped"); return true end
  local address = w.address
  local e = { scene = plan.scene, window = index, class = pw.class, context = pw.context, ws = target, rect = pw.rect,
    floating = pw.floating }
  M.snapped[address] = e
  if ws.id ~= target then
    -- marked before the dispatch: its event can come during it
    M.plan_own[address] = true
    if #M.memory_subs > 0 then M.memory_own[address] = true end
    Place.to_workspace(w, target, true, mon and mon.name)
  end
  if pw.floating then hl.dispatch(hl.dsp.window.float({ action = "on", window = Place.sel(w) })) end
  local function maximize(x)
    -- fullscreen state 1 keeps the bar (S11 still to check live)
    if pw.fullscreen == 1 then
      hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set", window = Place.sel(x) }))
    end
  end
  -- Omarchy re-arranges a moved window about 1 s later, and a new app may still resize itself: wait (settle_ms).
  later(M.settings.settle_ms, function()
    local now_w = Place.find(address)
    if not now_w or M.snapped[address] ~= e then return end
    if not (pw.floating and now_w.floating) then return maximize(now_w) end
    Place.put(now_w, Geometry.place_frac(Geometry.usable(mon), pw.rect), function(ok, reason)
      if ok then e.placed = true else log("plan place of " .. cls .. " failed: " .. tostring(reason)) end
      local again = Place.find(address)
      if again then maximize(again) end
    end)
  end)
  return true
end

-- A run of a plan scene ("Open all", login) ended: its placed windows are tracked like snapped ones (D21). Windows
-- the run did not place stay untracked.
function M.track_run(run)
  local plan = run.scene and M.plans and Plans.by_scene(M.plans, run.scene)
  if not plan then return end
  local slots, items = {}, {}
  for _, s in ipairs(run.book.slots) do
    local info = run.info[s.n]
    if s.state == "claimed" and info.address and info.target then
      slots[#slots + 1] = s
      items[#items + 1] = { class = s.class, context = s.context, rect = info.rect }
    end
  end
  for k, index in pairs(Plans.match_run(plan, items)) do
    local s, pw = slots[k], plan.windows[index]
    local info = run.info[s.n]
    M.snapped[info.address] = { scene = plan.scene, window = index, class = pw.class, context = pw.context,
      ws = info.target.ws, rect = pw.rect, floating = pw.floating, placed = true }
  end
end

function M.on_plan_event(event, w)
  if event == "window.active" then
    local prev = M.last_active
    M.last_active = w and w.address or nil
    local e = prev and prev ~= M.last_active and M.snapped[prev]
    -- D23: only a placed floating window, still on its plan's desktop, and not while a run moves windows
    if not (e and e.placed and e.floating) or (M.run and M.run.live) then return end
    local now_w = Place.find(prev)
    if not (now_w and now_w.floating and now_w.workspace and now_w.workspace.id == e.ws) then return end
    local p = place_of(now_w)
    if not (p and p.rect) then return end
    if not Plans.drifted(p.rect, e.rect) then e.zone_reported = false; return end
    if not e.zone_reported then e.zone_reported = report_plan_move(e, "zone", now_w) end
    return
  end
  local a = w and w.address
  if not a then return end
  if event == "window.close" then
    M.snapped[a], M.plan_own[a] = nil, nil
    if M.last_active == a then M.last_active = nil end
    return
  end
  local e = M.snapped[a] -- window.move_to_workspace
  if not e then return end
  if M.plan_own[a] then M.plan_own[a] = nil; return end
  if M.run and M.run.live then return end -- "Open all" moves its own windows
  if w.workspace and w.workspace.id == e.ws then e.desk_reported = false; return end
  if not e.desk_reported then e.desk_reported = report_plan_move(e, "desktop", w) end
end

-- Subscribe while some plan is loaded.
local function sync_plans()
  local on = M.plans ~= nil and #M.plans.plans > 0
  if on == (#M.plan_subs > 0) then return end
  for _, sub in ipairs(M.plan_subs) do pcall(sub.remove, sub) end
  M.plan_subs = {}
  if not on then return end
  for _, event in ipairs({ "window.close", "window.move_to_workspace", "window.active" }) do
    local sub = hl.on(event, function(w)
      local handled, e = pcall(function() _G.omaplace._m.on_plan_event(event, w) end)
      if not handled then log(event .. " plan handler failed: " .. tostring(e)) end
    end)
    if sub then M.plan_subs[#M.plan_subs + 1] = sub end
  end
end

-- Ask the service to open the ticked plans, once per Hyprland instance (14.7): never again when login.json already
-- names this instance (a reload). Done once per Lua state; a failed write is tried again on the next plans load.
local function login_check()
  if M.login_checked or not M.plans then return end
  local names = Plans.login_plans(M.plans)
  if #names == 0 then M.login_checked = true; return end
  local inst, base = instance(), runtime_dir()
  if not inst or not base then return end
  if (read_file(base .. "/login.json", 65536) or ""):find('"instance":"' .. inst .. '"', 1, true) then
    M.login_checked = true
    return
  end
  local text = Json.encode({ instance = inst, plans = names })
  if text and write_atomic("login.json", text .. "\n") then
    M.login_checked = true
    log("login: " .. #names .. " plan(s) to open")
  end
end

-- reload_plans(): read plans.lua again. true, or nil and no_file | bad_plans | failed. A bad file is ignored (the
-- plans loaded before stay); a missing one means no plans.
function M.reload_plans()
  local ok, res, why = pcall(function()
    local d = state_dir()
    local t, err
    if d then t, err = load_literal(d .. "/plans.lua", "plans") end
    if not d or err == "no_file" then
      M.plans, M.snapped, M.plan_own = nil, {}, {}
      sync_plans()
      return nil, "no_file"
    end
    local set
    if t then set, err = Plans.validate(t) end
    if not set then log("plans.lua " .. tostring(err) .. ", ignored"); sync_plans(); return nil, "bad_plans" end
    for _, skip in ipairs(set.skipped) do log("plans.lua: " .. skip .. ", skipped") end
    M.plans = set
    -- a snapped window follows its plan as it is now (an "Update plan" or a page edit); gone from the plans, it is dropped
    local open = {}
    for _, x in ipairs(hl.get_windows()) do
      if x.address then open[x.address] = true end
    end
    for address, e in pairs(M.snapped) do
      -- the same scene and window number while it still holds this app (keeps windows Open all placed), else a lookup
      local plan, index = Plans.by_scene(set, e.scene), e.window
      local pw = plan and plan.windows[index]
      if not (pw and pw.class == e.class and pw.context == e.context) then
        plan, index, pw = Plans.lookup(set, e.class, e.context)
      end
      local ws
      if plan and open[address] then ws = select(2, plan_target(plan)) end
      if ws then
        e.scene, e.window, e.ws, e.rect, e.floating = plan.scene, index, ws, pw.rect, pw.floating
        e.desk_reported, e.zone_reported = false, false
      else
        M.snapped[address] = nil
      end
    end
    sync_plans()
    login_check()
    return true
  end)
  if not ok then
    log("plans load failed: " .. tostring(res))
    pcall(sync_plans)
    return nil, "failed"
  end
  return res, why
end

-- desktops(req_id): every monitor's slots 1..10 and their workspace ids (14.8). With req_id the answer is also written
-- to $XDG_RUNTIME_DIR/omaplace/desktops-<req_id>.json, because `hyprctl eval` cannot hand a table back (LuaCall).
function M.desktops(req_id)
  local ok, d = pcall(function()
    local slots = Slots.with(rawget(_G, "o"))
    return Plans.desktops(hl.get_monitors(), slots.workspace_id,
      function(m, all) return Monitors.fingerprint(m, all).identity end)
  end)
  if not ok then log("desktops failed: " .. tostring(d)); return nil, "failed" end
  -- omagnet's own layouts ([layout_<name>] zones text), when omagnet is loaded: the page offers them by name (D31)
  local om = rawget(_G, "omagnet")
  if type(om) == "table" then
    local list = {}
    local cfg = type(om.cfg) == "table" and om.cfg or {}
    for name, text in pairs(type(cfg.layouts) == "table" and cfg.layouts or {}) do
      if type(name) == "string" and type(text) == "string" then list[#list + 1] = { name = name, zones = text } end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    d.omagnet = { loaded = true, layouts = list }
    -- D35: the layout omagnet's own config gives each desktop (workspace entry, else the monitor's), never its key override
    local ws_l = type(cfg.workspace_layouts) == "table" and cfg.workspace_layouts or {}
    local mon_l = type(cfg.zone_layouts) == "table" and cfg.zone_layouts or {}
    for _, m in ipairs(d.monitors or {}) do
      for _, s in ipairs(m.slots or {}) do
        local name = ws_l[tostring(s.workspace)] or mon_l[m.name]
        if type(name) == "string" and type(om.resolve_layout) == "function" then
          local ok, zones = pcall(om.resolve_layout, name)
          local parts = {}
          for _, z in ipairs(ok and type(zones) == "table" and zones or {}) do
            if type(z) == "table" and #z == 4 then parts[#parts + 1] = string.format("%.4f %.4f %.4f %.4f", z[1], z[2], z[3], z[4]) end
          end
          if #parts > 0 then s.omagnet = { name = name, zones = table.concat(parts, "; ") } end
        end
      end
    end
  end
  if req_id == nil then return d end
  if type(req_id) ~= "string" or #req_id > 64 or not req_id:match("^[%w_%-]+$") then return nil, "bad_req" end
  local text = Json.encode(d)
  if not text then return nil, "failed" end
  local written, err = write_atomic("desktops-" .. req_id .. ".json", text .. "\n")
  if not written then return nil, err end
  return d
end

-- The settings app floats, centred, like Omarchy's own small apps (D36). o.window is Omarchy's helper; without it the
-- window opens as the desktop puts it.
pcall(function()
  local o = rawget(_G, "o")
  if type(o) == "table" and type(o.window) == "function" then
    o.window("^(omaplace-settings)$", { float = true, center = true, size = { 1040, 720 } })
  end
end)

-- _m is internal: the next load of this file reads them (see above).
_G.omaplace = { version = M.version, reload_config = M.reload_config, status = M.status, open = M.open,
  open_file = M.open_file, capture = M.capture, session_save_now = M.session_save_now, sessions = M.sessions,
  reload_plans = function() return M.reload_plans() end, desktops = function(req_id) return M.desktops(req_id) end,
  _m = M, _rebuild_soon = rebuild_soon }

ensure_dir()
make_dir(state_dir())
-- move ids go on from the file, so an "Update plan" action left from before a restart never hits a new move
if not M.plan_moves then
  local base = runtime_dir()
  local seq = base and (read_file(base .. "/plan-moves.json", 65536) or ""):match('"seq":(%d+)')
  M.plan_moves = { seq = math.tointeger(tonumber(seq or 0)) or 0, list = {} }
end
interrupt_stale(old_m)
-- A reload keeps the memory in this Lua state (it can be newer than the file); a save the old timer still owed is done now.
if old_m and type(old_m.memory) == "table" then
  M.memory = old_m.memory
  if old_m.memory_timer then save_memory() end
else
  M.memory = load_memory()
end

local ok, err = pcall(function() load_config(); sync_session_safe(); assert(M.rebuild()) end)
if not ok then log("load failed: " .. tostring(err)) end
M.reload_plans()

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
