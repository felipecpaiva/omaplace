// js/OmagnetBridge.js: omaplace's desktop zones written into omagnet's config.toml (D43). Made-up config only.
import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./js_load.mjs"

const B = load("OmagnetBridge.js")
const Z = "0 0 0.5 1; 0.5 0 0.5 1"

test("a new config gets the layout and the desktop line", () => {
  const r = B.setDesktop("", 13, Z)
  assert.equal(r.changed, true)
  assert.match(r.text, /\[layout_omaplace-13\]\nzones = "0 0 0.5 1; 0.5 0 0.5 1"/)
  assert.match(r.text, /\[workspace_layouts\]\n13 = "omaplace-13"/)
})

test("the user's own settings are kept, and their own desktop line is never replaced", () => {
  const mine = 'margin = 8\n\n[workspace_layouts]\n3 = "coding"\n\n[layout_coding]\nzones = "0 0 1 1"\n'
  const r = B.setDesktop(mine, 13, Z)
  assert.match(r.text, /margin = 8/)
  assert.match(r.text, /3 = "coding"/)
  assert.match(r.text, /13 = "omaplace-13"/)
  assert.match(r.text, /\[layout_coding\]\nzones = "0 0 1 1"/)
  const refused = B.setDesktop(mine, 3, Z)
  assert.equal(refused.changed, false)
  assert.equal(refused.reason, "user_layout")
  assert.equal(refused.text, mine)
})

test("changing and taking away omaplace's own entry", () => {
  const one = B.setDesktop("", 13, Z).text
  const two = B.setDesktop(one, 13, "0 0 1 1")
  assert.match(two.text, /\[layout_omaplace-13\]\nzones = "0 0 1 1"/)
  assert.equal((two.text.match(/omaplace-13\]/g) || []).length, 1, "one section, updated in place")
  assert.equal(B.setDesktop(two.text, 13, "0 0 1 1").changed, false, "same zones: no change")
  const gone = B.setDesktop(two.text, 13, "")
  assert.equal(gone.changed, true)
  assert.doesNotMatch(gone.text, /omaplace-13/)
  assert.equal(B.setDesktop("", 0, Z).reason, "bad_workspace")
})
