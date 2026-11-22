// js/Desktops.js: the Desktops page's card models and plan edits (WP13). Made-up data only.
import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./js_load.mjs"

const D = load("Desktops.js")
const Store = load("SceneStore.js")

const MON = "Example Corp EX27"
const win = (cls, zone, extra) => ({ app: cls, class: cls, context: "", rect: [0, 0, 1, 1], order: zone || 1, floating: true,
  launch: "", folder: "", edited: "", zone, ...extra })
const plan = (layout, windows, extra) => ({ plan: true, layout, existing: "move", home_monitor: MON, home_slot: 2,
  key: "", saved_on: "", open_at_login: false, windows, ...extra })
const doc = (scenes) => ({ schema: 1, scenes, warnings: [], errors: [], readOnly: false })
const desk = (slot, extra) => ({ identity: MON, slot, focused: false, ...extra })
const live = { monitors: [{ identity: MON, name: "DP-1", focused: true, slots: [{ slot: 1, workspace: 1 }, { slot: 2, workspace: 2 }] }],
  modes: { 1: "tiled", 2: "floating" }, windows: { 2: 3 } }
// round trip through the file format: what the page saves must serialize and parse back without errors
const roundTrip = (d) => Store.parse(Store.serialize(d))

test("layout labels, picker values and mode words", () => {
  assert.equal(D.layoutLabel("tiled"), "Tiled")
  assert.equal(D.layoutLabel("full"), "Full screen")
  assert.equal(D.layoutLabel("free"), "Free floating")
  assert.equal(D.layoutLabel("columns:2"), "Zones: 2 columns")
  assert.equal(D.layoutLabel("0 0 0.5 1; 0.5 0 0.5 1"), "Zones: custom (2)")
  assert.equal(D.layoutLabel("nonsense"), "Bad layout")
  assert.equal(D.layoutChoice("grid:2x2"), "grid:2x2")
  assert.equal(D.layoutChoice("0 0 1 1"), "custom")
  assert.equal(D.layoutChoice(""), "")
  assert.equal(D.layoutChoice(undefined), "")
  assert.equal(D.modeLabel("floating"), "Floating")
  assert.equal(D.modeLabel("dwindle"), "")
  assert.equal(D.isZoneLayout("priority"), true)
  assert.equal(D.isZoneLayout("scrolling"), false)
  assert.deepEqual(["full", "free", "tiled", "scrolling", "rows:2"].map((l) => D.rowTitle(l, 2)), ["Full screen", "Window 2", "Column 2", "Column 2", "Zone 2"])
})

test("newSceneName: desk-<monitor>-<slot>, valid, at most 40, unique", () => {
  assert.equal(D.newSceneName(MON, 3, {}), "desk-example-corp-ex27-3")
  assert.equal(D.newSceneName(MON, 3, { "desk-example-corp-ex27-3": {} }), "desk-example-corp-ex27-3-2")
  assert.equal(D.newSceneName("", 1, {}), "desk-monitor-1")
  const long = D.newSceneName("A Very Long Monitor Description From Some Maker #2", 10, {})
  assert.ok(long.length <= 40 && /^[a-z0-9_-]{1,40}$/.test(long), long)
  const taken = {}
  for (let n = 0; n < 99; n++) taken[D.newSceneName(MON, 1, taken)] = {}
  assert.equal(D.newSceneName(MON, 1, taken), "")
})

test("findPlan: by monitor and slot, an empty monitor is the focused one, captured scenes never", () => {
  const scenes = { a: plan("tiled", []), b: plan("tiled", [], { home_monitor: "", home_slot: 4 }), c: { home_monitor: MON, home_slot: 5, windows: [] } }
  assert.equal(D.findPlan(scenes, MON, 2, false).name, "a")
  assert.equal(D.findPlan(scenes, MON, 4, false), null)
  assert.equal(D.findPlan(scenes, "Other", 4, true).name, "b")
  assert.equal(D.findPlan(scenes, MON, 5, true), null)
})

