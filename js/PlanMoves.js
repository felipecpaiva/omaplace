.pragma library
.import "Zones.js" as Zones
.import "Plan.js" as Plan
.import "SceneStore.js" as SceneStore
.import "Desktops.js" as Desktops
// Hand moves of planned windows (design D21, D23, 14.8): read plan-moves.json and turn a move into a
// scene edit for "Update plan". Pure: text and docs in, no files, no clock. Rects are fractions of the usable area,
// like scene rects.
// move: { id, scene, window (1-based), class, context, kind: "desktop" | "zone", to: { identity, slot, rect (null or absent for tiled windows), floating } }

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

function find(moves, id) { return moves.find((m) => m.id === id) || null }

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

const no = (code, reason) => ({ code, reason })

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

// A zone plan becomes free (D24): every window keeps the rect it has now (its zone's), `moved` the move's rect.
function toFree(scene, moved, rect) {
  for (const w of scene.windows) {
    w.rect = Plan.zoneRect(scene.layout, w.zone).rect || (rectOk(w.rect) ? w.rect : [0, 0, 1, 1]) // where the opener put it
    delete w.zone
    w.floating = true
  }
  moved.rect = rect.slice()
  scene.layout = "free"
}

// The scene edit for "Update plan" (design 14.8, D24). doc is a SceneStore doc and is never changed.
// Returns { doc, changed (false: the plan already says so), replace? (true: place the plan's open windows again),
// created? (the name of a new plan), removed? (the name of a plan left empty) } or { code: "not_found" | "not_possible", reason }.
function edit(scenesDoc, m) {
  if (!valid(m)) return no("not_possible", "the move is not readable")
  const doc = JSON.parse(JSON.stringify(scenesDoc))
  const scene = doc.scenes[m.scene]
  if (!scene || scene.plan !== true) return no("not_found", "plan " + m.scene + " is gone")
  const win = scene.windows[m.window - 1]
  if (!win || win.class !== m.class || (win.context || "") !== (m.context || "")) return no("not_found", "plan " + m.scene + " changed since the move")
  const out = { doc, changed: true }
  if (m.kind === "zone") {
    // Lua reports zone moves only of floating windows, which always have a rect
    if (!rectOk(m.to.rect)) return no("not_possible", "the move has no place")
    if (scene.layout === "free") {
      if (JSON.stringify(win.rect) === JSON.stringify(m.to.rect)) return { doc, changed: false }
      win.rect = m.to.rect.slice()
    } else if (!isZoneLayout(scene.layout)) {
      return no("not_possible", "layout " + scene.layout + " has no zones")
    } else {
      const z = zoneAt(scene.layout, m.to.rect)
      if (z === 0) toFree(scene, win, m.to.rect)
      else if (z === win.zone) return { doc, changed: false }
      else {
        const other = scene.windows.find((w) => w !== win && w.zone === z)
        // swap: the other window goes to the moved one's old zone, and a re-place moves it there
        if (other) { setZone(other, scene.layout, win.zone); out.replace = true }
        setZone(win, scene.layout, z)
      }
    }
  } else {
    // An empty home_monitor means the focused monitor. The move does not say which monitor had the focus, so such a
    // plan keeps "" and only its slot changes.
    const anyMonitor = (scene.home_monitor || "") === ""
    if ((anyMonitor || scene.home_monitor === m.to.identity) && scene.home_slot === m.to.slot) return { doc, changed: false }
    const twin = scene.windows.filter((w) => w.class === m.class && (w.context || "") === (m.context || "")).length > 1
    if (twin) return no("not_possible", "plan " + m.scene + " holds more than one " + m.class + " window, so the moved one is not known")
    // the plan of the target desktop; a plan on the focused monitor ("") is that desktop's plan too
    const name = Object.keys(doc.scenes).find((n) => n !== m.scene && doc.scenes[n].plan === true && ["", m.to.identity].indexOf(doc.scenes[n].home_monitor || "") !== -1 && doc.scenes[n].home_slot === m.to.slot)
    scene.windows.splice(m.window - 1, 1)
    if (name) {
      const why = joinPlan(doc.scenes[name], win, m.to)
      if (why) return no("not_possible", why)
      // a plan left empty is removed
      if (scene.windows.length === 0) { delete doc.scenes[m.scene]; out.removed = m.scene }
    } else if (scene.windows.length === 0) {
      scene.windows.push(win) // the only window: the plan follows it to the new desktop
      if (!anyMonitor) scene.home_monitor = m.to.identity
      scene.home_slot = m.to.slot
    } else {
      // no plan there (D24): a new free plan holds the window where it is now
      const identity = anyMonitor ? "" : m.to.identity
      const created = Desktops.newSceneName(identity, m.to.slot, doc.scenes)
      if (created === "") return no("not_possible", "no free scene name for desktop " + m.to.slot)
      delete win.zone
      win.rect = rectOk(m.to.rect) ? m.to.rect.slice() : [0, 0, 1, 1]
      win.floating = true
      win.order = 1
      doc.scenes[created] = Desktops.newPlan(identity, m.to.slot, "free")
      doc.scenes[created].windows.push(win)
      out.created = created
    }
  }
  // Any plan the edit makes invalid (a used zone, two plans on one desktop, full with two windows) refuses the edit.
  const before = SceneStore.planProblems(scenesDoc.scenes), problems = SceneStore.planProblems(doc.scenes)
  for (const n of Object.keys(problems)) if (!before[n]) return no("not_possible", "plan " + n + " would be invalid: " + problems[n])
  return out
}
