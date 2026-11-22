// js/AppSeam.js: the settings app's requests (D37). Made-up data only.
import test from "node:test"
import assert from "node:assert/strict"
import { load } from "./js_load.mjs"

const S = load("AppSeam.js")
const req = (op, args, contract = 1) => JSON.stringify({ contract, op, args })

test("requests are checked before any op runs", () => {
  assert.deepEqual(S.parse(req("open", ["work"])), { op: "open", args: ["work"] })
  assert.equal(S.parse(req("open", ["work"], 2)).error, "contract")
  assert.equal(S.parse(req("eval", ["x"])).error, "unknown_op")
  assert.equal(S.parse(req("toString", [])).error, "unknown_op", "no inherited names")
  assert.equal(S.parse(req("open", [])).error, "bad_args")
  assert.equal(S.parse(req("open", [3])).error, "bad_args")
  assert.equal(S.parse(req("setWindow", ["s", 1.5, "c", "f", "v"])).error, "bad_args", "an index is an integer")
  assert.equal(S.parse(req("setSetting", ["k", { x: 1 }])).error, "bad_args", "values are scalars")
  assert.equal(S.parse(req("editPlan", ["Mon", 2, false, "layout", "columns:2", "floating"])).op, "editPlan")
  assert.equal(S.parse(req("editPlan", ["Mon", 2, false, "app", { pos: 1, id: "org.example.Editor" }, ""])).op, "editPlan", "a plan edit takes { pos, id }")
  assert.equal(S.parse(req("editPlan", ["Mon", 2, false, "app", { pos: { deep: 1 } }, ""])).error, "bad_args", "flat objects only")
  assert.equal(S.parse(req("setSetting", ["k", { pos: 1 }])).error, "bad_args", "objects only where a plan edit takes them")
  assert.equal(S.parse("not json").error, "bad_request")
  assert.equal(S.parse("null").error, "bad_request")
})

test("ids, rule names and replies", () => {
  assert.equal(S.validId("a1-2"), true)
  assert.equal(S.validId("../x"), false)
  assert.equal(S.validId(""), false)
  assert.equal(S.ruleName("org.example.Editor", {}), "editor")
  assert.equal(S.ruleName("org.example.Editor", { editor: true, "editor-2": true }), "editor-3")
  assert.equal(S.ruleName("!!!", {}), "app")
  const r = JSON.parse(S.reply("a1", '{"ok":true}', { seq: 1 }))
  assert.equal(r.contract, 1)
  assert.equal(r.answer.ok, true)
  assert.equal(JSON.parse(S.reply("a1", "", null)).answer.ok, false, "no answer is a failure, never ok")
})
