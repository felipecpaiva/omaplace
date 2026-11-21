.pragma library
// Auto app memory (F5, mode `auto`): apply the moves Lua reported in moves.json to a scenes doc. Pure: no files, no clock.
// event: { class, context, from_scene, to_scene, rect: [x, y, w, h], floating, order, at }
// The input doc is never changed. Applying the same event twice changes nothing the second time: once the slot is gone
// from from_scene and present in to_scene, the event is skipped as already applied.

function same(win, ev) { return win.class === ev.class && (win.context || "") === (ev.context || "") }

function findSlot(scene, ev) { return scene.windows.findIndex((w) => same(w, ev)) }

function renumber(scene) { scene.windows.forEach((w, i) => { w.order = i + 1 }) }

function rectOk(r) { return Array.isArray(r) && r.length === 4 && r.every((v) => typeof v === "number" && isFinite(v)) }

// Windows are kept sorted by order (stable), so an event's order is a position.
function sortByOrder(scene) {
  const items = scene.windows.map((w, i) => ({ w, i }))
  items.sort((a, b) => (a.w.order - b.w.order) || (a.i - b.i))
  scene.windows = items.map((it) => it.w)
}

function one(doc, ev) {
  if (!ev || typeof ev.class !== "string" || ev.class === "") return "bad event"
  const from = doc.scenes[ev.from_scene]
  const to = doc.scenes[ev.to_scene]
  if (!from || !to) return "unknown scene"
  if (from === to) return "same scene"
  const at = findSlot(from, ev)
  if (at === -1) return findSlot(to, ev) === -1 ? "unknown slot" : "already applied"
  sortByOrder(from)
  const i = findSlot(from, ev)
  const slot = from.windows.splice(i, 1)[0]
  renumber(from)
  if (rectOk(ev.rect)) slot.rect = ev.rect.slice()
  if (typeof ev.floating === "boolean") slot.floating = ev.floating
  sortByOrder(to)
  const want = Number.isInteger(ev.order) && ev.order >= 1 ? ev.order : to.windows.length + 1
  to.windows.splice(Math.min(want, to.windows.length + 1) - 1, 0, slot)
  renumber(to)
  return null
}

// Returns { doc, applied, skipped: [{ index, class, reason }] }. `index` is the event's place in `events`.
function apply(scenesDoc, events) {
  const doc = JSON.parse(JSON.stringify(scenesDoc))
  const skipped = []
  let applied = 0
  ;(events || []).forEach((ev, index) => {
    const reason = one(doc, ev)
    if (reason === null) applied++
    else skipped.push({ index, class: ev && ev.class, reason })
  })
  return { doc, applied, skipped }
}
