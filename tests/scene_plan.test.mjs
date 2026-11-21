// SceneStore.js: plan scenes (design 14.2): plan, layout, open_at_login and window zones. Made-up data only.
import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./js_load.mjs"

const S = load("SceneStore.js")

const CAPTURED = `schema = 1

[scene.work]
existing = "move"
home_monitor = ""
home_slot = 2
key = ""
saved_on = "Example Corp EX27"

[scene.work.window.1]
app = "org.example.Mail"
class = "org.example.Mail"
context = ""
rect = "0.5 0 0.5 0.5"
order = 1
floating = true
launch = ""
folder = ""
edited = ""
`

const planText = (scene, windows) => `schema = 1

[scene.desk-2]
plan = true
${scene}
existing = "move"
home_monitor = "Example Corp EX27"
home_slot = 2
key = ""
saved_on = ""
${windows.map((w, i) => `
[scene.desk-2.window.${i + 1}]
app = "${w[0]}"
class = "${w[0]}"
context = ""
rect = "0 0 0.5 1"
order = ${i + 1}
floating = true
launch = ""
folder = ""
edited = ""${w[1] === undefined ? "" : "\nzone = " + w[1]}`).join("\n")}
`
const PLAN = planText(`layout = "columns:2"\nopen_at_login = false`, [["org.example.Editor", 1], ["org.example.Mail", 2]])

test("a plan scene reads plan, layout, open_at_login and zones, and round trips byte for byte", () => {
  const d = S.parse(PLAN)
  assert.deepEqual(d.errors, [])
  assert.deepEqual(d.warnings, [])
  const s = d.scenes["desk-2"]
  assert.equal(s.plan, true)
  assert.equal(s.layout, "columns:2")
  assert.equal(s.open_at_login, false)
  assert.equal(s.extra, undefined)
  assert.deepEqual(s.windows.map((w) => [w.class, w.zone, w.extra]), [["org.example.Editor", 1, undefined], ["org.example.Mail", 2, undefined]])
  assert.equal(S.serialize(d), PLAN)
})

test("a captured scene gets no plan keys on write and round trips byte for byte", () => {
  const d = S.parse(CAPTURED)
  assert.deepEqual(d.errors, [])
  assert.equal(S.serialize(d), CAPTURED)
})

test("every layout kind is accepted: tiled, scrolling, full, free, names, zones text", () => {
  for (const layout of ["tiled", "scrolling", "grid:2x2", "priority", "Rows:3", "0 0 0.25 1; 0.25 0 0.75 1"]) {
    assert.deepEqual(S.parse(planText(`layout = "${layout}"`, [["org.example.Editor", 2]])).errors, [], layout)
  }
  assert.deepEqual(S.parse(planText(`layout = "full"`, [["org.example.Editor", 1]])).errors, [])
  assert.deepEqual(S.parse(planText(`layout = "free"`, [["org.example.Editor"]])).errors, [], "free has no zones")
  assert.deepEqual(S.parse(planText(`layout = "tiled"`, [["org.example.Editor", 64]])).errors, [])
  assert.equal(S.parse(planText(`layout = "tiled"`, [])).scenes["desk-2"].open_at_login, undefined, "missing means off (D20)")
})

