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
    mv(7, toDesk(3)), mv(8, { to: null }), null, "x"] })
  assert.deepEqual(P.parse(text).map((m) => m.id), [1, 7])
  assert.deepEqual(P.parse("not json"), [])
  assert.deepEqual(P.parse('{"seq":1}'), [])
  assert.deepEqual(P.parse(""), [])
})

test("fresh: moves above the last id, oldest first; a counter that started again counts all as new", () => {
  const list = [mv(5), mv(3), mv(4)]
  assert.deepEqual(P.fresh(list, 0), { moves: [mv(3), mv(4), mv(5)], maxId: 5 })
  assert.deepEqual(P.fresh(list, 4), { moves: [mv(5)], maxId: 5 })
  assert.deepEqual(P.fresh(list, 5), { moves: [], maxId: 5 })
  assert.deepEqual(P.fresh([mv(1), mv(2)], 40).moves.map((m) => m.id), [1, 2])
  assert.deepEqual(P.fresh([], 7), { moves: [], maxId: 7 })
})

test("find and notice: by id; text holds class and scene only", () => {
  assert.equal(P.find([mv(1), mv(2)], 2).id, 2)
  assert.equal(P.find([mv(1)], 9), null)
  assert.deepEqual(P.notice(mv(1)), { headline: "omaplace: desk-2", body: "org.example.Editor left its zone" })
  assert.equal(P.notice(mv(1, toDesk(3))).body, "org.example.Editor moved to another desktop")
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

test("zone move: same zone changes nothing; taken zone, no zone, no zones in the layout are not possible", () => {
  assert.deepEqual(P.edit(doc(), mv(1, { to: { rect: [0, 0, 0.4, 1] } })).changed, false)
  const taken = P.edit(doc(), mv(1))
  assert.equal(taken.code, "not_possible")
  assert.match(taken.reason, /zone 2 already holds chromium/)
  const outside = P.edit(doc(), mv(1, { scene: "desk-3", class: "org.example.Mail", to: { rect: null } }))
  assert.deepEqual(outside, { code: "not_possible", reason: "the window is outside every zone" })
  const tiled = P.edit(doc(), mv(1, { scene: "desk-5", class: "org.example.Term" }))
  assert.equal(tiled.code, "not_possible")
  assert.match(tiled.reason, /layout tiled has no zones/)
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

test("desktop move of a single-window plan onto a desktop with a plan is not possible (one plan per desktop)", () => {
  const r = P.edit(doc(), mv(1, { scene: "desk-3", class: "org.example.Mail", ...toDesk(2) }))
  assert.equal(r.code, "not_possible")
  assert.match(r.reason, /already has plan/)
  assert.ok(!/[",]/.test(r.reason))
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

test("desktop move from a many-window plan: no plan there, a full plan, a taken or missing zone are not possible", () => {
  assert.match(P.edit(doc(), mv(1, toDesk(8))).reason, /no plan on desktop 8/)
  assert.match(P.edit(doc(), mv(1, toDesk(4))).reason, /full holds one window/)
  assert.match(P.edit(doc(), mv(1, toDesk(3, [0, 0, 0.3, 0.3]))).reason, /used twice/)
  assert.match(P.edit(doc(), mv(1, toDesk(3))).reason, /outside every zone/)
  assert.match(P.edit(doc(), mv(1, toDesk(2, null, { to: { identity: "Other Monitor", slot: 2, rect: null } }))).reason, /no plan on desktop 2/)
})
