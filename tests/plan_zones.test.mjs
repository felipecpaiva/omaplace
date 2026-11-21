// Plan.js for plan scenes (design 14.2): zone to rect and order, the layout for the opener, the full marker. Made-up data.
import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./js_load.mjs"

const P = load("Plan.js")
const { encode } = load("LuaLiteral.js")

const win = (cls, zone, extra) => ({ app: cls, class: cls, context: "", rect: [0, 0, 1, 1], order: 1, floating: true,
  launch: "", folder: "", edited: "", zone, ...extra })
const plan = (layout, windows) => ({ plan: true, layout, existing: "move", home_monitor: "", home_slot: 2, windows })
const launch = (cls) => ({ strategy: "desktop", mode: "launch", argv: ["uwsm-app", "--", cls + ".desktop"], contextKind: "none", reason: "" })
const target = { run: "r-1", fp: {}, slot: 2, layout: "tiled", expiry_s: 20 }
const open = (scene) => P.fromScene(scene, scene.windows.map((w) => launch(w.class)), target, {})

test("zoneRect gives the zone as fractions, the value the page stores with a zone", () => {
  assert.deepEqual(P.zoneRect("columns:2", 2), { rect: [0.5, 0, 0.5, 1] })
  assert.deepEqual(P.zoneRect("columns:3", 1), { rect: [0, 0, 0.3333, 1] })
  assert.deepEqual(P.zoneRect("grid:2x2", 4), { rect: [0.5, 0.5, 0.5, 0.5] })
  assert.deepEqual(P.zoneRect("priority", 2), { rect: [0.25, 0, 0.5, 1] })
  assert.deepEqual(P.zoneRect("0.1 0.2 0.3 0.4", 1), { rect: [0.1, 0.2, 0.3, 0.4] })
  assert.match(P.zoneRect("columns:2", 3).error, /zone 3: layout columns:2 has zones 1 to 2/)
  assert.match(P.zoneRect("columns:2", 0).error, /zone 0/)
  assert.match(P.zoneRect("tiled", 1).error, /layout "tiled": not a zone layout name/)
})

test("a zone layout floats, places each window in its zone, and orders zones left to right, then top to bottom", () => {
  // grid:2x2 zones: 1 top left, 2 top right, 3 bottom left, 4 bottom right; left to right puts 3 before 2
  const s = plan("grid:2x2", [win("org.example.D", 4), win("org.example.A", 1), win("org.example.B", 2), win("org.example.C", 3)])
  const p = open(s)
  assert.equal(p.layout, "floating")
  assert.deepEqual(p.windows.map((w) => [w.class, w.order, w.rect, w.floating]), [
    ["org.example.A", 1, [0, 0, 0.5, 0.5], true],
    ["org.example.C", 2, [0, 0.5, 0.5, 0.5], true],
    ["org.example.B", 3, [0.5, 0, 0.5, 0.5], true],
    ["org.example.D", 4, [0.5, 0.5, 0.5, 0.5], true]
  ])
  assert.ok(p.windows.every((w) => w.fullscreen === undefined))
  assert.deepEqual(s.windows[0].rect, [0, 0, 1, 1], "the scene is not changed")
})

test("zones text plans use the text's zones", () => {
  const p = open(plan("0.6 0 0.4 1; 0 0 0.6 1", [win("org.example.A", 1), win("org.example.B", 2)]))
  assert.deepEqual(p.windows.map((w) => [w.class, w.order, w.rect]), [["org.example.B", 1, [0, 0, 0.6, 1]], ["org.example.A", 2, [0.6, 0, 0.4, 1]]])
})

test("tiled and scrolling open in zone order, not floating, with their own layout", () => {
  for (const layout of ["tiled", "scrolling"]) {
    const p = P.fromScene(plan(layout, [win("org.example.B", 5), win("org.example.A", 2)]), [launch("org.example.B"), launch("org.example.A")],
      { ...target, layout: "floating" }, {})
    assert.equal(p.layout, layout)
    assert.deepEqual(p.windows.map((w) => [w.class, w.order, w.floating]), [["org.example.A", 1, false], ["org.example.B", 2, false]])
  }
})

test("full keeps the desktop's layout and marks its one window fullscreen = 1, which LuaLiteral writes", () => {
  const p = open(plan("full", [win("org.example.A", 1)]))
  assert.equal(p.layout, "tiled", "the target's layout, unchanged")
  assert.equal(p.windows[0].fullscreen, 1)
  assert.match(encode(p), /fullscreen = 1/)
  assert.equal(P.fromScene(plan("full", [win("org.example.A", 1)]), [launch("org.example.A")], { ...target, layout: "floating" }, {}).layout, "floating")
})

test("free uses the saved rects and order, like a captured scene", () => {
  const p = open(plan("free", [win("org.example.B", undefined, { rect: [0.5, 0, 0.5, 1], order: 2 }), win("org.example.A", undefined, { rect: [0, 0, 0.5, 1], order: 1 })]))
  assert.equal(p.layout, "floating")
  assert.deepEqual(p.windows.map((w) => [w.class, w.order, w.rect]), [["org.example.A", 1, [0, 0, 0.5, 1]], ["org.example.B", 2, [0.5, 0, 0.5, 1]]])
})

test("a bad plan never opens", () => {
  assert.throws(() => open(plan("columns:2", [win("org.example.A", 3)])), /Plan: bad plan: zone 3/)
  assert.throws(() => open(plan("nope", [win("org.example.A", 1)])), /Plan: bad plan: layout/)
  assert.throws(() => open({ ...plan("tiled", []), planError: "read error" }), /Plan: bad plan: read error/)
})

test("planMode maps every layout kind to the desktop mode", () => {
  assert.deepEqual(["tiled", "scrolling", "full", "free", "columns:2", "0 0 1 1"].map(P.planMode),
    ["tiled", "scrolling", "", "floating", "floating", "floating"])
})
