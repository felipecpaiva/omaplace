// js/PlanMoves.js: plan-moves.json reading, new vs notified, and the "Update plan" edit (design 14.8). Made-up data only.
import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./js_load.mjs"

const P = load("PlanMoves.js")
const S = load("SceneStore.js")

const MON = "Example Corp EX27"
const TOML = `schema = 1

[scene.desk-2]
plan = true
layout = "columns:2"
home_monitor = "${MON}"
home_slot = 2

[scene.desk-2.window.1]
class = "org.example.Editor"
rect = "0 0 0.5 1"
zone = 1

[scene.desk-2.window.2]
class = "chromium"
context = "Profile 1"
rect = "0.5 0 0.5 1"
zone = 2

[scene.desk-3]
plan = true
layout = "grid:2x2"
home_monitor = "${MON}"
home_slot = 3

[scene.desk-3.window.1]
class = "org.example.Mail"
zone = 1

[scene.desk-4]
plan = true
layout = "full"
home_monitor = "${MON}"
home_slot = 4

[scene.desk-4.window.1]
class = "org.example.Music"
zone = 1

[scene.desk-5]
plan = true
layout = "tiled"
home_monitor = "${MON}"
home_slot = 5

[scene.desk-5.window.1]
class = "org.example.Term"
zone = 1

[scene.desk-5.window.2]
class = "org.example.Files"
zone = 2

[scene.desk-6]
plan = true
layout = "free"
home_monitor = "${MON}"
home_slot = 6

[scene.desk-6.window.1]
class = "org.example.Notes"
rect = "0.1 0.1 0.3 0.3"

[scene.work]
home_slot = 0

[scene.work.window.1]
class = "org.example.Other"
`
const doc = () => {
  const d = S.parse(TOML)
  assert.deepEqual(d.errors, [])
  return d
}
const mv = (id, extra) => ({ id, scene: "desk-2", window: 1, class: "org.example.Editor", context: "", kind: "zone",
  to: { identity: MON, slot: 2, rect: [0.55, 0.1, 0.4, 0.8], floating: true }, ...extra })
const toDesk = (slot, rect, extra) => ({ kind: "desktop", to: { identity: MON, slot, rect: rect === undefined ? null : rect, floating: true }, ...extra })

test("parse keeps only well formed moves; bad text gives none", () => {
  const good = mv(1)
  const text = JSON.stringify({ seq: 9, moves: [good, mv(0), mv(2, { kind: "resize" }), mv(3, { window: 0 }), mv(4, { class: "" }),
    mv(5, { to: { rect: [1, 2] } }), mv(6, { kind: "desktop", to: { identity: MON, slot: 11, rect: null } }),
    mv(7, toDesk(3)), mv(8, { to: null }), null, "x",
    mv(9, { kind: "desktop", to: { identity: MON, slot: 5, floating: false } })] }) // a tiled window has no rect (WP12a)
  assert.deepEqual(P.parse(text).map((m) => m.id), [1, 7, 9])
  assert.deepEqual(P.parse("not json"), [])
  assert.deepEqual(P.parse('{"seq":1}'), [])
  assert.deepEqual(P.parse(""), [])
})

test("find: by id", () => {
  assert.equal(P.find([mv(1), mv(2)], 2).id, 2)
  assert.equal(P.find([mv(1)], 9), null)
})

test("zoneAt: the zone holding the centre, edges included at the screen's end, else 0", () => {
  assert.equal(P.zoneAt("columns:2", [0, 0, 0.4, 1]), 1)
  assert.equal(P.zoneAt("columns:2", [0.3, 0, 0.4, 1]), 2) // centre exactly on the line belongs to the right zone
  assert.equal(P.zoneAt("columns:2", [0.9, 0.9, 0.2, 0.2]), 2) // centre at the far corner
  assert.equal(P.zoneAt("grid:2x2", [0.6, 0.6, 0.2, 0.2]), 4)
  assert.equal(P.zoneAt("0 0 0.5 0.5", [0.6, 0.6, 0.2, 0.2]), 0)
  assert.equal(P.zoneAt("columns:2", null), 0)
  assert.equal(P.zoneAt("not a layout", [0, 0, 1, 1]), 0)
})

test("zone move: the window takes the zone holding its centre, with the zone's rect; the input doc is unchanged", () => {
  const d = doc()
  const before = JSON.stringify(d)
  const editor = mv(1, { scene: "desk-3", class: "org.example.Mail", to: { rect: [0.6, 0.6, 0.3, 0.3] } })
  const r = P.edit(d, editor)
  assert.equal(r.changed, true)
  assert.equal(r.doc.scenes["desk-3"].windows[0].zone, 4)
  assert.deepEqual(r.doc.scenes["desk-3"].windows[0].rect, [0.5, 0.5, 0.5, 0.5])
  assert.equal(JSON.stringify(d), before)
  assert.doesNotThrow(() => S.serialize(r.doc))
})

