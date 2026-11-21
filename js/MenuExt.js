.pragma library
// The Omarchy menu rows (WP8, design 3): add or remove one marked block in the user's omarchy-menu.jsonc text.
// Pure: text in, text out. Everything outside the block is kept byte for byte. The block goes right after the opening
// `{`, with a comma after every row, so the user's last entry never needs a comma added. The markers are whole-line
// `//` comments because Omarchy's reader (MenuModel.stripJsonc) only strips whole-line comments and trailing commas.

const BEGIN = "  // omaplace begin (added by the omaplace settings window; remove it there or delete these lines)"
const END = "  // omaplace end"
const BEGIN_RE = /^[ \t]*\/\/ omaplace begin\b.*$/m
const END_RE = /^[ \t]*\/\/ omaplace end\b.*$/m

// [id, icon, label, CLI arguments]. The icons are Nerd Font glyphs, like Omarchy's own rows.
const ROWS = [
  ["omaplace.save", "\u{f0193}", "Save this desktop", "save --ask"],
  ["omaplace.open", "\u{f0770}", "Open a scene", "open --pick"],
  ["omaplace.restore", "\u{f0450}", "Restore last session", "restore"],
  ["omaplace.rule", "\u{f034e}", "Always open here", "rule add"],
  ["omaplace.settings", "\u{f0493}", "Settings", "settings"]
]

// Omarchy's own reading of the file (MenuModel.readMenuJsonc): null when it is not a menu object.
function read(text) {
  const stripped = String(text).replace(/^\s*\/\/[^\n]*(\n|$)/gm, "").replace(/,(\s*[}\]])/g, "$1")
  if (!stripped.trim()) return {}
  try {
    const v = JSON.parse(stripped)
    return v && typeof v === "object" && !Array.isArray(v) ? v : null
  } catch (e) { return null }
}

// The menu runs an action with `bash -lc`, so the path is single quoted (a path holding a quote is refused).
function block(cli) {
  const q = "'" + cli + "'"
  const lines = [BEGIN, '  "omaplace": ' + JSON.stringify({ icon: "\u{f0570}", label: "Scenes" }) + ","]
  for (const r of ROWS) lines.push("  " + JSON.stringify(r[0]) + ": " + JSON.stringify({ icon: r[1], label: r[2], action: q + " " + r[3] }) + ",")
  lines.push(END)
  return lines.join("\n")
}

function hasRows(text) { return BEGIN_RE.test(String(text || "")) }

// { ok: true, text } or { ok: false, why }. Removing text that has no block gives the text back unchanged.
function removeRows(text) {
  const t = String(text || "")
  const b = BEGIN_RE.exec(t)
  if (!b) return { ok: true, text: t }
  const e = END_RE.exec(t.slice(b.index))
  if (!e) return { ok: false, why: "the omaplace block in the menu file has no end line, fix it by hand" }
  const start = b.index > 0 && t.charAt(b.index - 1) === "\n" ? b.index - 1 : b.index // the line break addRows put before it
  const end = b.index + e.index + e[0].length
  return { ok: true, text: t.slice(0, start) + t.slice(end) }
}

// cli: the absolute path of bin/omaplace, worked out when the block is written. An existing block is replaced.
function addRows(text, cli) {
  if (typeof cli !== "string" || cli.charAt(0) !== "/" || /['\r\n]/.test(cli)) return { ok: false, why: "bad path to the omaplace command" }
  const r = removeRows(text)
  if (!r.ok) return r
  const t = r.text
  const doc = read(t)
  if (doc === null) return { ok: false, why: "the menu file is not a JSON object Omarchy can read, left alone" }
  if (doc.items !== undefined) return { ok: false, why: "the menu file uses an items wrapper, add the rows by hand" }
  // The first `{` outside whole-line comments opens the object; none means an empty or comment-only file.
  const lines = t.split("\n")
  let at = -1, pos = 0
  for (const line of lines) {
    const i = /^\s*\/\//.test(line) ? -1 : line.indexOf("{")
    if (i !== -1) { at = pos + i; break }
    pos += line.length + 1
  }
  let out
  if (at === -1) out = t + (t === "" || t.endsWith("\n") ? "" : "\n") + "{\n" + block(cli) + "\n}\n"
  else out = t.slice(0, at + 1) + "\n" + block(cli) + (t.charAt(at + 1) === "\n" ? "" : "\n") + t.slice(at + 1)
  if (read(out) === null) return { ok: false, why: "adding the rows would break the menu file, left alone" }
  return { ok: true, text: out }
}
