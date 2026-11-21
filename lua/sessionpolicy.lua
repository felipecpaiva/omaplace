-- When to write the session snapshot (design 6.4). Pure: no hl, no files, no clock (time is passed in, in ms).
-- Trailing debounce after window and monitor events. A close burst (shutdown, close-all) freezes writing, so the
-- last good snapshot is not overwritten by a half-empty desktop.
local M = {}

M.BURST_COUNT = 3 -- this many window.close events...
M.BURST_MS = 2000 -- ...within this many ms (a close exactly BURST_MS after the first still counts)
M.FREEZE_MS = 60000

function M.new(debounce_ms)
  return { debounce_ms = math.tointeger(debounce_ms) or 15000, frozen_until = 0, closes = {} }
end

-- Checked again when the timer fires: a timer armed before a burst must not write inside the freeze.
function M.frozen(state, now) return now < state.frozen_until end

-- The write is owed at most MAX_WAIT_FACTOR x debounce after the first event of a burst, even if events keep coming.
M.MAX_WAIT_FACTOR = 2

-- The glue calls this when it writes (or gives up), so the next event starts a new burst.
function M.fired(state) state.first_at = nil end

-- A time to write at, capped by the burst's first event, then moved past the freeze when it falls inside it.
local function schedule(state, now, at)
  state.first_at = state.first_at or now
  at = math.min(at, state.first_at + M.MAX_WAIT_FACTOR * state.debounce_ms)
  if at < state.frozen_until then at = state.frozen_until end
  return { action = "schedule", at = at }
end

-- kind: "window.close" or any other window or monitor event. Returns schedule, freeze or none.
function M.on_event(state, kind, now)
  if type(now) ~= "number" then return { action = "none" } end
  if kind == "window.close" then
    local keep = {}
    for _, t in ipairs(state.closes) do
      if now - t <= M.BURST_MS then keep[#keep + 1] = t end
    end
    keep[#keep + 1] = now
    -- only the last BURST_COUNT closes matter, so the list stays bounded
    while #keep > M.BURST_COUNT do table.remove(keep, 1) end
    state.closes = keep
    if #keep >= M.BURST_COUNT then
      state.frozen_until = math.max(state.frozen_until, now + M.FREEZE_MS)
      return { action = "freeze", until_ms = state.frozen_until }
    end
  end
  return schedule(state, now, now + state.debounce_ms)
end

return M
