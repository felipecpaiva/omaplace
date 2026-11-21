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
  property int revision: 0
  property string lastAnswer: ""

  // Launcher entry (WP6), like omagnet's: written at load, removed at unload, and only ever over a file with our marker.
  readonly property string launcherSource: Summary.fromUrl(Qt.resolvedUrl("omaplace.desktop"))
  readonly property string launcherDest: root.home + "/.local/share/applications/omaplace.desktop"
  readonly property string launcherMarker: "X-Omaplace-Managed=true"
  property bool launcherInstalled: false

  // DesktopEntries is lazy: the first read is empty, so it is touched at load (no process, no timer).
  Component.onCompleted: { let touch = DesktopEntries.applications.values.length; root.installLauncher() }
  // find deletes the file only when grep finds the marker line in it: argv only, no shell.
  Component.onDestruction: {
    if (root.launcherInstalled)
      Quickshell.execDetached(["find", root.launcherDest, "-maxdepth", "0", "-type", "f", "-exec", "grep", "-qx", root.launcherMarker, "{}", ";", "-delete"])
  }

  IpcHandler {
    target: "io.github.felipecpaiva.omaplace"

    function save(name: string): string { return root.startSave(name) }
    function open(name: string): string { return root.startOpen(name) }
    function restore(gen: string): string { return root.startRestore(gen) }
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

  // Restore (design 6.5): one session plan; Lua sends each window to its own monitor and desktop. The rest of the flow is open's.
  function startRestore(gen) {
    if (root.req) return Summary.answer(root.fail("busy"))
    try {
      let current = Summary.instanceName(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "")
      let instance = Summary.pickSession(Summary.parseJson(root.readNow(sessionsFile)), current, String(gen || ""))
      if (instance === "") return Summary.answer(root.fail("not_found", "no previous session"))
      sessionFile.path = root.stateDir + "/session-" + instance + ".json"
      let snap = Summary.parseJson(root.readNow(sessionFile))
      if (!snap || !Array.isArray(snap.windows) || snap.windows.length === 0) return Summary.answer(root.fail("not_found", "that session has no windows"))
      return root.begin("open", { name: "last session", snapshot: snap })
    } catch (e) { return Summary.answer(root.fail("failed", String(e.message || e))) }
  }

  function launchesFor(wins, cfg) {
    let table = root.strategies(cfg), list = root.entries()
    return wins.map(function (w) {
      return AppResolve.resolve(w.class, list, table, { context: w.context, folder: w.folder, launch: w.launch, home: root.home })
    })
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
      r.run = "r" + root.counter + "-" + Date.now()
      let plan = r.snapshot
        ? Plan.fromSession(r.snapshot, root.launchesFor(r.snapshot.windows, cfg), { run: r.run, expiry_s: cfg.settings.expiry_seconds })
        : Plan.fromScene(r.scene, root.launchesFor(r.scene.windows, cfg), Summary.planTarget(r.scene, r.run, cfg.settings.expiry_seconds), cfg.rules)
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

  // ---- settings window (WP6). Plain functions the panel calls; it never writes a file itself. Each write uses the same
  // guards as above (busy, writableScenes, try/catch) and goes through writeConfig (which also tells Lua to reload) or
  // writeScenes (with the .bak first).

  function installLauncher() {
    if (root.launcherSource === "" || root.home === "") return
    let want = root.readNow(launcherSourceFile)
    if (want.indexOf(root.launcherMarker) === -1) return
    let have = root.readNow(launcherFile)
    if (have !== "" && have.indexOf(root.launcherMarker) === -1) return // a file of the user's own: never written over
    root.launcherInstalled = true
    // shortcut: FileView does not create ~/.local/share/applications; it exists on Omarchy, add a mkdir if a report says otherwise
    if (have !== want) launcherFile.setText(want)
  }

  // A fresh install has no ~/.config/omaplace until the first slow request; the window calls this when it opens.
  function ensureDirs() { if (!root.dirsReady && !root.req && !mkdirProc.running) mkdirProc.running = true }

  function refreshMonitors() { if (!monitorsProc.running) monitorsProc.running = true }

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
        ok: true, settings: cfg.settings, rules: rules, scenes: scenes, sessions: root.sessionRows(),
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
    if (["monitor", "slot", "follow", "enabled"].indexOf(field) === -1) return Summary.answer(root.fail("failed", "that rule field cannot be changed here"))
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
  }

  // ---- one-shot timers, armed only while a request runs

  Timer { id: luaCheck; interval: 2000; onTriggered: root.onLuaCheck() }
  Timer { id: deadline; onTriggered: root.finish(root.fail("failed", "timeout")) }

  // ---- files (writes are atomic: temp file, then rename)

  FileView { id: scenesFile; path: root.configDir + "/scenes.toml"; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false; onSaveFailed: root.writeError = "cannot write scenes.toml" }
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
      evalProc.command = ["hyprctl", "eval", "_G.omaplace.open_file(" + LuaLiteral.encode(root.req.planPath) + ")"]
      evalProc.running = true
    }
    onSaveFailed: root.finish(root.fail("failed", "cannot write the plan file"))
  }
  FileView { id: resultFile; blockWrites: true; atomicWrites: true; printErrors: false }
  // Settings window reads (WP6): each path is set right before a read and cleared after it.
  FileView { id: localStateFile; blockLoading: true; printErrors: false }
  FileView { id: countFile; blockLoading: true; printErrors: false }
  FileView { id: answerFile; blockLoading: true; printErrors: false }
  FileView { id: launcherSourceFile; path: root.launcherSource; blockLoading: true; printErrors: false }
  FileView { id: launcherFile; path: root.launcherDest; blockLoading: true; blockWrites: true; atomicWrites: true; printErrors: false }
}
