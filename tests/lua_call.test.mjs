import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { execFileSync } from "node:child_process"

const load = (f) => readFileSync(new URL("../js/" + f, import.meta.url), "utf8").replace(".pragma library", "")
const { wrap, code } = new Function(load("LuaCall.js") + "; return { wrap, code }")()

test("wrap builds one Lua chunk that answers with a code", () => {
  const lua = wrap("open_file", ['"/run/made-up/omaplace/plan-r1-2.lua"'])
  assert.match(lua, /^return \(function\(\) /)
  assert.match(lua, /o\.open_file\("\/run\/made-up\/omaplace\/plan-r1-2\.lua"\)/)
  assert.match(lua, /omaplace:no_lua/)
  assert.throws(() => wrap("open_file()..x", []), /bad method/)
})

test("wrap runs in Lua (run-all needs lua anyway)", () => {
  const run = (pre, chunk) => execFileSync("lua", ["-e", pre + " print((load(" + JSON.stringify(chunk) + "))())"]).toString().trim()
  const lua = wrap("open_file", ['"p"'])
  assert.equal(run("", lua), "omaplace:no_lua")
  assert.equal(run("omaplace = { open_file = function() return nil, 'bad_plan' end }", lua), "omaplace:bad_plan")
  assert.equal(run("omaplace = { open_file = function() return 'r1' end }", lua), "omaplace:ok")
})

test("code reads the answer, unknown errors read as failed, no answer reads as empty", () => {
  assert.equal(code("omaplace:ok\n"), "ok")
  assert.equal(code("omaplace:no_monitor"), "no_monitor")
  assert.equal(code('"omaplace:busy"'), "busy")
  assert.equal(code("omaplace:something_new"), "failed")
  assert.equal(code(""), "")
  assert.equal(code("ok"), "")
})

