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

// omaplace service (design 4.3, 6.2, 6.3, 7.2): the CLI's IPC target and the only file that runs processes.
// All data work goes through the js/ modules. One slow request (save, open, rule add) runs at a time; every other
// request answers busy meanwhile, so two writers never race on scenes.toml or config.toml.
// Idle cost: no timer armed, no process running, no file watched. While a request runs: two one-shot timers (the 2 s
// Lua check and request_timeout_s) and a watch on status.json during an open.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omaplace"
  readonly property string configDir: root.home + "/.config/omaplace"
  readonly property string procinfoPath: Summary.fromUrl(Qt.resolvedUrl("libexec/procinfo.sh"))

  property int counter: 0
  property bool dirsReady: false
  property bool watching: false
  // The request in flight: { id, kind: save | open | rule, name, run, cls, capture, resolved, terms, queue, retried, seen, other }
  property var req: null
  property string writeError: ""

  // DesktopEntries is lazy: the first read is empty, so it is touched at load (no process, no timer).
  Component.onCompleted: { let touch = DesktopEntries.applications.values.length }

  IpcHandler {
    target: "io.github.felipecpaiva.omaplace"

    function save(name: string): string { return root.startSave(name) }
    function open(name: string): string { return root.startOpen(name) }
    function restore(gen: string): string { return Summary.answer({ ok: false, code: "not_yet" }) }
    function list(): string { return root.listScenes() }
    function rename(fromName: string, toName: string): string { return root.renameScene(fromName, toName) }
    function remove(name: string): string { return root.removeScene(name) }
    function ruleAddFocused(): string { return root.startRuleAdd() }
    function ruleRemove(name: string): string { return root.removeRule(name) }
    function status(): string { return root.statusLine() }
    function settings(): string { return root.toggleSettings() }
  }

  // ---- files

  function readNow(view) { view.reload(); view.waitForJob(); return view.text() || "" }

  function writeScenes(oldText, text) {
    root.writeError = ""
    if (oldText !== "") bakScenes.setText(oldText)
    if (root.writeError === "") scenesFile.setText(text)
    return root.writeError
  }

  function writeConfig(oldText, text) {
    root.writeError = ""
    if (oldText !== "") bakConfig.setText(oldText)
    if (root.writeError === "") configFile.setText(text)
    if (root.writeError === "" && !reloadProc.running) reloadProc.running = true
    return root.writeError
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
    if (doc.errors.length > 0) return { error: root.fail("failed", "scenes.toml has a scene with a bad name, fix it first") }
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
    return root.begin("open", { name: name, scene: scene })
  }

  function step() {
    let r = root.req
    if (!r) return
    if (r.kind === "rule") activeProc.running = true
    else if (r.kind === "save") root.evalCapture()
    else root.writePlan()
  }

  function evalCapture() {
    evalProc.command = ["hyprctl", "eval", "_G.omaplace.capture(" + LuaLiteral.encode(root.req.id) + ", \"focused\")"]
    evalProc.running = true
  }

  function writePlan() {
    let r = root.req
    try {
      let cfg = root.config()
      let table = root.strategies(cfg), list = root.entries()
      let launches = r.scene.windows.map(function (w) {
        return AppResolve.resolve(w.class, list, table, { context: w.context, folder: w.folder, launch: w.launch, home: root.home })
      })
      r.run = "r" + root.counter + "-" + Date.now()
      let plan = Plan.fromScene(r.scene, launches, Summary.planTarget(r.scene, r.run, cfg.settings.expiry_seconds), cfg.rules)
      r.planPath = root.runtimeDir + "/plan-" + r.run + ".lua"
      planFile.path = r.planPath
      planFile.setText("return " + LuaLiteral.encode(plan) + "\n")
    } catch (e) { root.finish(root.fail("failed", String(e.message || e))) }
  }

  function afterEval() {
    let r = root.req
    if (!r) return
    if (r.kind === "open") {
      r.evaluated = true
      root.watching = true
      luaCheck.restart()
      root.onStatus(root.readNow(statusFile))
    } else {
      root.readCapture()
    }
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
      if (r.retried) { root.finish(root.fail("no_lua")); return }
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
      if (sc.capture.windows.length === 0) { root.finish(root.fail("failed", "no app on this desktop can be saved")); return }
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
    if (r.kind === "open") { if (!r.seen) root.finish(root.fail(r.other ? "busy" : "no_lua")) }
    else root.readCapture()
  }

  // Ends the request: exactly one result file, timers and watch off, busy cleared. An open also tells the user.
  function finish(res) {
    let r = root.req
    if (!r) return
    deadline.stop()
    luaCheck.stop()
    root.watching = false
    root.req = null
    resultFile.path = root.runtimeDir + "/result-" + r.id + ".json"
    resultFile.setText(Summary.answer(res) + "\n")
    if (r.kind === "open" && !notifyProc.running) {
      let text = res.state ? Summary.notifyText(res) : "could not open (" + res.code + ")"
      notifyProc.command = ["omarchy-notification-send", "omaplace: " + r.name, text]
      notifyProc.running = true
    }
  }

  // ---- processes (argv only)

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", "-m", "700", root.runtimeDir, root.configDir]
    onExited: (code) => {
      root.dirsReady = code === 0
      if (code === 0) root.step()
      else root.finish(root.fail("failed", "cannot create " + root.runtimeDir))
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

  Process { id: evalProc; onExited: root.afterEval() }
  Process { id: catProc; stdout: StdioCollector { onStreamFinished: root.onCaptureText(text) } }
  Process { id: procProc; stdout: StdioCollector { onStreamFinished: root.onProcinfo(text) } }
  Process { id: reloadProc; command: ["hyprctl", "eval", "_G.omaplace.reload_config()"] }
  Process { id: notifyProc }
  Process { id: settingsProc; command: ["omarchy-shell", "shell", "toggle", "io.github.felipecpaiva.omaplace"] }

  // ---- one-shot timers, armed only while a request runs

  Timer { id: luaCheck; interval: 2000; onTriggered: root.onLuaCheck() }
  Timer { id: deadline; onTriggered: root.finish(root.fail("failed", "timeout")) }

  // ---- files (writes are atomic: temp file, then rename)

  FileView { id: scenesFile; path: root.configDir + "/scenes.toml"; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write scenes.toml" }
  FileView { id: bakScenes; path: root.configDir + "/scenes.toml.bak"; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write scenes.toml.bak" }
  FileView { id: configFile; path: root.configDir + "/config.toml"; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write config.toml" }
  FileView { id: bakConfig; path: root.configDir + "/config.toml.bak"; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write config.toml.bak" }
  FileView {
    id: statusFile
    path: root.runtimeDir + "/status.json"
    blockLoading: true
    printErrors: false
    watchChanges: root.watching
    onFileChanged: { reload(); root.onStatus(text()) }
  }
  FileView {
    id: planFile
    blockWrites: true
    atomicWrites: true
    printErrors: false
    onSaved: {
      if (!root.req || root.req.kind !== "open" || root.req.planPath !== path) return
      evalProc.command = ["hyprctl", "eval", "_G.omaplace.open_file(" + LuaLiteral.encode(root.req.planPath) + ")"]
      evalProc.running = true
    }
    onSaveFailed: root.finish(root.fail("failed", "cannot write the plan file"))
  }
  FileView { id: resultFile; blockWrites: true; atomicWrites: true; printErrors: false }
}
