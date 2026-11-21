.pragma library
.import "Zones.js" as Zones
.import "Plan.js" as Plan
.import "SceneStore.js" as SceneStore
.import "PlansFile.js" as PlansFile
.import "AppResolve.js" as AppResolve
// The Desktops page (design 14.1, WP13): card models from the live desktops, the scenes and the rules, and the plan edits
// the page asks for. Pure: Service.qml reads the files, runs the commands and writes the result.
// A desktop's plan is found by home_monitor and home_slot, never by name (planUpdate can move a plan). A plan row is a
// "position" (pos): the zone number for zone layouts, the column for tiled and scrolling (stored as `zone`, 1..n), 1 for
// full, and the window's place in the list (1-based) for free, which has no zones.

const LAYOUT_CHOICES = [
  { value: "tiled", label: "Tiled" }, { value: "scrolling", label: "Scrolling" },
  { value: "full", label: "Full screen" }, { value: "free", label: "Free floating" },
  { value: "columns:2", label: "2 columns" }, { value: "columns:3", label: "3 columns" },
  { value: "rows:2", label: "2 rows" }, { value: "grid:2x2", label: "2 by 2 grid" }, { value: "priority", label: "Priority" }
]
const SIMPLE = ["tiled", "scrolling", "full", "free"]
const MODE_WORDS = { tiled: "Tiled", scrolling: "Scrolling", floating: "Floating" }
const MAX_COLUMNS = 10 // tiled, scrolling and free plans offer an empty row up to this many windows
const NAME_MAX = 40

function isZoneLayout(layout) { return typeof layout === "string" && layout !== "" && SIMPLE.indexOf(layout) === -1 }

// The badge words of a plan layout.
function layoutLabel(layout) {
  const known = LAYOUT_CHOICES.find((c) => c.value === layout)
  if (known) return isZoneLayout(layout) ? "Zones: " + known.label : known.label
  const z = Zones.ofLayout(layout)
  return z.error ? "Bad layout" : "Zones: custom (" + z.zones.length + ")"
}

// The picker value of a layout: its own name when listed, "custom" for zones text.
function layoutChoice(layout) {
  if (typeof layout !== "string" || layout === "") return ""
  return LAYOUT_CHOICES.some((c) => c.value === layout) ? layout : "custom"
}

function modeLabel(mode) { return MODE_WORDS[mode] || "" }

