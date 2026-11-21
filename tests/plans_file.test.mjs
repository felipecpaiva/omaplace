// js/PlansFile.js: the derived plans.lua (design 14.7). Made-up data only.
import test from "node:test"
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { load } from "./js_load.mjs"

const F = load("PlansFile.js")

const win = (cls, zone, extra) => ({ app: cls, class: cls, context: "", rect: [0, 0, 1, 1], order: 1, floating: true,
  launch: "", folder: "", edited: "", zone, ...extra })
const plan = (layout, windows, extra) => ({ plan: true, layout, existing: "move", home_monitor: "Example Corp EX27", home_slot: 2,
  key: "", saved_on: "", windows, ...extra })
const doc = (scenes) => ({ schema: 1, scenes, warnings: [], errors: [], readOnly: false })

test("each plan scene becomes an entry with its desktop, layout, mode and windows in their zones", () => {
  const e = F.entries(doc({
    "desk-2": plan("columns:2", [win("org.example.Editor", 1), win("chromium", 2, { context: "Profile 1" })], { open_at_login: true }),
    "desk-3": plan("full", [win("org.example.Mail", 1)], { home_slot: 3 }),
    captured: { existing: "move", home_monitor: "", home_slot: 0, windows: [win("org.example.Other", undefined)] }
  }))
  assert.deepEqual(e.skipped, [])
  assert.deepEqual(e.plans, [
    { scene: "desk-2", home_monitor: "Example Corp EX27", home_slot: 2, layout: "columns:2", mode: "floating", open_at_login: true,
      windows: [
        { class: "org.example.Editor", context: "", rect: [0, 0, 0.5, 1], floating: true, snap: true },
        { class: "chromium", context: "Profile 1", rect: [0.5, 0, 0.5, 1], floating: true, snap: true }
      ] },
    { scene: "desk-3", home_monitor: "Example Corp EX27", home_slot: 3, layout: "full", mode: "", open_at_login: false,
      windows: [{ class: "org.example.Mail", context: "", rect: [0, 0, 1, 1], floating: false, snap: true, fullscreen: 1 }] }
  ])
})

test("the same class and context in two plans is not snapped; another context or one plan twice is", () => {
  const e = F.entries(doc({
    a: plan("tiled", [win("org.example.Editor", 1), win("chromium", 2, { context: "Default" }), win("org.example.Term", 3), win("org.example.Term", 4)]),
    b: plan("columns:3", [win("org.example.Editor", 1), win("chromium", 2, { context: "Profile 1" })])
  }))
  const snap = (p) => e.plans.find((x) => x.scene === p).windows.map((w) => [w.class, w.context, w.snap])
  assert.deepEqual(snap("a"), [["org.example.Editor", "", false], ["chromium", "Default", true], ["org.example.Term", "", true], ["org.example.Term", "", true]])
  assert.deepEqual(snap("b"), [["org.example.Editor", "", false], ["chromium", "Profile 1", true]])
})

test("a bad plan is skipped with its reason and does not count for the ambiguity rule", () => {
  const e = F.entries(doc({
    good: plan("tiled", [win("org.example.Editor", 1)]),
    bad: plan("columns:2", [win("org.example.Editor", 9)]),
    read: plan("tiled", [], { planError: "layout: missing" })
  }))
  assert.deepEqual(e.plans.map((p) => [p.scene, p.windows[0].snap]), [["good", true]])
  assert.deepEqual(e.skipped.map((s) => s.scene), ["bad", "read"])
  assert.match(e.skipped[0].reason, /zone 9/)
  assert.match(e.skipped[1].reason, /layout: missing/)
})

test("build writes return { plans = ... } that Lua loads in an empty environment", () => {
  const r = F.build(doc({ "desk-2": plan("grid:2x2", [win("org.example.Editor", 4)], { home_monitor: 'Odd "name" \\ here' }) }))
  assert.equal(r.error, undefined)
  assert.match(r.text, /^return \{plans = \{/)
  const out = execFileSync("lua", ["-e", `
    local t = assert(load(io.read("a"), "plans", "t", {}))()
    local p = t.plans[1]; local w = p.windows[1]
    io.write(p.scene, "|", p.home_monitor, "|", p.mode, "|", tostring(p.open_at_login), "|", w.rect[1], " ", w.rect[4], "|", tostring(w.snap))`],
  { input: r.text, encoding: "utf8" })
  assert.equal(out, 'desk-2|Odd "name" \\ here|floating|false|0.5 0.5|true')
})

test("no plans is an empty list, and a file over 1 MB is refused, never cut", () => {
  assert.equal(F.build(doc({})).text, "return {plans = {}}\n")
  const many = {}
  for (let i = 0; i < 400; i++) many["p" + i] = plan("tiled", Array.from({ length: 60 }, (_, j) => win("org.example.App" + j + "x".repeat(20), j + 1)))
  const r = F.build(doc(many))
  assert.equal(r.text, undefined)
  assert.match(r.error, /over 1 MB/)
})

test("byteLength counts UTF-8 bytes, as Lua does", () => {
  assert.equal(F.byteLength("abc"), 3)
  assert.equal(F.byteLength("é"), 2)
  assert.equal(F.byteLength("€"), 3)
  assert.equal(F.byteLength("😀"), 4)
})
