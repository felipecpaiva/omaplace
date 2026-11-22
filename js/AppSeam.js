.pragma library
// The settings app's requests (design 17, D37, D38). The app writes app-<id>.json ({ contract, op, args }); the service
// checks it here and runs the matching Service.qml function. Pure: Node tested in tests/app_seam.test.mjs.

var CONTRACT = 1

// op: the argument kinds, in order. s string, i integer, b boolean, v any JSON scalar (a setting or field value),
// j a scalar or a flat object of scalars (a plan edit's argument, as { pos, id }).
var OPS = {
  refresh: [], open: ["s"], rename: ["s", "s"], removeScene: ["s"],
  setWindow: ["s", "i", "s", "s", "v"], pickFolder: ["s", "i", "s"],
  ruleNew: ["s", "s", "i"], ruleFromFocus: [], planFromDesktop: ["s", "i", "b", "s", "i"], setRule: ["s", "s", "v"], removeRule: ["s"],
  setSetting: ["s", "v"], menuAdd: [], menuRemove: [], restore: ["s"],
  editPlan: ["s", "i", "b", "s", "j", "s"], openOmagnet: [], result: ["s"]
}

var ID_RE = /^[a-z0-9-]{1,40}$/

function validId(id) { return typeof id === "string" && ID_RE.test(id) }

function kindOk(kind, v) {
  if (kind === "s") return typeof v === "string" && v.length <= 4096
  if (kind === "i") return Number.isInteger(v)
  if (kind === "b") return typeof v === "boolean"
  if (kind === "j" && v && typeof v === "object" && !Array.isArray(v)) {
    var keys = Object.keys(v)
    return keys.length <= 8 && keys.every(function (k) { return kindOk("v", v[k]) })
  }
  return v === null || typeof v === "boolean" || Number.isFinite(v) || (typeof v === "string" && v.length <= 4096)
}

// The request text -> { op, args } or { error }. A request from another contract is refused by name, so the app can say
// "update omaplace" instead of failing in a way nobody understands.
function parse(text) {
  var r
  try { r = JSON.parse(String(text || "")) } catch (e) { return { error: "bad_request" } }
  if (!r || typeof r !== "object") return { error: "bad_request" }
  if (r.contract !== CONTRACT) return { error: "contract" }
  if (typeof r.op !== "string" || !Object.prototype.hasOwnProperty.call(OPS, r.op)) return { error: "unknown_op" }
  var kinds = OPS[r.op], args = Array.isArray(r.args) ? r.args : []
  if (args.length !== kinds.length) return { error: "bad_args" }
  for (var i = 0; i < kinds.length; i++) if (!kindOk(kinds[i], args[i])) return { error: "bad_args" }
  return { op: r.op, args: args }
}

// A rule name for a new rule of app `app` that is not taken yet: letters, digits, - and _ only.
function ruleName(app, taken) {
  var base = String(app || "").toLowerCase().replace(/\.desktop$/, "").split(".").pop().replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "").slice(0, 30) || "app"
  var t = taken || {}
  if (!t[base]) return base
  for (var n = 2; n < 1000; n++) if (!t[base + "-" + n]) return base + "-" + n
  return ""
}

// The reply file text: the service's answer (its JSON text) and the model to show next.
function reply(id, answerText, model) {
  var a
  try { a = JSON.parse(String(answerText || "")) } catch (e) { a = { ok: false, code: "failed", reason: "no answer" } }
  return JSON.stringify({ contract: CONTRACT, id: id, answer: a, model: model }) + "\n"
}

// started: when this service started (ms); seq counts again from 1 after a shell restart, so the app goes by both.
function model(panel, desks, apps, monitors, busy, seq, started) {
  return { contract: CONTRACT, started: started, seq: seq, busy: busy === true, panel: panel, desks: desks, apps: apps, monitors: monitors || [] }
}
