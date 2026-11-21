// Load a js/*.js QML library in Node: drop `.pragma library`, and turn each `.import "X.js" as X` line into a variable that
// holds that library (loaded the same way). Returns every top-level function, var and const of the file.
import { readFileSync } from "node:fs"

export function load(file) {
  const src = readFileSync(new URL("../js/" + file, import.meta.url), "utf8").replace(".pragma library", "")
  const deps = {}
  const body = src.replace(/^\.import "([^"]+\.js)" as (\w+)\s*$/gm, (_, f, name) => { deps[name] = load(f); return "" })
  const names = [...body.matchAll(/^(?:function|var|const|let)\s+([A-Za-z_$][\w$]*)/gm)].map((m) => m[1])
  return new Function(...Object.keys(deps), body + "; return { " + names.join(", ") + " }")(...Object.values(deps))
}
