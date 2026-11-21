import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const load = (f) => readFileSync(new URL("../js/" + f, import.meta.url), "utf8").replace(".pragma library", "")
const S = new Function(load("Summary.js") + "; return { validName, answer, parseJson, fromUrl, entryList, appIdOf, isTerminal, joinArgs, terminalFields, sceneCapture, layoutOf, planTarget, runResult, notifyText, ruleFromCapture, sceneList }")()
const A = new Function(load("AppResolve.js") + "; return { resolve, defaultStrategies }")()
const F = new Function(load("ArgFilter.js") + "; return { filter }")()

const entries = [{ id: "org.example.Editor.desktop", startupWMClass: "", exec: "editor" }]
const strategies = A.defaultStrategies()
const capture = {
  schema: 1, kind: "capture",
  monitors: [{ fp: { identity: "Example Corp EX27" } }, { fp: { identity: "Example Corp EX24" } }],
  windows: [
    { class: "org.example.Editor", monitor: 1, slot: 2, order: 1, rect: [0, 0, 0.5, 1], floating: true, context: "", pid: 4242 },
    { class: "Alacritty", monitor: 1, slot: 2, order: 2, rect: [0.5, 0, 0.5, 1], floating: true, context: "", pid: 4343 },
    { class: "org.example.Unknown", monitor: 1, slot: 2, order: 3, rect: [0, 0, 1, 1], floating: true, context: "", pid: 1 },
    { class: "google-chrome", monitor: 1, slot: 2, order: 4, rect: [0, 0, 1, 1], floating: true, pid: 2 },
    { class: "google-chrome", monitor: 1, slot: 2, order: 5, rect: [0, 0, 1, 1], floating: true, context: "Profile 1", pid: 2 }
  ]
}

test("validName follows SceneStore's rule", () => {
  assert.equal(S.validName("work"), true)
  assert.equal(S.validName("dev_2-b"), true)
  for (const bad of ["", "Work", "a b", "x".repeat(41), 'a"b', null, 3]) assert.equal(S.validName(bad), false)
})

test("parseJson takes objects only and never throws", () => {
  assert.deepEqual(S.parseJson('{"a":1}'), { a: 1 })
  assert.equal(S.parseJson(""), null)
  assert.equal(S.parseJson("{half"), null)
  assert.equal(S.parseJson("3"), null)
  assert.equal(S.answer({ ok: true }), '{"ok":true}')
})

test("fromUrl and entryList", () => {
  assert.equal(S.fromUrl("file:///opt/a%20b/x.sh"), "/opt/a b/x.sh")
  assert.equal(S.fromUrl("qrc:/x"), "")
  assert.deepEqual(S.entryList([{ id: "a", startupClass: "A", execString: "a --x" }, { id: "" }, null]),
    [{ id: "a", startupWMClass: "A", exec: "a --x" }])
  assert.deepEqual(S.entryList(undefined), [])
})

test("appIdOf names the desktop entry, else keeps the class", () => {
  assert.equal(S.appIdOf(A.resolve("org.example.Editor", entries, strategies), "org.example.Editor"), "org.example.Editor")
  assert.equal(S.appIdOf(A.resolve("Alacritty", entries, strategies), "Alacritty"), "Alacritty")
  assert.equal(S.appIdOf(null, "x"), "x")
})

test("joinArgs round trips through quotes and refuses what scenes.toml cannot hold", () => {
  assert.equal(S.joinArgs(["agent", "--model", "fast"]), "agent --model fast")
  assert.equal(S.joinArgs(["vim", "my notes.md"]), "vim 'my notes.md'")
  assert.equal(S.joinArgs(["x", ""]), "x ''")
  assert.equal(S.joinArgs(["echo", 'a"b']), null)
  assert.equal(S.joinArgs(["echo", "it's here"]), null)
  assert.equal(S.joinArgs(["a\nb"]), null)
})

test("terminalFields: folder under home is shortened, a shell keeps no program, secrets are counted", () => {
  const home = "/srv/demo"
  const agent = { cwd: "/srv/demo/code/demo", argv: ["agent", "--token", "abc", "run"] }
  const t = S.terminalFields(agent, F.filter(agent.argv), home)
  assert.deepEqual(t, { folder: "~/code/demo", launch: "agent run", dropped: 2 })
  const shell = { cwd: "/tmp", argv: ["-bash"] }
  assert.deepEqual(S.terminalFields(shell, F.filter(shell.argv), home), { folder: "/tmp", launch: "", dropped: 0 })
  assert.deepEqual(S.terminalFields({}, F.filter([]), home), { folder: "", launch: "", dropped: 0 })
  const quoted = { cwd: '/tmp/a"b', argv: ["vim", 'x"y'] }
  assert.deepEqual(S.terminalFields(quoted, F.filter(quoted.argv), home), { folder: "", launch: "", dropped: 2 })
})

