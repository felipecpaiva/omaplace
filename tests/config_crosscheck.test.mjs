// Cross-check: the Lua and JS config parsers must read every fixture (from both sets) to the same values.
// Warning text differs by design, so only the warning count is compared.
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import { execFileSync } from "node:child_process"
import { fileURLToPath } from "node:url"

const root = fileURLToPath(new URL("..", import.meta.url))
const src = readFileSync(`${root}/js/ConfigIO.js`, "utf8").replace(".pragma library", "")
const C = new Function(src + "; return { parse }")()

const luaParse = (path) =>
  JSON.parse(
    execFileSync("lua", ["-e", `
      local C = dofile("${root}/lua/config.lua")
      local J = dofile("${root}/lua/json.lua")
      local f = assert(io.open(os.getenv("OMAPLACE_FIXTURE"), "rb")); local t = f:read("a"); f:close()
      local r = C.load(t)
      r.rules = J.object(r.rules); r.strategies = J.object(r.strategies)
      io.write(J.encode(r))`], { encoding: "utf8", env: { ...process.env, OMAPLACE_FIXTURE: path } }),
  )

// Normalise what may legitimately differ: warning text, and [] vs {} for empty maps.
const norm = (r) => {
  const out = structuredClone(r)
  out.warnings = (r.warnings || []).length
  for (const k of ["rules", "strategies"]) if (Array.isArray(out[k]) && out[k].length === 0) out[k] = {}
  return out
}

for (const set of ["config-lua", "config-js"]) {
  const dir = `${root}/tests/fixtures/${set}`
  for (const f of readdirSync(dir).filter((n) => n.endsWith(".toml"))) {
    test(`${set}/${f}: Lua and JS agree`, () => {
      const path = `${dir}/${f}`
      assert.deepEqual(norm(luaParse(path)), norm(C.parse(readFileSync(path, "utf8"))))
    })
  }
}
