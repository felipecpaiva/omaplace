-- Plain Lua check:  lua lua/tests/test_json.lua
local dir = arg[0]:match("^(.*)/") or "."
local J = dofile(dir .. "/../json.lua")

local checks = 0
local function eq(v, want, name)
  checks = checks + 1
  local got, err = J.encode(v)
  assert(got == want, string.format("%s: got %s (%s), want %s", name, tostring(got), tostring(err), want))
end

eq(nil, "null", "nil")
eq(true, "true", "true")
eq(false, "false", "false")
eq(3, "3", "integer")
eq(1.5, "1.5", "float")
eq(2.0, "2", "whole float")
eq(0 / 0, "null", "nan")
eq(math.huge, "null", "inf")
eq("a", '"a"', "string")
eq('q"b\\s\n\t\r', '"q\\"b\\\\s\\n\\t\\r"', "escapes")
eq("\1\31", '"\\u0001\\u001f"', "control chars")
eq("caf\195\169", '"caf\195\169"', "utf8 passes through")
eq({}, "[]", "empty is an array")
eq(J.object({}), "{}", "marked empty is an object")
eq({ 1, "b", false }, '[1,"b",false]', "array")
eq({ b = 1, a = { c = true } }, '{"a":{"c":true},"b":1}', "sorted keys")
eq({ [1] = "x", [3] = "y" }, '{"1":"x","3":"y"}', "sparse is an object")
eq({ a = { { x = 1 }, {} } }, '{"a":[{"x":1},[]]}', "nesting")

local got, err = J.encode({ f = print })
assert(got == nil and err:find("function"), "function is refused")
local loop = {}
loop.me = loop
got, err = J.encode(loop)
assert(got == nil and err:find("deep"), "cycle is refused")
checks = checks + 2

print("test_json ok (" .. checks .. " checks)")
