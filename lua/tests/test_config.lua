-- Plain Lua check:  lua lua/tests/test_config.lua
local dir = arg[0]:match("^(.*)/") or "."
local C = dofile(dir .. "/../config.lua")
local J = dofile(dir .. "/../json.lua")
local fixtures = dir .. "/../../tests/fixtures/config-lua/"

local function read(path)
  local f = assert(io.open(path, "rb"), "missing " .. path)
  local t = f:read("a")
  f:close()
  return t
end

local checks = 0
local function eq(got, want, name)
  checks = checks + 1
  assert(got == want, string.format("%s: got %s, want %s", name, tostring(got), tostring(want)))
end

-- every fixture parses to exactly the expected JSON
for _, name in ipairs({ "empty", "full", "bad", "unknown", "two-rules", "strategy" }) do
  local cfg = C.load(read(fixtures .. name .. ".toml"))
  cfg.rules, cfg.strategies = J.object(cfg.rules), J.object(cfg.strategies)
  eq(J.encode(cfg) .. "\n", read(fixtures .. name .. ".expected.json"), "fixture " .. name)
end

-- defaults come from the one table and match design 7.5
local d = C.load("").settings
eq(d.session, "on", "session default")
eq(d.expiry_seconds, 20, "expiry default")
eq(d.tiled_order, true, "tiled_order default")
eq(C.load(nil).schema, 1, "nil text is an empty file")

-- a bad value never switches a feature off and always says so
local cfg = C.load('expiry_seconds = "soon"\nrestore_at_login = "auto"\n')
eq(cfg.settings.expiry_seconds, 20, "bad number falls back")
eq(cfg.settings.restore_at_login, "auto", "good value beside a bad one kept")
eq(#cfg.warnings, 1, "one warning")
eq(cfg.warnings[1]:match("^line 1: ") ~= nil, true, "warning names the line")

-- comments, CRLF, duplicate keys (last wins), a # inside quotes
cfg = C.load('# top\r\nsession = "off" # why\r\nsession = "on"\r\n[rule.a]\r\napp = "x #1"\r\n')
eq(cfg.settings.session, "on", "last duplicate wins")
eq(cfg.rules.a.app, "x #1", "# inside quotes kept")
eq(#cfg.warnings, 0, "CRLF is fine")

-- an integer written as 3.0 is accepted, 3.5 is not; slot bounds
eq(C.load("[rule.a]\napp=\"x\"\nslot = 3.0").rules.a.slot, 3, "3.0 is 3")
eq(C.load("[rule.a]\napp=\"x\"\nslot = 3.5").rules.a.slot, 1, "3.5 falls back")
eq(C.load("[rule.a]\napp=\"x\"\nslot = 0").rules.a.slot, 1, "slot 0 falls back")
eq(C.load("[rule.a]\napp=\"x\"\nslot = 10").rules.a.slot, 10, "slot 10 ok")

-- hostile text never raises
for _, junk in ipairs({ "[", "]", "[[x]]", "=", "a=", "\0\0", string.rep("[rule.a]\n", 50), "[rule.]\napp=\"x\"" }) do
  local ok = pcall(C.load, junk)
  eq(ok, true, "junk does not raise")
end

print("test_config ok (" .. checks .. " checks)")
