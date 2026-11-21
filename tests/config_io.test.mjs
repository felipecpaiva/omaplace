import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"

const src = readFileSync(new URL("../js/ConfigIO.js", import.meta.url), "utf8").replace(".pragma library", "")
const C = new Function(src + "; return { parse, setValue, setRule, removeRule }")()
const dir = new URL("./fixtures/config-js/", import.meta.url)

test("every fixture parses to its expected json", () => {
  const names = readdirSync(dir).filter((f) => f.endsWith(".toml"))
  assert.ok(names.length >= 6)
  for (const f of names) {
    const want = JSON.parse(readFileSync(new URL(f.replace(".toml", ".expected.json"), dir), "utf8"))
    assert.deepEqual(C.parse(readFileSync(new URL(f, dir), "utf8")), want, f)
  }
})

test("empty text gives all defaults and no warnings", () => {
  const r = C.parse("")
  assert.deepEqual(Object.keys(r), ["schema", "settings", "rules", "strategies", "warnings"])
  assert.equal(r.settings.expiry_seconds, 20)
  assert.equal(r.settings.tiled_order, true)
  assert.deepEqual(r.warnings, [])
})

test("a bad value becomes the default plus one warning", () => {
  const r = C.parse('expiry_seconds = 9999\nsession = "maybe"\n')
  assert.equal(r.settings.expiry_seconds, 20)
  assert.equal(r.settings.session, "on")
  assert.equal(r.warnings.length, 2)
})

test("a string with a double quote is refused with a clear warning", () => {
  const r = C.parse('ignore = "a"b"\n')
  assert.equal(r.settings.ignore, "")
  assert.match(r.warnings[0], /double quote/)
})

test("CRLF input parses", () => {
  assert.equal(C.parse("expiry_seconds = 5\r\n").settings.expiry_seconds, 5)
})

test("setValue replaces in place and keeps the comment and neighbours", () => {
  const text = '# top\nschema = 1\nexpiry_seconds = 30   # keep me\nfuture = "x"\n\n[rule.a]\napp = "x"\n'
  assert.equal(C.setValue(text, "expiry_seconds", 45), text.replace("30   #", "45   #"))
})

test("setValue adds a missing key after the last top level key, before sections", () => {
  const text = 'schema = 1\n\n[rule.a]\napp = "x"\n'
  assert.equal(C.setValue(text, "settle_ms", 500), 'schema = 1\nsettle_ms = 500\n\n[rule.a]\napp = "x"\n')
})

test("setValue on empty text and on a comment only file", () => {
  assert.equal(C.setValue("", "session", "off"), 'session = "off"\n')
  assert.equal(C.setValue("# hello\n", "session", "off"), '# hello\nsession = "off"\n')
})

test("setValue refuses a value the parser would reject, and strings with a quote", () => {
  assert.throws(() => C.setValue("", "expiry_seconds", 0), /bad_value/)
  assert.throws(() => C.setValue("", "ignore", 'a"b'), /bad_value/)
  assert.throws(() => C.setValue("", "bad key", 1), /bad_key/)
})

test("setRule updates an existing rule and keeps its comments", () => {
  const text = '[rule.editor]\n# left screen\napp = "org.example.Editor"\nslot = 3 # three\n\n[rule.mail]\napp = "m"\n'
  const out = C.setRule(text, "editor", { slot: 5, follow: true })
  assert.equal(out, '[rule.editor]\n# left screen\napp = "org.example.Editor"\nslot = 5 # three\nfollow = true\n\n[rule.mail]\napp = "m"\n')
  assert.equal(C.parse(out).rules.editor.slot, 5)
})

test("setRule appends a new rule at the end", () => {
  const out = C.setRule('schema = 1\n', "mail", { app: "org.example.Mail", slot: 2 })
  assert.equal(out, 'schema = 1\n\n[rule.mail]\napp = "org.example.Mail"\nslot = 2\n')
  assert.equal(C.setRule("", "a-b_1", { app: "x" }), '[rule.a-b_1]\napp = "x"\n')
})

test("setRule rejects bad names and values", () => {
  assert.throws(() => C.setRule("", "bad name", { app: "x" }), /bad_name/)
  assert.throws(() => C.setRule("", "a", { slot: 11 }), /bad_value/)
})

test("removeRule removes one section and the comment above it, keeps the rest", () => {
  const text = '# header\n\n[rule.a]\napp = "a"\n\n# about b\n[rule.b]\napp = "b"\n\n[rule.c]\napp = "c"\n'
  const out = C.removeRule(text, "b")
  assert.equal(out, '# header\n\n[rule.a]\napp = "a"\n\n[rule.c]\napp = "c"\n')
  assert.deepEqual(Object.keys(C.parse(out).rules), ["a", "c"])
  assert.equal(C.removeRule(text, "missing"), text)
})

test("unknown lines and sections survive writes", () => {
  const text = 'future = 1\n[theme]\naccent = "#fff"\n[rule.a]\napp = "a"\n'
  const out = C.setRule(C.setValue(text, "session", "off"), "a", { slot: 4 })
  assert.match(out, /\[theme\]\naccent = "#fff"/)
  assert.equal(C.parse(out).extra["theme.accent"], "#fff")
})

test("session_keep needs at least 2 (this login and the previous one)", () => {
  const one = C.parse("session_keep = 1\n")
  assert.equal(one.settings.session_keep, 5)
  assert.equal(one.warnings.length, 1)
  assert.equal(C.parse("session_keep = 2\n").settings.session_keep, 2)
})
