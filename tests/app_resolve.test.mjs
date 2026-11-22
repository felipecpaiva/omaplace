import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const src = readFileSync(new URL("../js/AppResolve.js", import.meta.url), "utf8").replace(".pragma library", "")
const A = new Function(src + "; return { defaultStrategies, mergeStrategies, resolve, splitArgs }")()

// messy on purpose: .desktop suffixes, missing fields, odd case, reverse DNS ids, an Exec with field codes and a path
const entries = [
  { id: "org.example.Editor.desktop", startupWMClass: "", exec: "/opt/example/bin/editor %F" },
  { id: "Example-Mail", startupWMClass: "Example-mail-client", exec: "env MAIL=1 mail" },
  { id: "org.example.Photos", exec: "photos --gui" },
  { id: "chrome-abc-Default.desktop", startupWMClass: "chrome-abc-Default", exec: "google-chrome-stable --app-id=abc" },
  { id: "", startupWMClass: "ghost", exec: "ghost" },
  { id: "tool.desktop", exec: "/usr/bin/sometool" },
  { id: "google-chrome.desktop", startupWMClass: "google-chrome", exec: "google-chrome-stable %U" }
]
const T = A.defaultStrategies()
const r = (cls, slot, table) => A.resolve(cls, entries, table || T, slot)

test("desktop: exact id, with and without the .desktop suffix", () => {
  assert.deepEqual(r("org.example.Editor"), { strategy: "desktop", mode: "launch", argv: ["uwsm-app", "--", "org.example.Editor.desktop"], contextKind: "none", reason: "" })
})

test("desktop lookup chain: startup class, lower case, last part of the id, exec name", () => {
  assert.equal(r("Example-mail-client").argv[2], "Example-Mail.desktop")
  assert.equal(r("example-mail").argv[2], "Example-Mail.desktop")
  assert.equal(r("photos").argv[2], "org.example.Photos.desktop") // last part of the reverse DNS id
  assert.equal(r("sometool").argv[2], "tool.desktop") // exec basename
})

test("an unknown class is skipped, never guessed", () => {
  const x = r("mystery-app")
  assert.equal(x.mode, "skip")
  assert.equal(x.argv, null)
  assert.match(x.reason, /no desktop entry/)
})

test("web app class chrome-abc-Default launches its entry", () => {
  assert.deepEqual(r("chrome-abc-Default"), { strategy: "webapp", mode: "launch", argv: ["uwsm-app", "--", "chrome-abc-Default.desktop"], contextKind: "none", reason: "" })
  assert.equal(r("chrome-zzz-Default").mode, "skip") // no entry of its own: do not open the browser entry instead
})

test("terminal with a folder and a captured program", () => {
  const x = r("Alacritty", { folder: "~/code/demo", launch: "nvim 'my notes.md'", home: "/srv/example" })
  assert.deepEqual(x.argv, ["uwsm-app", "--", "alacritty", "--working-directory", "/srv/example/code/demo", "-e", "nvim", "my notes.md"])
  assert.equal(x.contextKind, "folder")
  assert.deepEqual(r("kitty", {}).argv, ["uwsm-app", "--", "kitty"])
})

test("tui class", () => {
  assert.deepEqual(r("org.omarchy.btop").argv, ["uwsm-app", "--", "omarchy-launch-tui", "btop"])
  assert.equal(r("org.omarchy.-x").mode, "skip")
})

test("Chrome with a profile context fills the template as separate argv elements", () => {
  const x = r("google-chrome", { context: "Profile 1" })
  assert.deepEqual(x.argv, ["uwsm-app", "--", "google-chrome-stable", "--profile-directory=Profile 1", "--new-window"])
  assert.equal(x.contextKind, "profile")
  assert.equal(x.strategy, "chrome")
})

test("Firefox, Brave and the code family", () => {
  assert.deepEqual(r("firefox", { context: "work" }).argv, ["uwsm-app", "--", "firefox", "-P", "work", "--new-window"])
  assert.equal(r("Brave-browser", { context: "Default" }).argv[2], "brave")
  const ide = r("Code", { context: "~/code/demo", home: "/srv/example" })
  assert.deepEqual(ide.argv, ["uwsm-app", "--", "code", "--new-window", "/srv/example/code/demo"])
  assert.equal(ide.contextKind, "folder")
})

test("a context that tries to break out stays one argv element or is refused", () => {
  const evil = "x\"; rm -x; $(id) `id`"
  assert.deepEqual(r("google-chrome", { context: evil }).argv.slice(3), ["--profile-directory=" + evil, "--new-window"])
  assert.equal(r("code", { context: "--eval" }).mode, "skip")
  assert.equal(r("google-chrome", { context: "Default", folder: "-x" }).mode, "skip")
})

test("context apps: unknown profile is skipped, no profile uses the plain entry", () => {
  assert.equal(r("google-chrome", { context: "?" }).mode, "skip")
  assert.equal(r("google-chrome", {}).argv[2], "google-chrome.desktop")
})

