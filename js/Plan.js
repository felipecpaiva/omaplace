.pragma library
.import "Zones.js" as Zones
.import "SceneStore.js" as SceneStore
// Build the plan the Lua module runs (design 5.4). Pure: the run id comes in, no clock, no random.
// The plan holds only plain values (strings, numbers, booleans, arrays, objects), so LuaLiteral.encode() can always write it.
// `launches[i]` is the AppResolve.resolve() result for window i (same order as scene.windows or snapshot.windows).

const LAYOUTS = ["floating", "tiled", "scrolling"]
const DEFAULT_EXPIRY_S = 20

function needRun(run) {
  if (typeof run !== "string" || run === "") throw new Error("Plan: a run id is required")
  return run
}
function layoutOf(v) { return LAYOUTS.indexOf(v) === -1 ? "floating" : v }
function rectOf(r) { return Array.isArray(r) && r.length === 4 ? r.map(Number) : [0, 0, 1, 1] }

// Name order keeps the choice stable when two rules name the same app.
function ruleFor(cls, rules) {
  const lc = String(cls).toLowerCase()
  for (const name of Object.keys(rules || {})) {
    const r = rules[name]
    if (r.enabled !== false && r.app !== "" && String(r.app).toLowerCase() === lc) return r
  }
  return null
}

// ---- plan scenes (design 14.2): zone to rect and order

// The desktop mode a plan layout needs: zone layouts and free float, tiled and scrolling keep their names, full ("") leaves
// the mode as it is.
function planMode(layout) {
  if (layout === "tiled" || layout === "scrolling") return layout
  return layout === "full" ? "" : "floating"
}

function fracRect(z) { return [z.x / Zones.UNIT, z.y / Zones.UNIT, z.w / Zones.UNIT, z.h / Zones.UNIT] }

// The rect to store in scenes.toml with a zone (design 14.7: computed once, here). Returns { rect } or { error }.
function zoneRect(layout, zone) {
  const z = Zones.ofLayout(layout)
  if (z.error) return { error: "layout " + JSON.stringify(layout) + ": " + z.error }
  if (!Number.isInteger(zone) || zone < 1 || zone > z.zones.length) {
    return { error: "zone " + zone + ": layout " + layout + " has zones 1 to " + z.zones.length }
  }
  return { rect: fracRect(z.zones[zone - 1]) }
}

// 1-based ranks of keys (arrays compared item by item), ties kept in input order.
function ranks(keys) {
  const idx = keys.map((k, i) => i)
  idx.sort((a, b) => { for (let j = 0; j < keys[a].length; j++) if (keys[a][j] !== keys[b][j]) return keys[a][j] - keys[b][j]; return a - b })
  const out = []
  idx.forEach((i, r) => { out[i] = r + 1 })
  return out
}

// Where each window of a plan scene goes, in scene.windows order: { rect, order, floating, fullscreen? }. Throws when the
// plan is not valid (SceneStore.planProblem), so a bad plan never opens.
function planWindows(scene) {
  const why = scene.planError || SceneStore.planProblem(scene)
  if (why) throw new Error("Plan: bad plan: " + why)
  const wins = scene.windows || []
  const layout = scene.layout
  if (layout === "free") return wins.map((w) => ({ rect: rectOf(w.rect), order: w.order, floating: w.floating !== false }))
  if (layout === "full") return wins.map(() => ({ rect: [0, 0, 1, 1], order: 1, floating: false, fullscreen: 1 }))
  if (layout === "tiled" || layout === "scrolling") {
    const order = ranks(wins.map((w) => [w.zone]))
    return wins.map((w, i) => ({ rect: [0, 0, 1, 1], order: order[i], floating: false }))
  }
  const zones = Zones.ofLayout(layout).zones
  const order = ranks(wins.map((w) => [zones[w.zone - 1].x, zones[w.zone - 1].y, w.zone]))
  return wins.map((w, i) => ({ rect: fracRect(zones[w.zone - 1]), order: order[i], floating: true }))
}

function modeFields(win, launch) {
  const l = launch || { mode: "skip", argv: null }
  win.mode = l.mode
  if (l.mode === "launch" && Array.isArray(l.argv)) win.launch = l.argv.slice()
  return win
}

// target: { run, fp, slot, layout?, expiry_s?, scene? }. `scene` is the scene name, carried to the plan for auto app memory. fp is the monitor fingerprint to open on, slot 0 is the current workspace.
// Windows are sorted by `order` (stable) because tiled and scrolling targets open them one at a time in that order.
// A plan scene (plan = true) gets rect, order and floating from its zones, and its layout from planMode(); `full` keeps
// the target's layout and marks its window fullscreen = 1.
function fromScene(scene, launches, target, rules) {
  const t = target || {}
  const placed = scene.plan === true ? planWindows(scene) : null
  const items = (scene.windows || []).map((w, i) => ({ w: placed ? Object.assign({}, w, placed[i]) : w, l: (launches || [])[i], i }))
  items.sort((a, b) => (a.w.order - b.w.order) || (a.i - b.i))
  const windows = items.map((it) => {
    const win = { class: it.w.class, order: it.w.order, rect: rectOf(it.w.rect), floating: it.w.floating !== false }
    modeFields(win, it.l)
    if (it.w.context) win.context = it.w.context
    if (placed && it.w.fullscreen) win.fullscreen = it.w.fullscreen
    const rule = ruleFor(it.w.class, rules)
    if (rule) win.desktop = { monitor: rule.monitor, slot: rule.slot, follow: rule.follow }
    return win
  })
  const plan = {
    run: needRun(t.run),
    target: { fp: t.fp || {}, slot: t.slot || 0 },
    existing: scene.existing === "new" ? "new" : "move",
    expiry_s: t.expiry_s || DEFAULT_EXPIRY_S,
    layout: placed && planMode(scene.layout) !== "" ? planMode(scene.layout) : layoutOf(t.layout),
    windows
  }
  if (typeof t.scene === "string" && t.scene !== "") plan.scene = t.scene
  return plan
}

// snapshot: the session snapshot of design 5.5. Each window keeps its own monitor index and slot; Lua resolves them.
// opts: { run, layout?, expiry_s? }. A snapshot carries no context, so none is set.
function fromSession(snapshot, launches, opts) {
  const o = opts || {}
  const items = (snapshot.windows || []).map((w, i) => ({ w, l: (launches || [])[i], i }))
  items.sort((a, b) => (a.w.monitor - b.w.monitor) || (a.w.slot - b.w.slot) || (a.w.order - b.w.order) || (a.i - b.i))
  const windows = items.map((it) => {
    const win = {
      class: it.w.class, monitor: it.w.monitor, slot: it.w.slot, order: it.w.order,
      rect: rectOf(it.w.rect), floating: it.w.floating !== false
    }
    return modeFields(win, it.l)
  })
  return {
    run: needRun(o.run),
    kind: "session",
    monitors: (snapshot.monitors || []).map((m) => m.fp || {}),
    existing: "move",
    expiry_s: o.expiry_s || DEFAULT_EXPIRY_S,
    layout: layoutOf(o.layout),
    windows
  }
}
