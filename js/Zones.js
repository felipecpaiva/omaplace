.pragma library
// Zone layouts, copied from omagnet's LayoutOps.js at omagnet commit 856de02 (built-in layouts and the zones text only,
// nothing of the editor). Keep the copied functions identical to omagnet's; tests/zones.test.mjs checks them against
// tests/fixtures/zones-golden.json, made by tools/gen-zones-golden.sh from an omagnet checkout.
// A layout is a list of zones {x, y, w, h}. Numbers are integers in ten-thousandths of the screen (UNIT = 10000). Text form:
// "x y w h; x y w h" with fractions.

var UNIT = 10000
var MAX_ZONES = 64

function span(i, n) { return [Math.round(i * UNIT / n), Math.round((i + 1) * UNIT / n)] }

// Zones for "columns:N", "rows:N", "grid:CxR" (1 to 12) or "priority"; null for anything else.
function builtin(name) {
  name = String(name == null ? "" : name).toLowerCase().replace(/\s/g, "")
  var m = /^([a-z]+):?(.*)$/.exec(name)
  if (!m) return null
  var count = function (v) { return /^[0-9]+$/.test(v) && Number(v) >= 1 && Number(v) <= 12 ? Number(v) : 0 }
  var z = [], i, j, a, b
  if (m[1] === "columns" || m[1] === "rows") {
    var n = count(m[2])
    if (!n) return null
    for (i = 0; i < n; i++) {
      a = span(i, n)
      z.push(m[1] === "columns" ? { x: a[0], y: 0, w: a[1] - a[0], h: UNIT } : { x: 0, y: a[0], w: UNIT, h: a[1] - a[0] })
    }
    return z
  }
  if (m[1] === "grid") {
    var g = /^([0-9]+)x([0-9]+)$/.exec(m[2])
    var c = g ? count(g[1]) : 0, r = g ? count(g[2]) : 0
    if (!c || !r) return null
    for (j = 0; j < r; j++) for (i = 0; i < c; i++) {
      a = span(i, c); b = span(j, r)
      z.push({ x: a[0], y: b[0], w: a[1] - a[0], h: b[1] - b[0] })
    }
    return z
  }
  if (name === "priority") return [{ x: 0, y: 0, w: 2500, h: UNIT }, { x: 2500, y: 0, w: 5000, h: UNIT }, { x: 7500, y: 0, w: 2500, h: UNIT }]
  return null
}

// Read "x y w h; ..." into zones. Returns { zones } or { error }. Same rules as G.parse_zones in Lua: four numbers per zone,
// positive size, inside the screen, 1 to 64 zones. A value is rounded to a ten-thousandth.
function parse(text) {
  var parts = String(text == null ? "" : text).split(";").filter(function (p) { return /\S/.test(p) })
  if (parts.length === 0) return { error: "no zones" }
  if (parts.length > MAX_ZONES) return { error: "at most 64 zones" }
  var zones = []
  for (var k = 0; k < parts.length; k++) {
    var words = parts[k].trim().split(/\s+/)
    if (words.length !== 4) return { error: "a zone needs four numbers: x y w h" }
    var v = words.map(function (w) { return /^-?[0-9]+\.?[0-9]*$/.test(w) ? Number(w) : NaN })
    if (v.some(function (n) { return isNaN(n) })) return { error: "a zone has something that is not a number" }
    if (v[2] <= 0 || v[3] <= 0 || v[0] < 0 || v[1] < 0 || v[0] + v[2] > 1 + 1e-9 || v[1] + v[3] > 1 + 1e-9) {
      return { error: "a zone must lie inside the screen (0 to 1)" }
    }
    var z = { x: Math.round(v[0] * UNIT), y: Math.round(v[1] * UNIT), w: Math.max(1, Math.round(v[2] * UNIT)), h: Math.max(1, Math.round(v[3] * UNIT)) }
    z.w = Math.min(z.w, UNIT - z.x); z.h = Math.min(z.h, UNIT - z.y)
    zones.push(z)
  }
  return { zones: zones }
}

function fmt(v) { return (v / UNIT).toFixed(4).replace(/\.?0+$/, "") || "0" }

function toText(zones) {
  return zones.map(function (z) { return [z.x, z.y, z.w, z.h].map(fmt).join(" ") }).join("; ")
}

// ---- omaplace's own (not in omagnet)

// The zones of a plan layout value: a built-in name, else zones text. Returns { zones } or { error }.
function ofLayout(layout) {
  var b = builtin(layout)
  if (b) return { zones: b }
  var p = parse(layout)
  return p.error ? { error: "not a zone layout name and not zones text (" + p.error + ")" } : p
}
