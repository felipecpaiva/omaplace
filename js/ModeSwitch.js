.pragma library
// Opening a plan (design 14.4, D22, 14.8 service rules): find the plan's workspace and decide how to bring the desktop to the
// plan's mode. Pure: the service runs the commands and calls decide() again after each one with what it learned.
// Modes are Plan.planMode() names (tiled, scrolling, floating, "" for leave as is). Omarchy prints and takes "dwindle" for
// tiled, so the names are mapped both ways here.

const MODES = ["tiled", "scrolling", "floating"]
const MAX_PRESSES = 2 // one press reaches any mode (next or back); the second is only for a press that did not take
// Omarchy's toggle order with no argument ("next"): tiled, scrolling, floating, tiled; "back" goes the other way.
const NEXT = { tiled: "scrolling", scrolling: "floating", floating: "tiled" }

// "dwindle" (Omarchy's word) reads as "tiled"; anything unknown reads as "".
function fromOmarchy(text) {
  const m = String(text || "").trim()
  if (m === "dwindle") return "tiled"
  return MODES.indexOf(m) === -1 ? "" : m
}

// The mode word omarchy-hyprland-workspace-layout-set takes.
function toOmarchy(mode) { return mode === "tiled" ? "dwindle" : mode }

// s: { want, current (layout-current's output), hasSet (false once the set command is known missing), userStarted,
// tries (set or toggle runs so far) }. Returns { step: "none" | "set" | "toggle" | "skip" | "fail", reason?, direction? }:
// direction ("next" or "back", the toggle's argument) comes with "toggle".
// skip and fail both leave the mode as it is and open anyway; the reason goes into the summary.
function decide(s) {
  const want = s.want || ""
  if (want === "") return { step: "none" }
  if (MODES.indexOf(want) === -1) return { step: "fail", reason: "unknown plan mode " + want }
  const cur = fromOmarchy(s.current)
  if (cur === want) return { step: "none" }
  const tries = s.tries || 0
  if (s.hasSet !== false) return tries === 0 ? { step: "set" } : { step: "fail", reason: "the desktop is still " + (cur || "unknown") + " after layout-set" }
  if (!s.userStarted) return { step: "skip", reason: "mode left as " + (cur || "unknown") + " (at login only omarchy-hyprland-workspace-layout-set can switch it)" }
  if (cur === "") return { step: "fail", reason: "cannot read the desktop's mode" }
  if (tries >= MAX_PRESSES) return { step: "fail", reason: "the desktop is still " + cur + " after " + tries + " presses" }
  return { step: "toggle", direction: NEXT[cur] === want ? "next" : "back" }
}

// The workspace id of a plan's desktop from _G.omaplace.desktops() (design 14.8), or 0 when that monitor or slot is not
// there. An empty home_monitor means the focused monitor.
function workspaceOf(desktops, homeMonitor, homeSlot) {
  const mons = desktops && Array.isArray(desktops.monitors) ? desktops.monitors : []
  const mon = mons.find((m) => m && (homeMonitor ? m.identity === homeMonitor : m.focused === true))
  const slot = mon && Array.isArray(mon.slots) ? mon.slots.find((s) => s && s.slot === homeSlot) : null
  const ws = slot ? slot.workspace : 0
  return Number.isInteger(ws) && ws > 0 ? ws : 0
}