test("zone move: same zone changes nothing; no rect and a layout without zones are not possible", () => {
  assert.deepEqual(P.edit(doc(), mv(1, { to: { rect: [0, 0, 0.4, 1] } })).changed, false)
  const noRect = P.edit(doc(), mv(1, { scene: "desk-3", class: "org.example.Mail", to: { rect: null } }))
  assert.deepEqual(noRect, { code: "not_possible", reason: "the move has no place" })
  assert.equal(P.edit(doc(), mv(1, { scene: "desk-3", class: "org.example.Mail", to: {} })).reason, "the move has no place")
  const tiled = P.edit(doc(), mv(1, { scene: "desk-5", class: "org.example.Term" }))
  assert.equal(tiled.code, "not_possible")
  assert.match(tiled.reason, /layout tiled has no zones/)
})

test("zone move onto a zone another window holds: the two swap zones and rects, and the plan is re-placed (D24)", () => {
  const r = P.edit(doc(), mv(1))
  assert.equal(r.changed, true)
  assert.equal(r.replace, true)
  const [editor, chrome] = r.doc.scenes["desk-2"].windows
  assert.deepEqual([editor.class, editor.zone, editor.rect], ["org.example.Editor", 2, [0.5, 0, 0.5, 1]])
  assert.deepEqual([chrome.class, chrome.zone, chrome.rect, chrome.context], ["chromium", 1, [0, 0, 0.5, 1], "Profile 1"])
  assert.doesNotThrow(() => S.serialize(r.doc))
  // a move into a free zone needs no re-place: only the moved window changed and it is already there
  assert.equal(P.edit(doc(), mv(1, { scene: "desk-3", class: "org.example.Mail", to: { rect: [0.6, 0.6, 0.3, 0.3] } })).replace, undefined)
})

test("zone move outside every zone: the plan becomes free, every window keeps its rect (D24)", () => {
  const d = doc()
  d.scenes["desk-2"].layout = "0 0 0.5 0.5; 0.5 0 0.5 0.5" // two zones in the top half only
  d.scenes["desk-2"].windows[0].rect = [0, 0, 0.5, 0.5]
  delete d.scenes["desk-2"].windows[1].rect // a window without a stored rect gets its zone's
  const r = P.edit(d, mv(1, { to: { rect: [0.1, 0.6, 0.3, 0.3] } }))
  assert.equal(r.changed, true)
  assert.equal(r.replace, undefined)
  const s = r.doc.scenes["desk-2"]
  assert.equal(s.layout, "free")
  assert.deepEqual(s.windows.map((w) => [w.class, w.zone, w.rect, w.floating]),
    [["org.example.Editor", undefined, [0.1, 0.6, 0.3, 0.3], true], ["chromium", undefined, [0.5, 0, 0.5, 0.5], true]])
  assert.deepEqual(S.planProblems(r.doc.scenes), {})
  assert.doesNotThrow(() => S.serialize(r.doc))
})

test("zone move of a free plan's window stores its new rect", () => {
  const notes = { scene: "desk-6", class: "org.example.Notes" }
  const r = P.edit(doc(), mv(1, { ...notes, to: { rect: [0.2, 0.2, 0.4, 0.4] } }))
  assert.deepEqual(r.doc.scenes["desk-6"].windows[0].rect, [0.2, 0.2, 0.4, 0.4])
  assert.equal(P.edit(doc(), mv(1, { ...notes, to: { rect: [0.1, 0.1, 0.3, 0.3] } })).changed, false)
})

test("a move whose plan is gone or changed is not found; an unreadable move is not possible", () => {
  assert.equal(P.edit(doc(), mv(1, { scene: "gone" })).code, "not_found")
  assert.equal(P.edit(doc(), mv(1, { scene: "work", class: "org.example.Other" })).code, "not_found") // not a plan
  assert.equal(P.edit(doc(), mv(1, { window: 3 })).code, "not_found")
  assert.equal(P.edit(doc(), mv(1, { class: "org.example.Changed" })).code, "not_found")
  assert.equal(P.edit(doc(), mv(1, { window: 2, class: "chromium", context: "Profile 2" })).code, "not_found")
  assert.equal(P.edit(doc(), { id: 1 }).code, "not_possible")
})

test("desktop move of a single-window plan rebinds its desktop; the same desktop changes nothing", () => {
  const r = P.edit(doc(), mv(1, { scene: "desk-3", class: "org.example.Mail", ...toDesk(7) }))
  assert.equal(r.changed, true)
  assert.equal(r.doc.scenes["desk-3"].home_slot, 7)
  assert.equal(r.doc.scenes["desk-3"].home_monitor, MON)
  assert.equal(P.edit(doc(), mv(1, { scene: "desk-3", class: "org.example.Mail", ...toDesk(3) })).changed, false)
})

