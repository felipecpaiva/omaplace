import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const src = readFileSync(new URL("../js/SceneStore.js", import.meta.url), "utf8").replace(".pragma library", "")
const S = new Function(src + "; return { parse, serialize, migrate, mergeCapture }")()

const THREE = `schema = 1

[scene.work]
existing = "move"
home_monitor = ""
home_slot = 2
key = ""
saved_on = "Example Corp EX27 #1"

[scene.work.window.2]
app = "org.example.Mail"
class = "org.example.Mail"
rect = "0.5 0 0.5 0.5"
order = 2
floating = true

[scene.work.window.1]
app = "org.example.Editor"
class = "org.example.Editor"
rect = "0 0 0.5 1"
order = 1
floating = true

[scene.work.window.10]
app = "google-chrome-stable"
class = "google-chrome"
context = "Profile 1"
rect = "0.5 0.5 0.5 0.5"
order = 3
floating = false
launch = ""
folder = ""
edited = "rect floating"
`

test("parses a scene with three windows, sorted by their number", () => {
  const d = S.parse(THREE)
  assert.deepEqual(d.warnings, [])
  assert.deepEqual(d.errors, [])
  assert.equal(d.schema, 1)
  assert.equal(d.readOnly, false)
  const w = d.scenes.work
  assert.equal(w.home_slot, 2)
  assert.deepEqual(w.windows.map((x) => x.class), ["org.example.Editor", "org.example.Mail", "google-chrome"])
  assert.deepEqual(w.windows[0].rect, [0, 0, 0.5, 1])
  assert.equal(w.windows[2].context, "Profile 1")
  assert.equal(w.windows[2].floating, false)
  assert.equal(w.windows[2].edited, "rect floating")
})

test("serialize then parse round trips, and serialize is stable", () => {
  const d = S.parse(THREE)
  const text = S.serialize(d)
  assert.deepEqual(S.parse(text).scenes, d.scenes)
  assert.equal(S.serialize(S.parse(text)), text)
  assert.match(text, /\[scene\.work\.window\.3\]/) // renumbered 1..n
})

test("unknown keys in a scene and a window are kept", () => {
  const d = S.parse('schema = 1\n[scene.a]\nnote = "hi"\n[scene.a.window.1]\nclass = "x"\ntag = 3\n')
  assert.equal(d.scenes.a.extra.note, "hi")
  const again = S.parse(S.serialize(d))
  assert.equal(again.scenes.a.windows[0].extra.tag, 3)
})

test("bad scene names are errors and the scene is not loaded", () => {
  for (const bad of ["Work", "a b", "x".repeat(41), "", "a.b"]) {
    const d = S.parse(`schema = 1\n[scene.${bad}]\nexisting = "move"\n[scene.ok]\n`)
    assert.ok(d.errors.some((e) => e.code === "bad_name"), JSON.stringify(bad))
    assert.deepEqual(Object.keys(d.scenes), ["ok"])
  }
  assert.throws(() => S.serialize({ schema: 1, scenes: { "Bad Name": { windows: [] } } }), /bad_name/)
})

test("a string with a double quote is refused with a warning and the default is used", () => {
  const d = S.parse('schema = 1\n[scene.a]\n[scene.a.window.1]\nclass = "x"\nlaunch = "run "now""\n')
  assert.equal(d.scenes.a.windows[0].launch, "")
  assert.match(d.warnings.join("\n"), /double quote/)
  assert.throws(() => S.serialize({ schema: 1, scenes: { a: { windows: [{ class: "x", launch: 'a"b' }] } } }), /bad_value/)
})

test("bad values give defaults and warnings; windows without a class are skipped", () => {
  const d = S.parse('schema = 1\n[scene.a]\nexisting = "maybe"\nhome_slot = 99\n[scene.a.window.1]\nclass = "x"\nrect = "1 2 3"\n[scene.a.window.2]\napp = "y"\n')
  assert.equal(d.scenes.a.existing, "move")
  assert.equal(d.scenes.a.home_slot, 0)
  assert.deepEqual(d.scenes.a.windows[0].rect, [0, 0, 1, 1])
  assert.equal(d.scenes.a.windows.length, 1)
  assert.equal(d.warnings.length, 4)
})

