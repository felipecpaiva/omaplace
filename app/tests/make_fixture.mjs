// Writes app/tests/fixture-model.json: the model the service would send (AppSeam.model), built with the plugin's own
// js/ code from made-up monitors, apps, rules, scenes and sessions. Run by bin-test before the Qt tests.
import { writeFileSync } from "node:fs"
import { load } from "../../tests/js_load.mjs"

const D = load("Desktops.js")
const Store = load("SceneStore.js")
const Seam = load("AppSeam.js")
const ConfigIO = load("ConfigIO.js")

const MON = "Example Corp EX27"
const apps = D.appChoices([
  { id: "org.example.Editor.desktop", name: "Editor", icon: "accessories-text-editor", startupClass: "org.example.Editor" },
  { id: "org.example.Chat.desktop", name: "Chat", icon: "internet-chat", startupClass: "org.example.Chat" },
  { id: "Pad.desktop", name: "Pad", execString: "xdg-terminal-exec --app-id=TUI.tile -e pad", icon: "utilities-terminal" },
  { id: "pad-app.desktop", name: "Pad", startupClass: "pad-app", icon: "text-x-generic" },
  { id: "Monitor.desktop", name: "Monitor", execString: "xdg-terminal-exec --app-id=TUI.tile -e top", icon: "utilities-system-monitor" },
  { id: "org.example.Calc.desktop", name: "Calculator", icon: "accessories-calculator", startupClass: "org.example.Calc" }
])
const win = (cls, zone, extra) => ({ app: cls, class: cls, context: "", rect: [0, 0, 0.5, 1], order: zone, floating: true,
  launch: "", folder: "", edited: "", zone, ...extra })
const doc = Store.parse(Store.serialize({ schema: 1, warnings: [], errors: [], readOnly: false, scenes: {
  "desk-2": { plan: true, layout: "columns:2", existing: "move", home_monitor: MON, home_slot: 2, key: "", saved_on: "", open_at_login: true,
    windows: [win("org.example.Editor", 1), win("org.example.Chat", 2, { rect: [0.5, 0, 0.5, 1] })] },
  "desk-laptop": { plan: true, layout: "free", existing: "move", home_monitor: "Example Panel", home_slot: 1, key: "", saved_on: "", open_at_login: false,
    windows: [win("org.example.Editor", undefined, { rect: [0, 0, 1, 1], order: 1 }), win("org.example.Chat", undefined, { rect: [0, 0, 1, 1], order: 2 })].map((w) => { delete w.zone; return w }) },
  work: { existing: "move", key: "", saved_on: "",
    windows: [win("org.example.Editor", 1, { folder: "~/projects/example", context: "?", zone: undefined })] }
} }))
const live = {
  monitors: [
    { identity: MON, name: "DP-2", focused: true, area: { x: 0, y: 30, w: 1600, h: 970 }, slots: Array.from({ length: 10 }, (_, i) => ({ slot: i + 1, workspace: 11 + i })) },
    { identity: "Example Panel", name: "eDP-1", focused: false, area: { x: 1600, y: 30, w: 1600, h: 970 }, slots: Array.from({ length: 10 }, (_, i) => ({ slot: i + 1, workspace: i + 1, ...(i === 0 ? { omagnet: { name: "columns:2", zones: "0 0 0.5 1; 0.5 0 0.5 1" } } : {}) })) }
  ],
  modes: { 1: "floating", 2: "tiled", 12: "floating", 13: "tiled" }, windows: { 12: 2, 1: 1, 13: 2 }, classes: ["org.example.Editor"],
  wsClasses: { 12: [{ cls: "org.example.Editor", at: [100, 80], size: [700, 800] }],
    13: [{ cls: "org.example.Calc", at: [40, 70], size: [500, 600] }, { cls: "TUI.tile", at: [800, 30], size: [800, 970] }],
    1: [{ cls: "org.example.Editor", at: [100, 130], size: [900, 700] }] },
  omagnet: { loaded: true, layouts: [{ name: "coding", zones: "0 0 0.7 1; 0.7 0 0.3 1" }] }
}
const desks = D.cards(live, doc, { apps, rules: {}, entries: [] })
desks.omagnet = D.omagnetLayouts(live.omagnet)
desks.reason = ""
desks.loading = false
const settings = ConfigIO.parse('schema = 1\nrestore_at_login = "ask"\napp_memory = "scene"\nignore = "steam"\n').settings
const panel = {
  ok: true, settings, menu: false, warnings: [], scenesWritable: true,
  rules: [
    { name: "editor", app: "org.example.Editor", monitor: MON, slot: 3, follow: false, enabled: true, rect: "0.5 0 0.5 1", keep_rect: true },
    { name: "chat", app: "org.example.Chat", monitor: "laptop", slot: 1, follow: true, enabled: false, rect: "", keep_rect: false }
  ],
  scenes: Object.keys(doc.scenes).map((name) => ({ name, plan: doc.scenes[name].plan === true, windows: doc.scenes[name].windows.map((w) => Object.assign({}, w,
    w.context === "?" ? { need: { kind: "folder", profiles: [] } } : {})) })),
  sessions: [
    { instance: "abc_1700000000_1", savedAt: 1700003600, windows: 6, current: true },
    { instance: "abc_1699900000_1", savedAt: 1699903600, windows: 4, current: false }
  ]
}
const model = Seam.model(panel, desks, apps, [MON, "Example Panel"], false, 1)
writeFileSync(new URL("./fixture-model.json", import.meta.url), JSON.stringify(model))
console.log("fixture-model.json: " + desks.groups.length + " monitors, " + apps.length + " apps")