function storable(s) { return typeof s === "string" && !/["\r\n]/.test(s) }

// ---- names and lookup

// A new plan's scene name: desk-<monitor>-<slot>, made unique against every scene name (SceneStore's a-z 0-9 - _, 40 max).
function newSceneName(identity, slot, scenes) {
  const slug = String(identity || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "monitor"
  const tail = "-" + slot
  const room = NAME_MAX - "desk-".length - tail.length - 3 // 3 left for a "-NN" when the name is taken
  const base = "desk-" + slug.slice(0, room).replace(/-+$/, "") + tail
  const taken = scenes || {}
  if (!taken[base]) return base
  for (let n = 2; n < 100; n++) if (!taken[base + "-" + n]) return base + "-" + n
  return ""
}

// The plan of one desktop: { name, scene } or null. An empty home_monitor is the focused monitor's.
function findPlan(scenes, identity, slot, focused) {
  for (const name of Object.keys(scenes || {})) {
    const s = scenes[name]
    if (s.plan !== true || s.home_slot !== slot) continue
    if (s.home_monitor === identity || ((s.home_monitor || "") === "" && focused === true)) return { name, scene: s }
  }
  return null
}

// ---- apps

// Installed apps for the picker, from DesktopEntries values: { value: id, label: name, icon, startupWMClass }, sorted by name.
function appChoices(values) {
  const out = []
  for (let i = 0; i < (values ? values.length : 0); i++) {
    const e = values[i]
    if (!e || !e.id || e.noDisplay) continue
    const id = String(e.id).replace(/\.desktop$/i, "")
    out.push({ value: id, label: String(e.name || id), icon: String(e.icon || ""), startupWMClass: String(e.startupClass || "") })
  }
  return out.sort((a, b) => a.label.toLowerCase() < b.label.toLowerCase() ? -1 : a.label.toLowerCase() > b.label.toLowerCase() ? 1 : 0)
}

// Classes seen for an app id in captured scenes (never plans: a plan's guessed class would confirm itself).
// shortcut: app memory (memory.lua) is not read, so an app only ever opened by hand stays "not confirmed"; read it here
// if that note shows too often.
function seenClasses(scenes) {
  const out = {}
  for (const name of Object.keys(scenes || {})) {
    const s = scenes[name]
    if (s.plan === true) continue
    for (const w of s.windows || []) if (w.app && w.class && !out[w.app]) out[w.app] = w.class
  }
  return out
}

// The class to plan for an app id (AppResolve.classFor): { class, confirmed }.
function classOf(id, apps, seen) {
  const a = (apps || []).find((x) => x.value === id)
  return AppResolve.classFor({ id, startupWMClass: a ? a.startupWMClass : "" }, seen)
}

// ---- card models

function columns(n) { return Array.from({ length: n }, (_, i) => [i / n, 0, 1 / n, 1]) }

// The rows of a plan: [{ pos, rect (fractions, null for an empty add row), index (window index or -1), win }].
function positions(scene) {
  const wins = scene.windows || []
  const at = (pred) => { const i = wins.findIndex(pred); return { index: i, win: i === -1 ? null : wins[i] } }
  const layout = scene.layout
  if (layout === "full") return [Object.assign({ pos: 1, rect: [0, 0, 1, 1] }, at(() => true))]
  if (layout === "free") {
    const rows = wins.map((w, i) => ({ pos: i + 1, rect: Array.isArray(w.rect) ? w.rect : [0, 0, 1, 1], index: i, win: w }))
    if (wins.length < MAX_COLUMNS) rows.push({ pos: wins.length + 1, rect: null, index: -1, win: null })
    return rows
  }
  if (layout === "tiled" || layout === "scrolling") {
    const sorted = wins.map((w, i) => ({ w, i })).sort((a, b) => (a.w.zone - b.w.zone) || (a.i - b.i))
    const rects = columns(Math.max(1, sorted.length))
    const rows = sorted.map((it, k) => ({ pos: it.w.zone, rect: rects[k], index: it.i, win: it.w }))
    const next = sorted.length ? sorted[sorted.length - 1].w.zone + 1 : 1
    if (sorted.length < MAX_COLUMNS) rows.push({ pos: next, rect: sorted.length ? null : rects[0], index: -1, win: null })
    return rows
  }
  const z = Zones.ofLayout(layout)
  if (z.error) return []
  return z.zones.map((zone, i) => Object.assign({ pos: i + 1, rect: Plan.fracRect(zone) }, at((w) => w.zone === i + 1)))
}

// Why a planned window will not snap when opened by hand (design 14.7). snapOff: PlansFile said snap = false.
function snapNotes(win, snapOff, rules, others) {
  const notes = []
  if (snapOff) notes.push("Also in plan " + others.join(", ") + ": it will not snap when you open it by hand. Open all still places it.")
  const rule = Plan.ruleFor(win.class, rules)
  if (rule) notes.push("It has a placement rule (desktop " + rule.slot + "): the rule decides where it opens by hand. Open all still places it.")
  if (win.context) notes.push("Only a window omaplace opens gets this profile or folder: one you open from the app itself is not snapped.")
  return notes
}

// ctx: { rules, apps (appChoices), seen (seenClasses), snaps ({ scene: [snap flags] }), holders ({ class\ncontext: [scenes] }) }
function rowsOf(name, scene, ctx) {
  const byId = {}
  for (const a of ctx.apps || []) byId[a.value] = a
  const snaps = ctx.snaps[name] || []
  return positions(scene).map((p) => {
    const row = { pos: p.pos, rect: p.rect, index: p.index, empty: !p.win, app: "", cls: "", label: "", icon: "", notes: [], win: p.win }
    if (!p.win) return row
    const w = p.win, a = byId[w.app]
    row.app = w.app
    row.cls = w.class
    row.label = a ? a.label : (w.app || w.class)
    row.icon = a ? a.icon : ""
    const c = AppResolve.classFor({ id: w.app, startupWMClass: a ? a.startupWMClass : "" }, ctx.seen)
    if (!c.confirmed || c.class !== w.class) row.notes.push("Class not confirmed: open it once (" + w.class + ").")
    const others = (ctx.holders[w.class + "\n" + (w.context || "")] || []).filter((n) => n !== name)
    row.notes = row.notes.concat(snapNotes(w, snaps[p.index] === false, ctx.rules, others))
    return row
  })
}

function cardOf(mon, slot, ws, found, live, ctx) {
  const mode = (live.modes || {})[ws] || ""
  const card = {
    key: mon.identity + "\n" + slot, identity: mon.identity, focused: mon.focused === true, monitorName: mon.name, slot, workspace: ws,
    windows: (live.windows || {})[ws] || 0, mode, plan: !!found, name: "", layout: "", choice: "", openAtLogin: false,
    error: "", badge: "No plan" + (mode ? ", now " + modeLabel(mode) : ""), rows: [], modeNote: ""
  }
  if (!found) return card
  const s = found.scene
  card.name = found.name
  card.layout = typeof s.layout === "string" ? s.layout : ""
  card.choice = layoutChoice(card.layout)
  card.openAtLogin = s.open_at_login === true
  card.error = s.planError || ""
  card.badge = card.error ? "Bad plan" : layoutLabel(card.layout)
  card.rows = card.error ? [] : rowsOf(found.name, s, ctx)
  const want = card.error ? "" : Plan.planMode(card.layout)
  if (want !== "" && mode !== "" && want !== mode) card.modeNote = "Open all switches this desktop from " + modeLabel(mode) + " to " + modeLabel(want) + "."
  return card
}

// The page model. live: { monitors: desktops().monitors, modes: { ws: mode }, windows: { ws: count } }; liveNames: monitor
// names when Lua gave no desktops. Returns { groups: [{ identity, name, connected, cards }] }: ten cards per monitor, then
// one group per plan monitor that is not connected (only its plans), so every plan stays reachable.
function cards(live, doc, ctx) {
  const l = live || {}
  const scenes = (doc && doc.scenes) || {}
  const c = Object.assign({ rules: {}, apps: [], seen: seenClasses(scenes) }, ctx || {})
  c.snaps = {}
  c.holders = {}
  for (const p of PlansFile.entries({ scenes }).plans) {
    c.snaps[p.scene] = p.windows.map((w) => w.snap)
    for (const w of p.windows) (c.holders[w.class + "\n" + w.context] = c.holders[w.class + "\n" + w.context] || []).push(p.scene)
  }
  let mons = Array.isArray(l.monitors) ? l.monitors.filter((m) => m && typeof m.identity === "string") : []
  if (mons.length === 0) mons = (c.liveNames || []).map((n) => ({ identity: n, name: n, focused: false, slots: [] }))
  const shown = {}
  const groups = mons.map((m) => {
    const list = []
    for (let slot = 1; slot <= 10; slot++) {
      const s = (m.slots || []).find((x) => x && x.slot === slot)
      const found = findPlan(scenes, m.identity, slot, m.focused)
      if (found) shown[found.name] = true
      list.push(cardOf(m, slot, s && Number.isInteger(s.workspace) ? s.workspace : 0, found, l, c))
    }
    return { identity: m.identity, name: m.name || m.identity, connected: true, cards: list }
  })
  const away = {}
  for (const name of Object.keys(scenes)) {
    const s = scenes[name]
    if (s.plan !== true || shown[name]) continue
    const id = s.home_monitor || ""
    if (!away[id]) { away[id] = { identity: id, name: (id || "Focused monitor") + " (not connected)", connected: false, cards: [] }; groups.push(away[id]) }
    const slot = Number.isInteger(s.home_slot) ? s.home_slot : 0
    away[id].cards.push(cardOf({ identity: id, name: id, focused: id === "" }, slot, 0, { name, scene: s }, {}, c))
  }
  return { groups }
}

// The heading of a plan row on the card.
function rowTitle(layout, pos) {
  if (layout === "full") return "Full screen"
  if (layout === "free") return "Window " + pos
  if (layout === "tiled" || layout === "scrolling") return "Column " + pos
  return "Zone " + pos
}

// ---- edits

function clone(v) { return JSON.parse(JSON.stringify(v)) }

function newPlan(identity, slot, layout) {
  return { existing: "move", home_monitor: identity, home_slot: slot, key: "", saved_on: "", plan: true, layout, open_at_login: false, windows: [] }
}

// Place window w at position pos of a layout: zone, rect, order and floating as the layout needs them.
function placeAt(w, layout, pos) {
  w.order = pos
  if (layout === "free") { delete w.zone; w.floating = true; if (!Array.isArray(w.rect)) w.rect = [0, 0, 1, 1]; return w }
  w.zone = pos
  if (isZoneLayout(layout)) { w.rect = Plan.zoneRect(layout, pos).rect; w.floating = true } else { w.rect = [0, 0, 1, 1]; w.floating = false }
  return w
}

// Windows in their plan order: by zone, else by place in the list.
function ordered(wins) {
  return wins.map((w, i) => ({ w, k: Number.isInteger(w.zone) ? w.zone : i + 1, i })).sort((a, b) => (a.k - b.k) || (a.i - b.i)).map((x) => x.w)
}

// A layout change keeps the windows in order and drops those that no longer fit. Returns { scene, dropped: [app names] }.
function relayout(scene, layout) {
  let count = Infinity
  if (layout === "full") count = 1
  else if (isZoneLayout(layout)) count = Zones.ofLayout(layout).zones.length
  const list = ordered(scene.windows || [])
  const out = Object.assign({}, scene, { layout, windows: list.slice(0, count).map((w, i) => placeAt(w, layout, i + 1)) })
  return { scene: out, dropped: list.slice(count).map((w) => w.app || w.class) }
}

function checkLayout(layout) {
  if (typeof layout !== "string" || layout.trim() === "") return "pick a layout"
  if (!storable(layout)) return "a layout cannot hold a double quote or a line break"
  if (SIMPLE.indexOf(layout) !== -1) return ""
  const z = Zones.ofLayout(layout)
  return z.error ? "zones: " + z.error.replace(/^not a zone layout name and not zones text \((.*)\)$/, "$1") : ""
}

// One edit of a desktop's plan. desk: { identity, slot, focused }; op and arg:
//   "layout", layout (a new plan is made when the desktop has none)
//   "app", { pos, id, class }   put an app at a position (its profile, folder and program are reset)
//   "clear", pos                take the app out of a position
//   "login", true or false      open at login
// Returns { doc, name, changed, dropped } (doc is a copy) or { error }. The edited plan must pass SceneStore.planProblems.
function edit(doc, desk, op, arg) {
  const d = desk || {}
  if (!Number.isInteger(d.slot) || d.slot < 1 || d.slot > 10) return { error: "desktop must be 1 to 10" }
  if (typeof d.identity !== "string" || !storable(d.identity)) return { error: "bad monitor name" }
  const scenes = (doc && doc.scenes) || {}
  const found = findPlan(scenes, d.identity, d.slot, d.focused)
  let name, scene, dropped = []
  if (op === "layout") {
    const layout = String(arg === undefined || arg === null ? "" : arg).trim()
    const why = checkLayout(layout)
    if (why) return { error: why }
    if (found && found.scene.layout === layout) return { doc, name: found.name, changed: false, dropped }
    if (found) { name = found.name; const r = relayout(clone(found.scene), layout); scene = r.scene; dropped = r.dropped }
    else {
      name = newSceneName(d.identity, d.slot, scenes)
      if (name === "") return { error: "no free scene name for this desktop" }
      scene = newPlan(d.identity, d.slot, layout)
    }
  } else {
    if (!found) return { error: "this desktop has no plan yet, pick a layout first" }
    name = found.name
    scene = clone(found.scene)
    const free = scene.layout === "free"
    const at = (pos) => free ? (pos >= 1 && pos <= scene.windows.length ? pos - 1 : -1) : scene.windows.findIndex((w) => w.zone === pos)
    if (op === "login") {
      if (typeof arg !== "boolean") return { error: "on or off is needed" }
      if (scene.open_at_login === arg) return { doc, name, changed: false, dropped }
      scene.open_at_login = arg
    } else if (op === "app") {
      const a = arg || {}
      if (!Number.isInteger(a.pos) || a.pos < 1) return { error: "bad position" }
      if (typeof a.class !== "string" || a.class === "" || !storable(a.class) || !storable(String(a.id || ""))) return { error: "that app cannot be saved" }
      const w = placeAt({ app: String(a.id || ""), class: a.class, context: "", rect: [0, 0, 1, 1], launch: "", folder: "", edited: "" }, scene.layout, a.pos)
      const i = at(a.pos)
      if (i !== -1) scene.windows[i] = w
      else if (free && a.pos !== scene.windows.length + 1) return { error: "bad position" }
      else scene.windows.push(w)
    } else if (op === "clear") {
      const i = at(arg)
      if (i === -1) return { doc, name, changed: false, dropped }
      scene.windows.splice(i, 1)
      if (scene.layout === "tiled" || scene.layout === "scrolling") for (const w of scene.windows) if (w.zone > arg) placeAt(w, scene.layout, w.zone - 1)
      if (free) scene.windows.forEach((w, k) => placeAt(w, "free", k + 1))
    } else return { error: "unknown edit " + op }
  }
  const next = Object.assign({}, scenes)
  next[name] = scene
  const why = SceneStore.planProblems(next)[name]
  if (why) return { error: why }
  return { doc: Object.assign({}, doc, { scenes: next }), name, changed: true, dropped }
}

// The status line after a layout change (D19: a zone layout makes the desktop floating when Open all runs).
function layoutSavedText(layout, mode, dropped) {
  const want = Plan.planMode(layout)
  let t = "Saved"
  if (want !== "" && want !== mode) t += ". Open all switches this desktop to " + modeLabel(want)
  if (dropped && dropped.length) t += ". Taken out (no room): " + dropped.join(", ")
  return t
}
