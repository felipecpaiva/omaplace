.pragma library
// omaplace config.toml reader and line-preserving writer. Pure: no Qt imports, no files, no clock.
// Format: the family TOML subset (key = value, [sections], # comments, "strings" without escapes, integers, true/false).
// parse() always returns { schema, settings, rules, strategies, warnings } and adds `extra` (flat map "section.key" or "key"
// to the raw parsed value) only when the file holds keys this version does not know. A bad value becomes its default plus one warning.
// The writers touch only the lines they must; comments, blank lines and unknown lines stay as they were.

const STRATEGY_USES = ["desktop", "webapp", "terminal", "tui", "context", "place_only", "command"]

const SETTING_SPECS = {
  schema: { type: "int", min: 1, max: 1000000, def: 1 },
  missing_monitor_scene: { type: "enum", values: ["focused", "skip"], def: "focused" },
  missing_monitor_rule: { type: "enum", values: ["focused", "skip"], def: "skip" },
  existing_default: { type: "enum", values: ["move", "new"], def: "move" },
  expiry_seconds: { type: "int", min: 1, max: 600, def: 20 },
  settle_ms: { type: "int", min: 0, max: 10000, def: 1100 },
  launch_tick_ms: { type: "int", min: 10, max: 5000, def: 150 },
  session: { type: "enum", values: ["on", "off"], def: "on" },
  session_debounce_s: { type: "int", min: 1, max: 3600, def: 15 },
  session_keep: { type: "int", min: 1, max: 50, def: 5 },
  request_timeout_s: { type: "int", min: 1, max: 600, def: 60 },
  restore_at_login: { type: "enum", values: ["off", "ask", "auto"], def: "off" },
  app_memory: { type: "enum", values: ["scene", "last_place", "auto"], def: "scene" },
  context_quiet_ms: { type: "int", min: 0, max: 30000, def: 2000 },
  tiled_order: { type: "bool", def: true },
  ignore: { type: "string", def: "" }
}
const RULE_SPECS = {
  app: { type: "string", def: "" },
  monitor: { type: "string", def: "" },
  slot: { type: "int", min: 1, max: 10, def: 1 },
  follow: { type: "bool", def: false },
  enabled: { type: "bool", def: true }
}
const STRATEGY_SPECS = {
  match: { type: "string", def: "" },
  use: { type: "enum", values: STRATEGY_USES, def: "desktop" },
  launch_context: { type: "string", def: "" },
  context: { type: "enum", values: ["profile", "folder", "none"], def: "none" }
}
const NAME_RE = /^[A-Za-z0-9_-]{1,40}$/

function defaultsOf(specs) {
  const o = {}
  for (const k of Object.keys(specs)) o[k] = specs[k].def
  return o
}

// ---- line level helpers (same subset as SceneStore.js; the two files are kept apart on purpose, QML libraries cannot share code)

// A '#' starts a comment only outside double quotes.
function stripComment(line) {
  let quoted = false
  for (let i = 0; i < line.length; i++) {
    const c = line.charAt(i)
    if (c === '"') quoted = !quoted
    else if (c === "#" && !quoted) return [line.slice(0, i), line.slice(i)]
  }
  return [line, ""]
}

function lineKind(line) {
  const t = stripComment(line)[0].trim()
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
  } else if (typeof v !== "string") return { ok: false, why: "expected a string" }
  return { ok: true, value: v }
}

// ---- parse

function parse(text) {
  const out = { schema: 1, settings: defaultsOf(SETTING_SPECS), rules: {}, strategies: {}, warnings: [] }
  const extra = {}
  const warn = (m) => out.warnings.push(m)
  let sec = { kind: "top", label: "", target: out.settings, specs: SETTING_SPECS }
  const lines = String(text).split(/\r?\n/)
  for (let n = 0; n < lines.length; n++) {
    const k = lineKind(lines[n])
    if (k.kind === "blank") continue
    if (k.kind === "bad") { warn("line " + (n + 1) + ": not a key = value line, ignored"); continue }
    if (k.kind === "section") {
      const m = /^(rule|strategy)\.(.*)$/.exec(k.name)
      if (!m) { sec = { kind: "unknown", label: k.name + "." }; continue }
      if (!NAME_RE.test(m[2])) { warn("section [" + k.name + "]: bad name, skipped"); sec = { kind: "skip" }; continue }
      const isRule = m[1] === "rule"
      const specs = isRule ? RULE_SPECS : STRATEGY_SPECS
      const target = defaultsOf(specs)
      ;(isRule ? out.rules : out.strategies)[m[2]] = target
      sec = { kind: m[1], label: k.name + ".", target, specs }
      continue
    }
    if (sec.kind === "skip") continue
    const spec = sec.specs && sec.specs[k.key]
    if (!spec) {
      const p = parseValue(k.raw)
      extra[sec.label + k.key] = p.ok ? p.value : k.raw
      continue
    }
    const r = coerce(spec, k.raw)
    if (r.ok) sec.target[k.key] = r.value
    else {
      sec.target[k.key] = spec.def
      warn(sec.label + k.key + ": " + r.why + ", using " + JSON.stringify(spec.def))
    }
  }
  out.schema = out.settings.schema
  if (out.schema > 1) warn("schema " + out.schema + " is newer than this version (1), read as is")
  for (const name of Object.keys(out.rules)) if (out.rules[name].app === "") warn("rule." + name + ".app: empty, the rule matches nothing")
  for (const name of Object.keys(out.strategies)) if (out.strategies[name].match === "") warn("strategy." + name + ".match: empty, the strategy matches nothing")
  if (Object.keys(extra).length > 0) out.extra = extra
  return out
}

