.pragma library
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

function modeFields(win, launch) {
  const l = launch || { mode: "skip", argv: null }
  win.mode = l.mode
  if (l.mode === "launch" && Array.isArray(l.argv)) win.launch = l.argv.slice()
  return win
}

// target: { run, fp, slot, layout?, expiry_s?, scene? }. `scene` is the scene name, carried to the plan for auto app memory. fp is the monitor fingerprint to open on, slot 0 is the current workspace.
// Windows are sorted by `order` (stable) because tiled and scrolling targets open them one at a time in that order.
function fromScene(scene, launches, target, rules) {
  const t = target || {}
  const items = (scene.windows || []).map((w, i) => ({ w, l: (launches || [])[i], i }))
  items.sort((a, b) => (a.w.order - b.w.order) || (a.i - b.i))
  const windows = items.map((it) => {
    const win = { class: it.w.class, order: it.w.order, rect: rectOf(it.w.rect), floating: it.w.floating !== false }
    modeFields(win, it.l)
    if (it.w.context) win.context = it.w.context
    const rule = ruleFor(it.w.class, rules)
    if (rule) win.desktop = { monitor: rule.monitor, slot: rule.slot, follow: rule.follow }
    return win
  })
  const plan = {
    run: needRun(t.run),
    target: { fp: t.fp || {}, slot: t.slot || 0 },
    existing: scene.existing === "new" ? "new" : "move",
    expiry_s: t.expiry_s || DEFAULT_EXPIRY_S,
    layout: layoutOf(t.layout),
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
