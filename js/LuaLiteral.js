.pragma library
// Encode a JS value as one Lua table literal (design 5.4). Pure. Throws on anything Lua cannot hold (undefined, null, NaN,
// Infinity, functions, symbols, class instances, cycles), so a bad plan fails loudly instead of becoming a silent nil.
// Strings go in double quotes with backslash, quote, newline and every control character escaped, so no input can end the
// string early. Whole floats such as 1.0 come out as 1 (a Lua integer): plans only carry numbers where that is fine.

const RESERVED = ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"]
const MAX_DEPTH = 64

function encodeString(s) {
  let out = '"'
  for (let i = 0; i < s.length; i++) {
    const ch = s.charAt(i), c = s.charCodeAt(i)
    if (ch === "\\") out += "\\\\"
    else if (ch === '"') out += '\\"'
    else if (ch === "\n") out += "\\n"
    else if (c < 0x20 || c === 0x7f) out += "\\" + String(c).padStart(3, "0")
    else out += ch
  }
  return out + '"'
}

function encodeKey(k) {
  if (/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(k) && RESERVED.indexOf(k) === -1) return k
  return "[" + encodeString(k) + "]"
}

function enc(v, depth) {
  if (depth > MAX_DEPTH) throw new Error("LuaLiteral: nested too deep")
  if (typeof v === "string") return encodeString(v)
  if (typeof v === "boolean") return v ? "true" : "false"
  if (typeof v === "number") {
    if (!isFinite(v)) throw new Error("LuaLiteral: not a finite number")
    return String(v)
  }
  if (Array.isArray(v)) {
    const parts = []
    for (let i = 0; i < v.length; i++) parts.push(enc(v[i], depth + 1)) // a hole reads as undefined and throws
    return "{" + parts.join(", ") + "}"
  }
  if (v !== null && typeof v === "object") {
    const proto = Object.getPrototypeOf(v)
    if (proto !== Object.prototype && proto !== null) throw new Error("LuaLiteral: not a plain object")
    return "{" + Object.keys(v).map((k) => encodeKey(k) + " = " + enc(v[k], depth + 1)).join(", ") + "}"
  }
  throw new Error("LuaLiteral: cannot encode " + (v === null ? "null" : typeof v))
}

function encode(value) { return enc(value, 0) }
