.pragma library
// omaplace scenes.toml: parse, serialize, migrate, and merge a re-capture. Pure: no files, no clock, no Hyprland.
// Format: the family TOML subset with numbered window sections, [scene.<name>] and [scene.<name>.window.<n>].
// A string cannot hold a double quote or a line break (no escapes): the parser warns and uses the default, serialize() throws.
// Doc shape: { schema, scenes: { name: { existing, home_monitor, home_slot, key, saved_on, windows: [window], extra? } },
//              warnings: [], errors: [{code, name}], readOnly }
// Window: { app, class, context, rect: [x, y, w, h], order, floating, launch, folder, edited, extra? }
// `edited` is a space separated list of the window fields the user changed in settings; mergeCapture keeps those.

const SCENE_NAME_RE = /^[a-z0-9_-]{1,40}$/
const SUPPORTED_SCHEMA = 1

const SCENE_SPECS = {
  existing: { type: "enum", values: ["move", "new"], def: "move" },
  home_monitor: { type: "string", def: "" },
  home_slot: { type: "int", min: 0, max: 10, def: 0 },
  key: { type: "string", def: "" },
  saved_on: { type: "string", def: "" }
}
const WINDOW_SPECS = {
  app: { type: "string", def: "" },
  class: { type: "string", def: "" },
  context: { type: "string", def: "" },
  rect: { type: "rect", def: [0, 0, 1, 1] },
  order: { type: "int", min: 1, max: 100000, def: 1 },
  floating: { type: "bool", def: true },
  launch: { type: "string", def: "" },
  folder: { type: "string", def: "" },
  edited: { type: "string", def: "" }
}
// class is the match key, never kept from old. context is kept when the user picked it (a re-capture may see "?").
const EDITABLE = ["app", "context", "rect", "order", "floating", "launch", "folder"]

function copyDefault(spec) { return Array.isArray(spec.def) ? spec.def.slice() : spec.def }
function defaultsOf(specs) {
  const o = {}
  for (const k of Object.keys(specs)) o[k] = copyDefault(specs[k])
  return o
}

function stripComment(line) {
  let quoted = false
  for (let i = 0; i < line.length; i++) {
    const c = line.charAt(i)
    if (c === '"') quoted = !quoted
    else if (c === "#" && !quoted) return line.slice(0, i)
  }
  return line
}

function lineKind(line) {
  const t = stripComment(line).trim()
  if (t === "") return { kind: "blank" }
  let m = /^\[([^\[\]]*)\]$/.exec(t)
  if (m) return { kind: "section", name: m[1].trim() }
  m = /^([A-Za-z0-9_-]+)\s*=\s*(.*)$/.exec(t)
  if (m) return { kind: "kv", key: m[1], raw: m[2] }
  return { kind: "bad" }
}

function parseValue(raw) {
  if (raw === "") return { ok: false, why: "empty value" }
  if (raw === "true") return { ok: true, value: true }
  if (raw === "false") return { ok: true, value: false }
  if (raw.charAt(0) === '"') {
    if (raw.length < 2 || raw.charAt(raw.length - 1) !== '"') return { ok: false, why: "unterminated string" }
    const inner = raw.slice(1, -1)
    if (inner.indexOf('"') !== -1) return { ok: false, why: "string holds a double quote (this format has no escapes)" }
    return { ok: true, value: inner }
  }
  if (/^-?\d+$/.test(raw)) return { ok: true, value: Number(raw) }
  if (/^-?\d+\.\d+$/.test(raw)) return { ok: true, value: Number(raw) }
  return { ok: false, why: "not a string, number or boolean" }
}

function parseRect(s) {
  const parts = s.trim().split(/\s+/).map(Number)
  if (parts.length !== 4 || parts.some((n) => !isFinite(n))) return null
  if (parts[2] <= 0 || parts[3] <= 0) return null
  return parts
}

