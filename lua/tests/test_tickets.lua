-- Plain Lua check:  lua lua/tests/test_tickets.lua   (time is passed in, in ms)
local dir = arg[0]:match("^(.*)/") or "."
local T = dofile(dir .. "/../tickets.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local function ns(list)
  local out = {}
  for _, s in ipairs(list) do out[#out + 1] = s.n end
  return table.concat(out, ",")
end
local opts = { expiry_ms = 20000, tick_ms = 150, quiet_ms = 2000 }

-- Floating: one launch per tick, in order; windows claim launched slots of their class.
do
  local b = T.new({
    { class = "a", mode = "launch" }, { class = "b", mode = "launch" }, { class = "a", mode = "launch" },
  }, 0, opts)
  eq(ns(T.next_launches(b, 0)), "1", "first tick: slot 1")
  eq(ns(T.next_launches(b, 0)), "", "same tick: nothing more")
  eq(T.next_wake(b, 0), 150, "wake at the next tick")
  eq(ns(T.next_launches(b, 150)), "2", "next tick: slot 2")
  eq(ns(T.next_launches(b, 300)), "3", "third tick: slot 3")
  eq(T.claim(b, { class = "c" }, 310), nil, "unknown class is not ours")
  eq(T.claim(b, { class = "a" }, 320).n, 1, "first a window takes slot 1")
  eq(T.claim(b, { class = "a" }, 330).n, 3, "second a window takes slot 3")
  eq(T.claim(b, { class = "a" }, 340), nil, "a third a window is not ours")
  eq(T.finished(b), false, "b still waiting")
  eq(T.next_wake(b, 340), 20150, "wake at b's expiry")
  eq(#T.expire(b, 20149), 0, "not yet")
  local gone = T.expire(b, 20150)
  eq(ns(gone), "2", "b expires")
  eq(b.slots[2].state, "expired", "expired state")
  eq(T.finished(b), true, "finished")
  eq(T.next_wake(b, 20150), nil, "nothing left to wake for")
end

-- A window never claims a slot that was not launched yet (non-context class).
do
  local b = T.new({ { class = "a", mode = "launch" }, { class = "a", mode = "launch" } }, 0, opts)
  T.next_launches(b, 0)
  eq(T.claim(b, { class = "a" }, 10).n, 1, "launched slot")
  eq(T.claim(b, { class = "a" }, 20), nil, "slot 2 not launched yet")
end

-- Tiled: strictly sequential in order, next only after the previous is claimed or expired.
do
  local b = T.new({
    { class = "a", mode = "launch" }, { class = "b", mode = "launch" }, { class = "c", mode = "launch" },
  }, 0, { expiry_ms = 1000, tick_ms = 150, quiet_ms = 2000, sequential = true })
  eq(ns(T.next_launches(b, 0)), "1", "first in order")
  eq(ns(T.next_launches(b, 5000 - 4500)), "", "waits for slot 1")
  eq(T.claim(b, { class = "b" }, 600), nil, "b not started, not claimed")
  eq(T.claim(b, { class = "a" }, 700).n, 1, "a claimed")
  eq(ns(T.next_launches(b, 700)), "2", "then slot 2")
  eq(T.next_wake(b, 700), 1700, "wake at slot 2 expiry")
  T.expire(b, 1700)
  eq(ns(T.next_launches(b, 1700)), "3", "slot 2 expired, slot 3 goes")
end

-- Move pass: existing windows claim by class and exact context; started in turn.
do
  local b = T.new({
    { class = "chrome", context = "Default", mode = "launch" },
    { class = "term", mode = "launch" },
    { class = "chrome", context = "Profile 1", mode = "launch" },
  }, 0, { sequential = true, expiry_ms = 1000 })
  eq(T.claim(b, { class = "chrome", existing = true }, 0), nil, "untagged chrome left alone in move pass")
  eq(T.claim(b, { class = "chrome", context = "Profile 1", existing = true }, 0).n, 3, "tagged chrome to its profile")
  eq(T.claim(b, { class = "term", existing = true }, 0).n, 2, "plain class moves")
  eq(ns(T.next_launches(b, 0)), "1", "slot 1 launches first")
  eq(T.claim(b, { class = "chrome" }, 50).n, 1, "the launched Default window")
  eq(ns(T.next_launches(b, 50)), "2", "then slot 2 moves (existing)")
  eq(ns(T.next_launches(b, 50)), "3", "then slot 3 moves")
  eq(T.finished(b), true, "all done")
end

-- Two Chrome profiles: one live context per class; restored windows go to the open context.
do
  local b = T.new({
    { class = "chrome", context = "Default", mode = "launch" },
    { class = "chrome", context = "Default", mode = "launch" },
    { class = "chrome", context = "Profile 1", mode = "launch" },
    { class = "term", mode = "launch" },
  }, 0, opts)
  eq(ns(T.next_launches(b, 0)), "1", "Default launches")
  eq(ns(T.next_launches(b, 150)), "4", "Profile 1 waits (class busy), term goes")
  eq(T.claim(b, { class = "chrome" }, 400).n, 1, "first Default window")
  eq(T.claim(b, { class = "chrome" }, 900).n, 2, "restored Default window takes the second Default slot")
  eq(T.claim(b, { class = "chrome" }, 1500), nil, "extra Default window is not given Profile 1's slot")
  eq(ns(T.next_launches(b, 3000)), "", "still quiet window (last window at 1500)")
  eq(T.next_wake(b, 3000), 3500, "wake when the class has been quiet 2 s")
  eq(ns(T.next_launches(b, 3500)), "3", "Profile 1 launches after the quiet window")
  eq(T.claim(b, { class = "chrome" }, 3600).n, 3, "Profile 1 window lands in its slot")
  eq(b.slots[2].state, "claimed", "Default slot 2 claimed without its own launch")
end

-- A context launch that never shows a window keeps the class busy until it expires.
do
  local b = T.new({
    { class = "chrome", context = "A", mode = "launch" }, { class = "chrome", context = "B", mode = "launch" },
  }, 0, { expiry_ms = 5000, quiet_ms = 2000, tick_ms = 150 })
  T.next_launches(b, 0)
  eq(ns(T.next_launches(b, 2500)), "", "B waits while A is pending")
  eq(T.next_wake(b, 2500), 5000, "wake at A's expiry")
  T.expire(b, 5000)
  eq(ns(T.next_launches(b, 5000)), "2", "B goes once A expired")
end

-- place_only and skip; "?" context is skipped; failures are final.
do
  local b = T.new({
    { class = "notes", mode = "place_only" }, { class = "x", mode = "skip" },
    { class = "chrome", context = "?", mode = "launch" }, { class = "y", mode = "launch" }, { class = "", mode = "launch" },
  }, 0, opts)
  eq(b.slots[2].state, "skipped", "skip mode")
  eq(b.slots[3].state, "skipped", "unknown context")
  eq(b.slots[5].state, "skipped", "empty class")
  eq(ns(T.next_launches(b, 0)), "1,4", "place_only starts without a tick, then one launch")
  T.fail(b, 4, "bad_launch")
  eq(b.slots[4].state, "failed", "failed")
  eq(T.claim(b, { class = "notes" }, 10).n, 1, "place_only claimed by the app's own window")
  eq(T.finished(b), true, "finished")
  eq(#T.new(nil, 0).slots, 0, "nil plan")
end

-- A claimed slot can still fail.
do
  local b = T.new({ { class = "a", mode = "launch" } }, 0, opts)
  T.claim(b, { class = "a", existing = true }, 0)
  T.fail(b, 1, "gone")
  eq(b.slots[1].state, "failed", "claimed slot failed")
  eq(b.slots[1].reason, "gone", "reason kept")
end

-- Tiled reorder: swaps from current places to the saved order.
do
  local function apply(list, pairs_)
    local at = {}
    for _, w in ipairs(list) do at[w.id] = w end
    for _, p in ipairs(pairs_) do
      local a, c = at[p[1]], at[p[2]]
      a.x, c.x, a.y, c.y = c.x, a.x, c.y, a.y
    end
    table.sort(list, function(p, q) return p.x < q.x or (p.x == q.x and p.y < q.y) end)
    local ids = {}
    for _, w in ipairs(list) do ids[#ids + 1] = w.id end
    return table.concat(ids, ",")
  end
  -- S8: opened 1, 2, 3 but landed 1, 3, 2
  local w = { { id = "A", order = 1, x = 0, y = 0 }, { id = "B", order = 2, x = 1000, y = 0 }, { id = "C", order = 3, x = 500, y = 0 } }
  local sw = T.swaps(w)
  eq(#sw, 1, "one swap fixes 1, 3, 2")
  eq(apply(w, sw), "A,B,C", "order now A, B, C by place")
  eq(w[1].order .. w[2].order .. w[3].order, "123", "orders left to right")
  eq(#T.swaps({ { id = "A", order = 1, x = 0, y = 0 }, { id = "B", order = 2, x = 5, y = 0 } }), 0, "already right")
  local rev = { { id = 1, order = 1, x = 300, y = 0 }, { id = 2, order = 2, x = 200, y = 0 }, { id = 3, order = 3, x = 100, y = 0 },
    { id = 4, order = 4, x = 0, y = 0 } }
  local rsw = T.swaps(rev)
  apply(rev, rsw)
  eq(rev[1].id .. rev[2].id .. rev[3].id .. rev[4].id, "1234", "reversed four sorted")
  eq(#rsw, 2, "two swaps for a reversal of four")
  local stack = { { id = "top", order = 2, x = 0, y = 0 }, { id = "low", order = 1, x = 0, y = 500 } }
  eq(#T.swaps(stack), 1, "same x: y decides")
  eq(#T.swaps(nil), 0, "nil input")
end

-- A window that arrives after the slot's expiry time does not take the slot (claim expires first).
do
  local b = T.new({ { class = "a", mode = "launch" } }, 0, opts)
  T.next_launches(b, 0)
  eq(T.claim(b, { class = "a" }, 20000), nil, "late window refused")
  eq(b.slots[1].state, "expired", "slot expired by claim")
end

-- Classes compare without case: a plan picked "aether" from the app list, the window is "Aether" (live 2026-11-22).
do
  local b = T.new({ { class = "aether", mode = "launch" } }, 0, opts)
  T.next_launches(b, 0)
  eq(T.claim(b, { class = "Aether" }, 10).n, 1, "claimed whatever the case")
  eq(b.slots[1].class, "aether", "the slot keeps its own spelling")
end

print(string.format("test_tickets: %d checks ok", checks))
