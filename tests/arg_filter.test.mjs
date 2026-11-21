import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const src = readFileSync(new URL("../js/ArgFilter.js", import.meta.url), "utf8").replace(".pragma library", "")
const { filter } = new Function(src + "; return { filter }")()

test("harmless arguments pass untouched", () => {
  const argv = ["nvim", "--cmd", "set number", "/tmp/example/notes.md", "--dir=/srv/example", "org.example.Editor.desktop", "--profile-directory=Profile 1"]
  assert.deepEqual(filter(argv), { argv, dropped: 0 })
})

test("secret flags drop with their value", () => {
  assert.deepEqual(filter(["tool", "--password", "hunter2", "run"]), { argv: ["tool", "run"], dropped: 2 })
  assert.deepEqual(filter(["tool", "--token=abc", "--api-key", "k1", "-v"]), { argv: ["tool", "-v"], dropped: 3 })
  assert.deepEqual(filter(["tool", "--secret", "--verbose"]), { argv: ["tool", "--verbose"], dropped: 1 })
  assert.deepEqual(filter(["tool", "--key", "abc"]), { argv: ["tool"], dropped: 2 })
  assert.deepEqual(filter(["tool", "--aws-secret-key=zzz", "--client_secret", "q"]), { argv: ["tool"], dropped: 3 })
})

test("a flag that only ends in key as part of a word is not a secret", () => {
  assert.deepEqual(filter(["tool", "--keyboard", "us"]).dropped, 0)
})

test("environment assignments drop", () => {
  assert.deepEqual(filter(["env", "API_URL=http://example.test", "FOO=bar", "run"]), { argv: ["env", "run"], dropped: 2 })
})

test("urls with user and password drop, plain urls stay", () => {
  assert.equal(filter(["git", "clone", "https://bob:pw123" + "@" + "example.test/repo.git"]).dropped, 1)
  assert.equal(filter(["x", "--remote=https://bob:pw123" + "@" + "example.test/r"]).dropped, 1)
  assert.deepEqual(filter(["git", "clone", "https://example.test/repo.git"]).dropped, 0)
})

test("known key prefixes drop, also behind a flag", () => {
  const out = filter(["x", "sk-abc123", "ghp_exampleexample", "--auth=github_pat_11AAAA", "--use=xoxb-1234-abcd", "AKIAIOSFODNN7EXAMPLE"])
  assert.deepEqual(out, { argv: ["x"], dropped: 5 })
})

test("long random looking strings drop", () => {
  assert.equal(filter(["x", "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"]).dropped, 1)
  assert.equal(filter(["x", "dGhpc2lzYW5leGFtcGxlb2ZhYmFzZTY0c3RyaW5n0K"]).dropped, 1)
  assert.equal(filter(["x", "--value=Zm9vYmFyMTIzNDU2Nzg5MGFiY2RlZg"]).dropped, 1)
})

test("long but ordinary words, paths and class names stay", () => {
  const argv = ["xdg-terminal-exec", "/usr/share/applications/org.example.Editor.desktop", "a-rather-long-descriptive-name", "~/code/example-project-folder", "1234567890123456789012"]
  assert.equal(filter(argv).dropped, 0)
})

test("bad input is an empty list", () => {
  assert.deepEqual(filter(undefined), { argv: [], dropped: 0 })
})
