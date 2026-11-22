-- Match new windows to the waiting slots of a run (design 5.4, 5.4a, 6.3). Pure: time is always passed in (ms).
-- Identity is class plus context only, never a title, pid or address (D3).
--
-- Slot states: waiting (not started), launched (started, no window yet), claimed, expired, skipped, failed.
-- A slot claimed in the "move existing" pass is `existing` and is started (moved) by next_launches in turn.
--
-- Context classes (any slot of the class has a context, D18): one launch of the class is live at a time. After a
-- launch, every new untagged window of that class belongs to the launched context until the class has been quiet
-- for `quiet_ms` (this catches windows a browser restores for that profile). Only then may the class launch again.
local T = {}

local FINAL = { claimed = true, expired = true, skipped = true, failed = true }

-- new(plan_windows, now, opts)  opts: expiry_ms (20000), tick_ms (150), quiet_ms (2000),
--   sequential (true on tiled or scrolling targets: one slot at a time in `order`).
-- plan_windows must already be in order (Plan.js sorts them).
function T.new(plan_windows, now, opts)
  opts = opts or {}
  local book = {
    slots = {}, gates = {}, gated = {}, next_tick = now,
    expiry_ms = opts.expiry_ms or 20000, tick_ms = opts.tick_ms or 150, quiet_ms = opts.quiet_ms or 2000,
    sequential = opts.sequential == true,
  }
  for i, w in ipairs(plan_windows or {}) do
    local mode = (w.mode == "launch" or w.mode == "place_only") and w.mode or "skip"
    local s = { n = i, class = tostring(w.class or ""), context = tostring(w.context or ""), order = w.order or i,
      mode = mode, state = "waiting", existing = false, started = false }
    if mode == "skip" or s.class == "" or s.context == "?" then s.state, s.started = "skipped", true end
    book.slots[i] = s
    if s.context ~= "" and s.state ~= "skipped" then book.gated[s.class:lower()] = true end
  end
  return book
end

local function gate_open(book, class, now)
  local g = book.gates[class]
  if not g then return false end
  if g.pending and g.pending.state == "launched" then return true end
  return now - g.last < book.quiet_ms
end

-- A slot is done for the sequence: final, and if claimed in the move pass, also moved.
local function done(s) return FINAL[s.state] and (not s.existing or s.started) end

-- Give a window a slot. window = { class, context (from its tag, or nil), existing (true in the move pass) }.
-- Returns the slot, or nil (the window is not ours).
function T.claim(book, window, now)
  T.expire(book, now)
  -- classes compare without case: an app picked by its desktop id ("aether") opens as "Aether" (live 2026-11-22)
  local cls = tostring(window.class or ""):lower()
  local function first(pred)
    for _, s in ipairs(book.slots) do
      if s.class:lower() == cls and pred(s) then return s end
    end
  end
  local s
  if window.existing then
    -- An untagged window has context "", so it never takes a context slot (design 5.4a rule 4).
    local ctx = window.context or ""
    s = first(function(x) return x.state == "waiting" and x.context == ctx end)
    if s then s.existing = true end
  elseif window.context ~= nil then
    s = first(function(x) return (x.state == "waiting" or x.state == "launched") and x.context == window.context end)
  elseif book.gated[cls] then
    if not gate_open(book, cls, now) then return nil end
    local g = book.gates[cls]
    g.last, g.pending = now, nil -- extra windows of this context keep the class busy too
    s = first(function(x) return (x.state == "waiting" or x.state == "launched") and x.context == g.ctx end)
  else
    s = first(function(x) return x.state == "launched" and x.context == "" end)
  end
  if not s then return nil end
  s.state, s.claimed_at = "claimed", now
  return s
end

-- Launched slots whose window did not come in time. Returns them (state now "expired").
function T.expire(book, now)
  local out = {}
  for _, s in ipairs(book.slots) do
    if s.state == "launched" and now - s.started_at >= book.expiry_ms then
      s.state = "expired"
      out[#out + 1] = s
    end
  end
  return out
end

-- Mark a slot failed (the glue could not launch, move or place it).
function T.fail(book, n, reason)
  local s = book.slots[n]
  -- a claimed slot can still fail (its window went away before its turn, or the put did not land)
  if s and s.state ~= "skipped" and s.state ~= "expired" then s.state = "failed" end
  if s then s.reason, s.started = reason, true end
  return s
end

local function start(book, s, now, list)
  s.started, s.started_at = true, now
  if s.state == "waiting" then
    s.state = "launched"
    if s.mode == "launch" and book.gated[s.class:lower()] then book.gates[s.class:lower()] = { ctx = s.context, pending = s, last = now } end
  end
  list[#list + 1] = s
end

-- May this slot launch now? Context classes wait for their gate; floating launches wait for the tick.
local function can_launch(book, s, now)
  if s.mode == "launch" and book.gated[s.class:lower()] and gate_open(book, s.class:lower(), now) then return false end
  return true
end

-- The slots to start now, marked started. The glue moves an `existing` slot's window, runs a `launch` slot's argv,
-- and does nothing for `place_only` (it waits for the app's own window). Call again until it returns {}.
function T.next_launches(book, now)
  local list = {}
  if book.sequential then
    for _, s in ipairs(book.slots) do
      if not done(s) then
        if not s.started and (s.existing or can_launch(book, s, now)) then start(book, s, now, list) end
        break
      end
    end
    return list
  end
  local ticked = false
  for _, s in ipairs(book.slots) do
    if not s.started then
      if s.existing or s.mode == "place_only" then
        start(book, s, now, list)
      elseif s.state == "waiting" and not ticked and now >= book.next_tick and can_launch(book, s, now) then
        start(book, s, now, list)
        ticked, book.next_tick = true, now + book.tick_ms
      end
    end
  end
  return list
end

-- True when every slot is final and every existing window was moved.
function T.finished(book)
  for _, s in ipairs(book.slots) do
    if not done(s) then return false end
  end
  return true
end

-- The next time (ms) something can change without a window event, or nil when nothing waits on time.
function T.next_wake(book, now)
  local best
  local function at(t) if t > now and (not best or t < best) then best = t end end
  for _, s in ipairs(book.slots) do
    if s.state == "launched" then at(s.started_at + book.expiry_ms) end
    if s.state == "waiting" and not s.existing then
      local g = book.gated[s.class:lower()] and s.mode == "launch" and book.gates[s.class:lower()]
      if g and gate_open(book, s.class:lower(), now) then
        if not (g.pending and g.pending.state == "launched") then at(g.last + book.quiet_ms) end
      elseif not book.sequential then
        at(book.next_tick)
      end
    end
  end
  return best
end

-- Swaps that put tiled windows in their saved left-to-right order (dwindle splits the focused window, so windows
-- opened in order can still land out of order, S8). windows = list of { id, x, y, order }. Returns a list of
-- { a, b } id pairs, to be done in that order; a swap exchanges the places of two windows exactly.
function T.swaps(windows)
  local function by_place(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
  end
  local places, want = {}, {}
  for i, w in ipairs(windows or {}) do places[i], want[i] = w, w end
  table.sort(places, by_place)
  table.sort(want, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return by_place(a, b)
  end)
  local out = {}
  for i = 1, #want do
    if places[i] ~= want[i] then
      local j = i + 1
      while places[j] ~= want[i] do j = j + 1 end
      out[#out + 1] = { places[i].id, want[i].id }
      places[i], places[j] = places[j], places[i]
    end
  end
  return out
end

return T