function coerce(spec, raw) {
  const p = parseValue(raw)
  if (!p.ok) return p
  const v = p.value
  if (spec.type === "int") {
    if (typeof v !== "number" || !Number.isInteger(v)) return { ok: false, why: "expected a whole number" }
    if (v < spec.min || v > spec.max) return { ok: false, why: "out of range " + spec.min + ".." + spec.max }
  } else if (spec.type === "enum") {
    if (typeof v !== "string" || spec.values.indexOf(v) === -1) return { ok: false, why: "expected one of " + spec.values.join(", ") }
  } else if (spec.type === "bool") {
    if (typeof v !== "boolean") return { ok: false, why: "expected true or false" }
  } else if (spec.type === "rect") {
    const r = typeof v === "string" ? parseRect(v) : null
    if (!r) return { ok: false, why: 'expected "x y w h" as four numbers, w and h above 0' }
    return { ok: true, value: r }
  } else if (typeof v !== "string") return { ok: false, why: "expected a string" }
  return { ok: true, value: v }
}

// ---- parse

function newScene() {
  const s = defaultsOf(SCENE_SPECS)
  s.windows = []
  return s
}

function parse(text) {
  const doc = { schema: 1, scenes: {}, warnings: [], errors: [], readOnly: false }
  const warn = (m) => doc.warnings.push(m)
  const numbered = {} // scene name -> [{n, win}]
  let sec = { kind: "top" }
  let schemaSeen = false
  const ensure = (name) => {
    if (!doc.scenes[name]) { doc.scenes[name] = newScene(); numbered[name] = [] }
    return doc.scenes[name]
  }
  const lines = String(text).split(/\r?\n/)
  for (let n = 0; n < lines.length; n++) {
    const k = lineKind(lines[n])
    if (k.kind === "blank") continue
    if (k.kind === "bad") { warn("line " + (n + 1) + ": not a key = value line, ignored"); continue }
    if (k.kind === "section") {
      const m = /^scene\.(.*?)(?:\.window\.(\d+))?$/.exec(k.name)
      if (!m) { warn("section [" + k.name + "]: unknown, kept out"); sec = { kind: "skip" }; continue }
      if (!SCENE_NAME_RE.test(m[1])) {
        if (!doc.errors.some((e) => e.name === m[1])) doc.errors.push({ code: "bad_name", name: m[1] })
        sec = { kind: "skip" }
        continue
      }
      const scene = ensure(m[1])
      if (m[2] === undefined) { sec = { kind: "scene", label: "scene." + m[1] + ".", target: scene, specs: SCENE_SPECS, scene }; continue }
      const win = defaultsOf(WINDOW_SPECS)
      numbered[m[1]].push({ n: Number(m[2]), win })
      win.order = Number(m[2])
      sec = { kind: "window", label: k.name + ".", target: win, specs: WINDOW_SPECS }
      continue
    }
    if (sec.kind === "skip") continue
    if (sec.kind === "top") {
      if (k.key !== "schema") { warn(k.key + ": unknown top level key, ignored"); continue }
      const r = coerce({ type: "int", min: 1, max: 1000000 }, k.raw)
      if (r.ok) { doc.schema = r.value; schemaSeen = true } else warn("schema: " + r.why + ", using 1")
      continue
    }
    const spec = sec.specs[k.key]
    const p = parseValue(k.raw)
    if (!spec) {
      if (p.ok) { (sec.target.extra = sec.target.extra || {})[k.key] = p.value } else warn(sec.label + k.key + ": " + p.why + ", ignored")
      continue
    }
    const r = coerce(spec, k.raw)
    if (r.ok) sec.target[k.key] = r.value
    else { sec.target[k.key] = copyDefault(spec); warn(sec.label + k.key + ": " + r.why + ", using " + JSON.stringify(spec.def)) }
  }
  for (const name of Object.keys(doc.scenes)) {
    numbered[name].sort((a, b) => a.n - b.n)
    for (const item of numbered[name]) {
      if (item.win.class === "") { warn("scene." + name + ".window." + item.n + ".class: empty, window skipped"); continue }
      doc.scenes[name].windows.push(item.win)
    }
  }
  if (!schemaSeen && Object.keys(doc.scenes).length > 0) warn("schema: missing, read as 1")
  return migrate(doc)
}

// Schema 1 is the only one so far. A newer schema is read but never written back.
function migrate(doc) {
  const out = Object.assign({}, doc)
  out.warnings = (doc.warnings || []).slice()
  out.readOnly = !!doc.readOnly
  const schema = doc.schema === undefined ? 1 : doc.schema
  if (schema > SUPPORTED_SCHEMA) {
    out.readOnly = true
    out.warnings.push("scenes.toml has schema " + schema + ", newer than this version (" + SUPPORTED_SCHEMA + "): read only, not rewritten")
  }
  return out
}