test("desktop move of a single-window plan onto a desktop with a plan joins it, and the empty plan is removed", () => {
  const mail = { scene: "desk-3", class: "org.example.Mail" }
  // tiled: added last
  const t = P.edit(doc(), mv(1, { ...mail, ...toDesk(5) }))
  assert.equal(t.changed, true)
  assert.equal(t.removed, "desk-3")
  assert.equal(t.scene, "desk-5")
  assert.equal(t.doc.scenes["desk-3"], undefined)
  assert.deepEqual(t.doc.scenes["desk-5"].windows.map((w) => [w.class, w.zone]),
    [["org.example.Term", 1], ["org.example.Files", 2], ["org.example.Mail", 3]])
  assert.deepEqual(S.planProblems(t.doc.scenes), {})
  assert.doesNotThrow(() => S.serialize(t.doc))
  // free: at its rect
  const f = P.edit(doc(), mv(1, { ...mail, ...toDesk(6, [0.5, 0.5, 0.4, 0.4]) }))
  assert.deepEqual(f.doc.scenes["desk-6"].windows[1].rect, [0.5, 0.5, 0.4, 0.4])
  assert.equal(f.doc.scenes["desk-3"], undefined)
  // zone plan: the zone by its centre (desk-2 is full, so empty its zone 2 first)
  const d = doc()
  d.scenes["desk-2"].windows.pop()
  const z = P.edit(d, mv(1, { ...mail, ...toDesk(2, [0.6, 0.1, 0.3, 0.3]) }))
  assert.deepEqual(z.doc.scenes["desk-2"].windows.map((w) => [w.class, w.zone]), [["org.example.Editor", 1], ["org.example.Mail", 2]])
  assert.equal(z.removed, "desk-3")
  // taken zone, outside every zone, a full plan: not possible, nothing removed
  assert.match(P.edit(doc(), mv(1, { ...mail, ...toDesk(2, [0.6, 0.1, 0.3, 0.3]) })).reason, /used twice/)
  assert.match(P.edit(doc(), mv(1, { ...mail, ...toDesk(2) })).reason, /outside every zone/)
  const full = P.edit(doc(), mv(1, { ...mail, ...toDesk(4) }))
  assert.equal(full.doc.scenes["desk-4"].layout, "tiled", "a full plan with a second window becomes tiled (D28)")
})

test("desktop move from a many-window plan joins the target plan by its layout", () => {
  const editor = mv(1, toDesk(3, [0.6, 0.1, 0.3, 0.3]))
  const z = P.edit(doc(), editor)
  assert.equal(z.changed, true)
  assert.deepEqual(z.doc.scenes["desk-2"].windows.map((w) => w.class), ["chromium"])
  const moved = z.doc.scenes["desk-3"].windows[1]
  assert.deepEqual([moved.class, moved.zone, moved.rect, moved.floating], ["org.example.Editor", 2, [0.5, 0, 0.5, 0.5], true])
  assert.doesNotThrow(() => S.serialize(z.doc))

  const t = P.edit(doc(), mv(1, toDesk(5)))
  assert.deepEqual(t.doc.scenes["desk-5"].windows.map((w) => [w.class, w.zone]),
    [["org.example.Term", 1], ["org.example.Files", 2], ["org.example.Editor", 3]])

  const f = P.edit(doc(), mv(1, toDesk(6, [0.2, 0.2, 0.5, 0.5])))
  const free = f.doc.scenes["desk-6"].windows[1]
  assert.equal(free.zone, undefined)
  assert.deepEqual(free.rect, [0.2, 0.2, 0.5, 0.5])
  assert.doesNotThrow(() => S.serialize(f.doc))
  const fKeep = P.edit(doc(), mv(1, toDesk(6)))
  assert.deepEqual(fKeep.doc.scenes["desk-6"].windows[1].rect, [0, 0, 0.5, 1])
})

test("desktop move from a many-window plan: a full plan becomes tiled; a taken or missing zone is not possible", () => {
  const f = P.edit(doc(), mv(1, toDesk(4)))
  assert.deepEqual([f.doc.scenes["desk-4"].layout, f.doc.scenes["desk-4"].windows.map((w) => [w.class, w.zone])],
    ["tiled", [["org.example.Music", 1], ["org.example.Editor", 2]]])
  assert.deepEqual(S.planProblems(f.doc.scenes), {})
  assert.match(P.edit(doc(), mv(1, toDesk(3, [0, 0, 0.3, 0.3]))).reason, /used twice/)
  assert.match(P.edit(doc(), mv(1, toDesk(3))).reason, /outside every zone/)
})

