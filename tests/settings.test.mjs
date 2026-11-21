// js/Settings.js: the settings window's pure helpers. Made-up data only.
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const load = (file, names) => {
  const src = readFileSync(new URL("../js/" + file, import.meta.url), "utf8").replace(".pragma library", "")
  return new Function(src + "; return { " + names.join(", ") + " }")()
}
const S = load("Settings.js", ["settingChange", "timingRows", "markEdited", "isEdited", "windowEdit", "profileDir", "profileOptions", "profilesFromLocalState",
  "monitorNames", "monitorChoices", "positionText", "sessionRows", "answerText", "KEEPABLE", "TIMING", "PANEL_KEYS"])
const C = load("ConfigIO.js", ["parse", "SETTING_SPECS"])
const Store = load("SceneStore.js", ["EDITABLE", "parse", "serialize", "mergeCapture"])
const specs = C.SETTING_SPECS

test("KEEPABLE is SceneStore's EDITABLE list", () => {
  assert.deepEqual(S.KEEPABLE, Store.EDITABLE)
})

test("every key the window writes is a known setting", () => {
  for (const k of S.PANEL_KEYS) assert.ok(specs[k], k)
  for (const t of S.TIMING) assert.equal(specs[t.key].type, "int", t.key)
})

test("settingChange: numbers within the config limits", () => {
  assert.deepEqual(S.settingChange(specs, "settle_ms", 900), { ok: true, value: 900 })
  assert.deepEqual(S.settingChange(specs, "settle_ms", "900"), { ok: true, value: 900 })
  assert.equal(S.settingChange(specs, "settle_ms", 10001).ok, false)
  assert.match(S.settingChange(specs, "session_keep", 0).why, /from 2 to 50/)
  assert.equal(S.settingChange(specs, "expiry_seconds", "2.5").ok, false)
  assert.equal(S.settingChange(specs, "expiry_seconds", "ten").ok, false)
})

test("settingChange: choices, and the ones coming later are refused", () => {
  assert.deepEqual(S.settingChange(specs, "session", "off"), { ok: true, value: "off" })
  assert.equal(S.settingChange(specs, "session", true).ok, false)
  assert.deepEqual(S.settingChange(specs, "app_memory", "last_place"), { ok: true, value: "last_place" })
  assert.match(S.settingChange(specs, "app_memory", "auto").why, /coming later/)
  assert.deepEqual(S.settingChange(specs, "restore_at_login", "off"), { ok: true, value: "off" })
  assert.equal(S.settingChange(specs, "restore_at_login", "ask").ok, false)
  assert.equal(S.settingChange(specs, "existing_default", "copy").ok, false)
})

test("settingChange: text, and keys the window does not own", () => {
  assert.deepEqual(S.settingChange(specs, "ignore", " steam, mpv "), { ok: true, value: "steam, mpv" })
  assert.equal(S.settingChange(specs, "ignore", 'a"b').ok, false)
  assert.equal(S.settingChange(specs, "schema", 2).ok, false)
  assert.equal(S.settingChange(specs, "tiled_order", false).ok, false)
  assert.equal(S.settingChange(specs, "nope", 1).ok, false)
})

test("timingRows carries the limits from config", () => {
  const rows = S.timingRows(specs, C.parse("settle_ms = 700\n").settings)
  assert.equal(rows.length, 7)
  assert.deepEqual(rows.find((r) => r.key === "settle_ms"), { key: "settle_ms", label: rows[1].label, min: 0, max: 10000, value: 700 })
  assert.deepEqual(rows.find((r) => r.key === "request_timeout_s").max, 600)
})

test("markEdited adds keepable fields once", () => {
  assert.equal(S.markEdited("", "folder"), "folder")
  assert.equal(S.markEdited("folder", "folder"), "folder")
  assert.equal(S.markEdited("folder  launch", "rect"), "folder launch rect")
  assert.equal(S.markEdited("launch", "context"), "launch")
  assert.equal(S.markEdited(undefined, "class"), "")
})

test("isEdited reads the edited list", () => {
  assert.equal(S.isEdited({ edited: "folder launch" }, "launch"), true)
  assert.equal(S.isEdited({ edited: "folder" }, "fold"), false)
  assert.equal(S.isEdited(null, "folder"), false)
})

test("windowEdit changes a copy and marks the field", () => {
  const win = { app: "demo", class: "foot", context: "", rect: [0, 0, 1, 1], folder: "~/a", launch: "", edited: "" }
  const r = S.windowEdit(win, "folder", " ~/code/demo ")
  assert.equal(r.ok, true)
  assert.equal(r.win.folder, "~/code/demo")
  assert.equal(r.win.edited, "folder")
  assert.equal(win.folder, "~/a")
  assert.notEqual(r.win.rect, win.rect)
  assert.equal(S.windowEdit(win, "launch", "htop -d 5").win.edited, "launch")
  assert.equal(S.windowEdit({ ...win, context: "?" }, "context", "Profile 1").win.context, "Profile 1")
  assert.equal(S.windowEdit(win, "class", "x").ok, false)
  assert.equal(S.windowEdit(win, "launch", 'say "hi"').ok, false)
  assert.equal(S.windowEdit(win, "context", "--incognito").ok, false)
  assert.equal(S.windowEdit(null, "folder", "x").ok, false)
})