// ---- serialize

function format(v) {
  if (typeof v === "string") {
    if (/["\r\n]/.test(v)) throw new Error("bad_value: a string cannot hold a double quote or a line break")
    return '"' + v + '"'
  }
  if (typeof v === "boolean") return String(v)
  if (typeof v === "number" && isFinite(v)) return String(v)
  throw new Error("bad_value: " + String(v))
}

function emit(out, obj, specs) {
  for (const key of Object.keys(specs)) {
    const v = obj[key] === undefined ? copyDefault(specs[key]) : obj[key]
    out.push(key + " = " + (specs[key].type === "rect" ? format(v.join(" ")) : format(v)))
  }
  const extra = obj.extra || {}
  for (const key of Object.keys(extra)) out.push(key + " = " + format(extra[key]))
}

function serialize(doc) {
  if (doc.readOnly) throw new Error("read_only: scenes.toml has a newer schema")
  const out = ["schema = " + format(doc.schema === undefined ? SUPPORTED_SCHEMA : doc.schema)]
  for (const name of Object.keys(doc.scenes || {})) {
    if (!SCENE_NAME_RE.test(name)) throw new Error("bad_name: " + name)
    const scene = doc.scenes[name]
    out.push("", "[scene." + name + "]")
    emit(out, scene, SCENE_SPECS)
    ;(scene.windows || []).forEach((win, i) => {
      out.push("", "[scene." + name + ".window." + (i + 1) + "]")
      emit(out, win, WINDOW_SPECS)
    })
  }
  return out.join("\n") + "\n"
}

// ---- merge a capture into an old scene

// capture: { saved_on?, windows: [{app, class, context, rect, order, floating, launch, folder}] }. The capture is the truth about
// which windows exist; for a slot found again, the fields listed in its `edited` value are kept from the old slot.
// Matching: first every exact (class, context) pair. Then a captured window whose context is unknown ("?") takes an unused
// old slot of its class (one whose context the user picked first), and one with no context ("") takes only such a picked
// slot. Such a window gets the old slot's context, since its own capture says nothing.
function contextPicked(ow) { return String(ow.edited || "").split(/\s+/).indexOf("context") !== -1 }

function mergeCapture(oldScene, capture) {
  const old = oldScene || newScene()
  const scene = Object.assign(newScene(), old)
  scene.windows = []
  if (old.extra) scene.extra = Object.assign({}, old.extra)
  if (capture.saved_on !== undefined) scene.saved_on = capture.saved_on
  const oldWindows = old.windows || []
  const caps = capture.windows || []
  const used = {}
  const match = caps.map(() => -1)
  const take = (ci, ok) => {
    for (let i = 0; i < oldWindows.length; i++) {
      if (used[i] || oldWindows[i].class !== caps[ci].class || !ok(oldWindows[i])) continue
      used[i] = true
      match[ci] = i
      return
    }
  }
  caps.forEach((cw, ci) => take(ci, (ow) => (ow.context || "") === (cw.context || "")))
  for (const picked of [true, false]) {
    caps.forEach((cw, ci) => {
      const ctx = cw.context || ""
      if (match[ci] !== -1 || (ctx !== "?" && ctx !== "") || (!picked && ctx === "")) return
      take(ci, (ow) => !picked || contextPicked(ow))
    })
  }
  caps.forEach((cw, ci) => {
    const win = Object.assign(defaultsOf(WINDOW_SPECS), cw)
    win.edited = ""
    const ow = match[ci] === -1 ? null : oldWindows[match[ci]]
    if (ow) {
      const keep = String(ow.edited || "").split(/\s+/).filter((f) => EDITABLE.indexOf(f) !== -1)
      for (const f of keep) win[f] = Array.isArray(ow[f]) ? ow[f].slice() : ow[f]
      if ((win.context || "") !== (ow.context || "")) win.context = ow.context || ""
      win.edited = keep.join(" ")
      if (ow.extra) win.extra = Object.assign({}, ow.extra)
    }
    scene.windows.push(win)
  })
  return scene
}
