.pragma library
// Pure helpers for the settings window (WP6): which settings the window may change, the edit of a scene window, browser
// profiles from a Chromium `Local State`, live monitor names, and the text the pages show. No files, no clock, no Qt:
// Service.qml reads the files and hands the text in, so Node can test every function here.

// The top-level keys the window writes, and values it shows but does not offer yet (a later restore at login).
const PANEL_KEYS = ["session", "restore_at_login", "app_memory", "existing_default", "missing_monitor_scene",
  "missing_monitor_rule", "ignore", "expiry_seconds", "settle_ms", "launch_tick_ms", "session_debounce_s", "session_keep",
  "context_quiet_ms", "request_timeout_s"]
const NOT_YET = { restore_at_login: ["ask", "auto"] }
const TIMING = [
  { key: "expiry_seconds", label: "Wait for a started app (seconds)" },
  { key: "settle_ms", label: "Settle time after an app opens (ms)" },
  { key: "launch_tick_ms", label: "Time between two launches (ms)" },
  { key: "session_debounce_s", label: "Session save delay (seconds)" },
  { key: "session_keep", label: "Sessions to keep" },
  { key: "context_quiet_ms", label: "Quiet time per profile or folder (ms)" },
  { key: "request_timeout_s", label: "Request timeout (seconds)" }
]
// Same list as EDITABLE in SceneStore.js (tests check it): the window fields a re-capture keeps once the user edited them.
// `context` is not in it: it is half of the key a re-capture matches slots by, so it cannot be kept from the old slot.
const KEEPABLE = ["app", "context", "rect", "order", "floating", "launch", "folder"]
const WINDOW_EDITS = ["folder", "launch", "context"]
// Strategy name (AppResolve) to the browser's folder under ~/.config, where its `Local State` file lives.
const PROFILE_DIRS = { chrome: "google-chrome", chromium: "chromium", brave: "BraveSoftware/Brave-Browser" }