test("desktop move from a many-window plan onto a desktop with no plan: a new free plan holds the window (D24)", () => {
  const r = P.edit(doc(), mv(1, toDesk(8, [0.1, 0.2, 0.3, 0.4])))
  assert.equal(r.changed, true)
  assert.equal(r.created, "desk-example-corp-ex27-8")
  assert.deepEqual(r.doc.scenes["desk-2"].windows.map((w) => w.class), ["chromium"])
  const s = r.doc.scenes[r.created]
  assert.deepEqual([s.plan, s.layout, s.home_monitor, s.home_slot, s.open_at_login], [true, "free", MON, 8, false])
  assert.deepEqual(s.windows.map((w) => [w.class, w.zone, w.rect, w.floating]), [["org.example.Editor", undefined, [0.1, 0.2, 0.3, 0.4], true]])
  assert.deepEqual(S.planProblems(r.doc.scenes), {})
  assert.doesNotThrow(() => S.serialize(r.doc))
  const back = S.parse(S.serialize(r.doc))
  assert.deepEqual(back.errors, [])
  assert.equal(back.scenes[r.created].layout, "free")

  // another monitor: its own plan; a tiled window without a rect gets the whole desktop
  const o = P.edit(doc(), mv(1, toDesk(2, null, { to: { identity: "Other Monitor", slot: 2, rect: null, floating: false } })))
  assert.equal(o.created, "desk-other-monitor-2")
  assert.equal(o.scene, o.created)
  assert.deepEqual([o.doc.scenes[o.created].windows[0].rect, o.doc.scenes[o.created].windows[0].floating], [[0, 0, 1, 1], false]) // stays tiled

  // a taken name gets a number
  const d = doc()
  d.scenes["desk-example-corp-ex27-8"] = { ...d.scenes.work }
  assert.equal(P.edit(d, mv(1, toDesk(8))).created, "desk-example-corp-ex27-8-2")
})

test("a plan on the focused monitor (\"\") moving a window to a desktop with no plan: the new plan is on \"\" too", () => {
  const d = doc()
  d.scenes["desk-5"].home_monitor = ""
  const r = P.edit(d, mv(1, { scene: "desk-5", class: "org.example.Term", ...toDesk(9) }))
  assert.equal(r.created, "desk-monitor-9")
  assert.equal(r.doc.scenes[r.created].home_monitor, "")
  assert.deepEqual(r.doc.scenes["desk-5"].windows.map((w) => w.class), ["org.example.Files"])
  // and a "" plan on the target slot counts as that desktop's plan: the window joins it
  d.scenes["desk-6"].home_monitor = ""
  const j = P.edit(d, mv(1, toDesk(6, [0.2, 0.2, 0.5, 0.5])))
  assert.equal(j.created, undefined)
  assert.deepEqual(j.doc.scenes["desk-6"].windows.map((w) => w.class), ["org.example.Notes", "org.example.Editor"])
})

test("desktop move of one of two windows of one app: the moved one is known by its index (D28)", () => {
  const d = doc()
  d.scenes["desk-5"].windows.push({ ...d.scenes["desk-5"].windows[0], zone: 3 })
  const r = P.edit(d, mv(1, { scene: "desk-5", window: 3, class: "org.example.Term", ...toDesk(6) }))
  assert.equal(r.changed, true)
  assert.deepEqual(r.doc.scenes["desk-5"].windows.map((w) => [w.class, w.zone]), [["org.example.Term", 1], ["org.example.Files", 2]])
  assert.deepEqual(r.doc.scenes["desk-6"].windows.map((w) => w.class), ["org.example.Notes", "org.example.Term"])
  // the index must still name that app
  assert.equal(P.edit(d, mv(1, { scene: "desk-5", window: 2, class: "org.example.Term", ...toDesk(6) })).code, "not_found")
})

test("a one-window plan on the focused monitor (home_monitor empty) keeps it empty and only changes its slot", () => {
  const d = doc()
  d.scenes["desk-3"].home_monitor = ""
  const mail = { scene: "desk-3", class: "org.example.Mail" }
  const r = P.edit(d, mv(1, { ...mail, ...toDesk(7) }))
  assert.equal(r.changed, true)
  assert.equal(r.doc.scenes["desk-3"].home_monitor, "")
  assert.equal(r.doc.scenes["desk-3"].home_slot, 7)
  assert.doesNotThrow(() => S.serialize(r.doc))
  // the same slot on whatever monitor is the same desktop for such a plan
  assert.equal(P.edit(d, mv(1, { ...mail, ...toDesk(3) })).changed, false)
})