test("bad plan values are errors with a reason, never a default, and the scene keeps what was read", () => {
  const ed = (zone) => [["org.example.Editor", zone]]
  const cases = [
    [planText(`layout = "columns:13"`, ed(1)), /layout: "columns:13" is not tiled, scrolling, full, free, and not a zone layout name/],
    [planText(`layout = "tiles"`, ed(1)), /"tiles" is not/],
    [planText(`open_at_login = false`, ed(1)), /layout: missing/],
    [planText(`layout = 2`, ed(1)), /layout: missing/],
    [planText(`layout = "tiled"\nopen_at_login = "no"`, ed(1)), /open_at_login: expected true or false/],
    [planText(`layout = "columns:2"`, ed(3)), /zone 3 of org.example.Editor: layout columns:2 has 2 zones/],
    [planText(`layout = "columns:2"`, ed(0)), /expected a whole number from 1/],
    [planText(`layout = "columns:2"`, ed(1.5)), /expected a whole number from 1/],
    [planText(`layout = "columns:2"`, ed(`"1"`)), /expected a whole number from 1/],
    [planText(`layout = "columns:2"`, ed(undefined)), /zone of org.example.Editor/],
    [planText(`layout = "columns:2"`, [["org.example.Editor", 1], ["org.example.Mail", 1]]), /zone 1 is used twice/],
    [planText(`layout = "full"`, [["org.example.Editor", 1], ["org.example.Mail", 2]]), /layout full holds one window, this plan has 2/],
    [planText(`layout = "full"`, ed(2)), /has 1 zone$/],
    [planText(`layout = "columns:2`, ed(1)), /scene.desk-2.layout: unterminated string/],
    [planText(`layout = "tiled"`, ed("x")), /window.1.zone: not a string, number or boolean/],
    [planText(`layout = "tiled"`, []).replace("plan = true", 'plan = "yes"'), /plan: expected true or false/],
    [planText(`layout = "tiled"`, []).replace("plan = true", "plan = false"), /layout: only a plan scene/],
    [planText(`open_at_login = true`, []).replace("plan = true\n", ""), /open_at_login: only a plan scene/],
    [CAPTURED.replace('class = "org.example.Mail"', 'class = "org.example.Mail"\nzone = 1'), /zone: only a plan scene/],
    [planText(`layout = "tiled"`, ed(1)).replace("home_slot = 2", "home_slot = 0"), /home_slot: a plan is bound to a desktop, expected 1..10/],
    [planText(`layout = "tiled"`, ed(1)).replace("home_slot = 2\n", ""), /home_slot: a plan is bound to a desktop/],
    [planText(`layout = "tiled"`, ed(1)).replace("home_slot = 2", "home_slot = 11"), /home_slot: a plan is bound to a desktop/],
    [planText(`layout = "free"`, ed(1)), /zone: free places by rect, no zones/],
    [planText(`layout = "tiled"`, [["org.example.Editor", 1], ["", 2]]), /window.2.class: empty, a plan window needs a class/, "parse report only"]
  ]
  for (const [text, why, reportOnly] of cases) {
    const d = S.parse(text)
    const name = Object.keys(d.scenes)[0]
    assert.equal(d.errors.length, 1, String(why))
    assert.equal(d.errors[0].code, "bad_plan")
    assert.equal(d.errors[0].name, name)
    assert.match(d.errors[0].reason, why)
    assert.equal(d.scenes[name].planError, d.errors[0].reason)
    // a parse report alone blocks the write through doc.errors (Service.qml), not through serialize()
    if (reportOnly) assert.doesNotThrow(() => S.serialize(d))
    else assert.throws(() => S.serialize(d), /bad_plan: scene/)
  }
  assert.equal(S.parse(planText(`layout = "tiles"`, ed(1))).scenes["desk-2"].layout, "tiles", "kept as read")
})

test("an empty class in a captured scene stays a warning, in a plan it is an error", () => {
  const cap = S.parse(CAPTURED.replace('class = "org.example.Mail"', 'class = ""'))
  assert.deepEqual(cap.errors, [])
  assert.match(cap.warnings.join("\n"), /class: empty, window skipped/)
  const plan = S.parse(planText(`layout = "tiled"`, [["", 1]]))
  assert.deepEqual(plan.warnings, [])
  assert.equal(plan.errors[0].code, "bad_plan")
})

test("a second plan on the same desktop is refused and names the first; another slot or monitor is fine", () => {
  const second = (slot, monitor) => `
[scene.desk-b]
plan = true
layout = "tiled"
home_monitor = "${monitor}"
home_slot = ${slot}

[scene.desk-b.window.1]
class = "org.example.Mail"
zone = 1
`
  const d = S.parse(PLAN + second(2, "Example Corp EX27"))
  assert.deepEqual(d.errors, [{ code: "bad_plan", name: "desk-b", reason: 'desktop 2 of "Example Corp EX27" already has plan desk-2' }])
  assert.throws(() => S.serialize(d), /bad_plan: scene desk-b: desktop 2/)
  assert.deepEqual(S.parse(PLAN + second(3, "Example Corp EX27")).errors, [])
  assert.deepEqual(S.parse(PLAN + second(2, "Example Corp EX32")).errors, [])
  const fixed = S.parse(PLAN + second(3, "Example Corp EX27"))
  fixed.scenes["desk-b"].home_slot = 2
  assert.throws(() => S.serialize(fixed), /already has plan desk-2/, "built in code is checked too")
})

test("serialize decides by planProblem only: a scene fixed in code writes even with its parse report", () => {
  const d = S.parse(PLAN.replace("zone = 2", "zone = 9"))
  assert.match(d.scenes["desk-2"].planError, /zone 9/)
  d.scenes["desk-2"].windows[1].zone = 2
  assert.equal(S.serialize(d), PLAN)
})

test("plan = false is a captured scene and keeps its line", () => {
  const text = CAPTURED.replace('existing = "move"', 'plan = false\nexisting = "move"')
  const d = S.parse(text)
  assert.deepEqual(d.errors, [])
  assert.equal(S.serialize(d), text)
})

test("serialize checks plan scenes built in code too, and a fixed scene writes", () => {
  const d = S.parse(PLAN)
  d.scenes["desk-2"].windows[1].zone = 5
  assert.throws(() => S.serialize(d), /bad_plan: scene desk-2: zone 5/)
  d.scenes["desk-2"].windows[1].zone = 2
  assert.equal(S.serialize(d), PLAN)
  const cap = S.parse(CAPTURED)
  cap.scenes.work.layout = "tiled"
  assert.throws(() => S.serialize(cap), /only a plan scene/)
})

test("a capture never merges into a plan scene", () => {
  const plan = S.parse(PLAN).scenes["desk-2"]
  assert.throws(() => S.mergeCapture(plan, { windows: [] }), /plan_scene/)
})
