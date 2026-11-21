import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const load = (f) => readFileSync(new URL("../js/" + f, import.meta.url), "utf8").replace(".pragma library", "")
const { pending } = new Function(load("MovesFeed.js") + "; return { pending }")()

const ev = (at, cls) => ({ at, class: cls || "org.example.Chat", context: "", floating: true, from_scene: "work", order: 1,
  rect: [0, 0, 1, 1], to_scene: "play" })

test("first read: every event, oldest first, and the newest at", () => {
  const r = pending(JSON.stringify([ev(300), ev(100), ev(200)]), -1)
  assert.deepEqual(r.events.map((e) => e.at), [100, 200, 300])
  assert.equal(r.maxAt, 300)
})

test("events at or before the last handled one are skipped", () => {
  const r = pending(JSON.stringify([ev(100), ev(200), ev(300)]), 200)
  assert.deepEqual(r.events.map((e) => e.at), [300])
  assert.equal(r.maxAt, 300)
  assert.deepEqual(pending(JSON.stringify([ev(100), ev(200)]), 200), { events: [], maxAt: 200 })
})

test("a file older than the last handled event means Hyprland restarted: all events count again", () => {
  const r = pending(JSON.stringify([ev(5), ev(9)]), 5000)
  assert.deepEqual(r.events.map((e) => e.at), [5, 9])
  assert.equal(r.maxAt, 9)
})

test("bad text, no array or no valid event changes nothing", () => {
  for (const t of ["", "not json", "{}", "null", JSON.stringify([{ class: "x" }, null, { at: "1" }])])
    assert.deepEqual(pending(t, 42), { events: [], maxAt: 42 })
  const r = pending(JSON.stringify([null, { at: Infinity }, ev(7)]), -1)
  assert.deepEqual(r.events.map((e) => e.at), [7])
})

test("the mark taken at load skips every event already in the file", () => {
  const text = JSON.stringify([ev(100), ev(200)])
  const mark = pending(text, -1).maxAt
  assert.deepEqual(pending(text, mark).events, [])
  assert.deepEqual(pending(JSON.stringify([ev(100), ev(200), ev(250)]), mark).events.map((e) => e.at), [250])
  assert.equal(pending("", -1).maxAt, -1) // no file: nothing to skip
})
