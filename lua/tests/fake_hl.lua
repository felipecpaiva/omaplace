-- A fake `hl` (and Omarchy's `o`) for glue tests. Usage:
--   local fake = dofile(dir .. "/fake_hl.lua").new()
--   fake.hl.on("monitor.added", fn); fake.emit("monitor.added", mon); fake.advance(500)
-- This is the only file that defines `hl`; nothing here is global.
local M = {}

local function dsp_proxy(calls, path)
  return setmetatable({}, {
    __index = function(_, name) return dsp_proxy(calls, path .. (path == "" and "" or ".") .. name) end,
    __call = function(_, args)
      local call = { name = path, args = args }
      calls[#calls + 1] = call
      return call
    end,
  })
end

function M.new()
  local fake = {
    handlers = {}, -- event -> list of fn
    rules = {}, rule_order = {}, -- window rules by name, in first-seen order
    monitors = {}, windows = {},
    exec_log = {}, dsp_calls = {}, dispatched = {},
    now = 0, timers = {}, next_timer = 0,
  }

  local hl = {}
  fake.hl = hl

  function hl.on(event, fn)
    local list = fake.handlers[event] or {}
    fake.handlers[event] = list
    list[#list + 1] = fn
  end

  function hl.window_rule(spec)
    local name = spec.name
    if type(name) ~= "string" then error("window_rule needs a name", 2) end
    if not fake.rules[name] then fake.rule_order[#fake.rule_order + 1] = name end
    fake.rules[name] = spec -- replaced in place: same name, same position
  end

  function hl.get_monitors() return fake.monitors end
  function hl.get_windows() return fake.windows end
  function hl.exec_cmd(cmd) fake.exec_log[#fake.exec_log + 1] = cmd end
  function hl.dispatch(call) fake.dispatched[#fake.dispatched + 1] = call end
  hl.dsp = dsp_proxy(fake.dsp_calls, "")

  -- One-shot timer: fires once, when advance() passes `ms`. Returns a handle with cancel().
  -- Both call forms work: hl.timer(ms, fn) and Hyprland's own hl.timer(fn, { type = "oneshot", timeout = ms }).
  function hl.timer(ms, fn)
    if type(ms) == "function" then
      local opts = fn
      ms, fn = type(opts) == "table" and opts.timeout or 0, ms
    end
    fake.next_timer = fake.next_timer + 1
    local t = { id = fake.next_timer, due = fake.now + ms, fn = fn, live = true }
    fake.timers[#fake.timers + 1] = t
    return { cancel = function() t.live = false end }
  end

  -- Omarchy's workspace module: block per monitor (by index in the monitor list) * 10 + slot.
  fake.o = { workspaces = {} }
  function fake.o.workspaces.workspace_id(monitor, slot)
    for i, m in ipairs(fake.monitors) do
      if m.name == monitor.name then return (i - 1) * 10 + slot end
    end
    return slot
  end

  function fake.emit(event, ...)
    for _, fn in ipairs(fake.handlers[event] or {}) do fn(...) end
  end

  function fake.set_monitors(list) fake.monitors = list end
  function fake.set_windows(list) fake.windows = list end

  -- The rules that are on: same order they were first added, `enabled = false` left out.
  function fake.active_rules()
    local out = {}
    for _, name in ipairs(fake.rule_order) do
      local r = fake.rules[name]
      if r.enabled ~= false then out[#out + 1] = r end
    end
    return out
  end

  -- How many timers are armed and have not fired or been cancelled.
  function fake.pending_timers()
    local n = 0
    for _, t in ipairs(fake.timers) do
      if t.live then n = n + 1 end
    end
    return n
  end

  -- Move the clock forward, firing due timers in time order (a timer made by a timer fires too if due).
  function fake.advance(ms)
    local target = fake.now + ms
    while true do
      local pick
      for _, t in ipairs(fake.timers) do
        if t.live and t.due <= target and (not pick or t.due < pick.due or (t.due == pick.due and t.id < pick.id)) then pick = t end
      end
      if not pick then break end
      pick.live = false
      fake.now = math.max(fake.now, pick.due)
      pick.fn()
    end
    fake.now = target
  end

  return fake
end

return M
