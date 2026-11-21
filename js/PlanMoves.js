.pragma library
.import "Zones.js" as Zones
.import "Plan.js" as Plan
.import "SceneStore.js" as SceneStore
// Hand moves of planned windows (design D21, D23, 14.8): read plan-moves.json, tell which moves are new, and turn a move
// into a scene edit for "Update plan". Pure: text and docs in, no files, no clock. Rects are fractions of the usable area,
// like scene rects.
// move: { id, scene, window (1-based), class, context, kind: "desktop" | "zone", to: { identity, slot, rect | null, floating } }

const FIXED_LAYOUTS = ["tiled", "scrolling", "full", "free"]

function rectOk(r) { return Array.isArray(r) && r.length === 4 && r.every((v) => typeof v === "number" && isFinite(v)) }
function idOk(v) { return Number.isInteger(v) && v >= 1 }

function valid(m) {
  if (!m || typeof m !== "object" || !idOk(m.id) || !idOk(m.window)) return false
  if (typeof m.scene !== "string" || typeof m.class !== "string" || m.class === "") return false
  if (m.kind !== "desktop" && m.kind !== "zone") return false
  const to = m.to
  if (!to || typeof to !== "object" || (to.rect !== null && to.rect !== undefined && !rectOk(to.rect))) return false
  return m.kind === "zone" || (typeof to.identity === "string" && Number.isInteger(to.slot) && to.slot >= 1 && to.slot <= 10)
}

// The moves of plan-moves.json that are well formed. Bad text gives none.
function parse(text) {
  let doc = null
  try { doc = JSON.parse(String(text || "")) } catch (e) { doc = null }
  const list = doc && Array.isArray(doc.moves) ? doc.moves : []
  return list.filter(valid)
}

// Moves not notified yet: id above lastId. When the newest id is below lastId, Lua's counter started again (Hyprland
// restarted), so every move counts as new. Returns { moves (oldest first), maxId } with maxId the value to remember.
function fresh(moves, lastId) {
  if (moves.length === 0) return { moves: [], maxId: lastId }
  const maxId = Math.max.apply(null, moves.map((m) => m.id))
  const from = maxId < lastId ? 0 : lastId
  return { moves: moves.filter((m) => m.id > from).sort((a, b) => a.id - b.id), maxId }
}

function find(moves, id) { return moves.find((m) => m.id === id) || null }

// The notification for a move: classes and scene names only (never titles).
function notice(m) {
  return { headline: "omaplace: " + m.scene, body: m.kind === "desktop" ? m.class + " moved to another desktop" : m.class + " left its zone" }
}

function isZoneLayout(layout) { return FIXED_LAYOUTS.indexOf(layout) === -1 }

// The zone (1-based) of a zone layout whose rect holds the centre of rect, or 0. First match wins where zones overlap.
function zoneAt(layout, rect) {
  const z = Zones.ofLayout(layout)
  if (z.error || !rectOk(rect)) return 0
  const cx = (rect[0] + rect[2] / 2) * Zones.UNIT, cy = (rect[1] + rect[3] / 2) * Zones.UNIT
  const inside = (v, a, len) => v >= a && (v < a + len || (a + len === Zones.UNIT && v <= Zones.UNIT))
  const i = z.zones.findIndex((r) => inside(cx, r.x, r.w) && inside(cy, r.y, r.h))
  return i + 1
}

// Reasons hold no commas or double quotes: the CLI's field reader stops at either.
const no = (code, reason) => ({ code, reason: reason.replace(/[",]/g, "") })

// Puts win into zone `zone` of scene (a zone layout): the zone and the rect the page would store (design 14.7).
function setZone(win, layout, zone) {
  win.zone = zone
  win.rect = Plan.zoneRect(layout, zone).rect
  win.floating = true
}

// win (taken out of its plan) goes into plan `target`, following the target's layout. Returns null or a not_possible reason.
function joinPlan(target, win, to) {
  const layout = target.layout
  if (layout === "free") {
    delete win.zone
    if (rectOk(to.rect)) win.rect = to.rect.slice()
    if (typeof to.floating === "boolean") win.floating = to.floating
  } else if (layout === "tiled" || layout === "scrolling" || layout === "full") {
    win.zone = target.windows.reduce((n, w) => Math.max(n, w.zone || 0), 0) + 1 // last in order; full refuses a second
  } else {
    const z = zoneAt(layout, to.rect)
    if (z === 0) return "the window is outside every zone of the plan there"
    setZone(win, layout, z)
  }
  target.windows.push(win)
  return null
}

// The scene edit for "Update plan" (design 14.8). doc is a SceneStore doc and is never changed.
// Returns { doc, changed } (changed false: the plan already says so) or { code: "not_found" | "not_possible", reason }.
// Reasons: see no().
function edit(scenesDoc, m) {
  if (!valid(m)) return no("not_possible", "the move is not readable")
  const doc = JSON.parse(JSON.stringify(scenesDoc))
  const scene = doc.scenes[m.scene]
  if (!scene || scene.plan !== true) return no("not_found", "plan " + m.scene + " is gone")
  const win = scene.windows[m.window - 1]
  if (!win || win.class !== m.class || (win.context || "") !== (m.context || "")) return no("not_found", "plan " + m.scene + " changed since the move")
  if (m.kind === "zone") {
    if (!isZoneLayout(scene.layout)) return no("not_possible", "layout " + scene.layout + " has no zones")
    const z = zoneAt(scene.layout, m.to.rect)
    // shortcut: outside every zone the plan would switch to free after a confirm (design 14.8), not built in WP12
    if (z === 0) return no("not_possible", "the window is outside every zone")
    if (z === win.zone) return { doc, changed: false }
    const other = scene.windows.find((w) => w !== win && w.zone === z)
    if (other) return no("not_possible", "zone " + z + " already holds " + other.class)
    setZone(win, scene.layout, z)
  } else {
    if ((scene.home_monitor || "") === m.to.identity && scene.home_slot === m.to.slot) return { doc, changed: false }
    if (scene.windows.length === 1) {
      scene.home_monitor = m.to.identity
      scene.home_slot = m.to.slot
    } else {
      const name = Object.keys(doc.scenes).find((n) => doc.scenes[n].plan === true && (doc.scenes[n].home_monitor || "") === m.to.identity && doc.scenes[n].home_slot === m.to.slot)
      if (!name) return no("not_possible", "no plan on desktop " + m.to.slot + " of that monitor")
      scene.windows.splice(m.window - 1, 1)
      const why = joinPlan(doc.scenes[name], win, m.to)
      if (why) return no("not_possible", why)
    }
  }
  // Any plan the edit makes invalid (a used zone, two plans on one desktop, full with two windows) refuses the edit.
  const before = SceneStore.planProblems(scenesDoc.scenes), problems = SceneStore.planProblems(doc.scenes)
  for (const n of Object.keys(problems)) if (!before[n]) return no("not_possible", "plan " + n + " would be invalid: " + problems[n])
  return { doc, changed: true }
}
