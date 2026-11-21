-- Plain Lua check:  lua lua/tests/test_shellquote.lua
-- Where `sh` can be run, each case is also executed and its words are counted, so quoting is checked by a real shell.
local dir = arg[0]:match("^(.*)/") or "."
local Q = dofile(dir .. "/../shellquote.lua")

local checks = 0
local function eq(argv, want, name)
  checks = checks + 1
  local got, err = Q.join(argv)
  assert(got == want, string.format("%s: got %s (%s), want %s", name, tostring(got), tostring(err), want))
end

eq({}, "", "empty list")
eq({ "ls" }, "'ls'", "one word")
eq({ "echo", "a b" }, "'echo' 'a b'", "space")
eq({ "it's" }, "'it'\\''s'", "single quote")
eq({ "" }, "''", "empty string stays an argument")
eq({ "a\nb" }, "'a\nb'", "newline")
eq({ "$HOME", "`x`", "$(x)", "a;b", "*" }, "'$HOME' '`x`' '$(x)' 'a;b' '*'", "metacharacters")
eq({ "'; rm -rf ~'" }, "''\\''; rm -rf ~'\\'''", "injection attempt")

for _, bad in ipairs({ { 1 }, { "a", {} }, { "a\0b" }, { "a", false } }) do
  checks = checks + 1
  local got, err = Q.join(bad)
  assert(got == nil and type(err) == "string", "rejects bad element")
end
checks = checks + 1
assert(Q.join("x") == nil, "rejects a non-list")

-- Round trip through a real shell: printf prints each word followed by a NUL byte. The commands only print.
local cases = {
  { "'; rm -rf ~'" }, { "a b", "", "it's", "x\ny" }, { "$HOME", "`id`", "$(id)", "\\", '"' },
}
for i, argv in ipairs(cases) do
  local p = io.popen("printf '%s\\0' " .. Q.join(argv), "r")
  if p then
    local out = p:read("a")
    p:close()
    local words = {}
    for w in out:gmatch("(.-)%z") do words[#words + 1] = w end
    checks = checks + 1 + #argv
    assert(#words == #argv, "shell saw " .. #words .. " words in case " .. i)
    for k, w in ipairs(argv) do assert(words[k] == w, "word " .. k .. " of case " .. i) end
  end
end

print("test_shellquote ok (" .. checks .. " checks)")