test("sceneCapture saves what can start, skips the rest, marks untagged context apps as ?", () => {
  const resolved = capture.windows.map((w) => A.resolve(w.class, entries, strategies, { context: w.context }))
  assert.equal(S.isTerminal(resolved[1], strategies), true)
  assert.equal(S.isTerminal(resolved[0], strategies), false)
  const terms = []
  terms[1] = { folder: "~/code/demo", launch: "agent run", dropped: 1 }
  const r = S.sceneCapture(capture, resolved, terms, strategies)
  assert.equal(r.capture.saved_on, "Example Corp EX24")
  assert.deepEqual(r.counts, { saved: 4, skipped: 1, need_profile: 1, dropped: 1 })
  assert.deepEqual(r.capture.windows.map((w) => w.class), ["org.example.Editor", "Alacritty", "google-chrome", "google-chrome"])
  assert.equal(r.capture.windows[1].folder, "~/code/demo")
  assert.equal(r.capture.windows[1].launch, "agent run")
  assert.equal(r.capture.windows[2].context, "?", "an untagged context app needs a profile")
  assert.equal(r.capture.windows[3].context, "Profile 1", "a tagged one keeps its profile")
  assert.equal(r.capture.windows[0].context, "", "a plain app has no context")
  assert.equal("pid" in r.capture.windows[0], false, "pid is never saved")
  const empty = S.sceneCapture({ windows: {} }, [], [], strategies)
  assert.deepEqual(empty.counts, { saved: 0, skipped: 0, need_profile: 0, dropped: 0 })
})

test("layoutOf and planTarget", () => {
  assert.equal(S.layoutOf({ windows: [{ floating: true }, { floating: true }] }), "floating")
  assert.equal(S.layoutOf({ windows: [{ floating: true }, { floating: false }] }), "tiled")
  assert.equal(S.layoutOf({ windows: [] }), "floating")
  assert.deepEqual(S.planTarget({ home_monitor: "", home_slot: 0, windows: [{ floating: false }] }, "r1-5", 20),
    { run: "r1-5", fp: {}, slot: 0, layout: "tiled", expiry_s: 20 })
  assert.deepEqual(S.planTarget({ home_monitor: "Example Corp EX27", home_slot: 3, windows: [] }, "r2-5", 9).fp,
    { identity: "Example Corp EX27" })
})

test("runResult waits for its own final run and counts items", () => {
  const items = [
    { class: "a", state: "placed" }, { class: "b", state: "moved" }, { class: "c", state: "skipped" },
    { class: "d", state: "not_reopened" }, { class: "e", state: "failed", reason: "gone" }
  ]
  assert.equal(S.runResult({ run: "r1", state: "running", items }, "r1"), null)
  assert.equal(S.runResult({ run: "r0", state: "done", items }, "r1"), null)
  assert.equal(S.runResult(null, "r1"), null)
  const r = S.runResult({ run: "r1", state: "partial", items }, "r1")
  assert.deepEqual(r, { ok: true, state: "partial", run: "r1", placed: 2, started: 1, skipped: 1, not_reopened: 1, failed: 1 })
  assert.equal(S.notifyText(r), "2 placed (1 started), 1 skipped, 1 not reopened, 1 failed")
  const i = S.runResult({ run: "r1", state: "interrupted", items: [] }, "r1")
  assert.equal(i.ok, false)
  assert.equal(i.code, "failed")
  assert.equal(S.notifyText(i), "0 placed (0 started), interrupted")
  assert.equal(S.notifyText(S.runResult({ run: "r1", state: "done", items: [items[0]] }, "r1")), "1 placed (1 started)")
})

test("ruleFromCapture uses the window's monitor identity and slot", () => {
  assert.deepEqual(S.ruleFromCapture(capture, "org.example.Editor"), {
    name: "org-example-editor",
    rule: { app: "org.example.Editor", monitor: "Example Corp EX24", slot: 2, follow: false, enabled: true }
  })
  assert.equal(S.ruleFromCapture(capture, "org.example.Missing"), null)
  assert.equal(S.ruleFromCapture({ monitors: [], windows: [{ class: "x", monitor: 0, slot: 0 }] }, "x"), null)
})

test("sceneList gives names and window counts", () => {
  assert.deepEqual(S.sceneList({ scenes: { work: { windows: [{}, {}] }, play: { windows: [] } } }),
    [{ name: "work", windows: 2 }, { name: "play", windows: 0 }])
  assert.deepEqual(S.sceneList(null), [])
})