test("appChoices skips hidden entries and sorts by name; classOf and seenClasses", () => {
  const apps = D.appChoices([{ id: "zed.desktop", name: "Zed", icon: "zed", startupClass: "dev.zed.Zed" }, { id: "hidden", noDisplay: true },
    { id: "org.example.Mail", name: "mail", icon: "" }, null, { name: "no id" }])
  assert.deepEqual(apps.map((a) => a.value), ["org.example.Mail", "zed"])
  assert.equal(apps[1].startupWMClass, "dev.zed.Zed")
  assert.deepEqual(D.classOf("zed", apps, {}), { class: "dev.zed.Zed", confirmed: true })
  assert.deepEqual(D.classOf("org.example.Mail", apps, { "org.example.Mail": "Mail" }), { class: "Mail", confirmed: true })
  assert.deepEqual(D.classOf("gone", apps, {}), { class: "gone", confirmed: false })
  const seen = D.seenClasses({ cap: { windows: [win("x", undefined, { app: "app-x", class: "X" })] }, p: plan("tiled", [win("y", 1, { app: "app-y", class: "Y" })]) })
  assert.deepEqual(seen, { "app-x": "X" })
})

test("cards: ten per monitor, badge with Omarchy's mode when there is no plan", () => {
  const m = D.cards(live, doc({}), {})
  assert.equal(m.groups.length, 1)
  const cards = m.groups[0].cards
  assert.equal(cards.length, 10)
  assert.deepEqual(cards.map((c) => c.slot), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  assert.equal(cards[0].badge, "No plan, now Tiled")
  assert.equal(cards[1].windows, 3)
  assert.equal(cards[4].badge, "No plan")
  assert.equal(cards[4].workspace, 0)
  assert.equal(cards[0].plan, false)
})

test("cards: no desktops from Lua falls back to the live monitor names; no data at all is empty", () => {
  const m = D.cards({}, doc({}), { liveNames: ["Panel A"] })
  assert.equal(m.groups[0].name, "Panel A")
  assert.equal(m.groups[0].cards.length, 10)
  assert.equal(m.fallback, true)
  assert.equal(m.groups[0].cards[0].editable, false)
  assert.equal(D.cards(live, doc({}), { liveNames: ["Panel A"] }).groups[0].cards[0].editable, true)
  assert.deepEqual(D.cards(null, null, null), { groups: [], fallback: false })
})

test("cards: a zone plan shows its zones with apps, notes, and the mode switch it needs", () => {
  const apps = [{ value: "org.example.Editor", label: "Editor", icon: "ed", startupWMClass: "org.example.Editor" }]
  const scenes = {
    a: plan("columns:2", [win("org.example.Editor", 1)], { home_slot: 1 }),
    b: plan("tiled", [win("org.example.Editor", 1), win("chromium", 2, { context: "Default" })], { home_slot: 3 })
  }
  const m = D.cards(live, doc(scenes), { apps, rules: { r: { app: "chromium", monitor: MON, slot: 7, follow: false, enabled: true } } })
  const c = m.groups[0].cards[0]
  assert.equal(c.plan, true)
  assert.equal(c.name, "a")
  assert.equal(c.badge, "Zones: 2 columns")
  assert.equal(c.choice, "columns:2")
  assert.equal(c.modeNote, "Open all switches this desktop from Tiled to Floating.")
  assert.deepEqual(c.rows.map((r) => [r.pos, r.rect, r.label, r.empty]), [[1, [0, 0, 0.5, 1], "Editor", false], [2, [0.5, 0, 0.5, 1], "", true]])
  assert.equal(c.rows[0].icon, "ed")
  assert.match(c.rows[0].notes[0], /Also in plan b/)
  const t = m.groups[0].cards[2]
  assert.equal(t.badge, "Tiled")
  assert.equal(t.modeNote, "") // mode unknown for a desktop Lua gave no workspace for
  const chrome = t.rows.find((r) => r.cls === "chromium")
  assert.ok(chrome.notes.some((n) => /^Class is a guess \(chromium\)\. Open the app once/.test(n)))
  assert.equal(chrome.want, "chromium")
  assert.ok(chrome.notes.some((n) => /placement rule \(desktop 7\)/.test(n)))
  assert.ok(chrome.notes.some((n) => /profile or folder/.test(n)))
  assert.deepEqual(t.rows.map((r) => [r.pos, r.rect]), [[1, [0, 0, 0.5, 1]], [2, [0.5, 0, 0.5, 1]], [3, null]])
})

test("cards: full, free and empty tiled plans; a bad plan shows its reason and no rows", () => {
  const scenes = {
    f: plan("full", [win("org.example.Mail", 1)], { home_slot: 1 }),
    g: plan("free", [win("org.example.Mail", undefined, { rect: [0.1, 0.1, 0.5, 0.5] })], { home_slot: 2 }),
    h: plan("scrolling", [], { home_slot: 3 }),
    x: plan("columns:2", [win("org.example.Mail", 3)], { home_slot: 4 })
  }
  const d = Store.parse(Store.serialize(doc({ f: scenes.f, g: scenes.g, h: scenes.h })) + "\n[scene.x]\nplan = true\nlayout = \"columns:2\"\nhome_monitor = \"" + MON + "\"\nhome_slot = 4\n\n[scene.x.window.1]\nclass = \"m\"\nzone = 3\n")
  const cards = D.cards(live, d, {}).groups[0].cards
  assert.deepEqual(cards[0].rows.map((r) => [r.pos, r.rect, r.label]), [[1, [0, 0, 1, 1], "org.example.Mail"]])
  assert.equal(cards[0].modeNote, "") // full leaves the mode as it is
  assert.deepEqual(cards[1].rows.map((r) => [r.pos, r.rect, r.empty]), [[1, [0.1, 0.1, 0.5, 0.5], false], [2, null, true]])
  assert.deepEqual(cards[2].rows.map((r) => [r.pos, r.rect, r.empty]), [[1, [0, 0, 1, 1], true]])
  assert.equal(cards[3].badge, "Bad plan")
  assert.match(cards[3].error, /zone 3/)
  assert.deepEqual(cards[3].rows, [])
})

test("cards: a plan on a monitor that is not connected still gets a card", () => {
  const m = D.cards(live, doc({ away: plan("tiled", [], { home_monitor: "Gone Monitor", home_slot: 5 }), focus: plan("tiled", [], { home_monitor: "", home_slot: 6 }) }), {})
  assert.equal(m.groups[0].cards[5].name, "focus") // an empty monitor is the focused one, shown there
  assert.equal(m.groups.length, 2)
  assert.equal(m.groups[1].connected, false)
  assert.equal(m.groups[1].name, "Gone Monitor (not connected)")
  assert.deepEqual(m.groups[1].cards.map((c) => [c.name, c.slot]), [["away", 5]])
})

test("edit layout: a desktop without a plan gets a new plan, named for its desktop, that round trips", () => {
  const r = D.edit(doc({}), desk(3), "layout", "columns:2")
  assert.equal(r.error, undefined)
  assert.equal(r.name, "desk-example-corp-ex27-3")
  const s = r.doc.scenes[r.name]
  assert.deepEqual([s.plan, s.layout, s.home_monitor, s.home_slot, s.open_at_login], [true, "columns:2", MON, 3, false])
  assert.deepEqual(roundTrip(r.doc).errors, [])
  assert.equal(D.edit(doc({}), desk(3), "layout", "").error, "pick a layout")
  assert.match(D.edit(doc({}), desk(3), "layout", 'a"b').error, /double quote/)
  assert.match(D.edit(doc({}), desk(3), "layout", "0 0 2 1").error, /^zones: a zone must lie inside/)
  assert.equal(D.edit(doc({}), desk(3), "layout", "0 0 0.5 1; 0.5 0 0.5 1").doc.scenes["desk-example-corp-ex27-3"].layout, "0 0 0.5 1; 0.5 0 0.5 1")
})

test("edit: bad desktops and unknown edits", () => {
  assert.match(D.edit(doc({}), desk(0), "layout", "tiled").error, /1 to 10/)
  assert.match(D.edit(doc({}), { identity: 'a"b', slot: 1 }, "layout", "tiled").error, /monitor/)
  assert.match(D.edit(doc({}), desk(2), "app", { pos: 1, id: "x", class: "x" }).error, /no plan yet/)
  assert.match(D.edit(doc({ a: plan("tiled", []) }), desk(2), "zap", 1).error, /unknown edit/)
})

test("edit layout: same layout is no change; fewer zones drop the rest in order; rects recomputed", () => {
  const d = doc({ a: plan("columns:3", [win("c", 3), win("a", 1), win("b", 2)]) })
  assert.equal(D.edit(d, desk(2), "layout", "columns:3").changed, false)
  const r = D.edit(d, desk(2), "layout", "rows:2")
  assert.deepEqual(r.dropped, ["c"])
  assert.deepEqual(r.doc.scenes.a.windows.map((w) => [w.class, w.zone, w.rect, w.floating]), [["a", 1, [0, 0, 1, 0.5], true], ["b", 2, [0, 0.5, 1, 0.5], true]])
  assert.deepEqual(d.scenes.a.windows.length, 3) // the input doc is not changed
  assert.deepEqual(roundTrip(r.doc).errors, [])
})

test("edit layout: full keeps one window, tiled has whole rects, free drops zones and keeps rects", () => {
  const d = doc({ a: plan("columns:2", [win("a", 1, { rect: [0, 0, 0.5, 1] }), win("b", 2, { rect: [0.5, 0, 0.5, 1] })]) })
  const full = D.edit(d, desk(2), "layout", "full")
  assert.deepEqual(full.dropped, ["b"])
  assert.deepEqual(full.doc.scenes.a.windows.map((w) => [w.zone, w.rect, w.floating]), [[1, [0, 0, 1, 1], false]])
  const tiled = D.edit(d, desk(2), "layout", "scrolling")
  assert.deepEqual(tiled.doc.scenes.a.windows.map((w) => [w.zone, w.order, w.rect, w.floating]), [[1, 1, [0, 0, 1, 1], false], [2, 2, [0, 0, 1, 1], false]])
  const free = D.edit(d, desk(2), "layout", "free")
  assert.deepEqual(free.doc.scenes.a.windows.map((w) => [w.zone, w.rect, w.floating]), [[undefined, [0, 0, 0.5, 1], true], [undefined, [0.5, 0, 0.5, 1], true]])
  for (const r of [full, tiled, free]) assert.deepEqual(roundTrip(r.doc).errors, [])
  const back = D.edit(free.doc, desk(2), "layout", "grid:2x2")
  assert.deepEqual(back.doc.scenes.a.windows.map((w) => [w.class, w.zone]), [["a", 1], ["b", 2]])
})

test("edit app: put, replace (resets profile and folder), refuse bad input; free appends only at the end", () => {
  const d = doc({ a: plan("columns:2", [win("old", 1, { context: "Default", folder: "~/x", edited: "context" })]) })
  const put = D.edit(d, desk(2), "app", { pos: 2, id: "org.example.Editor", class: "org.example.Editor" })
  assert.deepEqual(put.doc.scenes.a.windows[1], { app: "org.example.Editor", class: "org.example.Editor", context: "", rect: [0.5, 0, 0.5, 1],
    launch: "", folder: "", edited: "", order: 2, zone: 2, floating: true })
  const rep = D.edit(d, desk(2), "app", { pos: 1, id: "new", class: "New" })
  assert.deepEqual(rep.doc.scenes.a.windows.map((w) => [w.class, w.context, w.folder]), [["New", "", ""]])
  assert.match(D.edit(d, desk(2), "app", { pos: 3, id: "x", class: "x" }).error, /has 2 zones/)
  assert.match(D.edit(d, desk(2), "app", { pos: 0, id: "x", class: "x" }).error, /bad position/)
  assert.match(D.edit(d, desk(2), "app", { pos: 1, id: "x", class: "" }).error, /cannot be saved/)
  assert.match(D.edit(d, desk(2), "app", null).error, /bad position/)
  const f = doc({ a: plan("free", [win("a", undefined)].map((w) => { delete w.zone; return w })) })
  assert.match(D.edit(f, desk(2), "app", { pos: 5, id: "x", class: "x" }).error, /bad position/)
  const fa = D.edit(f, desk(2), "app", { pos: 2, id: "x", class: "x" })
  assert.deepEqual(fa.doc.scenes.a.windows.map((w) => [w.class, w.zone, w.rect]), [["a", undefined, [0, 0, 1, 1]], ["x", undefined, [0, 0, 1, 1]]])
  assert.deepEqual(roundTrip(fa.doc).errors, [])
  const tiledAdd = D.edit(doc({ a: plan("tiled", [win("a", 1, { floating: false })]) }), desk(2), "app", { pos: 2, id: "b", class: "b" })
  assert.deepEqual(tiledAdd.doc.scenes.a.windows.map((w) => [w.class, w.zone, w.rect, w.floating]), [["a", 1, [0, 0, 1, 1], false], ["b", 2, [0, 0, 1, 1], false]])
})

test("edit clear: zones leave a gap, tiled closes up, free renumbers, a missing position is no change", () => {
  const z = D.edit(doc({ a: plan("columns:3", [win("a", 1), win("b", 2), win("c", 3)]) }), desk(2), "clear", 2)
  assert.deepEqual(z.doc.scenes.a.windows.map((w) => [w.class, w.zone]), [["a", 1], ["c", 3]])
  const t = D.edit(doc({ a: plan("tiled", [win("a", 1), win("b", 2), win("c", 3)]) }), desk(2), "clear", 1)
  assert.deepEqual(t.doc.scenes.a.windows.map((w) => [w.class, w.zone, w.order]), [["b", 1, 1], ["c", 2, 2]])
  const fw = [win("a"), win("b")].map((w) => { delete w.zone; return w })
  const f = D.edit(doc({ a: plan("free", fw) }), desk(2), "clear", 1)
  assert.deepEqual(f.doc.scenes.a.windows.map((w) => [w.class, w.order]), [["b", 1]])
  assert.equal(D.edit(doc({ a: plan("tiled", []) }), desk(2), "clear", 4).changed, false)
  for (const r of [z, t, f]) assert.deepEqual(roundTrip(r.doc).errors, [])
})

test("edit login: on and off, no change, and a non-boolean is refused", () => {
  const d = doc({ a: plan("tiled", []) })
  assert.equal(D.edit(d, desk(2), "login", true).doc.scenes.a.open_at_login, true)
  assert.equal(D.edit(d, desk(2), "login", false).changed, false)
  assert.match(D.edit(d, desk(2), "login", "yes").error, /on or off/)
})

test("edit: an edit that leaves a bad plan is refused, the doc is untouched", () => {
  // a hand-edited plan with a zone out of range: clearing another zone keeps it bad, so nothing is returned to write
  const d = doc({ a: plan("columns:2", [win("a", 1), win("b", 5)]) })
  assert.match(D.edit(d, desk(2), "clear", 1).error, /zone 5 of b/)
})

test("layoutSavedText: the floating switch (D19) and what was taken out", () => {
  assert.equal(D.layoutSavedText("columns:2", "tiled", []), "Saved. Open all switches this desktop to Floating")
  assert.equal(D.layoutSavedText("tiled", "tiled", []), "Saved")
  assert.equal(D.layoutSavedText("full", "floating", ["b"]), "Saved. Taken out (no room): b")
})

test("seenClasses: open windows confirm a class through their desktop entry; live wins over a captured scene", () => {
  const entries = [{ id: "org.example.Notes.desktop", startupWMClass: "", exec: "notes-app" }, { id: "other", startupWMClass: "", exec: "" }]
  const cap = { cap: { windows: [win("x", undefined, { app: "org.example.Notes", class: "OldNotes" })] } }
  assert.deepEqual(D.seenClasses(cap, ["notes-app", "unknown.Class", "", null], entries), { "org.example.Notes": "notes-app" })
  assert.deepEqual(D.seenClasses(cap, undefined, undefined), { "org.example.Notes": "OldNotes" })
})

test("a guessed class: noted, then confirmed once the app is open, then a re-pick stores the real class", () => {
  const apps = [{ value: "org.example.Notes", label: "Notes", icon: "", startupWMClass: "" }]
  const entries = [{ id: "org.example.Notes", startupWMClass: "", exec: "notes-app" }]
  // picked while the app was never seen: the entry id is stored as a guess
  const guess = D.classOf("org.example.Notes", apps, D.seenClasses({}, [], entries))
  assert.deepEqual(guess, { class: "org.example.Notes", confirmed: false })
  const d = D.edit(doc({}), desk(1), "layout", "columns:2").doc
  const picked = D.edit(d, desk(1), "app", { pos: 1, id: "org.example.Notes", class: guess.class }).doc
  let row = D.cards(live, picked, { apps, entries }).groups[0].cards[0].rows[0]
  assert.equal(row.notes[0], "Class is a guess (org.example.Notes). Open the app once, then pick it again here.")
  assert.equal(row.want, "org.example.Notes")
  // the app is open now: the page sees its real class and the row asks for a re-pick (want differs from the stored class)
  const open = Object.assign({}, live, { classes: ["notes-app"] })
  row = D.cards(open, picked, { apps, entries }).groups[0].cards[0].rows[0]
  assert.match(row.notes[0], /real class is notes-app now: pick it again/)
  assert.equal(row.want, "notes-app")
  const now = D.classOf("org.example.Notes", apps, D.seenClasses(picked.scenes, open.classes, entries))
  assert.deepEqual(now, { class: "notes-app", confirmed: true })
  const fixed = D.edit(picked, desk(1), "app", { pos: 1, id: "org.example.Notes", class: now.class }).doc
  row = D.cards(open, fixed, { apps, entries }).groups[0].cards[0].rows[0]
  assert.deepEqual([row.cls, row.want], ["notes-app", "notes-app"])
  assert.ok(!row.notes.some((n) => /guess/.test(n)))
})

test("positions: free windows at the default rect are drawn stepped, others as saved", () => {
  const fw = [win("a"), win("b", undefined, { rect: [0.5, 0, 0.5, 1] }), win("c"), win("d", undefined, { rect: undefined })].map((w) => { delete w.zone; return w })
  assert.deepEqual(D.positions({ layout: "free", windows: fw }).map((r) => r.rect), [[0, 0, 0.6, 0.6], [0.5, 0, 0.5, 1], [0.08, 0.08, 0.6, 0.6], [0.16, 0.16, 0.6, 0.6], null])
})

test("edit on a not connected focused-monitor plan (identity empty, focused)", () => {
  const d = doc({ f: plan("tiled", [], { home_monitor: "", home_slot: 4 }) })
  const r = D.edit(d, { identity: "", slot: 4, focused: true }, "app", { pos: 1, id: "x", class: "x" })
  assert.deepEqual([r.name, r.doc.scenes.f.windows.length, r.doc.scenes.f.home_monitor], ["f", 1, ""])
  assert.deepEqual(roundTrip(r.doc).errors, [])
})

test("newSceneName: a long monitor name is cut and a taken name still gets a suffix within 40", () => {
  const id = "A Very Long Monitor Description From Some Maker"
  const first = D.newSceneName(id, 10, {})
  const second = D.newSceneName(id, 10, { [first]: {} })
  assert.equal(second, first + "-2")
  assert.ok(second.length <= 40 && /^[a-z0-9_-]+$/.test(second), second)
  assert.ok(first.endsWith("-10"))
})

test("pruneDrafts: a saved draft is dropped, a refused one kept, nothing dropped is null", () => {
  const groups = [{ cards: [{ key: "m\n1", layout: "0 0 1 1" }, { key: "m\n2", layout: "tiled" }] }]
  assert.deepEqual(D.pruneDrafts({ "m\n1": " 0 0 1 1 ", "m\n2": "0 0 2 1" }, groups), { "m\n2": "0 0 2 1" })
  assert.equal(D.pruneDrafts({ "m\n2": "0 0 2 1" }, groups), null)
  assert.equal(D.pruneDrafts(null, null), null)
})

test("positions: a bad layout has no rows, full without an app, tiled and free stop offering a row at 10", () => {
  assert.deepEqual(D.positions({ layout: "nonsense", windows: [] }), [])
  assert.deepEqual(D.positions({ layout: "full", windows: [] }).map((r) => [r.pos, r.index, r.win]), [[1, -1, null]])
  const ten = Array.from({ length: 10 }, (_, i) => win("a" + i, i + 1))
  assert.equal(D.positions({ layout: "tiled", windows: ten }).length, 10)
  assert.equal(D.positions({ layout: "tiled", windows: ten.slice(0, 9) }).length, 10)
  assert.equal(D.positions({ layout: "free", windows: ten }).length, 10)
  assert.equal(D.positions({ layout: "free", windows: ten.slice(0, 9) }).length, 10)
})

test("edit layout: no free scene name for a new plan is an error", () => {
  const taken = {}
  for (let n = 0; n < 99; n++) taken[D.newSceneName(MON, 3, taken)] = { windows: [] }
  assert.match(D.edit(doc(taken), desk(3), "layout", "tiled").error, /no free scene name/)
})

test("cards: a plan for the focused monitor with no monitor focused gets the not connected group", () => {
  const m = D.cards({ monitors: [{ identity: MON, name: "DP-1", focused: false, slots: [] }] }, doc({ f: plan("tiled", [], { home_monitor: "", home_slot: 1 }) }), {})
  assert.equal(m.groups[1].name, "Focused monitor (not connected)")
  assert.equal(m.groups[1].cards[0].focused, true)
})

test("omagnet layouts (D31): read, recognized by their zones, offered by name", () => {
  const om = D.omagnetLayouts({ loaded: true, layouts: [
    { name: "coding", zones: "0 0 0.7 1; 0.7 0 0.3 1" },
    { name: "bad name!", zones: "0 0 1 1" },
    { name: "broken", zones: "0 0 2 1" }] })
  assert.equal(om.loaded, true)
  assert.deepEqual(om.layouts.map((l) => l.name), ["coding"])
  assert.equal(D.layoutLabel("0 0 0.70 1; 0.7 0 0.3 1", om), "Zones: omagnet coding", "same zones, other spelling")
  assert.equal(D.layoutChoice("0 0 0.7 1; 0.7 0 0.3 1", om), om.layouts[0].zones)
  assert.equal(D.layoutChoice("0 0 0.5 1; 0.5 0 0.5 1", om), "custom", "other zones stay custom")
  assert.equal(D.layoutLabel("columns:2", om), "Zones: 2 columns", "built-ins keep their own names")
  assert.equal(D.layoutLabel("0 0 0.7 1; 0.7 0 0.3 1"), "Zones: custom (2)", "without omagnet: custom")
  assert.deepEqual(D.omagnetLayouts(undefined), { loaded: false, layouts: [] })
})

// D32, D33: same-name apps get a hint; an Exec's --app-id is the class; a shared class is counted (made-up apps)
test("app picker: same names get a hint, exec class, shared class", () => {
  const apps = D.appChoices([
    { id: "Pad.desktop", name: "Pad", execString: "xdg-terminal-exec --app-id=TUI.tile -e pad", icon: "t" },
    { id: "pad-app.desktop", name: "Pad", execString: "/opt/pad/pad-app", startupClass: "pad-app", icon: "p" },
    { id: "Other.desktop", name: "Other", execString: "xdg-terminal-exec --app-id TUI.tile -e other" },
    { id: "Odd.desktop", name: "Odd", execString: "kitty -e tool --class=Inner" },
    { id: "hidden.desktop", name: "Pad", noDisplay: true },
    { id: "a.one.desktop", name: "Notes", runInTerminal: true }, { id: "a.two.desktop", name: "notes", runInTerminal: true },
    { id: "a.three.desktop", name: "NOTES" }
  ])
  const by = (id) => apps.find((a) => a.value === id)
  assert.equal(by("Pad").label, "Pad (terminal)")
  assert.equal(by("pad-app").label, "Pad (pad-app)")
  assert.equal(by("Other").label, "Other", "a unique name gets no hint")
  assert.equal(by("hidden"), undefined, "hidden entries are not listed")
  assert.equal(by("Pad").startupWMClass, "TUI.tile", "--app-id=X is the class")
  assert.equal(by("Other").startupWMClass, "TUI.tile", "--app-id X too")
  assert.equal(by("Odd").startupWMClass, "", "a flag after -e belongs to the program")
  assert.equal(by("Pad").shared, 1, "one other app has TUI.tile")
  assert.equal(by("pad-app").shared, 0)
  assert.equal(by("a.one").label, "Notes (a.one)", "two terminal hints alike: every one shows its id")
  assert.equal(by("a.three").label, "NOTES (a.three)", "names compare without case")
})

test("a zone row warns when its app shares a window class", () => {
  const apps = D.appChoices([{ id: "Pad.desktop", name: "Pad", execString: "xdg-terminal-exec --app-id=TUI.tile -e pad" },
    { id: "Other.desktop", name: "Other", execString: "xdg-terminal-exec --app-id=TUI.tile -e other" }])
  const d = doc({ p: plan("columns:2", [win("TUI.tile", 1, { app: "Pad" })]) })
  const m = D.cards(live, d, { apps })
  const row = m.groups[0].cards[1].rows[0]
  assert.equal(row.label, "Pad")
  assert.ok(row.notes.some((n) => n.startsWith("1 other app opens with the same window class (TUI.tile)")))
})

// D34, D35: the picker follows the desktop's mode, omagnet's layout for a floating desktop first
test("layout picker order follows the mode", () => {
  const vals = (o) => o.map((x) => x.value)
  const tiled = D.layoutOptions("tiled", null, null)
  assert.deepEqual(vals(tiled).slice(0, 2), ["", "tiled"])
  assert.equal(tiled[1].label, "Tiled (now)")
  assert.equal(tiled[tiled.length - 1].value, "custom")
  assert.equal(D.layoutOptions("scrolling", null, null)[1].label, "Scrolling (now)")
  const none = D.layoutOptions("", null, null)
  assert.deepEqual(vals(none).slice(0, 3), ["", "tiled", "scrolling"], "unknown mode: usual order")
  assert.ok(none.every((o) => !o.label.includes("(now)")))
  const om = D.omagnetLayouts({ loaded: true, layouts: [{ name: "coding", zones: "0 0 0.7 1; 0.7 0 0.3 1" }] })
  const fl = D.layoutOptions("floating", om, { name: "coding", zones: "0.0000 0.0000 0.7000 1.0000; 0.7000 0.0000 0.3000 1.0000" })
  assert.equal(fl[1].label, "coding (omagnet, this desktop)")
  assert.equal(fl[1].value, om.layouts[0].zones, "same value as the named omagnet layout, so a saved plan shows it")
  assert.equal(fl.filter((o) => o.value === fl[1].value).length, 1, "listed once")
  assert.equal(fl[2].value, "free", "then the floating layouts")
  const two = D.layoutOptions("floating", om, { name: "columns:2", zones: "0 0 0.5 1; 0.5 0 0.5 1" })
  assert.equal(two[1].value, "columns:2")
  assert.equal(two[1].label, "2 columns (omagnet, this desktop)")
  assert.equal(D.layoutOptions("floating", om, { name: "bad name!", zones: "0 0 1 1" })[1].value, "free", "a bad name is ignored")
  assert.equal(D.layoutOptions("tiled", om, { name: "coding", zones: "0 0 1 1" })[1].value, "tiled", "omagnet only on floating")
})

test("cards carry the picker options with omagnet's desktop layout", () => {
  const l2 = { ...live, monitors: [{ ...live.monitors[0], slots: [{ slot: 1, workspace: 1 }, { slot: 2, workspace: 2, omagnet: { name: "columns:2", zones: "0 0 0.5 1; 0.5 0 0.5 1" } }] }] }
  const m = D.cards(l2, doc({}), {})
  assert.equal(m.groups[0].cards[0].options[1].value, "tiled", "desktop 1 is tiled")
  assert.equal(m.groups[0].cards[1].options[1].label, "2 columns (omagnet, this desktop)", "desktop 2 floating with omagnet")
})
