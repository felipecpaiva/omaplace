// js/ModeSwitch.js: every branch of the mode decision (design 14.4, 14.8) and the plan's workspace lookup. Made-up data.
import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./js_load.mjs"

const M = load("ModeSwitch.js")

test("Omarchy's mode words map both ways, unknown reads as empty", () => {
  assert.equal(M.fromOmarchy("dwindle\n"), "tiled")
  assert.equal(M.fromOmarchy("scrolling"), "scrolling")
  assert.equal(M.fromOmarchy("floating"), "floating")
  assert.equal(M.fromOmarchy("tiled"), "tiled")
  assert.equal(M.fromOmarchy("master"), "")
  assert.equal(M.fromOmarchy(undefined), "")
  assert.equal(M.toOmarchy("tiled"), "dwindle")
  assert.equal(M.toOmarchy("floating"), "floating")
})

test("nothing to do: a plan that leaves the mode (full), or the mode already matches", () => {
  assert.deepEqual(M.decide({ want: "", current: "dwindle", hasSet: false, userStarted: true }), { step: "none" })
  assert.deepEqual(M.decide({ want: "tiled", current: "dwindle\n", hasSet: false, userStarted: false }), { step: "none" })
  assert.deepEqual(M.decide({ want: "floating", current: "floating", hasSet: true, tries: 1 }), { step: "none" })
})

test("an unknown plan mode fails without running anything", () => {
  assert.equal(M.decide({ want: "master", current: "dwindle" }).step, "fail")
})

test("set command present or not yet known: set once, then verify", () => {
  assert.deepEqual(M.decide({ want: "floating", current: "dwindle", userStarted: false, tries: 0 }), { step: "set" })
  assert.deepEqual(M.decide({ want: "floating", current: "", hasSet: true, userStarted: true }), { step: "set" })
  const after = M.decide({ want: "floating", current: "dwindle", hasSet: true, userStarted: true, tries: 1 })
  assert.equal(after.step, "fail")
  assert.match(after.reason, /still tiled after layout-set/)
})

test("no set command at login: skip and say so", () => {
  const r = M.decide({ want: "floating", current: "scrolling", hasSet: false, userStarted: false })
  assert.equal(r.step, "skip")
  assert.match(r.reason, /mode left as scrolling/)
})

test("no set command, user started: toggle up to 2 times, verify after each", () => {
  const s = { want: "floating", hasSet: false, userStarted: true }
  assert.deepEqual(M.decide({ ...s, current: "dwindle", tries: 0 }), { step: "toggle", direction: "back" }) // tiled to floating: one press back
  assert.deepEqual(M.decide({ ...s, current: "scrolling", tries: 1 }), { step: "toggle", direction: "next" }) // a press that did not take: verify, press again
  assert.deepEqual(M.decide({ ...s, current: "floating", tries: 2 }), { step: "none" })
  const r = M.decide({ ...s, current: "dwindle", tries: 2 })
  assert.equal(r.step, "fail")
  assert.match(r.reason, /after 2 presses/)
})

test("the toggle direction reaches every mode in one press (Omarchy's next and back cycles)", () => {
  // the cycles of omarchy-hyprland-workspace-layout-toggle, in its own words
  const next = { dwindle: "scrolling", scrolling: "floating", floating: "dwindle" }
  const back = { dwindle: "floating", floating: "scrolling", scrolling: "dwindle" }
  for (const cur of ["dwindle", "scrolling", "floating"]) for (const want of ["tiled", "scrolling", "floating"]) {
    const d = M.decide({ want, current: cur, hasSet: false, userStarted: true, tries: 0 })
    if (M.fromOmarchy(cur) === want) { assert.equal(d.step, "none"); continue }
    const after = (d.direction === "next" ? next : back)[cur]
    assert.equal(M.fromOmarchy(after), want, cur + " to " + want + " by " + d.direction)
  }
})

test("no set command, mode unreadable: never press blind", () => {
  const r = M.decide({ want: "tiled", current: "", hasSet: false, userStarted: true })
  assert.equal(r.step, "fail")
  assert.match(r.reason, /cannot read/)
})

test("workspaceOf finds the slot's workspace on the plan's monitor, or the focused one", () => {
  const d = { monitors: [
    { identity: "Example Corp EX27", name: "DP-1", focused: false, slots: [{ slot: 1, workspace: 1 }, { slot: 2, workspace: 2 }] },
    { identity: "Made Up Panel", name: "eDP-1", focused: true, slots: [{ slot: 2, workspace: 12 }] }
  ] }
  assert.equal(M.workspaceOf(d, "Example Corp EX27", 2), 2)
  assert.equal(M.workspaceOf(d, "", 2), 12)
  assert.equal(M.workspaceOf(d, "Example Corp EX27", 3), 0)
  assert.equal(M.workspaceOf(d, "Gone Monitor", 1), 0)
  assert.equal(M.workspaceOf(null, "", 1), 0)
  assert.equal(M.workspaceOf({ monitors: [{ identity: "x", slots: [{ slot: 1, workspace: -5 }] }] }, "x", 1), 0)
  assert.equal(M.workspaceOf({ monitors: [{ identity: "x", slots: [{ slot: 1, workspace: "3" }] }] }, "x", 1), 0)
})
