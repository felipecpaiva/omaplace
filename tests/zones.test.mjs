// js/Zones.js against golden vectors made from omagnet's LayoutOps.js (tools/gen-zones-golden.sh), so no omagnet checkout is needed.
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { load } from "./js_load.mjs"

const Z = load("Zones.js")
const golden = JSON.parse(readFileSync(new URL("./fixtures/zones-golden.json", import.meta.url), "utf8"))
const header = readFileSync(new URL("../js/Zones.js", import.meta.url), "utf8")

test("Zones.js names the omagnet commit the golden vectors came from", () => {
  assert.match(header, new RegExp("omagnet commit " + golden.omagnet_commit + "\\b"))
})

test("builtin() and toText() match omagnet for every name, good and bad", () => {
  assert.ok(golden.builtin.length > 20)
  for (const g of golden.builtin) {
    const zones = Z.builtin(g.name)
    assert.deepEqual(zones, g.zones, g.name)
    if (zones) assert.equal(Z.toText(zones), g.text, g.name)
  }
})

test("parse() matches omagnet for every text, errors included, and formats back the same", () => {
  for (const g of golden.parse) {
    const r = Z.parse(g.text)
    if (g.error) assert.deepEqual(r, { error: g.error }, g.text)
    else {
      assert.deepEqual(r.zones, g.zones, g.text)
      assert.equal(Z.toText(r.zones), g.back, g.text)
    }
  }
})

test("ofLayout() takes a built-in name first, then zones text, and says why it refuses", () => {
  assert.equal(Z.ofLayout("columns:2").zones.length, 2)
  assert.deepEqual(Z.ofLayout("0 0 0.25 1; 0.25 0 0.75 1").zones, [{ x: 0, y: 0, w: 2500, h: 10000 }, { x: 2500, y: 0, w: 7500, h: 10000 }])
  for (const bad of ["tiled", "columns:13", "", "0 0 2 1"]) assert.match(Z.ofLayout(bad).error, /not a zone layout name and not zones text/)
})
