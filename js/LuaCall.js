.pragma library
// One `hyprctl eval` call into the omaplace Lua module, written so its printed answer says what happened (WP8 fix).
// Pure: builds the Lua text and reads the answer. `hyprctl eval` prints what the chunk returns.

const CODES = ["ok", "no_lua", "busy", "bad_plan", "no_monitor", "no_runtime", "bad_path", "failed"]

// method: a name on _G.omaplace; args: Lua literals already encoded (LuaLiteral.encode); replyPath: a file in the runtime
// folder (encoded too). `hyprctl eval` prints only "ok", never what the chunk returns (checked live 2026-11-21), so the
// chunk writes its answer "omaplace:<code>" to replyPath: no_lua when the module is missing, ok when the call returned
// a value, else the error it returned. The service reads that file after hyprctl exits.
function wrap(method, args, replyPath) {
  if (!/^[a-z_]+$/.test(method)) throw new Error("LuaCall: bad method name")
  if (typeof replyPath !== "string" || replyPath === "") throw new Error("LuaCall: reply path needed")
  return "(function() local o = rawget(_G, \"omaplace\"); local a; " +
    "if type(o) ~= \"table\" then a = \"omaplace:no_lua\" else " +
    "local r, e = o." + method + "(" + (args || []).join(", ") + "); a = r and \"omaplace:ok\" or (\"omaplace:\" .. tostring(e)) end; " +
    "local f = io.open(" + replyPath + ", \"w\"); if f then f:write(a); f:close() end end)()"
}

// The code in the reply file's text, or "" when the output says nothing we know (then the caller waits as before).
// An error code Lua may add later reads as "failed".
function code(output) {
  const m = /omaplace:([a-z_]+)/.exec(String(output || ""))
  if (!m) return ""
  return CODES.indexOf(m[1]) === -1 ? "failed" : m[1]
}
