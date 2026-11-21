#!/usr/bin/env bash
# Regenerates tests/fixtures/zones-golden.json by running omagnet's LayoutOps.js on fixed inputs.
# Usage: bash tools/gen-zones-golden.sh <path-to-omagnet-checkout>
# The committed output is what the tests use, so only the person refreshing the vectors needs omagnet.
# After a refresh, copy the changed functions into js/Zones.js and update the commit named in its header.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
src=${1:?usage: gen-zones-golden.sh <omagnet checkout>}
if ! git -C "$src" diff --quiet HEAD -- LayoutOps.js; then
  echo "LayoutOps.js has uncommitted changes in $src: commit or stash them first" >&2
  exit 1
fi
commit=$(git -C "$src" rev-parse --short HEAD)
out="$root/tests/fixtures/zones-golden.json"

node - "$src/LayoutOps.js" "$commit" > "$out" <<'JS'
const L = require(process.argv[2])
const names = ["columns:1", "columns:2", "columns:3", "columns:7", "columns:12", "rows:2", "rows:3", "grid:2x2", "grid:3x2",
  "grid:12x12", "priority", "Columns:2", " grid : 2x3 ", "columns2", "columns:0", "columns:13", "rows:", "grid:2", "grid:0x2",
  "tiled", "scrolling", "full", "free", "", "0 0 0.5 1"]
const texts = ["0 0 0.5 1; 0.5 0 0.5 1", "0 0 1 1", " 0 0 0.25 1 ;0.25 0 0.75 1; ", "0.1 0.2 0.3 0.4", "0.33333 0 0.33334 1",
  "0 0 1.5 1", "0.5 0 0.6 1", "-0.1 0 0.5 1", "0 0 0 1", "0 0 0.5", "0 0 a 1", "", " ; ", "columns:2",
  Array(65).fill("0 0 1 1").join("; "), Array(64).fill("0 0 1 1").join("; ")]
const out = {
  omagnet_commit: process.argv[3],
  builtin: names.map((name) => {
    const zones = L.builtin(name)
    return { name, zones, text: zones ? L.toText(zones) : null }
  }),
  parse: texts.map((text) => {
    const r = L.parse(text)
    return r.zones ? { text, zones: r.zones, back: L.toText(r.zones) } : { text, error: r.error }
  })
}
process.stdout.write(JSON.stringify(out, null, 1) + "\n")
JS
echo "wrote $out (omagnet $commit)"
