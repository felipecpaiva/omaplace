.pragma library
.import "Plan.js" as Plan
.import "SceneStore.js" as SceneStore
.import "LuaLiteral.js" as LuaLiteral
// The derived file ~/.local/state/omaplace/plans.lua (design 14.7): one Lua table literal of every plan = true scene, so Lua
// can snap a planned app to its desktop and zone without reading scenes.toml or doing zone math. Pure: the caller writes it.
// File shape: return { plans = { { scene, home_monitor, home_slot, layout, mode, open_at_login, windows = {
//   { class, context, rect = {x, y, w, h}, floating, fullscreen?, snap } } } } }
// `layout` is the plan's layout as saved; `mode` is the desktop mode it needs (Plan.planMode: floating, tiled, scrolling, or
// "" for full, which leaves the mode as it is). `fullscreen = 1` marks the window of a full plan.
// `snap = false` when the same class and context is in more than one plan (ambiguous, design 14.7). Rule conflicts are
// decided in Lua, not here.

const MAX_BYTES = 1048576 // the cap Lua puts on plan files it loads (lua/omaplace.lua)

// UTF-8 length, as Lua counts it.
function byteLength(s) {
  let n = 0
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i++ }
    else n += 3
  }
  return n
}

// Returns { plans, skipped: [{ scene, reason }] }. A plan that does not validate is skipped and reported, never guessed.
function entries(doc) {
  const plans = [], skipped = []
  const scenes = (doc && doc.scenes) || {}
  const problems = SceneStore.planProblems(scenes) // also refuses a second plan on one desktop
  for (const name of Object.keys(scenes)) {
    const scene = scenes[name]
    if (scene.plan !== true) continue
    if (problems[name]) { skipped.push({ scene: name, reason: problems[name] }); continue }
    let placed
    try { placed = Plan.planWindows(scene) } catch (e) { skipped.push({ scene: name, reason: String(e.message || e) }); continue }
    plans.push({
      scene: name, home_monitor: scene.home_monitor || "", home_slot: scene.home_slot, layout: scene.layout,
      mode: Plan.planMode(scene.layout), open_at_login: scene.open_at_login === true,
      windows: (scene.windows || []).map((w, i) => {
        const out = { class: w.class, context: w.context || "", rect: placed[i].rect, floating: placed[i].floating, snap: true }
        if (placed[i].fullscreen) out.fullscreen = placed[i].fullscreen
        return out
      })
    })
  }
  const inPlans = {} // class and context -> number of plans holding it
  const key = (w) => w.class + "\n" + w.context
  for (const p of plans) {
    const seen = {}
    for (const w of p.windows) if (!seen[key(w)]) { seen[key(w)] = true; inPlans[key(w)] = (inPlans[key(w)] || 0) + 1 }
  }
  for (const p of plans) for (const w of p.windows) w.snap = inPlans[key(w)] === 1
  return { plans, skipped }
}

// Returns { text, skipped } or, when the file would pass the cap Lua reads, { error, skipped } (never cut short).
function build(doc) {
  const e = entries(doc)
  const text = "return " + LuaLiteral.encode({ plans: e.plans }) + "\n"
  if (byteLength(text) > MAX_BYTES) return { error: "plans.lua would be over 1 MB, not written", skipped: e.skipped }
  return { text, skipped: e.skipped }
}