test("an edited folder survives a re-capture of the same window", () => {
  const old = { windows: [S.windowEdit({ app: "foot", class: "foot", context: "", rect: [0, 0, 1, 1], order: 1, floating: true,
    launch: "", folder: "~/x", edited: "" }, "folder", "~/code/demo").win] }
  const merged = Store.mergeCapture(old, { windows: [{ app: "foot", class: "foot", context: "", rect: [0, 0, 1, 1], order: 1,
    floating: true, launch: "", folder: "~/elsewhere" }] })
  assert.equal(merged.windows[0].folder, "~/code/demo")
  assert.equal(merged.windows[0].edited, "folder")
})

test("profilesFromLocalState reads only info_cache ids and names", () => {
  const text = JSON.stringify({
    browser: { last_known_version: "1.2.3" },
    profile: {
      last_used: "Profile 1",
      info_cache: {
        "Profile 1": { name: "Work", gaia_name: "Example Person", user_name: "not-an-address" },
        Default: { name: "Person 1", avatar_icon: "chrome://theme/IDR_PROFILE_AVATAR_26" },
        "Profile 3": { name: "  \u0007 " },
        "--bad": { name: "Dash" },
        'Pro"file': { name: "Quote" }
      }
    }
  })
  assert.deepEqual(S.profilesFromLocalState(text), [
    { id: "Default", name: "Person 1" },
    { id: "Profile 1", name: "Work" },
    { id: "Profile 3", name: "Profile 3" }
  ])
})

test("profilesFromLocalState: bad input gives no profiles", () => {
  assert.deepEqual(S.profilesFromLocalState(""), [])
  assert.deepEqual(S.profilesFromLocalState("{not json"), [])
  assert.deepEqual(S.profilesFromLocalState('{"profile":{"info_cache":[1,2]}}'), [])
  assert.deepEqual(S.profilesFromLocalState("null"), [])
})

test("profileOptions starts with an empty choice", () => {
  assert.deepEqual(S.profileOptions([{ id: "Default", name: "Person 1" }]), [
    { value: "", label: "Pick a profile" }, { value: "Default", label: "Person 1 (Default)" }])
  assert.equal(S.profileOptions(null).length, 1)
})

test("profileDir knows the Chromium family only", () => {
  assert.equal(S.profileDir("chrome"), "google-chrome")
  assert.equal(S.profileDir("brave"), "BraveSoftware/Brave-Browser")
  assert.equal(S.profileDir("firefox"), "")
})

test("monitorNames: Omarchy identities, twins numbered by connector, mirrors left out", () => {
  const list = [
    { name: "DP-2", description: "Example Corp EX27" },
    { name: "eDP-1", description: "Panel Co 14" },
    { name: "DP-1", description: "Example Corp EX27" },
    { name: "HDMI-A-1", description: "", mirrorOf: "none" },
    { name: "DP-3", description: "Example Corp EX27", mirrorOf: "DP-1" }
  ]
  assert.deepEqual(S.monitorNames(list), ["Example Corp EX27 #2", "Panel Co 14", "Example Corp EX27", "HDMI-A-1"])
  assert.deepEqual(S.monitorNames(null), [])
})

test("monitorChoices adds focused and a rule's unplugged monitor", () => {
  assert.deepEqual(S.monitorChoices(["A"], "A").map((c) => c.value), ["", "A"])
  const c = S.monitorChoices(["A"], "Gone Co 24")
  assert.equal(c[2].label, "Gone Co 24 (not connected)")
})

test("positionText for floating and tiled windows", () => {
  assert.equal(S.positionText({ floating: true, rect: [0, 0.5, 0.5, 0.5] }), "floating at 0%, 50%, size 50% by 50%")
  assert.equal(S.positionText({ floating: false, order: 3 }), "tiled, position 3")
  assert.equal(S.positionText(null), "")
})

test("sessionRows marks the current login and unknown counts", () => {
  const rows = S.sessionRows([{ instance: "b", saved_at: 200 }, { instance: "a", saved_at: 100 }, { saved_at: 1 }], { a: 4 }, "b")
  assert.deepEqual(rows, [
    { instance: "b", savedAt: 200, windows: -1, current: true },
    { instance: "a", savedAt: 100, windows: 4, current: false }
  ])
  assert.deepEqual(S.sessionRows(null, {}, ""), [])
})

test("answerText words every answer", () => {
  assert.deepEqual(S.answerText('{"ok":true}', "Renamed"), { ok: true, text: "Renamed", req: "" })
  assert.deepEqual(S.answerText('{"ok":true,"pending":true,"req":"q1-5"}'), { ok: true, text: "Working...", req: "q1-5" })
  assert.equal(S.answerText('{"ok":true,"rule":"demo"}').text, "Added the rule demo")
  assert.equal(S.answerText('{"ok":false,"code":"busy"}').ok, false)
  assert.match(S.answerText('{"ok":false,"code":"failed","reason":"cannot write"}').text, /cannot write$/)
  assert.equal(S.answerText("").ok, false)
})
