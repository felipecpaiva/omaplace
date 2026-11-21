.pragma library
// Auto app memory (WP10 wiring): which events of moves.json the service has not handled yet. Pure: text in, no files.
// `at` is Hyprland's uptime in ms when Lua noted the move, so it only orders events. When the newest event in the file
// is older than the last one handled, Hyprland restarted and its clock did too: every event counts as new again
// (AutoMove.apply skips the ones already applied, so that is safe).

function valid(ev) { return !!ev && typeof ev === "object" && typeof ev.at === "number" && isFinite(ev.at) }

// text: moves.json; lastAt: the highest `at` handled so far (-1 for none). Returns { events, maxAt }, maxAt being the
// value to remember once the events are handled. Bad text or no array gives no events and keeps lastAt.
function pending(text, lastAt) {
  let list = null
  try { list = JSON.parse(String(text || "")) } catch (e) { list = null }
  if (!Array.isArray(list)) return { events: [], maxAt: lastAt }
  const good = list.filter(valid)
  if (good.length === 0) return { events: [], maxAt: lastAt }
  const newest = Math.max.apply(null, good.map((ev) => ev.at))
  const from = newest < lastAt ? -1 : lastAt
  const events = good.filter((ev) => ev.at > from).sort((a, b) => a.at - b.at)
  return { events, maxAt: newest }
}
