import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const load = (f) => readFileSync(new URL("../js/" + f, import.meta.url), "utf8").replace(".pragma library", "")
const P = new Function(load("Plan.js") + "; return { fromScene, fromSession }")()
const { encode } = new Function(load("LuaLiteral.js") + "; return { encode }")()

const scene = {
  existing: "move",
  windows: [
    { app: "org.example.Mail", class: "org.example.Mail", context: "", rect: [0.5, 0, 0.5, 1], order: 2, floating: true },
    { app: "org.example.Editor", class: "org.example.Editor", context: "", rect: [0, 0, 0.5, 1], order: 1, floating: true },
    { app: "chromium", class: "chromium", context: "Profile 1", rect: [0, 0, 1, 1], order: 3, floating: false }
  ]
}
const launches = [
  { strategy: "desktop", mode: "launch", argv: ["uwsm-app", "--", "org.example.Mail.desktop"], contextKind: "none", reason: "" },
  { strategy: "desktop", mode: "launch", argv: ["uwsm-app", "--", "org.example.Editor.desktop"], contextKind: "none", reason: "" },
  { strategy: "place_only", mode: "place_only", argv: null, contextKind: "none", reason: "" }
]
const target = { run: "r-20261121-1", fp: { identity: "Example Corp EX27 #1" }, slot: 0, layout: "floating", expiry_s: 25 }
const rules = { editor: { app: "org.example.Editor", monitor: "Example Corp EX27 #1", slot: 3, follow: true, enabled: true } }

test("fromScene builds the plan of design 5.4, windows in saved order", () => {
  const p = P.fromScene(scene, launches, target, rules)
  assert.equal(p.run, "r-20261121-1")
  assert.deepEqual(p.target, { fp: { identity: "Example Corp EX27 #1" }, slot: 0 })
  assert.equal(p.existing, "move")
  assert.equal(p.expiry_s, 25)
  assert.equal(p.layout, "floating")
  assert.deepEqual(p.windows.map((w) => w.class), ["org.example.Editor", "org.example.Mail", "chromium"])
  assert.deepEqual(p.windows[0], {
    class: "org.example.Editor", order: 1, rect: [0, 0, 0.5, 1], floating: true, mode: "launch",
    launch: ["uwsm-app", "--", "org.example.Editor.desktop"], desktop: { monitor: "Example Corp EX27 #1", slot: 3, follow: true }
  })
  assert.deepEqual(p.windows[2], { class: "chromium", order: 3, rect: [0, 0, 1, 1], floating: false, mode: "place_only", context: "Profile 1" })
})

test("a rule applies per class, only when enabled; disabled and other classes get no desktop", () => {
  const off = { editor: { ...rules.editor, enabled: false } }
  assert.ok(P.fromScene(scene, launches, target, off).windows.every((w) => !("desktop" in w)))
  const p = P.fromScene(scene, launches, target, rules)
  assert.ok(!("desktop" in p.windows[1]))
  assert.ok(P.fromScene(scene, launches, target, undefined).windows.every((w) => !("desktop" in w)))
})

test("skip mode keeps the window so the run can report it", () => {
  const p = P.fromScene(scene, [launches[0], { strategy: "desktop", mode: "skip", argv: null, contextKind: "none", reason: "x" }], target, {})
  assert.equal(p.windows[0].mode, "skip")
  assert.ok(!("launch" in p.windows[0]))
  assert.equal(p.windows[2].mode, "skip") // missing launch result counts as skip
})

test("layout falls back to floating, expiry to 20, existing=new is kept", () => {
  const p = P.fromScene({ ...scene, existing: "new" }, launches, { run: "r", fp: {}, layout: "weird" }, {})
  assert.equal(p.layout, "floating")
  assert.equal(p.expiry_s, 20)
  assert.equal(p.existing, "new")
  assert.equal(P.fromScene(scene, launches, { ...target, layout: "scrolling" }, {}).layout, "scrolling")
})

test("a run id is required and never made up", () => {
  assert.throws(() => P.fromScene(scene, launches, { fp: {} }, {}), /run id/)
  assert.throws(() => P.fromSession({ windows: [] }, [], {}), /run id/)
})

test("the plan encodes to one Lua literal with no undefined or null", () => {
  const text = encode(P.fromScene(scene, launches, target, rules))
  assert.match(text, /^\{run = "r-20261121-1", target = \{fp = \{identity = "Example Corp EX27 #1"\}, slot = 0\}/)
  assert.ok(text.includes('launch = {"uwsm-app", "--", "org.example.Editor.desktop"}'))
  assert.ok(!text.includes("\n"))
})

const snapshot = {
  schema: 1, kind: "session", saved_at: 1763700000, mode: "per_monitor",
  monitors: [{ fp: { identity: "Example Corp EX27 #1", internal: false } }, { fp: { identity: "Example Panel", internal: true } }],
  windows: [
    { class: "org.example.Mail", monitor: 1, slot: 1, order: 1, rect: [0, 0, 1, 1], floating: false, fullscreen: 0, minimized: false },
    { class: "org.example.Editor", monitor: 0, slot: 2, order: 2, rect: [0.5, 0, 0.5, 1], floating: true, fullscreen: 0, minimized: false },
    { class: "org.example.Editor", monitor: 0, slot: 2, order: 1, rect: [0, 0, 0.5, 1], floating: true, fullscreen: 0, minimized: false }
  ]
}

test("fromSession keeps monitor and slot per window, ordered by monitor, slot, order", () => {
  const l = [launches[0], launches[1], launches[1]]
  const p = P.fromSession(snapshot, l, { run: "r-s1" })
  assert.equal(p.kind, "session")
  assert.deepEqual(p.monitors, [{ identity: "Example Corp EX27 #1", internal: false }, { identity: "Example Panel", internal: true }])
  assert.deepEqual(p.windows.map((w) => [w.monitor, w.slot, w.order]), [[0, 2, 1], [0, 2, 2], [1, 1, 1]])
  assert.equal(p.windows[2].class, "org.example.Mail")
  assert.equal(p.windows[2].mode, "launch")
  assert.deepEqual(p.windows[0].launch, ["uwsm-app", "--", "org.example.Editor.desktop"])
  assert.doesNotThrow(() => encode(p))
})
