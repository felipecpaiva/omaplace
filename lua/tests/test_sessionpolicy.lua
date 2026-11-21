-- Plain Lua check:  lua lua/tests/test_sessionpolicy.lua
local dir = arg[0]:match("^(.*)/") or "."
local P = dofile(dir .. "/../sessionpolicy.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- trailing debounce: every event schedules debounce_ms after itself (the glue re-arms its one timer)
local s = P.new(15000)
local r = P.on_event(s, "window.open", 1000)
eq(r.action, "schedule", "open schedules")
eq(r.at, 16000, "15 s after the event")
r = P.on_event(s, "window.active", 9000)
eq(r.at, 24000, "re-arm: a later event moves the write later")
eq(P.on_event(s, "monitor.added", 9500).at, 24500, "monitor events count too")
eq(P.on_event(s, "window.close", 10000).at, 25000, "one close is a normal event")
eq(P.frozen(s, 10000), false, "not frozen")
eq(P.new().debounce_ms, 15000, "default 15 s")
eq(P.on_event(s, "window.open", nil).action, "none", "no time: nothing")

-- a close burst: three closes within 2 s freeze writing for 60 s
s = P.new(15000)
P.on_event(s, "window.close", 0)
P.on_event(s, "window.close", 900)
r = P.on_event(s, "window.close", 2000)
eq(r.action, "freeze", "third close within 2 s freezes")
eq(r.until_ms, 62000, "for 60 s")
eq(P.frozen(s, 61999), true, "frozen until the end")
eq(P.frozen(s, 62000), false, "free at the end")

-- a fourth close extends the freeze
r = P.on_event(s, "window.close", 2500)
eq(r.action, "freeze", "still a burst")
eq(r.until_ms, 62500, "freeze extended")

-- closes spread out are not a burst
s = P.new(15000)
P.on_event(s, "window.close", 0)
P.on_event(s, "window.close", 1500)
eq(P.on_event(s, "window.close", 3001).action, "schedule", "3 closes over 3 s: no burst")
eq(P.on_event(s, "window.close", 3400).action, "freeze", "but 1500, 3001, 3400 are within 2 s")

-- a schedule that falls inside the freeze moves to its end
s = P.new(15000)
for _, t in ipairs({ 0, 100, 200 }) do P.on_event(s, "window.close", t) end
r = P.on_event(s, "window.active", 300)
eq(r.action, "schedule", "event in a freeze still schedules")
eq(r.at, 60200, "moved to the end of the freeze")
P.fired(s) -- the write happened: a new burst starts
eq(P.on_event(s, "window.open", 50000).at, 65000, "past the freeze: plain debounce")

-- the wait is capped: a write is owed at most 2 x debounce after the first event of a burst
s = P.new(15000)
eq(P.on_event(s, "window.active", 0).at, 15000, "first event")
eq(P.on_event(s, "window.active", 10000).at, 25000, "second event still moves it")
eq(P.on_event(s, "window.active", 20000).at, 30000, "third is capped at first + 30 s")
eq(P.on_event(s, "window.active", 29000).at, 30000, "and stays capped")
P.fired(s)
eq(P.on_event(s, "window.active", 31000).at, 46000, "after a write the next burst starts fresh")
-- the freeze still wins over the cap
s = P.new(15000)
P.on_event(s, "window.active", 0)
for _, t in ipairs({ 100, 200, 300 }) do P.on_event(s, "window.close", t) end
eq(P.on_event(s, "window.active", 400).at, 60300, "freeze end, not the cap")

-- a write armed before the burst is caught by the fire-time check
s = P.new(15000)
eq(P.on_event(s, "window.open", 0).at, 15000, "armed for 15 s")
for _, t in ipairs({ 14000, 14100, 14200 }) do P.on_event(s, "window.close", t) end
eq(P.frozen(s, 15000), true, "the 15 s timer finds the freeze")

-- the close list stays bounded
s = P.new(15000)
for t = 1, 500 do P.on_event(s, "window.close", t * 10000) end
eq(#s.closes, 1, "old closes are dropped")

print(string.format("test_sessionpolicy: %d checks ok", checks))
