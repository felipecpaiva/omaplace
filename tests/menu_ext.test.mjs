import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const load = (f) => readFileSync(new URL("../js/" + f, import.meta.url), "utf8").replace(".pragma library", "")
const M = new Function(load("MenuExt.js") + "; return { addRows, removeRows, hasRows, read }")()
const fixture = (f) => readFileSync(new URL("fixtures/menu/" + f, import.meta.url), "utf8")
const CLI = "/made/up/plugins/io.github.felipecpaiva.omaplace/bin/omaplace"
const IDS = ["omaplace", "omaplace.save", "omaplace.open", "omaplace.restore", "omaplace.rule", "omaplace.settings"]

// Omarchy's reader, copied from shell/plugins/menu/MenuModel.js (stripJsonc, then JSON.parse).
const omarchyRead = (raw) => JSON.parse(String(raw).replace(/^\s*\/\/[^\n]*(\n|$)/gm, "").replace(/,(\s*[}\]])/g, "$1") || "{}")

for (const f of ["empty-object.jsonc", "entries.jsonc", "comments.jsonc"]) {
  test("add then remove gives " + f + " back byte for byte", () => {
    const text = fixture(f)
    const added = M.addRows(text, CLI)
    assert.equal(added.ok, true)
    assert.equal(M.hasRows(added.text), true)
    const menu = omarchyRead(added.text)
    for (const id of IDS) assert.ok(menu[id], id)
    for (const id of Object.keys(omarchyRead(text))) assert.deepEqual(menu[id], omarchyRead(text)[id]) // other keys kept
    assert.ok(added.text.endsWith(text.slice(text.indexOf("{") + 1))) // everything after the brace is untouched
    const removed = M.removeRows(added.text)
    assert.equal(removed.ok, true)
    assert.equal(removed.text, text)
    assert.equal(M.hasRows(removed.text), false)
  })
}

test("the rows: a Scenes submenu and five actions on the CLI by full, quoted path", () => {
  const menu = omarchyRead(M.addRows("{\n}\n", CLI).text)
  assert.equal(menu.omaplace.label, "Scenes")
  assert.equal(menu.omaplace.action, undefined)
  assert.deepEqual(IDS.slice(1).map((id) => [menu[id].label, menu[id].action]), [
    ["Save this desktop", "'" + CLI + "' save --ask"],
    ["Open a scene", "'" + CLI + "' open --pick"],
    ["Restore last session", "'" + CLI + "' restore"],
    ["Always open here", "'" + CLI + "' rule add"],
    ["Settings", "'" + CLI + "' settings"]
  ])
})

test("an existing block is replaced, never doubled", () => {
  const text = fixture("comments.jsonc")
  const once = M.addRows(text, CLI).text
  const twice = M.addRows(once, "/made/up/other/bin/omaplace")
  assert.equal(twice.ok, true)
  assert.equal(twice.text.split("omaplace begin").length, 2)
  assert.match(twice.text, /made\/up\/other/)
  assert.equal(M.removeRows(twice.text).text, text)
})

test("an empty or missing file gets a new object", () => {
  const added = M.addRows("", CLI)
  assert.equal(added.ok, true)
  assert.ok(omarchyRead(added.text)["omaplace.save"])
  assert.equal(M.removeRows(added.text).text, "{\n}\n")
})

test("a comment-only file keeps its comments and gets an object after them", () => {
  const text = fixture("comments-only.jsonc")
  const added = M.addRows(text, CLI)
  assert.equal(added.ok, true)
  assert.ok(added.text.startsWith(text))
  assert.ok(omarchyRead(added.text)["omaplace.open"])
})

test("a one-line object stays valid both ways", () => {
  const added = M.addRows('{ "a": {"label":"A","action":"made-up"} }', CLI)
  assert.equal(added.ok, true)
  assert.equal(omarchyRead(added.text).a.label, "A")
  const removed = M.removeRows(added.text).text
  assert.equal(omarchyRead(removed).a.label, "A")
  assert.equal(M.hasRows(removed), false)
})

test("refuses what it cannot change safely", () => {
  assert.equal(M.addRows('{ "a": ', CLI).ok, false) // broken JSON
  assert.equal(M.addRows("[1, 2]", CLI).ok, false) // not an object
  assert.equal(M.addRows('{ "items": {} }', CLI).ok, false) // items wrapper
  assert.equal(M.addRows("{\n}\n", "relative/bin/omaplace").ok, false)
  assert.equal(M.addRows("{\n}\n", "/made/up/it's/omaplace").ok, false)
  const noEnd = "{\n  // omaplace begin\n  \"x\": {},\n}\n"
  assert.equal(M.removeRows(noEnd).ok, false)
  assert.equal(M.addRows(noEnd, CLI).ok, false)
})

test("removing from a file without the block changes nothing", () => {
  const text = fixture("entries.jsonc")
  assert.deepEqual(M.removeRows(text), { ok: true, text })
})
