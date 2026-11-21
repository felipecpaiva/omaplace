.pragma library
// Turn a window class into a launch plan. Pure: the caller passes the desktop entries and the strategy table.
// Never builds a shell string: the result is an argv array (always uwsm-app, --, ...) and context values go in as whole argv
// elements, so a profile or folder name can never be read as shell syntax.
// A strategy table is { name: { match, use, launch_context, context } }. `match` is a case-insensitive class pattern: `|` separates
// alternatives and `*` is a wildcard. The first entry in table order that matches wins; mergeStrategies() puts user entries first.
// entries: [{ id, startupWMClass, exec }] from the desktop entry database.

function defaultStrategies() {
  const t = {
    webapp: { match: "chrome-*-*|chromium-*-*|brave-*-*", use: "webapp", launch_context: "", context: "none" },
    tui: { match: "org.omarchy.*", use: "tui", launch_context: "", context: "none" },
    terminal: {
      match: "Alacritty|kitty|foot|footclient|ghostty|com.mitchellh.ghostty|org.wezfurlong.wezterm|org.gnome.Terminal|xterm",
      use: "terminal", launch_context: "", context: "folder"
    },
    chrome: {
      match: "google-chrome|google-chrome-stable|google-chrome-beta", use: "context",
      launch_context: "google-chrome-stable --profile-directory={context} --new-window", context: "profile"
    },
    chromium: {
      match: "chromium|chromium-browser", use: "context",
      launch_context: "chromium --profile-directory={context} --new-window", context: "profile"
    },
    brave: {
      match: "brave-browser|brave", use: "context",
      launch_context: "brave --profile-directory={context} --new-window", context: "profile"
    },
    firefox: {
      match: "firefox|org.mozilla.firefox", use: "context",
      launch_context: "firefox -P {context} --new-window", context: "profile"
    },
    place_only: { match: "obsidian|slack|spotify", use: "place_only", launch_context: "", context: "none" },
    command: { match: "", use: "command", launch_context: "", context: "none" }
  }
  // the code family: one entry each because each forks its own program name
  for (const bin of ["code", "code-oss", "code-insiders", "codium", "cursor", "windsurf"]) {
    t["ide_" + bin] = { match: bin, use: "context", launch_context: bin + " --new-window {folder}", context: "folder" }
  }
  return t
}

// User entries first, so they beat the defaults; a user entry with a default's name replaces it.
function mergeStrategies(user) {
  const out = {}
  const u = user || {}
  for (const k of Object.keys(u)) out[k] = u[k]
  const d = defaultStrategies()
  for (const k of Object.keys(d)) if (!(k in out)) out[k] = d[k]
  return out
}