// ---- line-preserving writers

function format(v) {
  if (typeof v === "string") {
    if (/["\r\n]/.test(v)) throw new Error("bad_value: a string cannot hold a double quote or a line break")
    return '"' + v + '"'
  }
  if (typeof v === "boolean") return String(v)
  if (typeof v === "number" && isFinite(v)) return String(v)
  throw new Error("bad_value: " + String(v))
}

function checked(spec, key, value) {
  if (!spec) return
  const r = coerce(spec, format(value))
  if (!r.ok) throw new Error("bad_value: " + key + " " + r.why)
}

function split(text) {
  const s = String(text)
  return { lines: s.split(/\r?\n/), eol: s.indexOf("\r\n") !== -1 ? "\r\n" : "\n" }
}

function sectionRange(lines, header) { // the last section with this header, as [headerIndex, endIndex), or null
  let start = -1
  for (let i = 0; i < lines.length; i++) {
    const k = lineKind(lines[i])
    if (k.kind === "section" && k.name === header) start = i
  }
  if (start === -1) return null
  let end = lines.length
  for (let i = start + 1; i < lines.length; i++) if (lineKind(lines[i]).kind === "section") { end = i; break }
  return [start, end]
}

// Set key inside lines[from, to). Replaces the value in place (comment kept), else inserts after the last key line.
function upsert(lines, from, to, key, value, topLevel) {
  let last = -1
  for (let i = from; i < to; i++) {
    const k = lineKind(lines[i])
    if (k.kind !== "kv") continue
    last = i
    if (k.key !== key) continue
    const parts = stripComment(lines[i])
    const prefix = /^\s*[A-Za-z0-9_-]+\s*=\s*/.exec(parts[0])[0]
    const gap = parts[1] === "" ? "" : /\s*$/.exec(parts[0])[0]
    lines[i] = prefix + format(value) + gap + parts[1]
    return
  }
  const entry = key + " = " + format(value)
  if (last !== -1) { lines.splice(last + 1, 0, entry); return }
  if (!topLevel) { lines.splice(from, 0, entry); return }
  let at = 0
  while (at < to && /^\s*#/.test(lines[at])) at++
  const next = lines[at]
  lines.splice(at, 0, entry)
  if (next !== undefined && lineKind(next).kind === "section") lines.splice(at + 1, 0, "")
}

function appendBlock(lines, block) {
  while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
  if (lines.length > 0) lines.push("")
  for (const l of block) lines.push(l)
  lines.push("")
}

function setValue(text, key, value) {
  if (!/^[A-Za-z0-9_-]+$/.test(key)) throw new Error("bad_key: " + key)
  checked(SETTING_SPECS[key], key, value)
  const s = split(text)
  let to = s.lines.length
  for (let i = 0; i < s.lines.length; i++) if (lineKind(s.lines[i]).kind === "section") { to = i; break }
  upsert(s.lines, 0, to, key, value, true)
  return s.lines.join(s.eol)
}

function setRule(text, name, rule) {
  if (!NAME_RE.test(name)) throw new Error("bad_name: " + name)
  const keys = Object.keys(RULE_SPECS).filter((k) => rule && rule[k] !== undefined)
  for (const k of keys) checked(RULE_SPECS[k], k, rule[k])
  const s = split(text)
  const header = "rule." + name
  const range = sectionRange(s.lines, header)
  if (!range) {
    appendBlock(s.lines, ["[" + header + "]"].concat(keys.map((k) => k + " = " + format(rule[k]))))
  } else {
    // each upsert may add a line, so the end moves
    let end = range[1]
    for (const k of keys) {
      const before = s.lines.length
      upsert(s.lines, range[0] + 1, end, k, rule[k], false)
      end += s.lines.length - before
    }
  }
  return s.lines.join(s.eol)
}

function removeRule(text, name) {
  const s = split(text)
  const range = sectionRange(s.lines, "rule." + name)
  if (!range) return String(text)
  // trailing comments and blanks of the section belong to what follows, so cut after the last real line
  let end = range[1]
  while (end - 1 > range[0] && lineKind(s.lines[end - 1]).kind !== "kv") end--
  let start = range[0]
  while (start > 0 && /^\s*#/.test(s.lines[start - 1])) start-- // a comment right above the header describes this rule
  if (end < s.lines.length && s.lines[end] === "" && (start === 0 || s.lines[start - 1] === "")) end++
  s.lines.splice(start, end - start)
  return s.lines.join(s.eol)
}
