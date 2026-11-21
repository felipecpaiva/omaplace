import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const src = readFileSync(new URL("../js/LuaLiteral.js", import.meta.url), "utf8").replace(".pragma library", "")
const { encode } = new Function(src + "; return { encode }")()

test("scalars", () => {
  assert.equal(encode("hi"), '"hi"')
  assert.equal(encode(7), "7")
  assert.equal(encode(-1.5), "-1.5")
  assert.equal(encode(true), "true")
  assert.equal(encode(false), "false")
})

test("arrays and objects, keys quoted when they are not Lua names", () => {
  assert.equal(encode([1, "a", [2]]), '{1, "a", {2}}')
  assert.equal(encode({}), "{}")
  assert.equal(encode({ run: "r1", rect: [0, 0, 0.5, 1] }), '{run = "r1", rect = {0, 0, 0.5, 1}}')
  assert.equal(encode({ "a-b": 1, "1x": 2, end: 3, ok_1: 4 }), '{["a-b"] = 1, ["1x"] = 2, ["end"] = 3, ok_1 = 4}')
})

test("quotes, backslashes, newlines and control characters are escaped", () => {
  assert.equal(encode('say "hi"'), '"say \\"hi\\""')
  assert.equal(encode("a\\b"), '"a\\\\b"')
  assert.equal(encode("line1\nline2"), '"line1\\nline2"')
  assert.equal(encode("t\tr\rz\u0000e\u001b1\u007f"), '"t\\009r\\013z\\000e\\0271\\127"')
})

test("an injection attempt stays one plain string", () => {
  const evil = '"]] os.execute("x") --'
  const out = encode(evil)
  assert.equal(out, '"\\"]] os.execute(\\"x\\") --"')
  assert.equal(encode({ launch: ["uwsm-app", "--", evil] }), '{launch = {"uwsm-app", "--", ' + out + "}}")
  assert.equal(encode("end\n\"; os.exit() --\n"), '"end\\n\\"; os.exit() --\\n"')
})

test("a key can be an injection attempt too", () => {
  assert.equal(encode({ '] = 1, x = os.exit() --': 1 }), '{["] = 1, x = os.exit() --"] = 1}')
})

test("unicode text passes through", () => {
  assert.equal(encode("café ✓"), '"café ✓"')
})

test("throws on what Lua cannot hold", () => {
  for (const bad of [undefined, null, NaN, Infinity, -Infinity, () => 1, Symbol("x"), 10n, new Date(0), new Map()]) {
    assert.throws(() => encode(bad), /LuaLiteral/, String(typeof bad))
  }
  assert.throws(() => encode({ a: undefined }), /LuaLiteral/)
  assert.throws(() => encode([1, , 3]), /LuaLiteral/)
  const cyc = {}; cyc.self = cyc
  assert.throws(() => encode(cyc), /too deep/)
})
