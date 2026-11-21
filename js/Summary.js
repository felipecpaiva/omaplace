.pragma library
// Pure helpers for the flows in Service.qml (design 6.2, 6.3): turn a capture into scene windows, a status into a result,
// a result into notification text. No files, no clock, no Qt. AppResolve and ArgFilter results come in as arguments, so
// this file needs no other module and Node can test it alone.

const SCENE_NAME_RE = /^[a-z0-9_-]{1,40}$/ // same as SceneStore.js
const SHELLS = ["bash", "zsh", "fish", "sh", "dash", "ksh", "nu", "tcsh", "xonsh"]
const FINAL = ["done", "partial", "failed", "interrupted"]

function validName(name) { return typeof name === "string" && SCENE_NAME_RE.test(name) }

function answer(obj) { return JSON.stringify(obj) }

function parseJson(text) {
  try { const v = JSON.parse(String(text)); return v !== null && typeof v === "object" ? v : null } catch (e) { return null }
}

function listOf(v) { return Array.isArray(v) ? v : [] }

// Path of a file next to the plugin's QML, from its URL (omahop's Paths.fromUrl).
function fromUrl(url) {
  const text = String(url)
  if (text.indexOf("file://") !== 0) return ""
  return decodeURIComponent(text.substring("file://".length))
}

// Quickshell DesktopEntry objects to the plain list AppResolve reads.
function entryList(values) {
  const out = []
  for (let i = 0; i < (values ? values.length : 0); i++) {
    const e = values[i]
    if (e && e.id) out.push({ id: String(e.id), startupWMClass: String(e.startupClass || ""), exec: String(e.execString || "") })
  }
  return out
}

// resolved: AppResolve.resolve() result. A launch through a desktop entry names the entry; anything else keeps the class.
function appIdOf(resolved, cls) {
  const argv = resolved && Array.isArray(resolved.argv) ? resolved.argv : []
  const last = argv.length === 3 ? argv[2] : ""
  return /\.desktop$/.test(last) ? last.slice(0, -".desktop".length) : cls
}

function isTerminal(resolved, strategies) {
  const s = resolved && strategies ? strategies[resolved.strategy] : null
  return !!s && s.use === "terminal"
}

