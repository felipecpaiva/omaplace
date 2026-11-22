import QtQuick
import Quickshell
import Quickshell.Io
import "js/SceneStore.js" as SceneStore
import "js/ConfigIO.js" as ConfigIO
import "js/AppResolve.js" as AppResolve
import "js/ArgFilter.js" as ArgFilter
import "js/Plan.js" as Plan
import "js/LuaLiteral.js" as LuaLiteral
import "js/Summary.js" as Summary
import "js/Settings.js" as Settings
import "js/MenuExt.js" as MenuExt
import "js/MovesFeed.js" as MovesFeed
import "js/AutoMove.js" as AutoMove
import "js/LuaCall.js" as LuaCall
import "js/PlansFile.js" as PlansFile
import "js/PlanMoves.js" as PlanMoves
import "js/ModeSwitch.js" as ModeSwitch
import "js/Desktops.js" as Desktops
import "js/AppSeam.js" as AppSeam

// omaplace service (design 4.3, 6.2, 6.3, 7.2): the CLI's IPC target and the only file that runs processes.
// All data work goes through the js/ modules. One slow request (save, open, rule add) runs at a time; every other
// request answers busy meanwhile, so two writers never race on scenes.toml or config.toml.
// Idle cost: no timer armed, no process running. Files watched: moves.json only while app_memory is "auto"; always
// scenes.toml (to rebuild plans.lua) and login.json (desktop plans, WP12b; Lua sends the plan move notifications itself). While a request runs: two
// one-shot timers (the 2 s Lua check and request_timeout_s) and a watch on status.json during an open.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omaplace"
  readonly property string configDir: root.home + "/.config/omaplace"
  readonly property string stateDir: root.home + "/.local/state/omaplace"
  readonly property string procinfoPath: Summary.fromUrl(Qt.resolvedUrl("libexec/procinfo.sh"))

  property int counter: 0
  property bool dirsReady: false
  property bool watching: false
  // The request in flight: { id, kind: save | open | rule, name, run, cls, capture, resolved, terms, queue, retried, seen, other }
  property var req: null
  property string writeError: ""

  // Settings window (WP6) state: live monitor names, the folder chooser, and a counter the window watches for answers
  // that arrive later (chooser, monitors).
  property var liveMonitors: []
  property bool picking: false
  property var pickTarget: null
  property bool pickStarted: false
  property int revision: 0
  property string lastAnswer: ""

  // Launcher entry (WP6), like omagnet's: written at load, removed at unload, and only ever over a file with our marker.
  readonly property string launcherSource: Summary.fromUrl(Qt.resolvedUrl("omaplace.desktop"))
  readonly property string launcherDest: root.home + "/.local/share/applications/omaplace.desktop"
  readonly property string launcherMarker: "X-Omaplace-Managed=true"
  property bool launcherInstalled: false

  // Omarchy menu rows (WP8): written only from the settings window's button, never at load, with a backup first.
  readonly property string menuPath: root.home + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  readonly property string cliPath: Summary.fromUrl(Qt.resolvedUrl("bin/omaplace"))

  // Auto app memory (WP10): on while app_memory is "auto"; the highest moves.json `at` already handled.
  property bool autoMemory: false
  property real lastMovesAt: -1
  // The result file of the request before this one: deleted when the next one ends (the CLI read it long before).
  property string lastResultPath: ""

  // Desktop plans (WP12b, design 14.8). plansText: what plans.lua holds now (a rewrite with the same text is skipped).
  // plansBusy/plansAgain: one reload_plans call at a time, one more if a write came meanwhile.
  // notices: notification argv lists waiting for noticeProc (open summaries), so none is dropped. loginQueue: plans
  // still to open at login, one request after another. chainNext: the callback of the running mode switch command.
  property string plansText: ""
  property bool plansBusy: false
  property bool plansAgain: false
  property var notices: []
  property bool noticeBusy: false
  property var loginQueue: []
  // Login work in flight in this service. The markers are written only once that work is done: the shell can rebuild
  // its plugins right after login (seen live 2026-11-22, 0.5 s after start), and a marker written first would leave the
  // new service copy with nothing to do.
  property bool loginBusy: false
  property bool restoreBusy: false
  property var chainNext: null
  property int chainToken: 0
  readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""

  // Desktops page (WP13): the live desktops, read only when the page asks (desktopsInfo), never on a timer.
  // desktopsLive: { monitors (Lua desktops()), modes: { workspace: tiled | scrolling | floating }, windows: { workspace: count },
  // classes (open window classes, to confirm a planned app's class), reason }. deskBusy/deskAgain: one read at a time, one
  // more if asked meanwhile. deskModes: workspaces still to ask. deskGen: the read the desk* processes belong to (an answer
  // of an older read is dropped). deskStarted: when the read began; one older than 10 s counts as stuck (no timer).
  property int deskGen: 0
  property real deskStarted: 0
  property var desktopsLive: ({})
  property bool deskBusy: false
  property bool deskAgain: false
  property int deskCounter: 0
  property string deskId: ""
  property var deskNext: ({})
  property var deskModes: []

  // DesktopEntries is lazy: the first read is empty, so it is touched at load (no process, no timer).
  // The folders come first: plans.lua and the login marker are written once mkdirProc is done.
  Component.onCompleted: { let touch = DesktopEntries.applications.values.length; root.installLauncher(); root.markMoves(); root.refreshAuto(); mkdirProc.running = true }
  // find deletes the file only when grep finds the marker line in it: argv only, no shell.
  Component.onDestruction: {
    if (root.launcherInstalled)
      Quickshell.execDetached(["find", root.launcherDest, "-maxdepth", "0", "-type", "f", "-exec", "grep", "-qx", root.launcherMarker, "{}", ";", "-delete"])
  }

  IpcHandler {
    target: "io.github.felipecpaiva.omaplace"

    function save(name: string): string { return root.startSave(name) }
    function open(name: string): string { return root.startOpen(name) }
    function openPlan(name: string): string { return root.startOpen(name) }
    function planUpdate(id: string): string { return root.planUpdate(id) }
    function restore(gen: string): string { return root.startRestore(gen) }
    function list(): string { return root.listScenes() }
    function rename(fromName: string, toName: string): string { return root.renameScene(fromName, toName) }
    function remove(name: string): string { return root.removeScene(name) }
    function ruleAddFocused(): string { return root.startRuleAdd() }
    function ruleRemove(name: string): string { return root.removeRule(name) }
    function status(): string { return root.statusLine() }
    function settings(): string { return root.toggleSettings() }
    // the settings app (design 17): one request file in, one reply file out; the model is pushed while the app is open
    function app(id: string): string { return root.appRequest(id) }
    function appModel(): string { return root.appModelNow() }
  }

  // ---- files

  function readNow(view) { view.reload(); view.waitForJob(); return view.text() || "" }

  function writeScenes(oldText, text) {
    root.writeError = ""
    if (oldText !== "") bakScenes.setText(oldText)
    if (root.writeError === "") scenesFile.setText(text)
    if (root.writeError === "") root.writePlans(text)
    return root.writeError
  }

  function writeConfig(oldText, text) {
    root.writeError = ""
    if (oldText !== "") bakConfig.setText(oldText)
    if (root.writeError === "") configFile.setText(text)
    if (root.writeError === "" && !reloadProc.running) reloadProc.running = true
    let err = root.writeError
    root.refreshAuto() // may write scenes.toml, which resets writeError
    return err
  }

  function config() { return ConfigIO.parse(root.readNow(configFile)) }
  function strategies(cfg) { return AppResolve.mergeStrategies(cfg.strategies) }
  function entries() { return Summary.entryList(DesktopEntries.applications.values) }
  function fail(code, reason) { let r = { ok: false, code: code }; if (reason) r.reason = reason; return r }

  // A scenes document that is safe to rewrite whole, or an error answer.
  function writableScenes() {
    let text = root.readNow(scenesFile)
    let doc = SceneStore.parse(text)
    if (doc.readOnly) return { error: root.fail("failed", "scenes.toml has a newer schema") }
    if (doc.errors.length > 0) return { error: root.fail("failed", doc.errors[0].code === "bad_plan" ? "scenes.toml: plan " + doc.errors[0].name + ": " + doc.errors[0].reason + ", fix it first" : "scenes.toml has a scene with a bad name, fix it first") }
    return { doc: doc, text: text }
  }

  // ---- immediate methods

  function listScenes() {
    try {
      return Summary.answer({ ok: true, scenes: Summary.sceneList(SceneStore.parse(root.readNow(scenesFile))) })
    } catch (e) { return Summary.answer(root.fail("failed")) }
  }

  function renameScene(fromName, toName) {
    if (root.req) return Summary.answer(root.fail("busy"))
    if (!Summary.validName(fromName) || !Summary.validName(toName)) return Summary.answer(root.fail("bad_name"))
    try {
      let w = root.writableScenes()
      if (w.error) return Summary.answer(w.error)
      if (!w.doc.scenes[fromName]) return Summary.answer(root.fail("not_found"))
      if (w.doc.scenes[toName]) return Summary.answer(root.fail("bad_name", "a scene with that name exists"))
      let scenes = {}
      for (let k in w.doc.scenes) scenes[k === fromName ? toName : k] = w.doc.scenes[k]
      w.doc.scenes = scenes
      let err = root.writeScenes(w.text, SceneStore.serialize(w.doc))
      return Summary.answer(err === "" ? { ok: true } : root.fail("failed", err))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  function removeScene(name) {
    if (root.req) return Summary.answer(root.fail("busy"))
    if (!Summary.validName(name)) return Summary.answer(root.fail("bad_name"))
    try {
      let w = root.writableScenes()
      if (w.error) return Summary.answer(w.error)
      if (!w.doc.scenes[name]) return Summary.answer(root.fail("not_found"))
      delete w.doc.scenes[name]
      let err = root.writeScenes(w.text, SceneStore.serialize(w.doc))
      return Summary.answer(err === "" ? { ok: true } : root.fail("failed", err))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  function removeRule(name) {
    if (root.req) return Summary.answer(root.fail("busy"))
    try {
      let text = root.readNow(configFile)
      if (!ConfigIO.parse(text).rules[name]) return Summary.answer(root.fail("not_found"))
      let err = root.writeConfig(text, ConfigIO.removeRule(text, name))
      return Summary.answer(err === "" ? { ok: true } : root.fail("failed", err))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  function statusLine() {
    let st = Summary.parseJson(root.readNow(statusFile)) || {}
    let items = Array.isArray(st.items) ? st.items.length : 0
    return Summary.answer({ ok: true, busy: root.req !== null, run: st.run || "", state: st.state || "idle", items: items })
  }

  function toggleSettings() {
    if (!settingsProc.running) settingsProc.running = true
    return Summary.answer({ ok: true })
  }

  // ---- slow requests: answer pending now, write result-<req>.json later

  function begin(kind, fields) {
    if (root.req) return Summary.answer(root.fail("busy"))
    root.rescanScenes() // so a run of a hand-made first scenes.toml is tracked by its plan
    root.counter++
    let r = fields || {}
    r.id = "q" + root.counter + "-" + Date.now()
    r.kind = kind
    root.req = r
    // half a second inside the CLI's own limit, so the CLI reads our timeout result instead of giving up first
    deadline.interval = Math.max(500, root.config().settings.request_timeout_s * 1000 - 500)
    deadline.restart()
    if (root.dirsReady) root.step()
    else mkdirProc.running = true
    return Summary.answer({ ok: true, pending: true, req: r.id })
  }

  function startSave(name) {
    if (!Summary.validName(name)) return Summary.answer(root.fail("bad_name"))
    return root.begin("save", { name: name })
  }

  function startRuleAdd() { return root.begin("rule", {}) }

  function startOpen(name) {
    if (!Summary.validName(name)) return Summary.answer(root.fail("bad_name"))
    if (root.req) return Summary.answer(root.fail("busy"))
    let scene = SceneStore.parse(root.readNow(scenesFile)).scenes[name]
    if (!scene) return Summary.answer(root.fail("not_found"))
    if (scene.planError) return Summary.answer(root.fail("failed", "plan " + name + ": " + scene.planError))
    // A plan opens on its own desktop after the mode switch (design 14.8); `user`: started by a person, not by login.
    return root.begin("open", { name: name, scene: scene, plan: scene.plan === true, user: true })
  }

  // Restore (design 6.5): one session plan; Lua sends each window to its own monitor and desktop. The rest of the flow is open's.
  function startRestore(gen) {
    if (root.req) return Summary.answer(root.fail("busy"))
    try {
      let current = Summary.instanceName(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "")
      let instance = Summary.pickSession(Summary.parseJson(root.readNow(sessionsFile)), current, String(gen || ""))
      if (instance === "") return Summary.answer(root.fail("not_found", "no previous session"))
      if (!/^[A-Za-z0-9_]{1,128}$/.test(instance)) return Summary.answer(root.fail("failed", "sessions.json names a bad instance"))
      sessionFile.path = root.stateDir + "/session-" + instance + ".json"
      let snap = Summary.parseJson(root.readNow(sessionFile))
      if (!snap || !Array.isArray(snap.windows) || snap.windows.length === 0) return Summary.answer(root.fail("not_found", "that session has no windows"))
      return root.begin("open", { name: "last session", snapshot: snap })
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  function launchesFor(wins, cfg) {
    let table = root.strategies(cfg), list = root.entries(), queues = {}
    return wins.map(function (w) {
      let ctx = w.context || root.guessProfile(w.class, table, queues)
      return AppResolve.resolve(w.class, list, table, { context: ctx, folder: w.folder, launch: w.launch, home: root.home })
    })
  }

  // A profile for a browser window saved without one (Settings.profileQueue); "" for any other app. queues: one per
  // browser folder for this launch list, so two windows get the two profiles that were open.
  function guessProfile(cls, table, queues) {
    let r = AppResolve.resolve(cls, [], table, { context: "?" })
    let dir = r.contextKind === "profile" ? Settings.profileDir(r.strategy) : ""
    if (dir === "") return ""
    if (!queues[dir]) {
      localStateFile.path = root.home + "/.config/" + dir + "/Local State"
      queues[dir] = Settings.profileQueue(root.readNow(localStateFile))
      localStateFile.path = ""
    }
    return Settings.nextProfile(queues[dir])
  }

  function step() {
    let r = root.req
    if (!r) return
    if (r.kind === "rule") activeProc.running = true
    else if (r.kind === "save") root.evalCapture()
    else if (r.plan) root.planDesktops()
    else root.writePlan()
  }

  function evalCapture() {
    evalProc.command = ["hyprctl", "eval", LuaCall.wrap("capture", [LuaLiteral.encode(root.req.id), "\"focused\""], LuaLiteral.encode(root.replyPath()))]
    evalProc.running = true
  }

  function writePlan() {
    let r = root.req
    try {
      let cfg = root.config()
      r.run = "r" + root.counter + "-" + Date.now()
      // a re-place (r.replace) waits 1 s at most: windows that are closed are not coming
      let plan = r.snapshot
        ? Plan.fromSession(r.snapshot, root.launchesFor(r.snapshot.windows, cfg), { run: r.run, expiry_s: cfg.settings.expiry_seconds })
        : Plan.fromScene(r.scene, r.replace ? r.scene.windows.map(function () { return { mode: "place_only" } }) : root.launchesFor(r.scene.windows, cfg),
          Object.assign(Summary.planTarget(r.scene, r.run, r.replace ? 1 : cfg.settings.expiry_seconds), { scene: r.name }), cfg.rules)
      if (r.replace) plan.only_tracked = true // only the windows Lua tracks for this plan, never another of the same app
      r.planPath = root.runtimeDir + "/plan-" + r.run + ".lua"
      planFile.path = r.planPath
      planFile.setText("return " + LuaLiteral.encode(plan) + "\n")
    } catch (e) { root.finish(root.fail("failed", String(e.message || e))) }
  }

  // text: what hyprctl printed (LuaCall's answer). A missing module or an error Lua returned at once ends the request now;
  // an answer we cannot read falls back to the status watch and the 2 s check.
  function afterEval(text) {
    let r = root.req
    if (!r) return
    let c = LuaCall.code(text)
    if (c === "no_lua") { root.finish(root.fail("no_lua")); return }
    if (c !== "" && c !== "ok") { root.finish(c === "busy" ? root.fail("busy") : root.fail("failed", c)); return }
    r.luaOk = c === "ok"
    if (r.kind === "open") {
      r.evaluated = true
      root.watching = true
      luaCheck.restart()
      root.onStatus(root.readNow(statusFile))
    } else {
      root.readCapture()
    }
  }

  function replyPath() { return root.runtimeDir + "/reply-" + root.req.id + ".txt" }

  function readReply() {
    if (!root.req) return
    replyProc.command = ["cat", "--", root.replyPath()]
    replyProc.running = true
  }

  function readCapture() {
    catProc.command = ["cat", root.runtimeDir + "/capture-" + root.req.id + ".json"]
    catProc.running = true
  }

  // Lua writes the capture before hyprctl eval returns; give it 2 s more once, then the module is missing.
  function onCaptureText(text) {
    let r = root.req
    if (!r) return
    let cap = Summary.parseJson(text)
    if (!cap) {
      if (r.retried) { root.finish(r.luaOk ? root.fail("failed", "no capture from the Lua module") : root.fail("no_lua")); return }
      r.retried = true
      luaCheck.restart()
      return
    }
    luaCheck.stop()
    r.capture = cap
    try {
      let cfg = root.config()
      r.cfgText = root.readNow(configFile)
      if (r.kind === "rule") { root.finishRule(cfg); return }
      let table = root.strategies(cfg), list = root.entries()
      let wins = Array.isArray(cap.windows) ? cap.windows : []
      r.resolved = wins.map(function (w) { return AppResolve.resolve(w.class, list, table, { context: w.context }) })
      r.terms = []
      r.queue = []
      for (let i = 0; i < wins.length; i++) {
        if (Summary.isTerminal(r.resolved[i], table) && wins[i].pid > 0) r.queue.push(i)
      }
      root.nextProcinfo()
    } catch (e) { root.finish(root.fail("failed", String(e.message || e))) }
  }

  function nextProcinfo() {
    let r = root.req
    if (!r) return
    if (r.queue.length === 0) { root.finishSave(); return }
    r.current = r.queue.shift()
    procProc.command = ["bash", root.procinfoPath, String(r.capture.windows[r.current].pid)]
    procProc.running = true
  }

  function onProcinfo(text) {
    let r = root.req
    if (!r) return
    let info = Summary.parseJson(text) || {}
    r.terms[r.current] = Summary.terminalFields(info, ArgFilter.filter(info.argv || []), root.home)
    root.nextProcinfo()
  }

  function finishSave() {
    let r = root.req
    try {
      let sc = Summary.sceneCapture(r.capture, r.resolved, r.terms, root.strategies(root.config()))
      if (sc.capture.windows.length === 0) { root.finish(root.fail("empty", "nothing to save on this desktop")); return }
      let w = root.writableScenes()
      if (w.error) { root.finish(w.error); return }
      w.doc.scenes[r.name] = SceneStore.mergeCapture(w.doc.scenes[r.name], sc.capture)
      let err = root.writeScenes(w.text, SceneStore.serialize(w.doc))
      if (err !== "") { root.finish(root.fail("failed", err)); return }
      let res = sc.counts
      res.ok = true
      root.finish(res)
    } catch (e) { root.finish(root.fail("failed", String(e.message || e))) }
  }

  function finishRule(cfg) {
    let r = root.req
    let rule = Summary.ruleFromCapture(r.capture, r.cls)
    if (!rule) { root.finish(root.fail("not_found", "the focused window is not on a desktop omaplace can name")); return }
    let err = root.writeConfig(r.cfgText, ConfigIO.setRule(r.cfgText, rule.name, rule.rule))
    root.finish(err === "" ? { ok: true, rule: rule.name } : root.fail("failed", err))
  }

  function onStatus(text) {
    let r = root.req
    if (!r || r.kind !== "open" || !r.evaluated) return
    let st = Summary.parseJson(text)
    if (!st) return
    if (st.run !== r.run) { r.other = st.state === "running"; return }
    r.seen = true
    luaCheck.stop()
    let res = Summary.runResult(st, r.run)
    if (res) root.finish(res)
  }

  function onLuaCheck() {
    let r = root.req
    if (!r) return
    if (r.kind === "open") {
      if (!r.seen) root.finish(r.other ? root.fail("busy") : r.luaOk ? root.fail("failed", "no status from the Lua module") : root.fail("no_lua"))
    }
    else root.readCapture()
  }

  // Ends the request: exactly one result file, timers and watch off, busy cleared. An open also tells the user.
  function finish(res) {
    let r = root.req
    if (!r) return
    if (r.loginRestore) restoreMarker.setText("auto\n")
    deadline.stop()
    luaCheck.stop()
    root.watching = false
    root.req = null
    // A mode switch command still running belongs to this request: stop it, and its late answer finds no callback.
    root.chainToken++
    root.chainNext = null
    chainRun.running = false
    chainOut.running = false
    chainCat.running = false
    // Spent files of this request (plans hold launch arguments) and the previous result. Paths come from our own ids.
    let spent = []
    if (r.planPath) spent.push(r.planPath)
    if (r.kind !== "open") spent.push(root.runtimeDir + "/capture-" + r.id + ".json")
    if (r.plan) spent.push(root.runtimeDir + "/desktops-" + r.id + ".json", root.runtimeDir + "/reply-" + r.id + "-desktops.txt")
    spent.push(root.runtimeDir + "/reply-" + r.id + ".txt")
    if (root.lastResultPath !== "") spent.push(root.lastResultPath)
    if (spent.length > 0) Quickshell.execDetached(["rm", "-f", "--"].concat(spent))
    if (r.modeNote) res.note = r.modeNote
    resultFile.path = root.runtimeDir + "/result-" + r.id + ".json"
    root.lastResultPath = resultFile.path
    resultFile.setText(Summary.answer(res) + "\n")
    // a re-place after "Update plan" that ran is not news (the CLI already said "plan updated"); one that failed is
    if (r.kind === "open" && (!r.replace || !res.state)) {
      let text =(res.state ? Summary.notifyText(res) : "could not open (" + res.code + ")") + (r.modeNote ? "; " + r.modeNote : "")
      root.notices.push(["omarchy-notification-send", "omaplace: " + r.name, text])
      root.nextNotice()
    }
    root.rescanScenes()
    root.refreshAuto()
    // The login.json watch can miss a file replaced by rename, so every request end reads it again.
    root.checkLogin()
    root.nextLogin()
  }

  // ---- auto app memory (WP10): moves Lua reported between scene desktops go into scenes.toml

  // At load: events already in moves.json were handled by an earlier shell (or happened while it was down) and are
  // never replayed. A replay could move a second window of the same class, since AutoMove matches by class and context.
  function markMoves() { root.lastMovesAt = MovesFeed.pending(root.readNow(movesFile), -1).maxAt }

  function refreshAuto() {
    try { root.autoMemory = root.config().settings.app_memory === "auto" } catch (e) { root.autoMemory = false }
    root.applyMoves()
  }

  // Runs when moves.json changes and after every request ends (the watch can miss a rename, design live lesson).
  // Never while a request runs: finish() calls it again. Writes scenes.toml only when an event was applied.
  function applyMoves() {
    if (!root.autoMemory || root.req) return
    try {
      let p = MovesFeed.pending(root.readNow(movesFile), root.lastMovesAt)
      if (p.events.length === 0) { root.lastMovesAt = p.maxAt; return }
      let w = root.writableScenes()
      if (w.error) { console.warn("omaplace: auto moves not applied: " + w.error.reason); return }
      let res = AutoMove.apply(w.doc, p.events)
      for (let s of res.skipped) {
        if (s.reason !== "already applied") console.log("omaplace: auto move skipped: " + s.class + ", " + s.reason)
      }
      if (res.applied > 0) {
        let err = root.writeScenes(w.text, SceneStore.serialize(res.doc))
        if (err !== "") { console.warn("omaplace: auto moves not applied: " + err); return }
      }
      root.lastMovesAt = p.maxAt
    } catch (e) { console.warn("omaplace: auto moves not applied: " + String(e.message || e)) }
  }

  // ---- desktop plans (WP12b, design 14.7, 14.8)

  // shortcut: a watch is re-armed after each change because a file replaced by rename drops it (live-M1); if a live check
  // shows changes still lost, login.json is also read after every reload_plans and request end (polling is not allowed).
  function rearm(view) { view.watchChanges = false; view.watchChanges = true }

  // plans.lua, derived from the plan = true scenes; Lua reloads it through reload_plans. text: scenes.toml, read when absent.
  // Returns true when it wrote (and so started a reload).
  function writePlans(text) {
    if (!root.dirsReady) return false // mkdirProc calls this again once the state folder exists
    try {
      let b = PlansFile.build(SceneStore.parse(text === undefined ? root.readNow(scenesFile) : text))
      if (b.error) { console.warn("omaplace: " + b.error); return false }
      if (b.text === root.plansText) return false
      for (let s of b.skipped) console.warn("omaplace: plan " + s.scene + " not snapped: " + s.reason)
      root.plansText = b.text
      plansFile.setText(b.text)
      return root.plansText !== "" // onSaveFailed clears it
    } catch (e) { console.warn("omaplace: plans.lua not written: " + String(e.message || e)) }
    return false
  }

  // A scenes.toml made after the service started is never seen by the watch (a watch on a missing file never fires,
  // live-M5). No polling: every request end and every settings window open read it again (writePlans writes only when
  // the plans changed) and arm the watch again, now that the file may exist.
  function rescanScenes() {
    root.writePlans()
    root.rearm(scenesFile)
  }

  function reloadPlans() {
    if (root.plansBusy) { root.plansAgain = true; return }
    root.plansBusy = true
    root.plansAgain = false
    plansEval.command = ["hyprctl", "eval", LuaCall.wrap("reload_plans", [], LuaLiteral.encode(root.runtimeDir + "/reply-plans.txt"))]
    plansEval.running = true
  }

  function afterReloadPlans(text) {
    root.plansBusy = false
    let c = LuaCall.code(text)
    if (c !== "ok") console.warn("omaplace: reload_plans: " + (c || "no answer"))
    if (root.plansAgain) root.reloadPlans()
    else Quickshell.execDetached(["rm", "-f", "--", root.runtimeDir + "/reply-plans.txt"]) // the next call writes a new one
    root.checkLogin() // reload_plans is also Lua's retry of its login.json write
  }

  function nextNotice() {
    if (root.noticeBusy || root.notices.length === 0) return
    root.noticeBusy = true
    noticeProc.command = root.notices.shift()
    noticeProc.running = true
  }

  // "Update plan": write the move's new place into its plan (PlanMoves.edit), with the same guards as every scenes write.
  function planUpdate(id) {
    if (root.req) return Summary.answer(root.fail("busy"))
    if (!/^[0-9]{1,9}$/.test(String(id))) return Summary.answer(root.fail("not_found"))
    try {
      let m = PlanMoves.find(PlanMoves.parse(root.readNow(planMovesFile)), Number(id))
      if (!m) return Summary.answer(root.fail("not_found", "that move is no longer in the list"))
      let w = root.writableScenes()
      if (w.error) return Summary.answer(w.error)
      let e = PlanMoves.edit(w.doc, m)
      if (e.code) return Summary.answer(root.fail(e.code, e.reason))
      let err = e.changed ? root.writeScenes(w.text, SceneStore.serialize(e.doc)) : ""
      if (err !== "") return Summary.answer(root.fail("failed", err))
      // a swap (D24): the plan's open windows go to their new zones; place_only never starts a closed one
      let res = { ok: true, scene: e.scene || m.scene, changed: e.changed }
      if (e.removed) res.removed = e.removed
      if (e.replace) {
        let b = Summary.parseJson(root.begin("open", { name: m.scene, scene: Object.assign({}, e.doc.scenes[m.scene], { existing: "move" }), replace: true }))
        if (!b || b.ok !== true) res.note = "windows not moved: " + ((b && b.code) || "failed")
      }
      return Summary.answer(res)
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  // Open at login (design 14.8): Lua lists the ticked plans once per Hyprland instance; the marker in the runtime folder
  // keeps a shell restart from opening them again. The marker is written before the first open.
  function checkLogin() {
    if (!root.dirsReady || !/^[A-Za-z0-9_]{1,128}$/.test(root.instance)) return
    let login = Summary.parseJson(root.readNow(loginFile))
    if (!login || login.instance !== root.instance || !Array.isArray(login.plans)) return
    if (root.loginBusy || root.readNow(markerFile) !== "") return
    root.loginBusy = true
    root.loginQueue = root.loginQueue.concat(login.plans.filter(function (n) { return typeof n === "string" && Summary.validName(n) }))
    root.nextLogin()
  }

  // Restore at login (D26): once per Hyprland instance (its own marker, so the plans' marker does not hide it), only
  // when the instance is a fresh login (Summary.loginRestore). "ask" sends one notification with a Restore button;
  // "auto" queues the restore first, so login plans opened after it keep their own desktops.
  function checkRestore() {
    if (!root.dirsReady || !/^[A-Za-z0-9_]{1,128}$/.test(root.instance)) return
    if (root.restoreBusy || root.readNow(restoreMarker) !== "") return
    let mode = ""
    try { mode = root.config().settings.restore_at_login } catch (e) { return }
    let d = Summary.loginRestore(mode, root.instance, Math.floor(Date.now() / 1000), Summary.parseJson(root.readNow(sessionsFile)))
    if (d.action === "none") return
    root.restoreBusy = true
    if (d.action === "auto") {
      root.loginQueue = [{ restore: true }].concat(root.loginQueue)
      root.nextLogin()
      return
    }
    let bin = root.launcherSource.slice(0, root.launcherSource.lastIndexOf("/")) + "/bin/omaplace"
    // its own process, so the marker is written only once the notification is out (the command returns at once; the
    // shell runs the button's command)
    restoreAsk.command = ["omarchy-notification-send", "-g", "\u{F0770}", "omaplace", "Restore the windows of your last session?",
      "--action", "Restore", bin, "restore"]
    restoreAsk.running = true
  }

  // The next login plan, when no request runs (finish() calls this again). Each is checked again against scenes.toml.
  function nextLogin() {
    while (!root.req && root.loginQueue.length > 0) {
      let name = root.loginQueue.shift()
      if (typeof name === "object") { // the restore of D26: its marker once it has run (finish), or now when it cannot
        root.startRestore("")
        if (root.req) { root.req.loginRestore = true; return }
        restoreMarker.setText("auto\n")
        continue
      }
      let scene = SceneStore.parse(root.readNow(scenesFile)).scenes[name]
      if (!scene || scene.plan !== true || scene.open_at_login !== true || scene.planError) { console.log("omaplace: login plan skipped: " + name); continue }
      root.begin("open", { name: name, scene: scene, plan: true, user: false })
      return
    }
    if (!root.req && root.loginQueue.length === 0 && root.loginBusy) { markerFile.setText("done\n"); root.loginBusy = false }
  }

  // ---- opening a plan: desktops(), then the mode switch (ModeSwitch.decide), then writePlan(). One command at a time;
  // a callback whose request already ended does nothing.

  function chain(proc, cmd, next) {
    let token = ++root.chainToken
    root.chainNext = function (v) { if (root.chainToken === token && root.req) next(v) }
    proc.command = cmd
    proc.running = true
  }

  function desktopsPath() { return root.runtimeDir + "/desktops-" + root.req.id + ".json" }
  function desktopsReply() { return root.runtimeDir + "/reply-" + root.req.id + "-desktops.txt" }

  function planDesktops() {
    let r = root.req
    r.tries = 0
    r.want = Plan.planMode(r.scene.layout)
    if (r.want === "") { root.writePlan(); return } // full leaves the mode as it is
    // desktops(req_id) writes desktops-<req_id>.json (like capture); one cat reads the reply code and that file together.
    root.chain(chainRun, ["hyprctl", "eval", LuaCall.wrap("desktops", [LuaLiteral.encode(r.id)], LuaLiteral.encode(root.desktopsReply()))], function () {
      root.chain(chainCat, ["cat", "--", root.desktopsReply(), root.desktopsPath()], root.onDesktops)
    })
  }

  function onDesktops(text) {
    let r = root.req
    let c = LuaCall.code(text)
    if (c === "no_lua") { root.finish(root.fail("no_lua")); return }
    let brace = text.indexOf("{")
    r.ws = ModeSwitch.workspaceOf(c === "ok" && brace !== -1 ? Summary.parseJson(text.slice(brace)) : null, r.scene.home_monitor || "", r.scene.home_slot)
    if (r.ws === 0) {
      r.modeNote = "mode not switched: " + (c === "ok" ? "the plan's desktop is not there" : "no desktop list from the Lua module (" + (c || "no answer") + ")")
      root.writePlan()
      return
    }
    root.readMode()
  }

  function readMode() { root.chain(chainOut, ["omarchy-hyprland-workspace-layout-current", String(root.req.ws)], root.onMode) }

  function onMode(text) {
    let r = root.req
    let d = ModeSwitch.decide({ want: r.want, current: text, hasSet: r.hasSet, userStarted: r.user, tries: r.tries })
    if (d.step === "set") {
      // env exits 127 when the command is not installed: then the toggle fallback decides. Caveat: a set command that is
      // installed but itself exits 127 (a program it runs is missing) also reads as not installed; the fallback still verifies
      root.chain(chainRun, ["env", "omarchy-hyprland-workspace-layout-set", String(r.ws), ModeSwitch.toOmarchy(r.want)], function (code) {
        if (code === 127) r.hasSet = false
        else r.tries++
        root.readMode()
      })
    } else if (d.step === "toggle") {
      r.direction = d.direction
      // the toggle cycles the focused desktop only: focus it, and press only when the focus really moved there
      root.chain(chainRun, ["hyprctl", "eval", "hl.dispatch(hl.dsp.focus({ workspace = \"" + r.ws + "\" }))"], function () {
        root.chain(chainOut, ["hyprctl", "activeworkspace", "-j"], root.onFocused)
      })
    } else {
      if (d.reason) r.modeNote = "mode not switched: " + d.reason
      root.writePlan()
    }
  }

  function onFocused(text) {
    let r = root.req
    let w = Summary.parseJson(text)
    if (!w || w.id !== r.ws) { r.modeNote = "mode not switched: desktop " + r.ws + " did not take the focus"; root.writePlan(); return }
    root.chain(chainRun, ["omarchy-hyprland-workspace-layout-toggle", r.direction], function () { r.tries++; root.readMode() })
  }

  // ---- Omarchy menu rows (WP8). Only the settings window's button calls these.

  function menuInstalled() { return MenuExt.hasRows(root.readNow(menuFile)) }

  function menuAdd() {
    try {
      let text = root.readNow(menuFile)
      let r = MenuExt.addRows(text, root.cliPath)
      if (!r.ok) return Summary.answer(root.fail("failed", r.why))
      root.writeError = ""
      if (text !== "") menuBak.setText(text)
      if (root.writeError === "") menuFile.setText(r.text)
      return Summary.answer(root.writeError === "" ? { ok: true } : root.fail("failed", root.writeError))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  // Takes out only our block; the backup from menuAdd is left as it was.
  function menuRemove() {
    try {
      let text = root.readNow(menuFile)
      let r = MenuExt.removeRows(text)
      if (!r.ok) return Summary.answer(root.fail("failed", r.why))
      if (r.text === text) return Summary.answer({ ok: true })
      root.writeError = ""
      menuFile.setText(r.text)
      return Summary.answer(root.writeError === "" ? { ok: true } : root.fail("failed", root.writeError))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  // ---- settings window (WP6). Plain functions the panel calls; it never writes a file itself. Each write uses the same
  // guards as above (busy, writableScenes, try/catch) and goes through writeConfig (which also tells Lua to reload) or
  // writeScenes (with the .bak first).

  function installLauncher() {
    if (root.launcherSource === "" || root.home === "") return
    let want = root.readNow(launcherSourceFile)
    if (want.indexOf(root.launcherMarker) === -1) return
    // The icon ships in the plugin folder, so the installed entry names it by full path (no install step outside it).
    let dir = root.launcherSource.slice(0, root.launcherSource.lastIndexOf("/"))
    want = want.replace(/^Icon=omaplace$/m, "Icon=" + dir + "/branding/logo/icon-256.png")
    let have = root.readNow(launcherFile)
    if (have !== "" && have.indexOf(root.launcherMarker) === -1) return // a file of the user's own: never written over
    root.launcherInstalled = true
    // shortcut: FileView does not create ~/.local/share/applications; it exists on Omarchy, add a mkdir if a report says otherwise
    if (have !== want) launcherFile.setText(want)
  }

  // A fresh install has no ~/.config/omaplace until the first slow request; the window calls this when it opens.
  function ensureDirs() { if (!root.dirsReady && !root.req && !mkdirProc.running) mkdirProc.running = true }

  function refreshMonitors() { if (!monitorsProc.running) monitorsProc.running = true }

  // ---- the settings app (design 17, D37, D38)

  property bool appAttached: false
  property int appSeq: 0

  function appModelNow() {
    root.appAttached = true
    root.ensureDirs()
    root.refreshMonitors()
    root.desktopsInfo()
    root.rescanScenes()
    root.pushModel()
    return Summary.answer({ ok: true, contract: AppSeam.CONTRACT })
  }

  function modelNow() {
    return AppSeam.model(root.panelData(), root.desktopCards(), root.appChoices(), root.req !== null, ++root.appSeq)
  }

  function pushModel() {
    if (!root.appAttached || !root.dirsReady) return
    let m = root.modelNow()
    // a late answer (the folder chooser) rides on the next model once
    if (root.lastAnswer !== "") { m.late = Summary.parseJson(root.lastAnswer); root.lastAnswer = "" }
    appOutFile.path = root.runtimeDir + "/app-model.json"
    appOutFile.setText(JSON.stringify(m) + "\n")
  }

  function appRequest(id) {
    if (!AppSeam.validId(id)) return Summary.answer(root.fail("bad_request"))
    root.appAttached = true
    appReqFile.path = root.runtimeDir + "/app-" + id + ".json"
    let text = root.readNow(appReqFile)
    appReqFile.path = ""
    Quickshell.execDetached(["rm", "-f", "--", root.runtimeDir + "/app-" + id + ".json"])
    let r = AppSeam.parse(text)
    let answer = r.error ? Summary.answer(root.fail(r.error)) : root.appOp(r.op, r.args)
    appOutFile.path = root.runtimeDir + "/app-" + id + "-reply.json"
    appOutFile.setText(AppSeam.reply(id, answer, root.modelNow()))
    return answer
  }

  // The allow-listed ops (AppSeam.OPS): each is the function the panel called.
  function appOp(op, a) {
    switch (op) {
    case "refresh": root.refreshMonitors(); root.desktopsInfo(); root.rescanScenes(); return Summary.answer({ ok: true })
    case "open": return root.startOpen(a[0])
    case "rename": return root.renameScene(a[0], a[1])
    case "removeScene": return root.removeScene(a[0])
    case "setWindow": return root.setSceneWindow(a[0], a[1], a[2], a[3], a[4])
    case "pickFolder": return root.pickFolder(a[0], a[1], a[2])
    case "ruleNew": return root.ruleNew(a[0], a[1], a[2])
    case "setRule": return root.setRuleField(a[0], a[1], a[2])
    case "removeRule": return root.removeRule(a[0])
    case "setSetting": return root.setSetting(a[0], a[1])
    case "menuAdd": return root.menuAdd()
    case "menuRemove": return root.menuRemove()
    case "restore": return root.startRestore(a[0])
    case "editPlan": return root.editPlan(a[0], a[1], a[2], a[3], a[4], a[5])
    case "openOmagnet": root.openOmagnet(); return Summary.answer({ ok: true })
    case "result": return root.resultOf(a[0]) || Summary.answer({ ok: true, pending: true })
    }
    return Summary.answer(root.fail("unknown_op"))
  }

  // A new rule from the app (D39: picked, not "the focused window", which would be the settings app itself).
  function ruleNew(app, monitor, slot) {
    if (root.req) return Summary.answer(root.fail("busy"))
    if (app === "" || !Number.isInteger(slot) || slot < 1 || slot > 10) return Summary.answer(root.fail("failed", "pick an app and a desktop from 1 to 10"))
    try {
      let text = root.readNow(configFile)
      let cfg = ConfigIO.parse(text)
      for (let n in cfg.rules) if (cfg.rules[n].app === app) return Summary.answer(root.fail("failed", "this app has a rule already: " + n))
      let name = AppSeam.ruleName(app, cfg.rules)
      if (name === "") return Summary.answer(root.fail("failed", "no free rule name"))
      let err = root.writeConfig(text, ConfigIO.setRule(text, name, { app: app, monitor: monitor, slot: slot, follow: false }))
      return Summary.answer(err === "" ? { ok: true, rule: name } : root.fail("failed", err))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  onRevisionChanged: root.pushModel()
  onReqChanged: if (root.req === null) Qt.callLater(root.pushModel)

  // Everything the window shows, read now. Windows with an unknown context carry what the picker needs (`need`).
  function panelData() {
    try {
      let cfg = root.config()
      let table = root.strategies(cfg)
      let doc = SceneStore.parse(root.readNow(scenesFile))
      let needs = {}
      let scenes = Object.keys(doc.scenes).map(function (name) {
        let wins = doc.scenes[name].windows.map(function (w) {
          let out = Object.assign({}, w)
          if (w.context === "?") {
            if (!needs[w.class]) needs[w.class] = root.contextInfo(w.class, table)
            out.need = needs[w.class]
          }
          return out
        })
        return { name: name, windows: wins }
      })
      let rules = Object.keys(cfg.rules).map(function (name) { return Object.assign({ name: name }, cfg.rules[name]) })
      return {
        ok: true, settings: cfg.settings, rules: rules, scenes: scenes, sessions: root.sessionRows(), menu: root.menuInstalled(),
        warnings: cfg.warnings.concat(doc.warnings), scenesWritable: !doc.readOnly && doc.errors.length === 0
      }
    } catch (e) {
      return { ok: false, reason: String(e.message || e), settings: ConfigIO.parse("").settings, rules: [], scenes: [], sessions: [], warnings: [], scenesWritable: false }
    }
  }

  // What the picker offers for a window of this class: kind "profile" (with the Chromium profiles found), "folder", or "none".
  // Only profile ids and names leave Local State (Settings.profilesFromLocalState); the text is dropped right after.
  function contextInfo(cls, table) {
    let r = AppResolve.resolve(cls, [], table, { context: "?" })
    let dir = r.contextKind === "profile" ? Settings.profileDir(r.strategy) : ""
    let profiles = []
    if (dir !== "") {
      localStateFile.path = root.home + "/.config/" + dir + "/Local State"
      profiles = Settings.profilesFromLocalState(root.readNow(localStateFile))
      localStateFile.path = ""
    }
    return { kind: r.contextKind, profiles: profiles }
  }

  // sessions.json plus the window count of each session file. Instance names are checked before they become a path.
  function sessionRows() {
    let index = Summary.parseJson(root.readNow(sessionsFile))
    let counts = {}
    for (let e of (Array.isArray(index) ? index : [])) {
      if (!e || typeof e.instance !== "string" || !/^[A-Za-z0-9_]{1,128}$/.test(e.instance)) continue
      countFile.path = root.stateDir + "/session-" + e.instance + ".json"
      let snap = Summary.parseJson(root.readNow(countFile))
      counts[e.instance] = snap && Array.isArray(snap.windows) ? snap.windows.length : -1
    }
    countFile.path = ""
    let rows = Settings.sessionRows(index, counts, Summary.instanceName(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""))
    return rows.filter(function (r) { return /^[A-Za-z0-9_]{1,128}$/.test(r.instance) })
  }

  function setSetting(key, value) {
    if (root.req) return Summary.answer(root.fail("busy"))
    let c = Settings.settingChange(ConfigIO.SETTING_SPECS, key, value)
    if (!c.ok) return Summary.answer(root.fail("failed", c.why))
    if (!root.dirsReady) { root.ensureDirs(); return Summary.answer(root.fail("failed", "the settings folder is not ready yet, try again")) }
    try {
      let text = root.readNow(configFile)
      let err = root.writeConfig(text, ConfigIO.setValue(text, key, c.value))
      return Summary.answer(err === "" ? { ok: true } : root.fail("failed", err))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  function setRuleField(name, field, value) {
    if (root.req) return Summary.answer(root.fail("busy"))
    if (["monitor", "slot", "follow", "enabled", "keep_rect"].indexOf(field) === -1) return Summary.answer(root.fail("failed", "that rule field cannot be changed here"))
    try {
      let text = root.readNow(configFile)
      if (!ConfigIO.parse(text).rules[name]) return Summary.answer(root.fail("not_found"))
      let change = {}
      change[field] = value
      let err = root.writeConfig(text, ConfigIO.setRule(text, name, change))
      return Summary.answer(err === "" ? { ok: true } : root.fail("failed", err))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  // index is the window's place in the scene; cls must still match, since the CLI may have rewritten scenes.toml meanwhile.
  function setSceneWindow(scene, index, cls, field, value) {
    if (root.req) return Summary.answer(root.fail("busy"))
    if (!Summary.validName(scene)) return Summary.answer(root.fail("bad_name"))
    try {
      let w = root.writableScenes()
      if (w.error) return Summary.answer(w.error)
      let s = w.doc.scenes[scene]
      let win = s ? s.windows[index] : null
      if (!win || win.class !== cls) return Summary.answer(root.fail("not_found", "the scene changed on disk, look again"))
      let edit = Settings.windowEdit(win, field, value)
      if (!edit.ok) return Summary.answer(root.fail("failed", edit.why))
      s.windows[index] = edit.win
      let err = root.writeScenes(w.text, SceneStore.serialize(w.doc))
      return Summary.answer(err === "" ? { ok: true } : root.fail("failed", err))
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  // Omarchy's file chooser for an IDE window's project folder. The answer arrives later as lastAnswer and revision.
  function pickFolder(scene, index, cls) {
    if (root.req || root.picking) return Summary.answer(root.fail("busy"))
    root.pickTarget = { scene: scene, index: index, cls: cls }
    root.picking = true
    root.pickStarted = false
    pickProc.running = true
    return Summary.answer({ ok: true, pending: true })
  }

  function onPicked(text) {
    let t = root.pickTarget
    root.pickTarget = null
    root.picking = false
    let folder = String(text || "").split("\n")[0]
    if (!t || folder === "") return
    root.lastAnswer = root.setSceneWindow(t.scene, t.index, t.cls, "context", Summary.shortHome(folder, root.home))
    root.revision++
  }

  // The final answer of a slow request the window started (open, restore, rule add), or "" when it is not there.
  function resultOf(id) {
    if (!/^q[0-9]+-[0-9]+$/.test(String(id))) return ""
    answerFile.path = root.runtimeDir + "/result-" + id + ".json"
    let text = root.readNow(answerFile).trim()
    answerFile.path = ""
    return text
  }

  // ---- Desktops page (WP13): live desktops for the cards, and plan edits. Commands run one at a time through async
  // Process: desktops() through hyprctl eval (its own ids and files, not a request's), hyprctl workspaces -j for the window
  // counts, hyprctl clients -j for the open window classes, then omarchy-hyprland-workspace-layout-current per shown
  // workspace. revision++ when the read is done.

  function desktopsInfo() {
    // A read can wedge when a command never starts (no exit comes). Without a timer, the next ask after 10 s starts over.
    if (root.deskBusy && Date.now() - root.deskStarted < 10000) { root.deskAgain = true; return }
    if (!root.dirsReady) { root.deskAgain = true; root.ensureDirs(); return } // mkdirProc calls this again
    root.deskGen++
    for (let p of [deskEval, deskCat, deskWs, deskClients, deskMode]) p.running = false
    root.deskBusy = true
    root.deskStarted = Date.now()
    root.deskAgain = false
    root.deskNext = { reason: "", monitors: [], windows: {}, modes: {}, classes: [] }
    root.deskId = "panel-" + (++root.deskCounter)
    root.deskRun(deskEval, ["hyprctl", "eval", LuaCall.wrap("desktops", [LuaLiteral.encode(root.deskId)], LuaLiteral.encode(root.deskReplyPath()))])
  }

  function deskRun(proc, cmd) { proc.gen = root.deskGen; proc.command = cmd; proc.running = true }

  function deskReplyPath() { return root.runtimeDir + "/reply-" + root.deskId + "-desktops.txt" }
  function deskJsonPath() { return root.runtimeDir + "/desktops-" + root.deskId + ".json" }

  // One cat reads the reply code and desktops-<id>.json together (like onDesktops); both files are removed after.
  function onDeskReply(text) {
    Quickshell.execDetached(["rm", "-f", "--", root.deskReplyPath(), root.deskJsonPath()])
    let c = LuaCall.code(text)
    let brace = text.indexOf("{")
    let d = c === "ok" && brace !== -1 ? Summary.parseJson(text.slice(brace)) : null
    root.deskNext.monitors = d && Array.isArray(d.monitors) ? d.monitors : []
    root.deskNext.omagnet = d ? d.omagnet : null
    if (!d) root.deskNext.reason = c === "no_lua" ? "The omaplace Lua module is not loaded in Hyprland" : "No desktop list from the Lua module (" + (c || "no answer") + ")"
    root.deskRun(deskWs, ["hyprctl", "workspaces", "-j"])
  }

  // Only the classes are kept (never titles).
  function onDeskClients(text) {
    let list = Summary.parseJson(text)
    let seen = {}
    for (let w of (Array.isArray(list) ? list : [])) {
      let cls = w ? String(w.initialClass || w.class || "") : ""
      if (cls !== "") seen[cls] = true
    }
    root.deskNext.classes = Object.keys(seen)
    root.nextDeskMode()
  }

  function onDeskWorkspaces(text) {
    let counts = {}
    let list = Summary.parseJson(text)
    for (let w of (Array.isArray(list) ? list : [])) if (w && Number.isInteger(w.id) && w.id > 0) counts[w.id] = Number(w.windows) || 0
    root.deskNext.windows = counts
    let wsList = []
    for (let m of root.deskNext.monitors) {
      for (let s of (m && Array.isArray(m.slots) ? m.slots : [])) if (s && Number.isInteger(s.workspace) && s.workspace > 0) wsList.push(s.workspace)
    }
    root.deskModes = wsList
    root.deskRun(deskClients, ["hyprctl", "clients", "-j"])
  }

  function nextDeskMode() {
    if (root.deskModes.length === 0) {
      root.desktopsLive = root.deskNext
      root.deskBusy = false
      root.revision++
      if (root.deskAgain) root.desktopsInfo()
      return
    }
    root.deskRun(deskMode, ["omarchy-hyprland-workspace-layout-current", String(root.deskModes[0])])
  }

  function onDeskMode(text) {
    let ws = root.deskModes.shift()
    let mode = ModeSwitch.fromOmarchy(text)
    if (mode !== "") root.deskNext.modes[ws] = mode
    root.nextDeskMode()
  }

  // Installed apps for the page's app picker: id, name, icon, StartupWMClass (Desktops.appChoices).
  function appChoices() { return Desktops.appChoices(DesktopEntries.applications.values) }

  // The page model, read now from scenes.toml and config.toml plus the last desktopsInfo().
  function desktopCards() {
    try {
      let doc = SceneStore.parse(root.readNow(scenesFile))
      let m = Desktops.cards(root.desktopsLive, doc, { rules: root.config().rules, apps: root.appChoices(), entries: root.entries(), liveNames: root.liveMonitors })
      m.reason = root.desktopsLive.reason || ""
      m.omagnet = Desktops.omagnetLayouts(root.desktopsLive.omagnet)
      m.loading = root.deskBusy && !root.desktopsLive.monitors
      return m
    } catch (e) { return { groups: [], reason: String(e.message || e), loading: false } }
  }

  // One plan edit from a card (Desktops.edit) on a fresh read of scenes.toml, with the same guards as every scenes write.
  // mode: the desktop's mode now, for the status text. The answer carries `text` for the status line.
  function editPlan(identity, slot, focused, op, arg, mode) {
    if (root.req) return Summary.answer(root.fail("busy"))
    try {
      let w = root.writableScenes()
      if (w.error) return Summary.answer(w.error)
      // the app picker gives an entry id; its class comes from the entry, an open window or a captured scene (design 14.7)
      if (op === "app" && arg) {
        let seen = Desktops.seenClasses(w.doc.scenes, root.desktopsLive.classes, root.entries())
        arg = { pos: arg.pos, id: String(arg.id || ""), class: Desktops.classOf(String(arg.id || ""), root.appChoices(), seen).class }
      }
      let e = Desktops.edit(w.doc, { identity: identity, slot: slot, focused: focused }, op, arg)
      if (e.error) return Summary.answer(root.fail("failed", e.error))
      let err = e.changed ? root.writeScenes(w.text, SceneStore.serialize(e.doc)) : ""
      if (err !== "") return Summary.answer(root.fail("failed", err))
      return Summary.answer({ ok: true, scene: e.name, text: op === "layout" ? Desktops.layoutSavedText(String(arg).trim(), mode, e.dropped) : "Saved" })
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  // ---- processes (argv only)

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", "-m", "700", root.runtimeDir, root.configDir, root.stateDir]
    onExited: (code) => {
      root.dirsReady = code === 0
      if (code !== 0) { root.finish(root.fail("failed", "cannot create " + root.runtimeDir)); return }
      root.step()
      // reload_plans at every start, even with plans.lua unchanged (Lua's retry of its login.json write): the first write
      // of a start always happens (plansText is empty) and reloads; only a build that failed needs the call here
      if (!root.writePlans()) root.reloadPlans()
      root.checkRestore() // first: a restore queued before the login plans runs before them (D26)
      root.checkLogin()
      if (root.deskAgain) root.desktopsInfo() // the Desktops page asked before the runtime folder existed
    }
  }

  Process {
    id: activeProc
    command: ["hyprctl", "activewindow", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        let w = Summary.parseJson(text)
        let cls = w ? String(w.initialClass || "") : ""
        if (!root.req) return
        if (cls === "") { root.finish(root.fail("not_found", "no focused window")); return }
        root.req.cls = cls
        root.evalCapture()
      }
    }
  }

  // hyprctl prints only "ok": when it is done, read the answer the Lua chunk wrote (LuaCall.wrap).
  Process { id: evalProc; stdout: StdioCollector { onStreamFinished: root.readReply() } }
  Process { id: replyProc; stdout: StdioCollector { onStreamFinished: root.afterEval(text) } }
  Process { id: catProc; stdout: StdioCollector { onStreamFinished: root.onCaptureText(text) } }
  Process { id: procProc; stdout: StdioCollector { onStreamFinished: root.onProcinfo(text) } }
  Process { id: reloadProc; command: ["hyprctl", "eval", "_G.omaplace.reload_config()"] }
  Process { id: restoreAsk; onExited: (code) => { if (code === 0) restoreMarker.setText("ask\n"); else console.warn("omaplace: restore question not sent (" + code + ")") } }
  Process { id: noticeProc; onExited: { root.noticeBusy = false; root.nextNotice() } }
  Process { id: plansEval; onExited: { plansReply.command = ["cat", "--", root.runtimeDir + "/reply-plans.txt"]; plansReply.running = true } }
  Process { id: plansReply; stdout: StdioCollector { onStreamFinished: root.afterReloadPlans(text) } }
  // The mode switch chain (opening a plan): chainOut and chainCat answer with their output, chainRun with its exit code.
  // chainCat is separate because onDesktops starts chainOut from inside the cat's own answer.
  Process { id: chainCat; stdout: StdioCollector { onStreamFinished: if (root.chainNext) root.chainNext(text) } }
  Process { id: chainOut; stdout: StdioCollector { onStreamFinished: if (root.chainNext) root.chainNext(text) } }
  Process { id: chainRun; onExited: (code) => { if (root.chainNext) root.chainNext(code) } }
  // Desktops page reads (WP13), one after another.
  // `gen`: the read each one belongs to; an answer from an older read (desktopsInfo started over) is dropped.
  Process { id: deskEval; property int gen: 0; onExited: if (gen === root.deskGen) root.deskRun(deskCat, ["cat", "--", root.deskReplyPath(), root.deskJsonPath()]) }
  Process { id: deskCat; property int gen: 0; stdout: StdioCollector { onStreamFinished: if (deskCat.gen === root.deskGen) root.onDeskReply(text) } }
  Process { id: deskWs; property int gen: 0; stdout: StdioCollector { onStreamFinished: if (deskWs.gen === root.deskGen) root.onDeskWorkspaces(text) } }
  Process { id: deskClients; property int gen: 0; stdout: StdioCollector { onStreamFinished: if (deskClients.gen === root.deskGen) root.onDeskClients(text) } }
  Process { id: deskMode; property int gen: 0; stdout: StdioCollector { onStreamFinished: if (deskMode.gen === root.deskGen) root.onDeskMode(text) } }
  // omagnet's own settings window, for its layout editor (D31); only offered while omagnet's Lua is loaded.
  function openOmagnet() { Quickshell.execDetached(["omarchy-shell", "shell", "toggle", "io.github.felipecpaiva.omagnet"]) }
  Process { id: settingsProc; command: ["omarchy-shell", "shell", "toggle", "io.github.felipecpaiva.omaplace"] }

  Process {
    id: monitorsProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      onStreamFinished: { root.liveMonitors = Settings.monitorNames(Summary.parseJson(text)); root.revision++ }
    }
  }
  Process {
    id: pickProc
    command: ["omarchy", "file", "select", "--title", "Project folder for this window", "--directory"]
    stdout: StdioCollector { onStreamFinished: root.onPicked(text) }
    // A pick exits 0 and arrives through stdout, in either order; only a cancel or a failure clears the pick here.
    onExited: (code) => { if (code !== 0 && root.picking) root.onPicked("") }
    // A chooser that never started sends no exit: clear the pick, or the window stays hidden and every pick busy.
    onStarted: root.pickStarted = true
    onRunningChanged: if (!running && !root.pickStarted && root.picking) root.onPicked("")
  }

  // ---- one-shot timers, armed only while a request runs

  Timer { id: luaCheck; interval: 2000; onTriggered: root.onLuaCheck() }
  Timer { id: deadline; onTriggered: root.finish(root.fail("failed", "timeout")) }

  // ---- files (writes are atomic: temp file, then rename)

  // Watched so a hand edit of scenes.toml rebuilds plans.lua; our own writes call writePlans() themselves.
  FileView {
    id: scenesFile
    path: root.configDir + "/scenes.toml"
    blockLoading: true
    blockWrites: true
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onSaveFailed: root.writeError = "cannot write scenes.toml"
    onFileChanged: { root.writePlans(); Qt.callLater(root.rearm, scenesFile) }
  }
  FileView { id: bakScenes; path: root.configDir + "/scenes.toml.bak"; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write scenes.toml.bak" }
  FileView { id: configFile; path: root.configDir + "/config.toml"; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write config.toml" }
  FileView { id: bakConfig; path: root.configDir + "/config.toml.bak"; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write config.toml.bak" }
  FileView { id: sessionsFile; path: root.stateDir + "/sessions.json"; blockLoading: true; printErrors: false }
  FileView { id: sessionFile; blockLoading: true; printErrors: false }
  FileView {
    id: statusFile
    path: root.runtimeDir + "/status.json"
    blockLoading: true
    printErrors: false
    watchChanges: root.watching
    onFileChanged: root.onStatus(root.readNow(statusFile))
  }
  // Lua replaces status.json by rename, which a file watch can miss, so a live request also reads it every 250 ms.
  // Bounded: runs only while a request waits (root.watching), never while idle.
  Timer { id: statusPoll; interval: 250; repeat: true; running: root.watching; onTriggered: root.onStatus(root.readNow(statusFile)) }
  FileView {
    id: planFile
    blockWrites: true
    atomicWrites: true
    printErrors: false
    onSaved: {
      if (!root.req || root.req.kind !== "open" || root.req.planPath !== path) return
      evalProc.command = ["hyprctl", "eval", LuaCall.wrap("open_file", [LuaLiteral.encode(root.req.planPath)], LuaLiteral.encode(root.replyPath()))]
      evalProc.running = true
    }
    onSaveFailed: root.finish(root.fail("failed", "cannot write the plan file"))
  }
  FileView { id: resultFile; blockWrites: true; atomicWrites: true; printErrors: false }
  // Settings window reads (WP6): each path is set right before a read and cleared after it.
  FileView { id: localStateFile; blockLoading: true; printErrors: false }
  FileView { id: countFile; blockLoading: true; printErrors: false }
  FileView { id: answerFile; blockLoading: true; printErrors: false }
  FileView { id: appReqFile; blockLoading: true; printErrors: false }
  FileView { id: appOutFile; blockWrites: true; atomicWrites: true; printErrors: false }
  FileView { id: launcherSourceFile; path: root.launcherSource; blockLoading: true; printErrors: false }
  FileView { id: menuFile; path: root.menuPath; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write the Omarchy menu file" }
  FileView { id: menuBak; path: root.menuPath + ".omaplace.bak"; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write the menu backup" }
  // moves.json is only ever replaced by a rename, which a watch can miss; finish() reads it too.
  FileView { id: movesFile; path: root.runtimeDir + "/moves.json"; blockLoading: true; printErrors: false; watchChanges: root.autoMemory; onFileChanged: root.applyMoves() }
  // Desktop plans (WP12b). plan-moves.json and login.json are Lua's; plans.lua and the login marker are ours.
  FileView {
    id: plansFile
    path: root.stateDir + "/plans.lua"
    blockWrites: true
    atomicWrites: true
    printErrors: false
    onSaved: root.reloadPlans()
    onSaveFailed: { root.plansText = ""; console.warn("omaplace: cannot write plans.lua") }
  }
  // Read only by planUpdate(): Lua sends the move notifications itself.
  FileView { id: planMovesFile; path: root.runtimeDir + "/plan-moves.json"; blockLoading: true; printErrors: false }
  FileView { id: loginFile; path: root.runtimeDir + "/login.json"; blockLoading: true; printErrors: false; watchChanges: true; onFileChanged: { root.checkLogin(); Qt.callLater(root.rearm, loginFile) } }
  FileView { id: restoreMarker; path: root.runtimeDir + "/restore-done-" + root.instance; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write the restore marker" }
  FileView { id: markerFile; path: root.runtimeDir + "/login-done-" + root.instance; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write the login marker" }
  FileView { id: launcherFile; path: root.launcherDest; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false }
}