test("place_only apps are never started", () => {
  assert.deepEqual(r("Spotify"), { strategy: "place_only", mode: "place_only", argv: null, contextKind: "none", reason: "" })
  assert.notEqual(r("Slack").strategy, "place_only", "Slack is started on restore (2026-11-22)")
})

test("a typed launch wins and is split with quotes, but not for terminals", () => {
  const x = r("org.example.Editor", { launch: "editor --open \"a b\" 'c d'" })
  assert.deepEqual(x.argv, ["uwsm-app", "--", "editor", "--open", "a b", "c d"])
  assert.equal(x.strategy, "command")
  assert.equal(r("Alacritty", { launch: "htop" }).strategy, "terminal")
})

test("user strategies come first and add classes without code", () => {
  const user = { notes: { match: "org.example.Notes|example-notes", use: "place_only", launch_context: "", context: "none" } }
  const table = A.mergeStrategies(user)
  assert.equal(Object.keys(table)[0], "notes")
  assert.equal(r("EXAMPLE-NOTES", {}, table).mode, "place_only")
  const over = A.mergeStrategies({ chromium: { match: "chromium", use: "desktop", launch_context: "", context: "none" } })
  assert.equal(Object.keys(over).filter((k) => k === "chromium").length, 1)
  assert.equal(r("chromium", { context: "Default" }, over).strategy, "chromium")
})

test("every default strategy has the four fields and a known use", () => {
  for (const [k, v] of Object.entries(T)) {
    assert.deepEqual(Object.keys(v), ["match", "use", "launch_context", "context"], k)
    assert.ok(["desktop", "webapp", "terminal", "tui", "context", "place_only", "command"].includes(v.use), k)
  }
  for (const k of ["webapp", "terminal", "tui", "chrome", "chromium", "brave", "firefox", "place_only", "command"]) assert.ok(T[k], k)
})

test("argv never holds the shell string form: every launch starts with uwsm-app --", () => {
  for (const cls of ["org.example.Editor", "Alacritty", "org.omarchy.btop", "google-chrome", "chrome-abc-Default", "photos"]) {
    const x = r(cls, { context: "Default", folder: "/srv/x" })
    assert.deepEqual(x.argv.slice(0, 2), ["uwsm-app", "--"], cls)
  }
})

test("VS Code's real window class resolves to the code IDE strategy (live S10)", () => {
  const r = A.resolve("com.microsoft.VSCode", [], A.defaultStrategies(), { context: "~/code/demo", home: "/srv/example" })
  assert.equal(r.contextKind, "folder")
  assert.deepEqual(r.argv.slice(0, 3), ["uwsm-app", "--", "code"])
})

test("a terminal reopens as the same terminal, so its class matches the slot (live 2026-11-21)", () => {
  const foot = A.resolve("foot", [], A.defaultStrategies(), { folder: "~/code/demo", home: "/srv/example" })
  assert.deepEqual(foot.argv, ["uwsm-app", "--", "foot", "--working-directory=/srv/example/code/demo"])
  const agent = A.resolve("foot", [], A.defaultStrategies(), { folder: "/srv/example/p", launch: "agent --resume" })
  assert.deepEqual(agent.argv, ["uwsm-app", "--", "foot", "--working-directory=/srv/example/p", "agent", "--resume"])
  const other = A.resolve("xterm", [], A.defaultStrategies(), { folder: "/srv/example/p" })
  assert.deepEqual(other.argv, ["uwsm-app", "--", "xdg-terminal-exec", "--dir=/srv/example/p"])
  assert.equal(A.resolve("foot", [], A.defaultStrategies(), { folder: "-rf" }).mode, "skip")
})

test("classFor: StartupWMClass first, then a class seen for the entry, else the id as an unconfirmed guess", () => {
  const C = new Function(src + "; return { classFor }")()
  assert.deepEqual(C.classFor({ id: "Example-Mail.desktop", startupWMClass: "Example-mail-client" }, { "Example-Mail": "other" }),
    { class: "Example-mail-client", confirmed: true })
  assert.deepEqual(C.classFor({ id: "org.example.Photos.desktop", startupWMClass: "" }, { "org.example.Photos": "photos" }),
    { class: "photos", confirmed: true })
  assert.deepEqual(C.classFor({ id: "org.example.Photos.desktop" }, { "org.example.Other": "x" }), { class: "org.example.Photos", confirmed: false })
  assert.deepEqual(C.classFor({ id: "org.example.Photos" }, undefined), { class: "org.example.Photos", confirmed: false })
  assert.deepEqual(C.classFor({ id: "toString" }, {}), { class: "toString", confirmed: false }, "no prototype keys")
  assert.deepEqual(C.classFor({ id: "org.example.Photos" }, { "org.example.Photos": "" }), { class: "org.example.Photos", confirmed: false })
})