// Join argv into the launch string AppResolve.splitArgs reads back. Returns null when an argument cannot be stored
// (scenes.toml strings hold no double quote or line break), so the caller drops the program instead of guessing.
function joinArgs(argv) {
  const parts = []
  for (const a of argv) {
    if (/["\r\n]/.test(a)) return null
    if (a === "" || /[\s']/.test(a)) {
      if (a.indexOf("'") !== -1) return null
      parts.push("'" + a + "'")
    } else parts.push(a)
  }
  return parts.join(" ")
}

function shortHome(folder, home) {
  const h = String(home || "").replace(/\/$/, "")
  if (h !== "" && (folder === h || folder.indexOf(h + "/") === 0)) return "~" + folder.slice(h.length)
  return folder
}

// info: procinfo.sh output ({cwd, argv} or {}). filtered: ArgFilter.filter(info.argv). A shell in the foreground means
// "just a terminal in that folder", so no program is kept.
function terminalFields(info, filtered, home) {
  const out = { folder: "", launch: "", dropped: 0 }
  if (!info || typeof info.cwd !== "string") return out
  if (!/["\r\n]/.test(info.cwd)) out.folder = shortHome(info.cwd, home)
  else out.dropped++
  const argv = filtered ? listOf(filtered.argv) : []
  out.dropped += filtered ? filtered.dropped || 0 : 0
  const prog = String(argv[0] || "").replace(/^-/, "").split("/").pop()
  if (argv.length === 0 || SHELLS.indexOf(prog) !== -1) return out
  const joined = joinArgs(argv)
  if (joined === null) out.dropped++
  else out.launch = joined
  return out
}

// capture: design 5.5 (kind "capture"). resolved[i] and terms[i] belong to capture.windows[i]; terms[i] is the result of
// terminalFields() or undefined. Windows with no way to start them are not saved (counted as skipped). A window of a
// context app (strategy use "context") without an omaplace tag has an unknown profile or folder: it is saved with
// context "?" and counted, so the settings window can ask once (design 5.4a rule 3).
function sceneCapture(capture, resolved, terms, strategies) {
  const wins = listOf(capture && capture.windows)
  const mons = listOf(capture && capture.monitors)
  const out = { saved_on: "", windows: [] }
  const counts = { saved: 0, skipped: 0, need_profile: 0, dropped: 0 }
  if (wins.length > 0) {
    const m = mons[wins[0].monitor]
    out.saved_on = m && m.fp && typeof m.fp.identity === "string" ? m.fp.identity : ""
  }
  wins.forEach((w, i) => {
    const r = resolved[i]
    const strat = r && strategies ? strategies[r.strategy] : null
    const context = String(w.context || "") !== "" ? String(w.context) : strat && strat.use === "context" ? "?" : ""
    if (!r || (r.mode === "skip" && context !== "?")) { counts.skipped++; return }
    const t = terms[i] || { folder: "", launch: "", dropped: 0 }
    counts.dropped += t.dropped
    if (context === "?") counts.need_profile++
    out.windows.push({
      app: appIdOf(r, w.class), class: String(w.class), context,
      rect: Array.isArray(w.rect) && w.rect.length === 4 ? w.rect.slice() : [0, 0, 1, 1],
      order: Number(w.order) || 1, floating: w.floating === true, launch: t.launch, folder: t.folder
    })
    counts.saved++
  })
  return { capture: out, counts }
}

// The scene's own layout, for an empty target workspace (Lua reads the live one when it has windows).
function layoutOf(scene) {
  const wins = listOf(scene && scene.windows)
  return wins.length > 0 && wins.every((w) => w.floating !== false) ? "floating" : wins.length > 0 ? "tiled" : "floating"
}

function planTarget(scene, run, expiry) {
  return {
    run, fp: scene.home_monitor ? { identity: scene.home_monitor } : {}, slot: scene.home_slot || 0,
    layout: layoutOf(scene), expiry_s: expiry
  }
}

// status: status.json. Null until the run with this id ends. "moved" is a window that was already open; "placed" one
// omaplace started, so placed counts both and started counts the second.
function runResult(status, run) {
  if (!status || status.run !== run || FINAL.indexOf(status.state) === -1) return null
  const c = { moved: 0, placed: 0, skipped: 0, not_reopened: 0, failed: 0, waiting: 0 }
  for (const it of listOf(status.items)) if (it && c[it.state] !== undefined) c[it.state]++
  const r = {
    ok: status.state === "done" || status.state === "partial", state: status.state, run,
    placed: c.moved + c.placed, started: c.placed, skipped: c.skipped, not_reopened: c.not_reopened, failed: c.failed + c.waiting
  }
  if (!r.ok) r.code = "failed"
  return r
}

function notifyText(result) {
  const parts = [result.placed + " placed (" + result.started + " started)"]
  if (result.skipped) parts.push(result.skipped + " skipped")
  if (result.not_reopened) parts.push(result.not_reopened + " not reopened")
  if (result.failed) parts.push(result.failed + " failed")
  if (result.state === "interrupted") parts.push("interrupted")
  return parts.join(", ")
}

function ruleName(cls) {
  return String(cls).toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40)
}

// The rule for the focused window (class from the active window), placed where the capture saw it.
function ruleFromCapture(capture, cls) {
  const w = listOf(capture && capture.windows).find((x) => x.class === cls)
  const name = ruleName(cls)
  if (!w || name === "" || !(w.slot >= 1 && w.slot <= 10)) return null
  const m = listOf(capture.monitors)[w.monitor]
  const monitor = m && m.fp && typeof m.fp.identity === "string" && !/["\r\n]/.test(m.fp.identity) ? m.fp.identity : ""
  return { name, rule: { app: cls, monitor, slot: w.slot, follow: false, enabled: true } }
}

function sceneList(doc) {
  return Object.keys((doc && doc.scenes) || {}).map((name) => ({ name, windows: listOf(doc.scenes[name].windows).length }))
}

// Same rule as lua/omaplace.lua: every character outside [A-Za-z0-9_] becomes "_", cut to 128.
function instanceName(sig) { return String(sig).replace(/[^A-Za-z0-9_]/g, "_").slice(0, 128) }

// index: sessions.json (newest first, [{instance, saved_at}]). gen "" or "previous" is the newest instance that is not
// `current`; "1", "2" count the same previous ones; anything else must be an instance name. Returns "" when none fits.
function pickSession(index, current, gen) {
  const names = listOf(index).map((e) => (e && typeof e.instance === "string" ? e.instance : "")).filter((n) => n !== "")
  const before = names.filter((n) => n !== current)
  if (gen === "" || gen === "previous") return before[0] || ""
  if (/^[0-9]+$/.test(gen)) return before[Number(gen) - 1] || ""
  return names.indexOf(gen) === -1 ? "" : gen
}
