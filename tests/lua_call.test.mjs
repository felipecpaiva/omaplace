import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { execFileSync } from "node:child_process"

const load = (f) => readFileSync(new URL("../js/" + f, import.meta.url), "utf8").replace(".pragma library", "")
const { wrap, code } = new Function(load("LuaCall.js") + "; return { wrap, code }")()

import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"

test("wrap builds one Lua chunk that writes its answer to the reply file", () => {
  const lua = wrap("open_file", ['"/run/made-up/omaplace/plan-r1-2.lua"'], '"/run/made-up/omaplace/reply-q1.txt"')
  assert.match(lua, /o\.open_file\("\/run\/made-up\/omaplace\/plan-r1-2\.lua"\)/)
  assert.match(lua, /omaplace:no_lua/)
  assert.match(lua, /io\.open\("\/run\/made-up\/omaplace\/reply-q1\.txt", "w"\)/)
  assert.throws(() => wrap("open_file()..x", [], '"r"'), /bad method/)
  assert.throws(() => wrap("open_file", []), /reply path/)
})

test("wrap runs in Lua and the reply file holds the code (hyprctl eval prints only ok, live 2026-11-21)", () => {
  const dir = mkdtempSync(tmpdir() + "/omaplace-luacall-")
  const reply = dir + "/reply.txt"
  const run = (pre) => {
    execFileSync("lua", ["-e", pre + " ; " + wrap("open_file", ['"p"'], JSON.stringify(reply))])
    return readFileSync(reply, "utf8")
  }
  try {
    assert.equal(run(""), "omaplace:no_lua")
    assert.equal(run("omaplace = { open_file = function() return nil, 'bad_plan' end }"), "omaplace:bad_plan")
    assert.equal(run("omaplace = { open_file = function() return 'r1' end }"), "omaplace:ok")
  } finally { rmSync(dir, { recursive: true, force: true }) }
})

test("code reads the answer, unknown errors read as failed, no answer reads as empty", () => {
  assert.equal(code("omaplace:ok\n"), "ok")
  assert.equal(code("omaplace:no_monitor"), "no_monitor")
  assert.equal(code('"omaplace:busy"'), "busy")
  assert.equal(code("omaplace:something_new"), "failed")
  assert.equal(code(""), "")
  assert.equal(code("ok"), "")
})

test("wrapData runs in Lua and the reply holds the code, then the table as JSON (WP12b)", () => {
  const { wrapData, data } = new Function(load("LuaCall.js") + "; return { wrapData, data }")()
  assert.throws(() => wrapData("desktops()", [], '"r"'), /bad method/)
  assert.throws(() => wrapData("desktops", []), /reply path/)
  const dir = mkdtempSync(tmpdir() + "/omaplace-luacall-")
  const reply = dir + "/reply.txt"
  const run = (pre) => {
    execFileSync("lua", ["-e", pre + " ; " + wrapData("desktops", [], JSON.stringify(reply))])
    return readFileSync(reply, "utf8")
  }
  try {
    assert.equal(run(""), "omaplace:no_lua")
    assert.equal(data(run("")), null)
    assert.equal(run("omaplace = { desktops = function() return nil, 'no_monitor' end }"), "omaplace:no_monitor")
    assert.equal(run("omaplace = { desktops = function() return true end }"), "omaplace:failed")
    const text = run(String.raw`omaplace = { desktops = function() return { monitors = { { identity = 'Example Corp "EX27"\\x', name = 'DP-1',
      focused = true, slots = { { slot = 1, workspace = 1 }, { slot = 2, workspace = 12 } } }, { identity = 'tab\tb', name = 'HDMI-A-1',
      focused = false, slots = {} } } } end }`)
    assert.equal(code(text), "ok")
    assert.deepEqual(data(text), { monitors: [
      { identity: 'Example Corp "EX27"\\x', name: "DP-1", focused: true, slots: [{ slot: 1, workspace: 1 }, { slot: 2, workspace: 12 }] },
      { identity: "tab\tb", name: "HDMI-A-1", focused: false, slots: [] }
    ] })
  } finally { rmSync(dir, { recursive: true, force: true }) }
  assert.equal(data("omaplace:ok\nnot json"), null)
  assert.equal(data("omaplace:busy\n{}"), null)
})

