-- Plain Lua check:  lua lua/tests/test_memory.lua   (pure, made-up apps and monitors)
local dir = arg[0]:match("^(.*)/") or "."
local Memory = dofile(dir .. "/../memory.lua")

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

local fp = { identity = "Example Panel", make = "Example Corp", model = "EX1", internal = true, width = 2000,
  height = 1000, scale = 1.5, transform = 0, serial_hash = "", last_connector = "eDP-1" }
local function ev(kind, cls, extra)
  local e = { kind = kind, class = cls, fp = fp, slot = 2, rect = { 0.25, 0, 0.75, 1 }, floating = true }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

-- key: no context is the class alone; a context never collides with another class
eq(Memory.key("a.A"), "a.A", "key without context")
eq(Memory.key("a.A", ""), "a.A", "empty context is none")
eq(Memory.key("a.A", "Default") ~= Memory.key("a.A"), true, "context key differs")

-- scene: only runs record
local mem = Memory.new()
eq(Memory.update(mem, ev("placed", "org.example.Chat"), "scene", 100), true, "scene records a run")
eq(Memory.lookup(mem, "org.example.Chat").slot, 2, "lookup slot")
eq(Memory.lookup(mem, "org.example.Chat").rect[1], 0.25, "lookup rect")
eq(Memory.lookup(mem, "org.example.Chat").saved_at, 100, "saved_at kept")
eq(Memory.update(mem, ev("closed", "org.example.Chat", { slot = 5 }), "scene", 101), false, "scene ignores a close")
eq(Memory.update(mem, ev("moved", "org.example.Chat", { slot = 5 }), "scene", 101), false, "scene ignores a move")
eq(Memory.lookup(mem, "org.example.Chat").slot, 2, "still the run's place")
eq(Memory.lookup(mem, "org.example.Other"), nil, "unknown class")
eq(Memory.lookup(mem, "org.example.Chat", "Profile 1"), nil, "a context entry is separate")
eq(Memory.update(mem, ev("placed", "org.example.Chat"), "off", 1), false, "off records nothing")
eq(Memory.update(mem, ev("placed", "org.example.Chat"), "nonsense", 1), false, "unknown mode records nothing")

-- last_place (and auto, for now): also the last window's close or move
for _, mode in ipairs({ "last_place", "auto" }) do
  mem = Memory.new()
  eq(Memory.update(mem, ev("closed", "org.example.Chat", { slot = 4, others = 1 }), mode, 1), false,
    mode .. ": not the last window")
  eq(Memory.lookup(mem, "org.example.Chat"), nil, mode .. ": nothing recorded")
  eq(Memory.update(mem, ev("closed", "org.example.Chat", { slot = 4, others = 0 }), mode, 2), true, mode .. ": last closes")
  eq(Memory.lookup(mem, "org.example.Chat").slot, 4, mode .. ": close place")
  eq(Memory.update(mem, ev("moved", "org.example.Chat", { slot = 6 }), mode, 3), true, mode .. ": move")
  eq(Memory.lookup(mem, "org.example.Chat").slot, 6, mode .. ": move place")
  eq(Memory.update(mem, ev("placed", "org.example.Chat", { slot = 7, others = 3 }), mode, 4), true,
    mode .. ": a run counts with other windows open")
end

-- bad input is refused
mem = Memory.new()
eq(Memory.update(mem, ev("placed", ""), "scene", 1), false, "empty class")
eq(Memory.update(mem, ev("placed", "a.A", { slot = 0 }), "scene", 1), false, "slot 0")
eq(Memory.update(mem, ev("placed", "a.A", { slot = 11 }), "scene", 1), false, "slot 11")
eq(Memory.update(mem, ev("placed", "a.A", { fp = "x" }), "scene", 1), false, "no fingerprint")
eq(Memory.update(mem, ev("placed", "a.A", { rect = { 0, 0, 0 / 0, 1 } }), "scene", 1), true, "bad rect: place kept")
eq(Memory.lookup(mem, "a.A").rect, nil, "bad rect dropped")
eq(Memory.update(mem, nil, "scene", 1), false, "nil event")
eq(Memory.update(mem, ev("placed", "a.A", { slot = 3.0 }), "scene", 1), true, "whole float slot")
eq(math.type(Memory.lookup(mem, "a.A").slot), "integer", "slot stored as an integer")