function matches(pattern, cls) {
  const c = String(cls).toLowerCase()
  for (const alt of String(pattern || "").split("|")) {
    if (alt === "") continue
    const re = new RegExp("^" + alt.toLowerCase().replace(/[.+?^${}()\[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$")
    if (re.test(c)) return true
  }
  return false
}

// Split a typed launch string into argv. Honors "double" and 'single' quotes; no variables, no escapes, no globbing.
function splitArgs(s) {
  const out = []
  let cur = "", has = false, quote = ""
  for (const ch of String(s || "")) {
    if (quote) { if (ch === quote) quote = ""; else cur += ch; continue }
    if (ch === '"' || ch === "'") { quote = ch; has = true; continue }
    if (/\s/.test(ch)) { if (has || cur !== "") out.push(cur); cur = ""; has = false; continue }
    cur += ch
  }
  if (has || cur !== "") out.push(cur)
  return out
}

function idOf(entry) { return String(entry.id || "").replace(/\.desktop$/i, "") }

// Same order as omahop's icon lookup (id, class, lower case, last part of a reverse DNS id), then the Exec program name.
function findEntry(cls, entries) {
  const list = entries || []
  const lc = String(cls).toLowerCase()
  const steps = [
    (e) => idOf(e) === cls,
    (e) => e.startupWMClass === cls,
    (e) => idOf(e).toLowerCase() === lc || String(e.startupWMClass || "").toLowerCase() === lc,
    (e) => { const p = idOf(e).split("."); return p.length > 2 && p[p.length - 1].toLowerCase() === lc },
    (e) => { const w = String(e.exec || "").trim().split(/\s+/)[0] || ""; return w !== "" && w.split("/").pop().toLowerCase() === lc }
  ]
  for (const step of steps) for (const e of list) if (idOf(e) !== "" && step(e)) return e
  return null
}

const prefix = ["uwsm-app", "--"]
function skip(strategy, contextKind, reason) { return { strategy, mode: "skip", argv: null, contextKind, reason } }
function launch(strategy, contextKind, tail) { return { strategy, mode: "launch", argv: prefix.concat(tail), contextKind, reason: "" } }
function safeWord(s) { return s !== "" && s.charAt(0) !== "-" }

function expandHome(folder, home) {
  if (home && (folder === "~" || folder.indexOf("~/") === 0)) return home.replace(/\/$/, "") + folder.slice(1)
  return folder
}

// slot: { context, folder, launch, home? } (all optional). home is only used to expand a leading ~ in a folder, argv has no shell.
function resolve(cls, entries, strategies, slot) {
  const s = slot || {}
  const table = strategies || defaultStrategies()
  let name = "desktop", entry = null
  for (const k of Object.keys(table)) {
    if (table[k].use !== "command" && matches(table[k].match, cls)) { name = k; entry = table[k]; break }
  }
  const use = entry ? entry.use : "desktop"
  const kind = entry && use === "context" ? entry.context : use === "terminal" ? "folder" : "none"
  const typed = splitArgs(s.launch)

  if (typed.length > 0 && use !== "terminal") return launch("command", "none", typed)
  if (use === "place_only") return { strategy: name, mode: "place_only", argv: null, contextKind: "none", reason: "" }

  if (use === "tui") {
    const cmd = String(cls).slice("org.omarchy.".length)
    if (!/^[A-Za-z0-9._-]+$/.test(cmd) || cmd.charAt(0) === "-") return skip(name, "none", "bad tui name")
    return launch(name, "none", ["omarchy-launch-tui", cmd])
  }

  if (use === "terminal") {
    const folder = expandHome(String(s.folder || ""), s.home)
    const tail = ["xdg-terminal-exec"]
    if (folder !== "") tail.push("--dir=" + folder)
    return launch(name, "folder", tail.concat(typed))
  }

  if (use === "context") {
    const ctx = String(s.context || "")
    if (ctx === "?") return skip(name, kind, "profile or folder not chosen yet")
    if (ctx !== "") {
      if (!safeWord(ctx)) return skip(name, kind, "context starts with a dash")
      const folder = expandHome(String(s.folder || ""), s.home)
      if (folder !== "" && !safeWord(folder)) return skip(name, kind, "folder starts with a dash")
      const values = { "{context}": ctx, "{folder}": kind === "folder" ? expandHome(ctx, s.home) : folder }
      const tail = []
      for (const tok of splitArgs(entry.launch_context)) {
        let t = tok
        for (const k of Object.keys(values)) t = t.split(k).join(values[k])
        if (t !== "") tail.push(t)
      }
      if (tail.length === 0) return skip(name, kind, "strategy has no launch_context")
      return launch(name, kind, tail)
    }
    // no context saved: fall through to the plain desktop entry
  }

  const e = findEntry(cls, entries)
  if (!e) return skip(name, kind, "no desktop entry for this class")
  if (use === "webapp" && String(e.startupWMClass || "").toLowerCase() !== String(cls).toLowerCase() && idOf(e).toLowerCase() !== String(cls).toLowerCase()) {
    return skip(name, kind, "no web app entry for this class")
  }
  return launch(name, kind, [idOf(e) + ".desktop"])
}
