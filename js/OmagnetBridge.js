.pragma library
.import "ConfigIO.js" as ConfigIO
// The bridge to omagnet (D43): a desktop plan with zones is also written into omagnet's config.toml, so dragging a window
// on that desktop snaps to the same zones. omaplace owns only what it names: the section [layout_omaplace-<ws>] and the
// line "<ws> = ..." in [workspace_layouts] when it points at that section. A layout the user made in omagnet, or a line
// that points elsewhere, is never changed. Pure: Node tested in tests/omagnet_bridge.test.mjs.

function layoutName(ws) { return "omaplace-" + ws }

function sectionLines(lines, header) {
  const r = ConfigIO.sectionRange(lines, header)
  return r ? lines.slice(r[0] + 1, r[1]) : null
}

// The value of `key` in [workspace_layouts], or "" (a bare or quoted key).
function wsValue(lines, ws) {
  const body = sectionLines(lines, "workspace_layouts") || []
  const re = new RegExp('^\\s*"?' + ws + '"?\\s*=\\s*"([^"]*)"')
  for (const l of body) { const m = re.exec(l); if (m) return m[1] }
  return ""
}

// text: omagnet's config.toml ("" when it does not exist). zones: "x y w h; ..." or "" to take omaplace's entry away.
// Returns { text, changed, reason }; reason says why nothing changed when the user's own line is there.
function setDesktop(text, ws, zones) {
  if (!Number.isInteger(ws) || ws < 1) return { text, changed: false, reason: "bad_workspace" }
  const name = layoutName(ws)
  const s = ConfigIO.split(text || "")
  const lines = s.lines
  const current = wsValue(lines, ws)
  if (current !== "" && current !== name) return { text, changed: false, reason: "user_layout" }
  const before = lines.join("\n")
  if (zones) {
    const lr = ConfigIO.sectionRange(lines, "layout_" + name)
    if (lr) ConfigIO.upsert(lines, lr[0] + 1, lr[1], "zones", zones, false)
    else ConfigIO.appendBlock(lines, ["[layout_" + name + "]", "zones = " + JSON.stringify(zones)])
    const wr = ConfigIO.sectionRange(lines, "workspace_layouts")
    if (wr) ConfigIO.upsert(lines, wr[0] + 1, wr[1], String(ws), name, false)
    else ConfigIO.appendBlock(lines, ["[workspace_layouts]", ws + " = " + JSON.stringify(name)])
  } else {
    const wr = ConfigIO.sectionRange(lines, "workspace_layouts")
    if (wr) {
      const re = new RegExp('^\\s*"?' + ws + '"?\\s*=\\s*"' + name + '"')
      for (let i = wr[1] - 1; i > wr[0]; i--) if (re.test(lines[i])) lines.splice(i, 1)
    }
    const lr = ConfigIO.sectionRange(lines, "layout_" + name)
    if (lr) lines.splice(lr[0], lr[1] - lr[0])
  }
  const after = lines.join("\n")
  return { text: after === before ? text : after.replace(/\n*$/, "\n"), changed: after !== before, reason: "" }
}
