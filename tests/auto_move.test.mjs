import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const load = (f) => readFileSync(new URL("../js/" + f, import.meta.url), "utf8").replace(".pragma library", "")
const { apply } = new Function(load("AutoMove.js") + "; return { apply }")()

const win = (cls, order, extra) => ({ app: cls, class: cls, context: "", rect: [0, 0, 1, 1], order, floating: true,
  launch: "", folder: "", edited: "", ...extra })
const doc = () => ({ schema: 1, scenes: {
  three: { existing: "move", windows: [win("org.example.Mail", 1), win("chrome", 2, { context: "Profile 1", launch: "chrome --p", edited: "rect" }), win("org.example.Term", 3, { folder: "/made/up" })] },
  four: { existing: "move", windows: [win("org.example.Notes", 1), win("org.example.Chat", 2)] }
} })
const ev = (extra) => ({ class: "org.example.Mail", context: "", from_scene: "three", to_scene: "four", rect: [0.5, 0, 0.5, 1],
  floating: false, order: 2, at: 1000, ...extra })

test("a slot leaves one scene and joins the other with the event's place, orders renumbered", () => {
  const before = doc()
  const r = apply(before, [ev()])
  assert.equal(r.applied, 1)
  assert.deepEqual(r.skipped, [])
  assert.deepEqual(r.doc.scenes.three.windows.map((w) => [w.class, w.order]), [["chrome", 1], ["org.example.Term", 2]])
  assert.deepEqual(r.doc.scenes.four.windows.map((w) => [w.class, w.order]),
    [["org.example.Notes", 1], ["org.example.Mail", 2], ["org.example.Chat", 3]])
  const moved = r.doc.scenes.four.windows[1]
  assert.deepEqual(moved.rect, [0.5, 0, 0.5, 1])
  assert.equal(moved.floating, false)
  assert.deepEqual(before, doc(), "input untouched")
})

test("a Chrome profile context matches by class and context, and other fields stay", () => {
  const r = apply(doc(), [ev({ class: "chrome", context: "Profile 1", order: 1 })])
  assert.equal(r.applied, 1)
  const w = r.doc.scenes.four.windows[0]
  assert.deepEqual([w.class, w.context, w.launch, w.edited, w.order], ["chrome", "Profile 1", "chrome --p", "rect", 1])
  // another profile of the same class is a different slot
  const r2 = apply(doc(), [ev({ class: "chrome", context: "Profile 2" })])
  assert.equal(r2.applied, 0)
  assert.equal(r2.skipped[0].reason, "unknown slot")
})

test("applying the same event twice changes nothing the second time", () => {
  const once = apply(doc(), [ev()])
  const twice = apply(once.doc, [ev()])
  assert.equal(twice.applied, 0)
  assert.equal(twice.skipped[0].reason, "already applied")
  assert.deepEqual(twice.doc, once.doc)
  assert.deepEqual(apply(doc(), [ev(), ev()]).doc, once.doc)
})

test("unknown scenes and slots are skipped and reported, the rest still apply", () => {
  const r = apply(doc(), [ev({ to_scene: "nope" }), ev({ class: "org.example.Ghost" }), ev({ to_scene: "three" }), { x: 1 }, ev()])
  assert.equal(r.applied, 1)
  assert.deepEqual(r.skipped.map((s) => [s.index, s.reason]),
    [[0, "unknown scene"], [1, "unknown slot"], [2, "same scene"], [3, "bad event"]])
})

test("a bad rect keeps the old one; an order past the end appends", () => {
  const r = apply(doc(), [ev({ rect: [1, "x"], order: 99 })])
  assert.deepEqual(r.doc.scenes.four.windows[2].rect, [0, 0, 1, 1])
  assert.equal(r.doc.scenes.four.windows[2].class, "org.example.Mail")
})