test("a newer schema is read only with a warning, and cannot be serialized", () => {
  const d = S.parse('schema = 2\n[scene.a]\n[scene.a.window.1]\nclass = "x"\n')
  assert.equal(d.readOnly, true)
  assert.match(d.warnings.join("\n"), /newer/)
  assert.equal(d.scenes.a.windows.length, 1)
  assert.throws(() => S.serialize(d), /read_only/)
  assert.equal(S.migrate({ schema: 1, scenes: {} }).readOnly, false)
})

test("empty text is an empty schema 1 document", () => {
  const d = S.parse("")
  assert.deepEqual(d.scenes, {})
  assert.equal(S.serialize(d), "schema = 1\n")
})

const oldScene = () => S.parse(THREE).scenes.work
const cap = (extra) => ({
  saved_on: "Example Corp EX27 #1",
  windows: [
    { app: "org.example.Editor", class: "org.example.Editor", context: "", rect: [0, 0, 0.4, 1], order: 1, floating: true, launch: "", folder: "" },
    { app: "org.example.Mail", class: "org.example.Mail", context: "", rect: [0.4, 0, 0.6, 1], order: 2, floating: true, launch: "", folder: "" },
    { app: "google-chrome-stable", class: "google-chrome", context: "Profile 1", rect: [0.4, 0.5, 0.6, 0.5], order: 3, floating: true, launch: "", folder: "" }
  ].concat(extra || [])
})

test("mergeCapture replaces windows but keeps the fields named in edited", () => {
  const merged = S.mergeCapture(oldScene(), cap())
  assert.equal(merged.home_slot, 2) // scene level fields stay
  assert.deepEqual(merged.windows[0].rect, [0, 0, 0.4, 1]) // not edited: new capture wins
  const chrome = merged.windows[2]
  assert.deepEqual(chrome.rect, [0.5, 0.5, 0.5, 0.5]) // edited: kept from old
  assert.equal(chrome.floating, false) // edited: kept from old
  assert.equal(chrome.edited, "rect floating")
  assert.equal(merged.windows[0].edited, "")
})

test("mergeCapture matches by class and context, so another profile is a new slot", () => {
  const c = cap()
  c.windows[2].context = "Default"
  const merged = S.mergeCapture(oldScene(), c)
  assert.deepEqual(merged.windows[2].rect, [0.4, 0.5, 0.6, 0.5])
  assert.equal(merged.windows[2].edited, "")
})

test("mergeCapture drops windows that are gone, adds new ones, never reuses an old slot twice", () => {
  const c = cap([{ app: "x", class: "org.example.Mail", context: "", rect: [0, 0, 1, 1], order: 4, floating: true, launch: "", folder: "" }])
  c.windows.splice(0, 1)
  const merged = S.mergeCapture(oldScene(), c)
  assert.deepEqual(merged.windows.map((w) => w.class), ["org.example.Mail", "google-chrome", "org.example.Mail"])
  assert.equal(merged.windows.length, 3)
})

test("mergeCapture into no old scene, and does not change its input", () => {
  const old = oldScene()
  const before = JSON.stringify(old)
  S.mergeCapture(old, cap())
  assert.equal(JSON.stringify(old), before)
  const fresh = S.mergeCapture(undefined, cap())
  assert.equal(fresh.windows.length, 3)
  assert.equal(fresh.existing, "move")
  assert.ok(S.serialize({ schema: 1, scenes: { fresh } }).includes("[scene.fresh.window.3]"))
})

test("an edited list cannot name the match key", () => {
  const old = oldScene()
  old.windows[0].edited = "class context app"
  const merged = S.mergeCapture(old, cap())
  assert.equal(merged.windows[0].edited, "app")
})