-- cap: at most 200, the oldest goes first
mem = Memory.new()
for i = 1, 205 do Memory.update(mem, ev("placed", "org.example.App" .. i), "scene", i) end
local n = 0
for _ in pairs(mem.apps) do n = n + 1 end
eq(n, 200, "capped at 200")
eq(Memory.lookup(mem, "org.example.App1"), nil, "oldest dropped")
eq(Memory.lookup(mem, "org.example.App5"), nil, "fifth oldest dropped")
eq(Memory.lookup(mem, "org.example.App6") ~= nil, true, "sixth kept")
Memory.update(mem, ev("placed", "org.example.App6"), "scene", 300) -- refreshed: now the newest
Memory.update(mem, ev("placed", "org.example.New"), "scene", 301)
eq(Memory.lookup(mem, "org.example.App6") ~= nil, true, "a refreshed entry is not the oldest")
eq(Memory.lookup(mem, "org.example.App7"), nil, "the next oldest went instead")

-- encode and decode round trip through load(text, "memory", "t", {})
mem = Memory.new()
Memory.update(mem, ev("placed", "org.example.Chat"), "scene", 1700000000)
Memory.update(mem, ev("placed", "google-chrome", { context = "Profile 1", rect = { 0.1, 0.2, 0.3, 0.4 } }), "scene", 2)
Memory.update(mem, ev("placed", "org.example.Tiled", { rect = false, floating = false }), "scene", 3)
local evil = 'x"] = 1 } os.exit(1) return { ["\n\\\0\127'
Memory.update(mem, ev("placed", evil, { context = "]] --\r\t" }), "scene", 4)
local text = assert(Memory.encode(mem))
eq(text:sub(1, 9), "return {[", "starts with return")
eq(text:find("0x", 1, true), nil, "no hex floats")
eq(text:find("\n", 1, true), #text, "one line, newlines escaped")
local raw = load(text, "memory", "t", {})()
eq(type(raw.apps), "table", "loads in an empty environment")
local back = assert(Memory.decode(text))
eq(Memory.lookup(back, "org.example.Chat").fp.scale, 1.5, "fingerprint float")
eq(Memory.lookup(back, "org.example.Chat").fp.internal, true, "fingerprint bool")
eq(Memory.lookup(back, "org.example.Chat").saved_at, 1700000000, "saved_at")
eq(Memory.lookup(back, "google-chrome", "Profile 1").rect[2], 0.2, "rect exact")
eq(Memory.lookup(back, "google-chrome"), nil, "context still separate")
eq(Memory.lookup(back, "org.example.Tiled").rect, nil, "no rect")
eq(Memory.lookup(back, "org.example.Tiled").floating, false, "not floating")
local e = Memory.lookup(back, evil, "]] --\r\t")
eq(e ~= nil, true, "injection attempt is found by its own name")
eq(e.class, evil, "class stays the same string")
eq(e.context, "]] --\r\t", "context stays the same string")
eq(back.seq, 4, "seq restored")
eq(Memory.encode(back), text, "encode is stable")
Memory.update(back, ev("placed", "org.example.Next"), "scene", 5)
eq(Memory.lookup(back, "org.example.Next").n, 5, "seq continues after a load")

-- decode refuses what it cannot use, and drops bad entries
eq(Memory.decode("not lua"), nil, "parse error")
eq(Memory.decode("return 5"), nil, "not a table")
eq(Memory.decode("return os.exit(1)"), nil, "no globals in the environment")
eq(Memory.decode(string.rep(" ", Memory.MAX_TEXT + 1)), nil, "too big")
eq(Memory.decode(nil), nil, "nil text")
local mixed = Memory.decode('return { apps = { ["a.A"] = { class = "a.A", fp = {}, slot = 1, n = 3 },'
  .. ' ["b.B"] = { class = "b.B", fp = {}, slot = 99 }, ["c.C"] = { class = "x.X", fp = {}, slot = 1 },'
  .. ' ["d.D"] = function() end } }')
eq(Memory.lookup(mixed, "a.A") ~= nil, true, "good entry kept")
eq(Memory.lookup(mixed, "b.B"), nil, "bad slot dropped")
eq(Memory.lookup(mixed, "x.X"), nil, "key that does not match its class dropped")
eq(mixed.seq, 3, "seq from the entries")

print(string.format("test_memory: %d checks ok", checks))
