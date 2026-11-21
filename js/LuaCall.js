.pragma library
// One `hyprctl eval` call into the omaplace Lua module, written so its printed answer says what happened (WP8 fix).
// Pure: builds the Lua text and reads the answer. `hyprctl eval` prints what the chunk returns.

const CODES = ["ok", "no_lua", "busy", "bad_plan", "no_monitor", "no_runtime", "bad_path", "failed"]

// method: a name on _G.omaplace; args: Lua literals already encoded (LuaLiteral.encode). The answer is
// "omaplace:<code>": no_lua when the module is missing, ok when the call returned a value, else the error it returned.
function wrap(method, args) {
  if (!/^[a-z_]+$/.test(method)) throw new Error("LuaCall: bad method name")
  return "return (function() local o = rawget(_G, \"omaplace\"); if type(o) ~= \"table\" then return \"omaplace:no_lua\" end; " +
    "local r, e = o." + method + "(" + (args || []).join(", ") + "); if r then return \"omaplace:ok\" end; " +
    "return \"omaplace:\" .. tostring(e) end)()"
}

// The code in hyprctl's output, or "" when the output says nothing we know (then the caller waits as before).
// An error code Lua may add later reads as "failed".
function code(output) {
  const m = /omaplace:([a-z_]+)/.exec(String(output || ""))
  if (!m) return ""
  return CODES.indexOf(m[1]) === -1 ? "failed" : m[1]
}