function storable(s) { return typeof s === "string" && !/["\r\n]/.test(s) }

// A change from the window: { ok, value } (value coerced to the spec's type) or { ok: false, why }.
// specs: ConfigIO's SETTING_SPECS. The write itself validates again; this gives the window a plain answer first.
function settingChange(specs, key, value) {
  const spec = specs ? specs[key] : null
  if (PANEL_KEYS.indexOf(key) === -1 || !spec) return { ok: false, why: key + " is not a setting this window changes" }
  if (spec.type === "int") {
    const n = typeof value === "number" ? value : /^\s*-?\d+\s*$/.test(String(value)) ? Number(value) : NaN
    if (!Number.isInteger(n)) return { ok: false, why: "a whole number is needed" }
    if (n < spec.min || n > spec.max) return { ok: false, why: "pick a number from " + spec.min + " to " + spec.max }
    return { ok: true, value: n }
  }
  if (spec.type === "enum") {
    const v = String(value)
    if (spec.values.indexOf(v) === -1) return { ok: false, why: "pick one of " + spec.values.join(", ") }
    if ((NOT_YET[key] || []).indexOf(v) !== -1) return { ok: false, why: v + " is coming later" }
    return { ok: true, value: v }
  }
  if (spec.type === "bool") return typeof value === "boolean" ? { ok: true, value } : { ok: false, why: "on or off is needed" }
  const s = String(value).trim()
  if (!storable(s)) return { ok: false, why: "a double quote or a line break cannot be saved" }
  return { ok: true, value: s }
}

// Rows for the Advanced fold: label, limits and current value of each timing setting.
function timingRows(specs, settings) {
  return TIMING.map((t) => ({ key: t.key, label: t.label, min: specs[t.key].min, max: specs[t.key].max, value: settings[t.key] }))
}

// Add a field to a window's `edited` list (space separated, no duplicates). Fields a re-capture cannot keep are not added.
function markEdited(edited, field) {
  const list = String(edited || "").split(/\s+/).filter((f) => f !== "")
  if (KEEPABLE.indexOf(field) !== -1 && list.indexOf(field) === -1) list.push(field)
  return list.join(" ")
}

function isEdited(win, field) { return !!win && String(win.edited || "").split(/\s+/).indexOf(field) !== -1 }

// An edit of one scene window from the window: { ok, win } with a changed copy, or { ok: false, why }.
function windowEdit(win, field, value) {
  if (!win || WINDOW_EDITS.indexOf(field) === -1) return { ok: false, why: "that field cannot be edited here" }
  const v = String(value === undefined || value === null ? "" : value).trim()
  if (!storable(v)) return { ok: false, why: "a double quote or a line break cannot be saved" }
  if (field === "context" && v.charAt(0) === "-") return { ok: false, why: "a profile or folder cannot start with a dash" }
  const out = Object.assign({}, win)
  if (Array.isArray(win.rect)) out.rect = win.rect.slice()
  out[field] = v
  out.edited = markEdited(win.edited, field)
  return { ok: true, win: out }
}

function profileDir(strategy) { return PROFILE_DIRS[strategy] || "" }

// Profiles of a Chromium browser from its `Local State` JSON: only `profile.info_cache` directory ids and their display
// names are read; nothing else of that file leaves this function. Ids that cannot be stored or start with a dash are
// left out. Sorted by id, so "Default" comes before "Profile 1".
function profilesFromLocalState(text) {
  let doc = null
  try { doc = JSON.parse(String(text)) } catch (e) { return [] }
  const cache = doc && doc.profile && doc.profile.info_cache
  if (!cache || typeof cache !== "object" || Array.isArray(cache)) return []
  const out = []
  for (const id of Object.keys(cache)) {
    if (!/^[A-Za-z0-9 _.-]{1,64}$/.test(id) || id.charAt(0) === "-") continue
    const info = cache[id]
    const raw = info && typeof info.name === "string" ? info.name : ""
    const name = raw.replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 64)
    out.push({ id, name: name === "" ? id : name })
  }
  return out.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
}

// Choices for the profile picker of a window with an unknown profile.
function profileOptions(profiles) {
  return [{ value: "", label: "Pick a profile" }].concat((profiles || []).map((p) => ({ value: p.id, label: p.name + " (" + p.id + ")" })))
}

// Live monitors from `hyprctl monitors -j`, named as Omarchy names them (lua/monitors.lua identity_of): the description,
// with " #2", " #3" for later twins in connector name order; mirrors are left out. Returns names in the input order.
function monitorNames(list) {
  const mons = (Array.isArray(list) ? list : []).filter((m) => m && typeof m.name === "string" && (m.mirrorOf === undefined || m.mirrorOf === "none"))
  const described = (m) => (typeof m.description === "string" && m.description !== "" ? m.description : m.name)
  return mons.map((m) => {
    const same = mons.filter((o) => described(o) === described(m)).map((o) => o.name).sort()
    const i = same.indexOf(m.name)
    return i <= 0 ? described(m) : described(m) + " #" + (i + 1)
  })
}

// Choices for a rule's monitor: the focused monitor (empty), the live ones, and the rule's own when it is not plugged in.
function monitorChoices(live, current) {
  const out = [{ value: "", label: "Focused monitor" }]
  for (const n of live || []) out.push({ value: n, label: n })
  if (current && (live || []).indexOf(current) === -1) out.push({ value: current, label: current + " (not connected)" })
  return out
}

function pct(n) { return Math.round(Number(n) * 100) + "%" }

// One line about where a window goes: its place on a floating desktop, its rank on a tiled one.
function positionText(win) {
  if (!win) return ""
  if (win.floating === false) return "tiled, position " + (Number(win.order) || 1)
  const r = Array.isArray(win.rect) && win.rect.length === 4 ? win.rect : [0, 0, 1, 1]
  return "floating at " + pct(r[0]) + ", " + pct(r[1]) + ", size " + pct(r[2]) + " by " + pct(r[3])
}

// Saved sessions for the Session page. index: sessions.json; counts: instance -> window count (-1 when unreadable);
// current: this login's instance name.
function sessionRows(index, counts, current) {
  return (Array.isArray(index) ? index : [])
    .filter((e) => e && typeof e.instance === "string" && e.instance !== "")
    .map((e) => ({
      instance: e.instance, savedAt: Number(e.saved_at) || 0,
      windows: counts && typeof counts[e.instance] === "number" ? counts[e.instance] : -1, current: e.instance === current
    }))
}

// Plain words for an answer from Service.qml (one JSON line), for the window's status line.
function answerText(text, okText) {
  let a = null
  try { a = JSON.parse(String(text)) } catch (e) { a = null }
  if (!a || typeof a !== "object") return { ok: false, text: "No answer from the omaplace service", req: "" }
  const req = typeof a.req === "string" ? a.req : ""
  if (a.ok) return { ok: true, text: a.pending ? "Working..." : a.rule ? "Added the rule " + a.rule : okText || "Saved", req }
  const words = {
    busy: "omaplace is busy with another request, try again in a moment",
    not_found: "Not found",
    bad_name: "Names use a to z, 0 to 9, dash and underscore, up to 40 characters",
    no_lua: "The omaplace Lua module is not loaded in Hyprland",
    empty: "Nothing to save on this desktop",
    failed: "That did not work"
  }
  const base = words[a.code] || "That did not work"
  return { ok: false, text: a.reason ? base + ": " + a.reason : base, req: "" }
}

// What the window shows before the service answers, or when it is not running.
function emptyData() {
  return { ok: false, settings: {}, rules: [], scenes: [], sessions: [], warnings: [], scenesWritable: false }
}
