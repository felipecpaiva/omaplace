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

  -- Returns a subscription like Hyprland's HL.EventSubscription (remove, is_active).
  function hl.on(event, fn)
    local list = fake.handlers[event] or {}
    fake.handlers[event] = list
    list[#list + 1] = fn
    local active = true
    return {
      is_active = function() return active end,
      remove = function()
        if not active then return end
        active = false
        for i, f in ipairs(list) do
          if f == fn then table.remove(list, i); return end
        end
      end,
    }
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

  -- One-shot timer: fires once, when advance() passes `ms`. Returns a handle with set_enabled and cancel.
  -- Both call forms work: hl.timer(ms, fn) and Hyprland's own hl.timer(fn, { type = "oneshot", timeout = ms }).
  function hl.timer(ms, fn)
    if type(ms) == "function" then
      local opts = fn
      ms, fn = type(opts) == "table" and opts.timeout or 0, ms
    end
    fake.next_timer = fake.next_timer + 1
    local t = { id = fake.next_timer, due = fake.now + ms, ms = ms, fn = fn, live = true }
    fake.timers[#fake.timers + 1] = t
    -- Hyprland's HL.Timer has set_enabled and is_enabled (method calls); cancel() is kept for older tests.
    return {
      cancel = function() t.live = false end,
      -- like Hyprland's: enabling starts the countdown again, from now, with the last timeout; but a one-shot that
      -- has fired is dead and cannot be re-armed (checked live 2026-11-21), so enabling it does nothing
      set_enabled = function(_, on)
        if t.fired then return end
        t.live = on == true
        if t.live then t.due = fake.now + t.ms end
      end,
      set_timeout = function(_, new_ms) t.ms = new_ms end,
      is_enabled = function() return t.live end,
    }
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
      pick.live, pick.fired = false, true
      fake.now = math.max(fake.now, pick.due)
      pick.fn()
    end
    fake.now = target
  end

  return fake
end

return M
